import AppKit
import Observation
import ServiceManagement

enum Language: String, CaseIterable {
    case system, vietnamese, english

    var title: String {
        switch self {
        case .system: L("Theo hệ thống", "Match system")
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        }
    }
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: L("Tự động", "Auto")
        case .light: L("Sáng", "Light")
        case .dark: L("Tối", "Dark")
        }
    }
}

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    var language: Language {
        didSet { defaults.set(language.rawValue, forKey: "language"); Localization.english = usesEnglish }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() }
    }

    var showsMenuBarItem: Bool {
        didSet { defaults.set(showsMenuBarItem, forKey: "showsMenuBarItem") }
    }

    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    var loginItemError: String?

    private init() {
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        showsMenuBarItem = defaults.object(forKey: "showsMenuBarItem") as? Bool ?? true
        Localization.english = usesEnglish
    }

    var usesEnglish: Bool {
        switch language {
        case .vietnamese: false
        case .english: true
        case .system: !(Locale.preferredLanguages.first ?? "").hasPrefix("vi")
        }
    }

    func applyAppearance() {
        NSApp.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func setLaunchesAtLogin(_ on: Bool) {
        loginItemError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginItemError = L("Không bật được: ", "Couldn't change: ") + error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Đọc được từ mọi luồng (quét chạy nền); `Preferences` giữ bản gốc và cập nhật cờ này.
enum Localization {
    nonisolated(unsafe) static var english = false
}

/// Chuỗi hai ngôn ngữ đặt ngay tại chỗ dùng. Trong view, đọc `Preferences.shared.language` để view vẽ lại khi đổi.
func L(_ vietnamese: String, _ english: String) -> String {
    Localization.english ? english : vietnamese
}
