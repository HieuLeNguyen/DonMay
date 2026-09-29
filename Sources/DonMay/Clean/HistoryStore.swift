import Foundation

enum BackupPolicy {
    static let keepDays = 7
    static let maxBudget: Int64 = 2 * .gb
    static let lowDiskFree: Int64 = 2 * .gb
    static let graceHours = 24

    /// 10% dung lượng trống, tối đa 2 GB.
    static func budget(free: Int64) -> Int64 { min(maxBudget, free / 10) }
}

enum AppFolders {
    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DonMay")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var backups: URL { support.appendingPathComponent("Backups") }
    static var history: URL { support.appendingPathComponent("history.json") }
}

enum HistoryStore {
    static func load() -> [HistorySession] {
        guard let data = try? Data(contentsOf: AppFolders.history) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistorySession].self, from: data)) ?? []
    }

    static func save(_ sessions: [HistorySession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: AppFolders.history, options: .atomic)
    }
}
