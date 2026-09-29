import Foundation

/// Danh sách vị trí được phép dọn. Công cụ chỉ đụng tới những gì các hàm dưới đây liệt kê.
enum Rules {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var library: URL { home.under("Library") }

    static func all(finding: (AppKind) -> Void = { _ in }) -> [Candidate] {
        let groups: [(AppKind, () -> [Candidate])] = [
            (.xcode, xcode), (.simulator, simulator), (.claude, claude), (.codex, codex), (.zen, zen), (.figma, figma),
            (.pencil, pencil), (.homebrew, homebrew), (.cli, cli), (.notes, notes), (.documents, documents),
            (.desktop, desktop), (.downloads, downloads), (.macos, macos), (.updates, updates),
        ]
        return groups.flatMap { app, rule in
            finding(app)
            return rule()
        }
    }

    // MARK: - Xcode

    static func xcode() -> [Candidate] {
        var list: [Candidate] = []
        let developer = library.under("Developer", "Xcode")

        let deltas = library.under("Containers", "com.apple.CoreDevice.CoreDeviceService", "Data", "Library", "Caches",
                                   "AppInstallationBinaryDeltas")
        if Permissions.hasFullDiskAccess, deltas.exists {
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
            let scratch = job.under("tmp")
            guard scratch.exists else { continue }
            list.append(Candidate(app: .claude, name: title + " · dữ liệu tạm", urls: [scratch],
                                  regenerateHint: "Chỉ xoá thư mục tmp, job vẫn còn trong danh sách của Claude",
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

        for project in home.under(".claude", "projects").children() where project.isDirectory {
            list.append(Candidate(app: .claude, name: "Hội thoại · \(projectName(project.lastPathComponent))", urls: [project],
                                  undo: .backup, regenerateHint: "Không resume được các phiên đã xoá") { m in
                conversationRisk(m)
            })
        }
        let fileHistory = home.under(".claude", "file-history")
        if fileHistory.exists {
            list.append(.fixed(.claude, "Lịch sử sửa tệp", fileHistory, .warn, "Mất khả năng rewind các lần Claude sửa tệp ở phiên cũ"))
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

    /// Phiên sửa trong 30 ngày qua còn hay được resume; cũ hơn thì hiếm khi cần.
    private static func conversationRisk(_ m: Measurement) -> (Risk, String) {
        (m.lastModified ?? .distantPast) > Date().addingTimeInterval(-30 * 86_400)
            ? (.warn, "Có phiên trong 30 ngày qua, xoá thì không resume được")
            : (.safe, "Hơn 30 ngày không đụng tới")
    }

    /// "-Users-an-Documents-blood-pressure" → "blood-pressure": dò từng đoạn xem thư mục nào có thật,
    /// vì tên thư mục dự án cũng có thể chứa dấu gạch.
    static func projectName(_ encoded: String) -> String {
        let tokens = encoded.split(separator: "-", omittingEmptySubsequences: false).dropFirst().map(String.init)
        var path = URL(fileURLWithPath: "/")
        var pending: [String] = []
        for token in tokens {
            pending.append(token)
            let candidate = path.appendingPathComponent(pending.joined(separator: "-"))
            if candidate.isDirectory {
                path = candidate
                pending = []
            }
        }
        if !pending.isEmpty { return pending.joined(separator: "-") }
        return path.path == home.path ? "Thư mục nhà" : path.lastPathComponent
    }

    // MARK: - Codex

    static func codex() -> [Candidate] {
        var list: [Candidate] = []
        let root = home.under(".codex")
        for year in root.under("sessions").children() where year.isDirectory {
            for month in year.children() where month.isDirectory {
                list.append(Candidate(app: .codex, name: "Phiên hội thoại · \(month.lastPathComponent)/\(year.lastPathComponent)",
                                      urls: [month], undo: .backup, regenerateHint: "Không resume được các phiên đã xoá") { m in
                    conversationRisk(m)
                })
            }
        }
        let archived = root.under("archived_sessions")
        if archived.exists {
            list.append(.fixed(.codex, "Phiên đã lưu trữ", archived, .safe, "Phiên Ngài đã lưu trữ trong Codex", undo: .backup))
        }
        let logs = ["logs_2.sqlite", "logs_2.sqlite-wal", "logs_2.sqlite-shm", "log"].map { root.under($0) }.filter(\.exists)
        if !logs.isEmpty {
            list.append(Candidate(app: .codex, name: "Nhật ký", urls: logs, regenerateHint: "Codex ghi lại từ đầu") { _ in
                (.safe, "Chỉ dùng để gỡ lỗi. Nên thoát Codex trước")
            })
        }
        for (name, url, risk, reason) in [
            ("Runtime", home.under(".cache", "codex-runtimes"), Risk.warn, "Codex tải lại khi chạy"),
            ("Shell snapshot", root.under("shell_snapshots"), .safe, "Tự tạo lại"),
            ("Computer use", root.under("computer-use"), .warn, "Codex tải lại khi dùng computer use"),
            ("Plugin đã cài", root.under("plugins"), .keep, "Plugin Ngài đã cài vào Codex"),
        ] where url.exists {
            list.append(.fixed(.codex, name, url, risk, reason))
        }
        return list
    }

    // MARK: - Homebrew

    private static let brewPrefix = URL(fileURLWithPath: FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")

    static func homebrew() -> [Candidate] {
        var list: [Candidate] = []
        let cache = library.under("Caches", "Homebrew")
        if cache.exists { list.append(.fixed(.homebrew, "Bộ nhớ đệm tải về", cache, .safe, "brew tải lại khi cài hoặc nâng cấp")) }

        let old = oldKegs(in: brewPrefix.under("Cellar")) + oldKegs(in: brewPrefix.under("Caskroom"))
        if !old.isEmpty {
            list.append(Candidate(app: .homebrew, name: "\(old.count) phiên bản gói cũ", urls: old,
                                  regenerateHint: "brew install lại phiên bản cũ nếu cần", id: "homebrew:old") { _ in
                (.safe, "Đã có bản mới hơn, giống việc brew cleanup làm")
            })
        }
        let cellar = brewPrefix.under("Cellar")
        if cellar.exists { list.append(.fixed(.homebrew, "Gói đang cài", cellar, .keep, "Gỡ bằng brew uninstall, không xoá tay")) }
        return list
    }

    /// Mỗi gói giữ bản đang được liên kết trong opt/ (hoặc bản mới nhất); các bản còn lại là bản cũ.
    private static func oldKegs(in root: URL) -> [URL] {
        root.children().filter(\.isDirectory).flatMap { formula -> [URL] in
            let versions = formula.children().filter { $0.isDirectory && !$0.lastPathComponent.hasPrefix(".") }
            guard versions.count > 1 else { return [] }
            let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: brewPrefix.under("opt", formula.lastPathComponent).path))
                .map { URL(fileURLWithPath: $0, relativeTo: brewPrefix.under("opt")).standardizedFileURL.lastPathComponent }
            let current = linked ?? versions.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }?.lastPathComponent
            return versions.filter { $0.lastPathComponent != current }
        }
    }

    // MARK: - Ghi chú

    static func notes() -> [Candidate] {
        let root = library.under("Group Containers", "group.com.apple.notes")
        guard Permissions.hasFullDiskAccess, root.exists else { return [] }
        let media = ["Accounts", "Media"].map { root.under($0) }.filter(\.exists)
        let store = ["NoteStore.sqlite", "NoteStore.sqlite-wal"].map { root.under($0) }.filter(\.exists)
        var list: [Candidate] = []
        if !store.isEmpty {
            list.append(Candidate(app: .notes, name: "Nội dung ghi chú", urls: store, id: "notes:store") { _ in
                (.keep, "Dữ liệu gốc của Ghi chú. Chỉ theo dõi dung lượng")
            })
        }
        if !media.isEmpty {
            list.append(Candidate(app: .notes, name: "Ảnh và tệp đính kèm", urls: media, id: "notes:media") { _ in
                (.keep, "Xoá ghi chú có đính kèm lớn ngay trong ứng dụng Ghi chú")
            })
        }
        return list
    }

    // MARK: - Bản cập nhật ứng dụng

    static func updates() -> [Candidate] {
        let caches = library.under("Caches")
        let markers = [".ShipIt", "-updater", ".Sparkle", "GoogleUpdater", "SoftwareUpdate"]
        return caches.children().filter { url in
            url.isDirectory && markers.contains { url.lastPathComponent.localizedCaseInsensitiveContains($0) }
        }
        .map { url in
            let name = url.lastPathComponent
                .replacingOccurrences(of: ".ShipIt", with: "").replacingOccurrences(of: "-updater", with: "")
            return .fixed(.updates, "Bản cập nhật · \(name)", url, .safe,
                          "Bản cập nhật đã tải sẵn. Ứng dụng tải lại khi cần", hint: "Ứng dụng tải lại khi kiểm tra cập nhật")
        }
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
            ("CocoaPods", library.under("Caches", "CocoaPods"), .safe, "pod install tải lại"),
            ("Firebase emulator", home.under(".cache", "firebase"), .safe, "Emulator tải lại khi chạy"),
            ("Gradle", home.under(".gradle", "caches"), .safe, "Gradle tải lại khi build"),
        ].filter { $0.1.exists }.map { .fixed(.cli, $0.0, $0.1, $0.2, $0.3) }
    }

    // MARK: - Cập nhật macOS

    static func macos() -> [Candidate] {
        var list = MachineInfoReader.installers().map {
            Candidate.fixed(.macos, $0.deletingPathExtension().lastPathComponent, $0, .warn,
                            "Bộ cài macOS đầy đủ. Tải lại được từ App Store", hint: "Tải lại từ App Store")
        }
        let downloads = MachineInfoReader.updateDownloadLocations.map(URL.init(fileURLWithPath:)).filter(\.exists)
        if !downloads.isEmpty {
            list.append(Candidate(app: .macos, name: "Bản cập nhật macOS đã tải sẵn", urls: downloads,
                                  regenerateHint: "macOS tải lại khi cần", id: "macos:updates") { _ in
                (.keep, "Thư mục của hệ thống, cần quyền quản trị. Tắt Tự tải trong Cài đặt › Cập nhật phần mềm")
            })
        }
        return list
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

    /// "Xcode_26.1.xip", "Figma-124.3.dmg" → có "Xcode.app", "Figma.app" trong /Applications.
    private static func isInstalled(_ installer: URL) -> Bool {
        let stem = installer.deletingPathExtension().lastPathComponent.lowercased()
        let token = stem.split(whereSeparator: { "_- .".contains($0) || $0.isNumber }).first.map(String.init) ?? stem
        guard token.count >= 3 else { return false }
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        return apps.contains { $0.lowercased().hasPrefix(token) && $0.hasSuffix(".app") }
    }

    static func downloads() -> [Candidate] {
        guard let root = AppKind.downloads.folder else { return [] }
        let files = root.children().filter { !$0.isDirectory && !$0.lastPathComponent.hasPrefix(".") }
        var list: [Candidate] = []

        let installers = files.filter { ["dmg", "pkg", "xip", "mpkg"].contains($0.pathExtension.lowercased()) }
        let installed = installers.filter(isInstalled)
        let pending = installers.filter { !installed.contains($0) }
        if !installed.isEmpty {
            list.append(Candidate(app: .downloads, name: "\(installed.count) bộ cài đã cài xong", urls: installed,
                                  regenerateHint: "Tải lại từ trang gốc", id: "downloads:installed") { _ in
                (.safe, "Ứng dụng tương ứng đã có trong Applications")
            })
        }
        if !pending.isEmpty {
            list.append(Candidate(app: .downloads, name: "\(pending.count) bộ cài chưa thấy ứng dụng tương ứng", urls: pending,
                                  regenerateHint: "Tải lại từ trang gốc nếu còn", id: "downloads:pending") { _ in
                (.warn, "Có thể là bản duy nhất của phần mềm Ngài đã mua")
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
