import Foundation

/// Danh sách vị trí được phép dọn. Công cụ chỉ đụng tới những gì các hàm dưới đây liệt kê.
enum Rules {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var library: URL { home.under("Library") }

    static func all() -> [Candidate] {
        xcode() + simulator() + claude() + zen() + figma() + pencil() + cli() + documents() + desktop() + downloads()
    }

    // MARK: - Xcode

    static func xcode() -> [Candidate] {
        var list: [Candidate] = []
        let developer = library.under("Developer", "Xcode")

        let deltas = library.under("Containers", "com.apple.CoreDevice.CoreDeviceService", "Data", "Library", "Caches",
                                   "AppInstallationBinaryDeltas")
        if deltas.exists {
            list.append(.fixed(.xcode, "Bản cài lên iPhone thật", deltas, .safe,
                               "Xcode tự tạo lại ở lần Run lên máy thật kế tiếp"))
        }

        for dir in developer.under("DerivedData").children() where dir.isDirectory {
            list.append(derivedData(dir))
        }

        let supports = developer.under("iOS DeviceSupport").children().filter(\.isDirectory)
        let newestMajor = supports.compactMap(iOSMajor).max() ?? 0
        for dir in supports {
            let label = dir.lastPathComponent.components(separatedBy: " (").first ?? dir.lastPathComponent
            let outdated = (iOSMajor(dir) ?? newestMajor) < newestMajor
            list.append(Candidate(app: .xcode, name: "Hỗ trợ máy thật · \(label)", urls: [dir],
                                  regenerateHint: "Cắm lại máy, Xcode tải lại") { m in
                if outdated { return (.safe, "Phiên bản iOS cũ. Cắm lại máy thì Xcode tải lại") }
                let recent = (m.lastModified ?? dir.modificationDate ?? .distantPast) > Date().addingTimeInterval(-60 * 86_400)
                return recent ? (.warn, "Máy dùng để debug gần đây. Tải lại mất 5–10 phút")
                              : (.safe, "Hơn 60 ngày chưa dùng. Cắm lại máy thì Xcode tải lại")
            })
        }

        let archives = developer.under("Archives")
        if archives.exists {
            list.append(.fixed(.xcode, "Archives", archives, .keep, "Chứa dSYM để đọc crash log của bản đã phát hành"))
        }
        for (name, url, hint) in [
            ("Gói Swift đã tải (SwiftPM)", library.under("Caches", "org.swift.swiftpm"), "Xcode tải lại khi resolve package"),
            ("Bộ nhớ đệm Xcode", library.under("Caches", "com.apple.dt.Xcode"), "Tự tạo lại"),
        ] where url.exists {
            list.append(.fixed(.xcode, name, url, .safe, hint))
        }
        return list
    }

    /// "iPhone13,2 26.6.2 (23G90)" → 26
    private static func iOSMajor(_ dir: URL) -> Int? {
        let parts = dir.lastPathComponent.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1].split(separator: ".").first ?? "")
    }

    private static func derivedData(_ dir: URL) -> Candidate {
        let folder = dir.lastPathComponent
        if folder.hasSuffix(".noindex") {
            let name = folder.replacingOccurrences(of: ".noindex", with: "")
            return .fixed(.xcode, name, dir, .safe, "Tự tạo lại khi build")
        }
        let project = folder.components(separatedBy: "-").dropLast().joined(separator: "-")
        let info = NSDictionary(contentsOf: dir.under("info.plist"))
        let workspace = info?["WorkspacePath"] as? String
        let lastAccess = info?["LastAccessedDate"] as? Date
        let workspaceGone = workspace.map { !FileManager.default.fileExists(atPath: $0) } ?? false
        let displayName = workspace.map { "DerivedData · \(project) (\(URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent))" }
            ?? "DerivedData · \(project)"
        return Candidate(app: .xcode, name: displayName, urls: [dir], regenerateHint: "Build lại trong Xcode",
                         lastUsed: lastAccess) { m in
            if workspaceGone { return (.safe, "Thư mục dự án không còn trên máy") }
            let used = lastAccess ?? m.lastModified ?? .distantPast
            if used > Date().addingTimeInterval(-2 * 86_400) {
                return (.warn, "Dự án đang mở. Lần build sau sẽ chạy lại từ đầu")
            }
            return (.safe, "Tự tạo lại khi build")
        }
    }

    // MARK: - Simulator

    private struct DeviceList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let isAvailable: Bool
            let dataPath: String?
            let lastBootedAt: String?
        }
        let devices: [String: [Device]]
    }

    private struct Runtime: Decodable {
        let identifier: String
        let version: String
        let runtimeIdentifier: String
        let sizeBytes: Int64?
        let deletable: Bool?
        let lastUsedAt: String?
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-1" → "iOS 26.1"
    private static func runtimeLabel(_ identifier: String) -> String {
        let tail = identifier.components(separatedBy: "SimRuntime.").last ?? identifier
        let parts = tail.split(separator: "-")
        guard let platform = parts.first else { return tail }
        return platform + " " + parts.dropFirst().joined(separator: ".")
    }

    static func simulator() -> [Candidate] {
        var list: [Candidate] = []
        let iso = ISO8601DateFormatter()
        var runtimesInUse = Set<String>()

        if let data = try? Shell.xcrun(["simctl", "list", "devices", "-j"]),
           let parsed = try? JSONDecoder().decode(DeviceList.self, from: data) {
            for (runtime, devices) in parsed.devices {
                for device in devices {
                    runtimesInUse.insert(runtime)
                    let folder = library.under("Developer", "CoreSimulator", "Devices", device.udid)
                    guard folder.exists else { continue }
                    let booted = device.state == "Booted"
                    let version = runtimeLabel(runtime)
                    list.append(Candidate(app: .simulator, name: "Máy ảo \(device.name) · \(version)", urls: [folder],
                                          undo: .irreversible, regenerateHint: "Tạo lại máy ảo trong Xcode",
                                          action: .simulatorDevice(udid: device.udid),
                                          lastUsed: device.lastBootedAt.flatMap(iso.date(from:)),
                                          id: "sim:\(device.udid)") { m in
                        if !device.isAvailable { return (.safe, "Runtime đã gỡ, máy ảo không chạy được nữa") }
                        if booted { return (.warn, "Đang chạy. Mất mọi ứng dụng và dữ liệu cài trong máy ảo") }
                        return (.warn, "Mất mọi ứng dụng và dữ liệu cài trong máy ảo")
                    })
                }
            }
        }

        if let data = try? Shell.xcrun(["simctl", "runtime", "list", "-j"]),
           let parsed = try? JSONDecoder().decode([String: Runtime].self, from: data) {
            for runtime in parsed.values where runtime.deletable != false {
                let used = runtimesInUse.contains(runtime.runtimeIdentifier)
                list.append(Candidate(app: .simulator, name: "Runtime iOS \(runtime.version)",
                                      urls: [URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes")],
                                      undo: .irreversible, regenerateHint: "Tải lại trong Xcode › Settings › Components",
                                      action: .simulatorRuntime(identifier: runtime.identifier),
                                      knownSize: runtime.sizeBytes ?? 0,
                                      lastUsed: runtime.lastUsedAt.flatMap(iso.date(from:)),
                                      id: "runtime:\(runtime.identifier)") { _ in
                    used ? (.keep, "Có máy ảo đang dùng runtime này")
                         : (.warn, "Không máy ảo nào dùng. Tải lại mất vài GB")
                })
            }
        }

        let caches = library.under("Developer", "CoreSimulator", "Caches")
        if caches.exists { list.append(.fixed(.simulator, "Bộ nhớ đệm Simulator", caches, .safe, "Tự tạo lại")) }
        return list
    }

    // MARK: - Claude

    private struct JobState: Decodable {
        let state: String?
        let name: String?
        let updatedAt: String?
    }

    private static func shortened(_ text: String, limit: Int = 48) -> String {
        let line = text.components(separatedBy: .newlines).first ?? text
        return line.count > limit ? String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    static func claude() -> [Candidate] {
        var list: [Candidate] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for job in home.under(".claude", "jobs").children() where job.isDirectory {
            let state = (try? Data(contentsOf: job.under("state.json"))).flatMap { try? JSONDecoder().decode(JobState.self, from: $0) }
            let updated = state?.updatedAt.flatMap(iso.date(from:))
            let title = state?.name.map { "Job \(job.lastPathComponent) · \(shortened($0))" } ?? "Job \(job.lastPathComponent)"
            list.append(Candidate(app: .claude, name: title, urls: [job], regenerateHint: "Job đã xong, không cần tạo lại",
                                  lastUsed: updated) { m in
                let recent = (updated ?? m.lastModified ?? .distantPast) > Date().addingTimeInterval(-30 * 60)
                switch state?.state {
                case "working", "active", "running":
                    return (.warn, "Job đang chạy. Chỉ xoá khi job đã xong")
                case "blocked", "waiting":
                    return (.warn, "Job đang chờ Ngài trả lời")
                default:
                    return recent ? (.warn, "Job vừa chạy trong 30 phút qua") : (.safe, "Job đã kết thúc")
                }
            })
        }

        let projects = home.under(".claude", "projects")
        if projects.exists {
            list.append(.fixed(.claude, "Bản ghi hội thoại", projects, .keep, "Cần để resume phiên cũ", undo: .backup))
        }
        let desktop = library.under("Application Support", "Claude")
        let vm = desktop.under("vm_bundles")
        if vm.exists {
            list.append(.fixed(.claude, "Máy ảo của Claude Desktop", vm, .warn,
                               "Claude tải lại khoảng 10 GB khi dùng chế độ agent"))
        }
        let caches = ["Cache", "Code Cache", "GPUCache"].map { desktop.under($0) }.filter(\.exists)
        if !caches.isEmpty {
            list.append(Candidate(app: .claude, name: "Bộ nhớ đệm Claude Desktop", urls: caches,
                                  regenerateHint: "Tự tạo lại") { _ in (.safe, "Tự tạo lại") })
        }
        return list
    }

    // MARK: - Trình duyệt và công cụ thiết kế

    static func zen() -> [Candidate] {
        var list: [Candidate] = []
        let cache = library.under("Caches", "zen")
        if cache.exists { list.append(.fixed(.zen, "Bộ nhớ đệm trang", cache, .safe, "Tự tạo lại. Nên đóng Zen trước")) }
        for profile in library.under("Application Support", "zen", "Profiles").children() where profile.isDirectory {
            let label = profile.lastPathComponent.components(separatedBy: ".").dropFirst().joined(separator: ".")
            let storage = profile.under("storage")
            if storage.exists {
                list.append(.fixed(.zen, "Dữ liệu trang web · \(label)", storage, .warn,
                                   "Có thể bị đăng xuất khỏi các trang web", undo: .backup))
            }
            let places = profile.under("places.sqlite")
            if places.exists {
                list.append(.fixed(.zen, "Lịch sử và dấu trang · \(label)", places, .keep, "Lịch sử duyệt web và dấu trang"))
            }
        }
        return list
    }

    static func figma() -> [Candidate] {
        let root = library.under("Application Support", "Figma", "DesktopProfile")
        let versions = root.children().filter { $0.lastPathComponent.hasPrefix("v") && $0.isDirectory }
            .sorted { (Int($0.lastPathComponent.dropFirst()) ?? 0) < (Int($1.lastPathComponent.dropFirst()) ?? 0) }
        guard let latest = versions.last else { return [] }
        var list: [Candidate] = []
        let hint = "Figma tải lại khi mở file. Nên đóng Figma trước"
        if latest.under("Cache").exists { list.append(.fixed(.figma, "Bộ nhớ đệm file thiết kế", latest.under("Cache"), .safe, hint)) }
        let code = ["Code Cache", "GPUCache", "DawnWebGPUCache"].map { latest.under($0) }.filter(\.exists)
        if !code.isEmpty {
            list.append(Candidate(app: .figma, name: "Bộ nhớ đệm mã và GPU", urls: code, regenerateHint: "Tự tạo lại") { _ in (.safe, "Tự tạo lại") })
        }
        let old = versions.dropLast()
        if !old.isEmpty {
            list.append(Candidate(app: .figma, name: "Hồ sơ phiên bản cũ \(old.map(\.lastPathComponent).joined(separator: ", "))",
                                  urls: Array(old), regenerateHint: "Không cần") { _ in
                (.safe, "Figma đã chuyển sang \(latest.lastPathComponent)")
            })
        }
        return list
    }

    static func pencil() -> [Candidate] {
        var list: [Candidate] = []
        let support = library.under("Application Support", "Pencil")
        let caches = ["Cache", "Code Cache", "GPUCache", "DawnWebGPUCache", "DawnGraphiteCache"].map { support.under($0) }.filter(\.exists)
            + [library.under("Caches", "dev.pencil.desktop")].filter(\.exists)
        if !caches.isEmpty {
            list.append(Candidate(app: .pencil, name: "Bộ nhớ đệm", urls: caches, regenerateHint: "Tự tạo lại") { _ in
                (.safe, "Tự tạo lại. Nên đóng Pencil trước")
            })
        }
        let sessions = home.under(".pencil", "claude-sessions")
        if sessions.exists {
            list.append(.fixed(.pencil, "Phiên Claude trong Pencil", sessions, .warn,
                               "Mất lịch sử trò chuyện với Claude trong Pencil", undo: .backup))
        }
        let backup = home.under(".pencil", "backup")
        if backup.exists { list.append(.fixed(.pencil, "Bản sao lưu file .pen", backup, .keep, "Bản sao lưu thiết kế")) }
        return list
    }

    static func cli() -> [Candidate] {
        [
            ("Bộ nhớ đệm npm", home.under(".npm"), Risk.safe, "npm install tải lại"),
            ("Homebrew", library.under("Caches", "Homebrew"), .safe, "brew tải lại khi cài"),
            ("CocoaPods", library.under("Caches", "CocoaPods"), .safe, "pod install tải lại"),
            ("Firebase emulator", home.under(".cache", "firebase"), .safe, "Emulator tải lại khi chạy"),
            ("Codex runtimes", home.under(".cache", "codex-runtimes"), .warn, "Codex CLI tải lại khi chạy"),
            ("Gradle", home.under(".gradle", "caches"), .safe, "Gradle tải lại khi build"),
        ].filter { $0.1.exists }.map { .fixed(.cli, $0.0, $0.1, $0.2, $0.3) }
    }

    // MARK: - Thư mục

    private static let buildFolders: Set<String> = ["build", ".build", "node_modules", "DerivedData", "Pods", ".dart_tool", ".gradle"]

    static func documents() -> [Candidate] {
        guard let root = AppKind.documents.folder else { return [] }
        var found: [URL] = []

        func walk(_ dir: URL, depth: Int) {
            guard depth <= 4 else { return }
            for child in dir.children() where child.isDirectory {
                let name = child.lastPathComponent
                if buildFolders.contains(name) { found.append(child); continue }
                if name == ".git" || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcassets") { continue }
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)

        return found.map { folder in
            let project = folder.deletingLastPathComponent()
            let tracked = isTrackedByGit(folder)
            let projectActive = (project.modificationDate ?? .distantPast) > Date().addingTimeInterval(-7 * 86_400)
            return Candidate(app: .documents, name: "\(folder.lastPathComponent) · \(project.lastPathComponent)", urls: [folder],
                             regenerateHint: "Build lại hoặc cài lại gói trong dự án") { m in
                if tracked { return (.keep, "Có tệp được git theo dõi, có thể là mã nguồn chứ không phải sản phẩm build") }
                let recent = projectActive || (m.lastModified ?? .distantPast) > Date().addingTimeInterval(-7 * 86_400)
                return recent ? (.warn, "Dự án đang làm. Tạo lại được nhưng mất thời gian")
                              : (.safe, "Sản phẩm build, tạo lại được")
            }
        }
    }

    private static func isTrackedByGit(_ folder: URL) -> Bool {
        let data = try? Shell.run("/usr/bin/git", ["-C", folder.deletingLastPathComponent().path, "ls-files", "--", folder.lastPathComponent])
        return !(data ?? Data()).isEmpty
    }

    private static let screenshotPrefixes = ["Screenshot", "Screen Shot", "Ảnh màn hình", "Bản ghi màn hình", "Screen Recording", "Simulator Screen"]

    static func desktop() -> [Candidate] {
        guard let root = AppKind.desktop.folder else { return [] }
        let monthAgo = Date().addingTimeInterval(-30 * 86_400)
        let files = root.children().filter { !$0.isDirectory && !$0.lastPathComponent.hasPrefix(".") }
        let shots = files.filter { url in screenshotPrefixes.contains { url.lastPathComponent.hasPrefix($0) } }
        let oldShots = shots.filter { ($0.modificationDate ?? .distantFuture) < monthAgo }
        var list: [Candidate] = []
        if !oldShots.isEmpty {
            list.append(Candidate(app: .desktop, name: "\(oldShots.count) ảnh chụp và bản ghi màn hình cũ hơn 30 ngày",
                                  urls: oldShots, regenerateHint: "Không tạo lại được", id: "desktop:oldshots") { _ in
                (.warn, "Xem lại trước nếu cần giữ ảnh nào")
            })
        }
        let large = files.filter { !oldShots.contains($0) && FileSizer.measure($0).size >= 200 * .mb }
        list += large.map { .fixed(.desktop, $0.lastPathComponent, $0, .warn, "Tệp lớn trên Desktop", hint: "Không tạo lại được") }
        return list
    }

    static func downloads() -> [Candidate] {
        guard let root = AppKind.downloads.folder else { return [] }
        let files = root.children().filter { !$0.isDirectory && !$0.lastPathComponent.hasPrefix(".") }
        var list: [Candidate] = []

        let installers = files.filter { ["dmg", "pkg", "xip", "mpkg"].contains($0.pathExtension.lowercased()) }
        if !installers.isEmpty {
            list.append(Candidate(app: .downloads, name: "\(installers.count) bộ cài (.dmg, .pkg, .xip)", urls: installers,
                                  regenerateHint: "Tải lại từ trang gốc", id: "downloads:installers") { _ in
                (.safe, "Bộ cài thường không cần sau khi đã cài")
            })
        }

        let duplicates = DuplicateFinder.duplicates(in: files.filter { !installers.contains($0) })
        if !duplicates.isEmpty {
            list.append(Candidate(app: .downloads, name: "\(duplicates.count) bản tải trùng", urls: duplicates,
                                  regenerateHint: "Bản gốc cũ nhất vẫn giữ lại", id: "downloads:duplicates") { _ in
                (.safe, "Trùng nội dung với một tệp khác trong Downloads. Giữ bản cũ nhất")
            })
        }

        let quarterAgo = Date().addingTimeInterval(-90 * 86_400)
        let old = files.filter { !installers.contains($0) && !duplicates.contains($0) && ($0.modificationDate ?? .distantFuture) < quarterAgo }
        if !old.isEmpty {
            list.append(Candidate(app: .downloads, name: "\(old.count) tệp cũ hơn 90 ngày", urls: old,
                                  regenerateHint: "Không tạo lại được", id: "downloads:old") { _ in
                (.warn, "Xem lại trước nếu cần giữ tệp nào")
            })
        }
        return list
    }
}
