import AppKit
import Foundation

enum Cleaner {
    static func clean(_ items: [CleanItem], backups: Set<String>, progress: @escaping @Sendable (Double, String) -> Void) async -> HistorySession {
        let sessionID = UUID()
        var entries: [HistoryEntry] = []
        let items = await Task.detached { expandBackups(items, backups: backups) }.value
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
                    guard paths.count == 1 else { throw Archiver.Failure(message: L("Chỉ sao lưu được một thư mục mỗi mục", "Only one folder per item can be backed up")) }
                    entry.archiveSize = try Archiver.archive(directory: URL(fileURLWithPath: paths[0]), to: archive)
                    entry.archivePath = archive.path
                    entry.expiresAt = Calendar.current.date(byAdding: .day, value: BackupPolicy.keepDays, to: Date())
                    entry.outcome = .packed
                } else if item.undo == .backup {
                    entry.outcome = .irreversible
                    entry.regenerateHint = L("Đã xoá không sao lưu", "Deleted without backup")
                }
                do {
                    for path in paths where FileManager.default.fileExists(atPath: path) {
                        try moveToPurge(URL(fileURLWithPath: path))
                    }
                } catch where entry.outcome == .packed {
                    entry.error = L("Đã nén xong nhưng xoá bản gốc chưa hết: \(error.localizedDescription). Bản nén được giữ lại.", "Archived, but the original wasn't fully deleted: \(error.localizedDescription). The archive was kept.")
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

    /// Mục sao lưu chọn nhiều phần con: mỗi phần một bản nén riêng để khôi phục từng phần.
    private static func expandBackups(_ items: [CleanItem], backups: Set<String>) -> [CleanItem] {
        items.flatMap { item -> [CleanItem] in
            guard item.undo == .backup, backups.contains(item.id), item.paths.count > 1 else { return [item] }
            return item.paths.map { path in
                var part = item
                part.action = .files([path])
                part.size = FileSizer.measure(URL(fileURLWithPath: path)).size
                part.name = "\(item.name.components(separatedBy: " · ").dropLast().joined(separator: " · ")) · \(URL(fileURLWithPath: path).lastPathComponent)"
                return part
            }
        }
    }

    // MARK: - Xoá nhanh, dọn nền

    /// Dời mục vào thư mục chờ xoá: cùng ổ nên chỉ là đổi tên, không phải duyệt từng tệp. Dời không được
    /// (khác ổ, bị khoá) thì xoá thẳng.
    static func moveToPurge(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: AppFolders.purge, withIntermediateDirectories: true)
        let target = AppFolders.purge.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        do {
            try fm.moveItem(at: url, to: target)
        } catch {
            try forceRemove(url)
        }
    }

    /// Xoá, và nếu vướng thư mục chỉ-đọc (gói Swift trong DerivedData để quyền r-x) hay cờ khoá thì trả
    /// lại quyền ghi cho chính chủ rồi xoá lại.
    static func forceRemove(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) || (try? url.checkResourceIsReachable()) == true else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            _ = try? Shell.run("/usr/bin/chflags", ["-R", "nouchg", url.path])
            _ = try? Shell.run("/bin/chmod", ["-R", "u+w", url.path])
            do {
                try fm.removeItem(at: url)
            } catch {
                throw Archiver.Failure(message: L("Không có quyền xoá một số tệp trong \(url.lastPathComponent). Thoát ứng dụng đang dùng nó (ví dụ Xcode) rồi thử lại.", "No permission to delete some files in \(url.lastPathComponent). Quit the application using it (for example Xcode) and try again."))
            }
        }
    }

    /// Xoá thật mọi thứ trong thư mục chờ, ưu tiên thấp. Trả về số mục còn sót.
    static func drainPurge(progress: @escaping @Sendable (Int) -> Void) async -> Int {
        await Task.detached(priority: .utility) {
            let items = AppFolders.purge.children()
            var remaining = items.count
            var failed = 0
            for item in items {
                if (try? forceRemove(item)) == nil { failed += 1 }
                remaining -= 1
                progress(remaining)
            }
            return failed
        }.value
    }

    static var hasPendingPurge: Bool { !AppFolders.purge.children().isEmpty }

    private static func ensureRoomForArchive(of item: CleanItem) throws {
        let free = SystemMetrics.diskFree()
        guard free > item.estimatedPackedSize + 512 * .mb else {
            throw Archiver.Failure(message: L("Không đủ chỗ trống để nén \(Format.bytes(item.estimatedPackedSize))", "Not enough free space to archive \(Format.bytes(item.estimatedPackedSize))"))
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
            throw Archiver.Failure(message: L("Mục này không có bản nén", "This item has no archive"))
        }
        var destination = URL(fileURLWithPath: original)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = destination.deletingLastPathComponent()
                .appendingPathComponent(destination.lastPathComponent + L(" (khôi phục)", " (restored)"))
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
        if let error { throw Archiver.Failure(message: error[NSAppleScript.errorMessage] as? String ?? L("Không dọn được Thùng rác", "Couldn't empty the Trash")) }
    }
}

extension Shell {
    static func xcrun(_ arguments: [String], ignoringFailure: Bool) throws {
        do { try xcrun(arguments) } catch where ignoringFailure {}
    }
}
