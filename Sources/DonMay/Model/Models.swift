import Foundation

enum Risk: String, Codable, CaseIterable {
    case safe, warn, keep

    var title: String {
        switch self {
        case .safe: L("An toàn", "Safe")
        case .warn: L("Cần cân nhắc", "Review")
        case .keep: L("Nên giữ", "Keep")
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
        case .spike: L("Tăng bất thường", "Unusual growth")
        case .up: L("Đang tăng", "Growing")
        case .flat: L("Ổn định", "Stable")
        }
    }
}

enum AppGroup: String, CaseIterable, Identifiable {
    case design, develop, browser, folders, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .design: L("Công cụ thiết kế", "Design tools")
        case .develop: L("Công cụ develop", "Developer tools")
        case .browser: L("Trình duyệt", "Browsers")
        case .folders: L("Thư mục", "Folders")
        case .system: L("Hệ thống", "System")
        }
    }
}

enum AppKind: String, CaseIterable, Codable, Identifiable {
    case figma, pencil, xcode, claude, codex, simulator, homebrew, cli, zen, notes, desktop, downloads, documents, macos, updates

    var id: String { rawValue }

    var group: AppGroup {
        switch self {
        case .figma, .pencil: .design
        case .xcode, .claude, .codex, .simulator, .homebrew, .cli: .develop
        case .zen: .browser
        case .notes, .desktop, .downloads, .documents: .folders
        case .macos, .updates: .system
        }
    }

    var title: String {
        switch self {
        case .figma: "Figma"
        case .pencil: "Pencil"
        case .xcode: "Xcode"
        case .claude: "Claude CLI"
        case .codex: "Codex"
        case .homebrew: "Homebrew"
        case .notes: L("Ghi chú", "Notes")
        case .updates: L("Bản cập nhật ứng dụng", "App updates")
        case .simulator: "Simulator"
        case .cli: L("npm & CLI khác", "npm & other CLIs")
        case .zen: "Zen"
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        case .documents: "Documents"
        case .macos: L("Cập nhật macOS", "macOS updates")
        }
    }

    var detail: String {
        switch self {
        case .figma: L("Bộ nhớ đệm file thiết kế và mã", "Design file and code caches")
        case .pencil: L("Bộ nhớ đệm, phiên Claude và bản sao lưu của Pencil", "Pencil caches, Claude sessions and backups")
        case .xcode: L("Dữ liệu build, hỗ trợ máy thật, gói Swift", "Build data, device support, Swift packages")
        case .claude: L("Job nền, hội thoại từng dự án, máy ảo của Claude Desktop", "Background jobs, per-project conversations, Claude Desktop VM")
        case .codex: L("Phiên hội thoại, nhật ký và runtime của Codex", "Codex sessions, logs and runtimes")
        case .homebrew: L("Bộ nhớ đệm tải về và phiên bản gói cũ", "Download cache and old package versions")
        case .notes: L("Dữ liệu và tệp đính kèm của Ghi chú", "Notes data and attachments")
        case .updates: L("Bản cập nhật các ứng dụng đã tải sẵn về máy", "App updates already downloaded to this Mac")
        case .simulator: L("Máy ảo và runtime iOS", "iOS simulators and runtimes")
        case .cli: "npm, CocoaPods, Firebase CLI, Gradle"
        case .zen: L("Bộ nhớ đệm và dữ liệu trang web", "Cache and website data")
        case .desktop: L("Ảnh chụp màn hình và tệp lớn trên Desktop", "Screenshots and large files on the Desktop")
        case .downloads: L("Bộ cài, tệp tải trùng, tệp cũ", "Installers, duplicate downloads, old files")
        case .documents: L("Thư mục build trong các dự án", "Build folders inside projects")
        case .macos: L("Bộ cài và bản cập nhật macOS đã tải về máy", "Downloaded macOS installers and updates")
        }
    }

    var bundleID: String? {
        switch self {
        case .figma: "com.figma.Desktop"
        case .pencil: "dev.pencil.desktop"
        case .xcode: "com.apple.dt.Xcode"
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        case .notes: "com.apple.Notes"
        case .updates: "com.apple.AppStore"
        case .simulator: "com.apple.iphonesimulator"
        case .zen: "app.zen-browser.zen"
        case .macos: "com.apple.systempreferences"
        case .homebrew, .cli, .desktop, .downloads, .documents: nil
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
        case .figma, .pencil, .zen, .codex: true
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
