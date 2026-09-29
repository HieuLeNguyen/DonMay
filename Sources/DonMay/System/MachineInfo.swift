import Foundation

struct MachineInfo {
    var modelName = "Mac"
    var modelIdentifier = ""
    var chip = ""
    var memory = ""
    var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var bootTime: Date?
    var lastShutdown: Date?
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var updates = UpdateInfo()

    var uptime: TimeInterval? { bootTime.map { Date().timeIntervalSince($0) } }
}

/// Trạng thái Cập nhật phần mềm của macOS: có tự tải / tự cài không, và đã tải gì về máy.
struct UpdateInfo {
    var automaticDownload: Bool?
    var automaticInstallMacOS: Bool?
    var lastCheck: Date?
    var pending: [String] = []
    var downloadedSize: Int64 = 0
    var installers: [(name: String, size: Int64)] = []
}

enum MachineInfoReader {
    static func read() -> MachineInfo {
        var info = MachineInfo()
        if let data = try? Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"]),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hardware = (json["SPHardwareDataType"] as? [[String: Any]])?.first {
            info.modelName = hardware["machine_name"] as? String ?? info.modelName
            info.modelIdentifier = hardware["machine_model"] as? String ?? ""
            info.chip = hardware["chip_type"] as? String ?? hardware["cpu_type"] as? String ?? ""
            info.memory = hardware["physical_memory"] as? String ?? ""
        }
        if let data = try? Shell.run("/usr/bin/sw_vers", []), let text = String(data: data, encoding: .utf8) {
            let fields = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line -> (String, String)? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            })
            info.osVersion = "macOS \(fields["ProductVersion"] ?? "")\(fields["ProductVersionExtra"].map { " \($0)" } ?? "") (\(fields["BuildVersion"] ?? ""))"
        }
        info.bootTime = bootTime()
        info.lastShutdown = lastShutdown(before: info.bootTime)
        info.diskTotal = SystemMetrics.diskTotal()
        info.diskFree = SystemMetrics.diskFree()
        info.updates = updates()
        return info
    }

    static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }

    /// `last shutdown` không in năm: lấy lần gần nhất trước lúc khởi động, lùi một năm nếu rơi vào tương lai.
    private static func lastShutdown(before boot: Date?) -> Date? {
        guard let data = try? Shell.run("/usr/bin/last", ["shutdown"]), let text = String(data: data, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("shutdown") }) else { return nil }
        // Bỏ thứ trong tuần: DateFormatter từ chối "Fri 18 Sep" vì năm mặc định 2000 khiến ngày 18/09 không phải thứ Sáu.
        let stamp = line.split(separator: " ", omittingEmptySubsequences: true).suffix(3).joined(separator: " ")
        let parsed = ["d MMM HH:mm", "MMM d HH:mm"].lazy.compactMap { pattern -> Date? in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter.date(from: stamp)
        }.first
        guard let parsed else { return nil }
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
        parts.year = calendar.component(.year, from: Date())
        guard var date = calendar.date(from: parts) else { return nil }
        if date > (boot ?? Date()) { date = calendar.date(byAdding: .year, value: -1, to: date) ?? date }
        return date
    }

    static func updates() -> UpdateInfo {
        var info = UpdateInfo()
        let prefs = UserDefaults(suiteName: "/Library/Preferences/com.apple.SoftwareUpdate")
        info.automaticDownload = prefs?.object(forKey: "AutomaticDownload").map { ($0 as? NSNumber)?.boolValue ?? false }
        info.automaticInstallMacOS = prefs?.object(forKey: "AutomaticallyInstallMacOSUpdates").map { ($0 as? NSNumber)?.boolValue ?? false }
        info.lastCheck = prefs?.object(forKey: "LastSuccessfulDate") as? Date
        info.pending = (prefs?.array(forKey: "RecommendedUpdates") as? [[String: Any]] ?? [])
            .compactMap { $0["Display Name"] as? String }
        info.downloadedSize = updateDownloadLocations.reduce(0) { $0 + FileSizer.measure(URL(fileURLWithPath: $1)).size }
        info.installers = installers().map { ($0.deletingPathExtension().lastPathComponent, FileSizer.measure($0).size) }
        return info
    }

    static let updateDownloadLocations = [
        "/Library/Updates",
        "/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate",
        "/System/Library/AssetsV2/com_apple_MobileAsset_SoftwareUpdate",
    ]

    static func installers() -> [URL] {
        let apps = URL(fileURLWithPath: "/Applications")
        return apps.children().filter { $0.lastPathComponent.hasPrefix("Install macOS") && $0.pathExtension == "app" }
    }
}
