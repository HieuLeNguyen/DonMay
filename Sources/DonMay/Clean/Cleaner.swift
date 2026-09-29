import AppKit
import Foundation

enum Cleaner {
    static func clean(_ items: [CleanItem], backups: Set<String>, progress: @escaping @Sendable (Double, String) -> Void) async -> HistorySession {
        let sessionID = UUID()
        var entries: [HistoryEntry] = []
        for (index, item) in items.enumerated() {
            progress(Double(index) / Double(items.count), item.name)
            let entry = await Task.detached(priority: .userInitiated) {
                clean(item, backup: backups.contains(item.id), sessionID: sessionID)
            }.value
            entries.append(entry)
        }
        progress(1, "")
        return HistorySession(id: sessionID, date: Date(), entries: entries)
    }

    private static func clean(_ item: CleanItem, backup: Bool, sessionID: UUID) -> HistoryEntry {
        var entry = HistoryEntry(app: item.app, name: item.name, paths: paths(of: item.action), size: item.size,
                                 outcome: .regenerated, regenerateHint: item.regenerateHint)
        let archive = AppFolders.backups.appendingPathComponent(sessionID.uuidString)
            .appendingPathComponent(entry.id.uuidString + ".aar")
        do {
            switch item.action {
            case let .simulatorDevice(udid):
                try Shell.xcrun(["simctl", "shutdown", udid], ignoringFailure: true)
                try Shell.xcrun(["simctl", "delete", udid])
                entry.outcome = .irreversible
            case let .simulatorRuntime(identifier):
                try Shell.xcrun(["simctl", "runtime", "delete", identifier])
                entry.outcome = .irreversible
            case let .files(paths):
                try paths.forEach(Safety.check)
                if item.undo == .backup && backup {
                    try ensureRoomForArchive(of: item)
                    guard paths.count == 1 else { throw Archiver.Failure(message: "Chỉ sao lưu được một thư mục mỗi mục") }
                    entry.archiveSize = try Archiver.archive(directory: URL(fileURLWithPath: paths[0]), to: archive)
                    entry.archivePath = archive.path
                    entry.expiresAt = Calendar.current.date(byAdding: .day, value: BackupPolicy.keepDays, to: Date())
                    entry.outcome = .packed
                } else if item.undo == .backup {
                    entry.outcome = .irreversible
                    entry.regenerateHint = "Đã xoá không sao lưu"
                }
                do {
                    for path in paths where FileManager.default.fileExists(atPath: path) {
                        try FileManager.default.removeItem(atPath: path)
                    }
                } catch where entry.outcome == .packed {
                    entry.error = "Đã nén xong nhưng xoá bản gốc chưa hết: \(error.localizedDescription). Bản nén được giữ lại."
                    return entry
                }
            }
        } catch {
            entry.outcome = .failed
            entry.error = error.localizedDescription
            try? FileManager.default.removeItem(at: archive)
            entry.archivePath = nil
            entry.archiveSize = nil
        }
        return entry
    }

    private static func ensureRoomForArchive(of item: CleanItem) throws {
        let free = SystemMetrics.diskFree()
        guard free > item.estimatedPackedSize + 512 * .mb else {
            throw Archiver.Failure(message: "Không đủ chỗ trống để nén \(Format.bytes(item.estimatedPackedSize))")
        }
    }

    private static func paths(of action: RemovalAction) -> [String] {
        switch action {
        case let .files(paths): paths
        case let .simulatorDevice(udid): ["simctl device \(udid)"]
        case let .simulatorRuntime(identifier): ["simctl runtime \(identifier)"]
        }
    }

    // MARK: - Khôi phục và dọn bản nén

    static func restore(_ entry: HistoryEntry) throws -> HistoryEntry {
        guard entry.outcome == .packed, let archivePath = entry.archivePath, let original = entry.paths.first else {
            throw Archiver.Failure(message: "Mục này không có bản nén")
        }
        var destination = URL(fileURLWithPath: original)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = destination.deletingLastPathComponent()
                .appendingPathComponent(destination.lastPathComponent + " (khôi phục)")
        }
        try Archiver.extract(URL(fileURLWithPath: archivePath), into: destination)
        try? FileManager.default.removeItem(atPath: archivePath)
        var restored = entry
        restored.outcome = .restored
        restored.archivePath = nil
        return restored
    }

    static func dropArchive(_ entry: HistoryEntry) -> HistoryEntry {
        if let path = entry.archivePath { try? FileManager.default.removeItem(atPath: path) }
        var dropped = entry
        dropped.outcome = .expired
        dropped.archivePath = nil
        return dropped
    }

    /// Xoá bản nén hết hạn. Ổ còn dưới `lowDiskFree` thì xoá bản cũ nhất trước, nhưng không đụng bản
    /// tạo trong `graceHours` giờ qua — nếu không, trên ổ gần đầy bản nén vừa tạo sẽ mất ngay. Trả về số bản đã xoá.
    static func purge(_ sessions: inout [HistorySession]) -> Int {
        var dropped = 0
        let now = Date()
        for s in sessions.indices {
            for e in sessions[s].entries.indices where sessions[s].entries[e].outcome == .packed
                && (sessions[s].entries[e].expiresAt ?? .distantFuture) < now {
                sessions[s].entries[e] = dropArchive(sessions[s].entries[e])
                dropped += 1
            }
        }
        let packed = sessions.indices.flatMap { s in sessions[s].entries.indices.map { (s, $0) } }
            .filter { sessions[$0.0].entries[$0.1].outcome == .packed
                && sessions[$0.0].date < now.addingTimeInterval(-Double(BackupPolicy.graceHours) * 3600) }
            .sorted { sessions[$0.0].date < sessions[$1.0].date }
        for (s, e) in packed where SystemMetrics.diskFree() < BackupPolicy.lowDiskFree {
            sessions[s].entries[e] = dropArchive(sessions[s].entries[e])
            dropped += 1
        }
        return dropped
    }

    // MARK: - Thùng rác

    static func trashSize() -> Int64? {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil else { return nil }
        return FileSizer.measure(trash).size
    }

    @MainActor
    static func emptyTrash() throws {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error { throw Archiver.Failure(message: error[NSAppleScript.errorMessage] as? String ?? "Không dọn được Thùng rác") }
    }
}

extension Shell {
    static func xcrun(_ arguments: [String], ignoringFailure: Bool) throws {
        do { try xcrun(arguments) } catch where ignoringFailure {}
    }
}
