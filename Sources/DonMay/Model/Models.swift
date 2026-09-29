import Foundation

enum Risk: String, Codable, CaseIterable {
    case safe, warn, keep

    var title: String {
        switch self {
        case .safe: "An toàn"
        case .warn: "Cần cân nhắc"
        case .keep: "Nên giữ"
        }
    }
}

enum UndoPolicy: String, Codable {
    case regenerate
    case backup
    case irreversible
}

enum GrowthLevel: Int, Comparable {
    case flat, up, spike

    static func < (lhs: GrowthLevel, rhs: GrowthLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .spike: "Tăng bất thường"
        case .up: "Đang tăng"
        case .flat: "Ổn định"
        }
    }
}

enum AppGroup: String, CaseIterable, Identifiable {
    case design, develop, browser, folders, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .design: "Công cụ thiết kế"
        case .develop: "Công cụ develop"
        case .browser: "Trình duyệt"
        case .folders: "Thư mục"
        case .system: "Hệ thống"
        }
    }
}

enum AppKind: String, CaseIterable, Codable, Identifiable {
    case figma, pencil, xcode, claude, simulator, cli, zen, desktop, downloads, documents, macos

    var id: String { rawValue }

    var group: AppGroup {
        switch self {
        case .figma, .pencil: .design
        case .xcode, .claude, .simulator, .cli: .develop
        case .zen: .browser
        case .desktop, .downloads, .documents: .folders
        case .macos: .system
        }
    }

    var title: String {
        switch self {
        case .figma: "Figma"
        case .pencil: "Pencil"
        case .xcode: "Xcode"
        case .claude: "Claude CLI"
        case .simulator: "Simulator"
        case .cli: "npm & CLI khác"
        case .zen: "Zen"
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        case .documents: "Documents"
        case .macos: "Cập nhật macOS"
        }
    }

    var detail: String {
        switch self {
        case .figma: "Bộ nhớ đệm file thiết kế và mã"
        case .pencil: "Bộ nhớ đệm, phiên Claude và bản sao lưu của Pencil"
        case .xcode: "Dữ liệu build, hỗ trợ máy thật, gói Swift"
        case .claude: "Job nền của Claude Code, máy ảo của Claude Desktop"
        case .simulator: "Máy ảo và runtime iOS"
        case .cli: "npm, Homebrew, Firebase CLI, Codex"
        case .zen: "Bộ nhớ đệm và dữ liệu trang web"
        case .desktop: "Ảnh chụp màn hình và tệp lớn trên Desktop"
        case .downloads: "Bộ cài, tệp tải trùng, tệp cũ"
        case .documents: "Thư mục build trong các dự án"
        case .macos: "Bộ cài và bản cập nhật macOS đã tải về máy"
        }
    }

    var bundleID: String? {
        switch self {
        case .figma: "com.figma.Desktop"
        case .pencil: "dev.pencil.desktop"
        case .xcode: "com.apple.dt.Xcode"
        case .claude: "com.anthropic.claudefordesktop"
        case .simulator: "com.apple.iphonesimulator"
        case .zen: "app.zen-browser.zen"
        case .macos: "com.apple.systempreferences"
        case .cli, .desktop, .downloads, .documents: nil
        }
    }

    var folder: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .desktop: return home.appendingPathComponent("Desktop")
        case .downloads: return home.appendingPathComponent("Downloads")
        case .documents: return home.appendingPathComponent("Documents")
        default: return nil
        }
    }

    /// Ứng dụng đang mở thì bộ nhớ đệm có thể bị ghi lại ngay khi đang xoá.
    var shouldQuitBeforeCleaning: Bool {
        switch self {
        case .figma, .pencil, .zen: true
        default: false
        }
    }
}

enum RemovalAction: Codable, Hashable {
    case files([String])
    case simulatorDevice(udid: String)
    case simulatorRuntime(identifier: String)
}

struct CleanItem: Identifiable, Hashable {
    let id: String
    let app: AppKind
    var name: String
    var reason: String
    var displayPath: String
    var size: Int64
    var lastUsed: Date?
    var risk: Risk
    var undo: UndoPolicy
    var growth24: Int64
    var growth7: Int64
    var action: RemovalAction
    var regenerateHint: String

    var paths: [String] {
        if case let .files(paths) = action { return paths }
        return []
    }

    var level: GrowthLevel {
        guard size > 0 else { return .flat }
        let ratio7 = Double(growth7) / Double(size)
        let ratio24 = Double(growth24) / Double(size)
        if (growth7 >= 400 * .mb && ratio7 >= 0.4) || (growth24 >= 500 * .mb && ratio24 >= 0.3) { return .spike }
        if growth7 >= 100 * .mb && ratio7 >= 0.1 { return .up }
        return .flat
    }

    /// Tỉ lệ đo bằng gzip trên dữ liệu trang web của Zen, phiên Claude và bản ghi hội thoại: 60–69%.
    var estimatedPackedSize: Int64 { Int64(Double(size) * 0.7) }
}

extension Int64 {
    static let kb: Int64 = 1024
    static let mb: Int64 = 1024 * 1024
    static let gb: Int64 = 1024 * 1024 * 1024
}

enum HistoryOutcome: String, Codable {
    case regenerated
    case irreversible
    case packed
    case restored
    case expired
    case failed
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var app: AppKind
    var name: String
    var paths: [String]
    var size: Int64
    var outcome: HistoryOutcome
    var regenerateHint: String
    var archivePath: String?
    var archiveSize: Int64?
    var expiresAt: Date?
    var error: String?
}

struct HistorySession: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var entries: [HistoryEntry]

    var keptArchiveSize: Int64 {
        entries.filter { $0.outcome == .packed }.reduce(0) { $0 + ($1.archiveSize ?? 0) }
    }

    var freed: Int64 {
        entries.filter { $0.outcome != .failed && $0.outcome != .restored }.reduce(0) { $0 + $1.size } - keptArchiveSize
    }
}
