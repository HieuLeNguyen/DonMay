import AppKit

enum Permissions {
    /// Chỉ đọc được TCC.db khi có Full Disk Access; mở thử không bật hộp thoại nào.
    static var hasFullDiskAccess: Bool {
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = FileHandle(forReadingAtPath: db.path) else { return false }
        try? handle.close()
        return true
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
