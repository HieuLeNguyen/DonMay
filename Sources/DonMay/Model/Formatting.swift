import Foundation

enum Format {
    static func bytes(_ value: Int64) -> String {
        let v = Double(value)
        if value <= 0 { return "0 B" }
        if value >= .gb { return decimal(v / Double(Int64.gb), digits: 1) + " GB" }
        if value >= .mb { return decimal(v / Double(Int64.mb), digits: 0) + " MB" }
        return decimal(v / Double(Int64.kb), digits: 0) + " KB"
    }

    static func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded()))%" }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1: return L("hôm nay", "today")
        case ..<31: return L("\(days) ngày trước", days == 1 ? "1 day ago" : "\(days) days ago")
        case ..<365: return L("\(days / 30) tháng trước", days / 30 == 1 ? "1 month ago" : "\(days / 30) months ago")
        default: return L("\(days / 365) năm trước", days / 365 == 1 ? "1 year ago" : "\(days / 365) years ago")
        }
    }

    static func dateTime(_ date: Date) -> String {
        (Localization.english ? englishDateTime : vietnameseDateTime).string(from: date)
    }

    private static let vietnameseDateTime = dateFormatter("vi_VN", "dd/MM/yyyy · HH:mm")
    private static let englishDateTime = dateFormatter("en_US", "MMM d, yyyy · HH:mm")

    private static func dateFormatter(_ locale: String, _ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = format
        return formatter
    }

    private static let decimalFormatters: [String: NumberFormatter] = Dictionary(uniqueKeysWithValues: ["vi_VN", "en_US"].flatMap { locale in
        [0, 1].map { digits in (locale + "\(digits)", numberFormatter(locale, digits)) }
    })

    private static func numberFormatter(_ locale: String, _ digits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        decimalFormatters[(Localization.english ? "en_US" : "vi_VN") + "\(digits)"]?.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func abbreviatingHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
