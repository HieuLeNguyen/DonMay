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
        ".pencil",
        ".npm",
        ".cache",
        ".gradle/caches",
        "Documents",
        "Desktop",
        "Downloads",
    ].map { home + "/" + $0 }

    private static let buildFolders: Set<String> = ["build", ".build", "node_modules", "DerivedData", "Pods", ".dart_tool", ".gradle"]

    static func check(_ path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        guard let root = allowedRoots.first(where: { resolved.hasPrefix($0 + "/") }) else {
            throw Refusal(path: path, reason: "nằm ngoài các vị trí được phép dọn")
        }
        if resolved.contains("/.git/") || resolved.hasSuffix("/.git") {
            throw Refusal(path: path, reason: "là kho git")
        }
        if root.hasSuffix("/Documents") && !buildFolders.contains(url.lastPathComponent) {
            throw Refusal(path: path, reason: "trong Documents chỉ được xoá thư mục build")
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
