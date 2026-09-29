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
        case ..<1: return "hôm nay"
        case ..<31: return "\(days) ngày trước"
        case ..<365: return "\(days / 30) tháng trước"
        default: return "\(days / 365) năm trước"
        }
    }

    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy · HH:mm"
        return formatter
    }()

    private static func decimal(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func abbreviatingHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
