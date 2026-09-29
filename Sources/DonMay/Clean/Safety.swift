import Foundation

/// Chốt cuối trước mọi lệnh xoá: đường dẫn phải nằm trong danh sách gốc được phép và không phải chính gốc đó.
enum Safety {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    private static let allowedRoots: [String] = [
        "Library/Developer",
        "Library/Caches",
        "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches",
        "Library/Application Support/Claude",
        "Library/Application Support/zen/Profiles",
        "Library/Application Support/Figma/DesktopProfile",
        "Library/Application Support/Pencil",
        ".claude/jobs",
        ".claude/projects",
        ".claude/file-history",
        ".codex/sessions",
        ".codex/archived_sessions",
        ".codex/shell_snapshots",
        ".codex/computer-use",
        ".codex/log",
        ".Trash",
        ".pencil",
        ".npm",
        ".cache",
        ".gradle/caches",
        "Documents",
        "Desktop",
        "Downloads",
    ].map { home + "/" + $0 } + brewRoots

    private static let brewRoots = ["/opt/homebrew", "/usr/local"].flatMap { ["\($0)/Cellar", "\($0)/Caskroom"] }

    private static let allowedFiles = Set(["logs_2.sqlite", "logs_2.sqlite-wal", "logs_2.sqlite-shm"].map { home + "/.codex/" + $0 })

    private static let buildFolders: Set<String> = ["build", ".build", "node_modules", "DerivedData", "Pods", ".dart_tool", ".gradle"]

    static func check(_ path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if url.deletingLastPathComponent().path == "/Applications" && url.lastPathComponent.hasPrefix("Install macOS")
            && url.pathExtension == "app" { return }
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        if allowedFiles.contains(resolved) { return }
        guard let root = allowedRoots.first(where: { resolved.hasPrefix($0 + "/") }) else {
            throw Refusal(path: path, reason: "nằm ngoài các vị trí được phép dọn")
        }
        if resolved.contains("/.git/") || resolved.hasSuffix("/.git") {
            throw Refusal(path: path, reason: "là kho git")
        }
        if root.hasSuffix("/Documents") {
            let inside = resolved.dropFirst(root.count + 1).split(separator: "/").map(String.init)
            guard inside.contains(where: buildFolders.contains) else {
                throw Refusal(path: path, reason: "trong Documents chỉ được xoá thư mục build hoặc thứ nằm trong nó")
            }
        }
        if brewRoots.contains(root) && resolved.dropFirst(root.count + 1).split(separator: "/").count < 2 {
            throw Refusal(path: path, reason: "chỉ được xoá một phiên bản cũ của gói, không xoá cả gói")
        }
        if (root.hasSuffix("/Desktop") || root.hasSuffix("/Downloads")) && url.deletingLastPathComponent().path != root {
            throw Refusal(path: path, reason: "chỉ được xoá tệp nằm ngay trong Desktop hoặc Downloads")
        }
    }

    struct Refusal: LocalizedError {
        let path: String
        let reason: String
        var errorDescription: String? { "Từ chối xoá \(Format.abbreviatingHome(path)): \(reason)" }
    }
}
