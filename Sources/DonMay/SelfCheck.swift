import Foundation

/// `DonMay --scan-report` in kết quả quét; `DonMay --self-test` thử nén/giải nén và chốt an toàn trong thư mục tạm.
enum SelfCheck {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--scan-report") { scanReport(); exit(0) }
        if args.contains("--self-test") { exit(selfTest() ? 0 : 1) }
    }

    private static func scanReport() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let items = await Scanner.scan { _ in }
            for item in items {
                let growth = item.level == .flat ? "" : " [\(item.level.title) +\(Format.bytes(item.growth7))/7d]"
                print("\(item.app.title.padding(toLength: 14, withPad: " ", startingAt: 0)) \(Format.bytes(item.size).padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.risk.title.padding(toLength: 13, withPad: " ", startingAt: 0)) \(item.undo.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(item.name)\(growth) — \(item.reason)")
            }
            print("Tổng \(items.count) mục · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
            done.signal()
        }
        done.wait()
    }

    private static func selfTest() -> Bool {
        var ok = true
        func expect(_ condition: Bool, _ label: String) {
            print((condition ? "PASS " : "FAIL ") + label)
            ok = ok && condition
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("donmay-selftest-\(UUID().uuidString)")
        let source = root.appendingPathComponent("data")
        try? fm.createDirectory(at: source.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let payload = Data(repeating: 65, count: 300_000)
        try? payload.write(to: source.appendingPathComponent("sub/a.txt"))
        try? "xin chào".write(to: source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("data.aar")
        do {
            let size = try Archiver.archive(directory: source, to: archive)
            expect(size > 0 && size < 300_000, "Nén LZFSE: \(Format.bytes(size)) cho 300 KB")
            try fm.removeItem(at: source)
            try Archiver.extract(archive, into: source)
            expect((try? Data(contentsOf: source.appendingPathComponent("sub/a.txt"))) == payload, "Giải nén khôi phục đúng nội dung tệp lồng")
            expect((try? String(contentsOf: source.appendingPathComponent("b.txt"), encoding: .utf8)) == "xin chào", "Giải nén giữ đúng tệp UTF-8")
        } catch {
            expect(false, "Nén/giải nén ném lỗi: \(error.localizedDescription)")
        }
        try? fm.removeItem(at: root)

        let home = fm.homeDirectoryForCurrentUser.path
        func refused(_ path: String) -> Bool { (try? Safety.check(path)) == nil }
        expect(refused(home), "Từ chối xoá thư mục home")
        expect(refused(home + "/Documents"), "Từ chối xoá cả Documents")
        expect(refused(home + "/Documents/MyProjects/period_pregnancy_company"), "Từ chối xoá mã nguồn dự án")
        expect(refused(home + "/Documents/MyProjects/x/.git"), "Từ chối xoá kho git")
        expect(refused(home + "/Library/Developer"), "Từ chối xoá chính gốc được phép")
        expect(refused(home + "/Downloads/sub/file.dmg"), "Từ chối tệp nằm sâu trong Downloads")
        expect(refused("/System/Library"), "Từ chối đường dẫn hệ thống")
        expect(!refused(home + "/Library/Developer/Xcode/DerivedData/Foo-abc"), "Cho phép DerivedData")
        expect(!refused(home + "/Documents/MyProjects/x/.build"), "Cho phép thư mục .build trong dự án")
        expect(!refused(home + "/Downloads/setup.dmg"), "Cho phép bộ cài ngay trong Downloads")

        let item = CleanItem(id: "t", app: .xcode, name: "t", reason: "", displayPath: "", size: 10 * .gb, lastUsed: nil,
                             risk: .safe, undo: .regenerate, growth24: 0, growth7: 5 * .gb, action: .files([]), regenerateHint: "")
        expect(item.level == .spike, "5 GB mới trên 10 GB là tăng bất thường")
        var steady = item
        steady.growth7 = 200 * .mb
        expect(steady.level == .flat, "200 MB mới trên 10 GB là ổn định")
        let cache = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/donmay-selftest-\(UUID().uuidString)")
        try? fm.createDirectory(at: cache.appendingPathComponent("inner"), withIntermediateDirectories: true)
        try? payload.write(to: cache.appendingPathComponent("inner/data.bin"))
        let packedItem = CleanItem(id: "packed", app: .zen, name: "thử nén", reason: "", displayPath: "", size: 300_000, lastUsed: nil,
                                   risk: .warn, undo: .backup, growth24: 0, growth7: 0, action: .files([cache.path]), regenerateHint: "")
        let done = DispatchSemaphore(value: 0)
        var session: HistorySession?
        Task.detached {
            session = await Cleaner.clean([packedItem], backups: ["packed"]) { _, _ in }
            done.signal()
        }
        done.wait()
        if let entry = session?.entries.first {
            expect(entry.outcome == .packed && !fm.fileExists(atPath: cache.path), "Dọn có sao lưu: xoá bản gốc, giữ bản nén")
            expect(entry.archivePath.map(fm.fileExists(atPath:)) == true, "Bản nén nằm trong khu sao lưu")
            if let restored = try? Cleaner.restore(entry) {
                expect(restored.outcome == .restored && (try? Data(contentsOf: cache.appendingPathComponent("inner/data.bin"))) == payload,
                       "Khôi phục đưa dữ liệu về đúng chỗ cũ")
                expect(entry.archivePath.map(fm.fileExists(atPath:)) == false, "Khôi phục xong thì xoá bản nén")
            } else {
                expect(false, "Khôi phục ném lỗi")
            }
            if let archiveFolder = entry.archivePath.map({ URL(fileURLWithPath: $0).deletingLastPathComponent() }) {
                try? fm.removeItem(at: archiveFolder)
            }
        } else {
            expect(false, "Cleaner không trả về kết quả")
        }
        try? fm.removeItem(at: cache)

        let outside = CleanItem(id: "x", app: .xcode, name: "ngoài", reason: "", displayPath: "", size: 1, lastUsed: nil,
                                risk: .safe, undo: .regenerate, growth24: 0, growth7: 0,
                                action: .files([fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures").path]), regenerateHint: "")
        let refusedDone = DispatchSemaphore(value: 0)
        var refusedSession: HistorySession?
        Task.detached {
            refusedSession = await Cleaner.clean([outside], backups: []) { _, _ in }
            refusedDone.signal()
        }
        refusedDone.wait()
        expect(refusedSession?.entries.first?.outcome == .failed && fm.fileExists(atPath: fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures").path),
               "Cleaner từ chối đường dẫn ngoài danh sách, Pictures còn nguyên")

        let oldArchive = fm.temporaryDirectory.appendingPathComponent("donmay-old-\(UUID().uuidString).aar")
        let freshArchive = fm.temporaryDirectory.appendingPathComponent("donmay-fresh-\(UUID().uuidString).aar")
        fm.createFile(atPath: oldArchive.path, contents: Data([1]))
        fm.createFile(atPath: freshArchive.path, contents: Data([1]))
        func packedEntry(_ path: URL, expires: Date) -> HistoryEntry {
            HistoryEntry(app: .zen, name: "t", paths: ["/x"], size: 1, outcome: .packed, regenerateHint: "",
                         archivePath: path.path, archiveSize: 1, expiresAt: expires)
        }
        var sessions = [
            HistorySession(date: Date().addingTimeInterval(-8 * 86_400), entries: [packedEntry(oldArchive, expires: Date().addingTimeInterval(-86_400))]),
            HistorySession(date: Date(), entries: [packedEntry(freshArchive, expires: Date().addingTimeInterval(7 * 86_400))]),
        ]
        _ = Cleaner.purge(&sessions)
        expect(sessions[0].entries[0].outcome == .expired && !fm.fileExists(atPath: oldArchive.path), "Bản nén hết hạn bị xoá")
        expect(sessions[1].entries[0].outcome == .packed && fm.fileExists(atPath: freshArchive.path),
               "Bản nén vừa tạo được giữ dù ổ đang gần đầy")
        try? fm.removeItem(at: freshArchive)

        expect(ConfirmSheet.matchesConfirmWord("XOÁ") && ConfirmSheet.matchesConfirmWord("xóa") && ConfirmSheet.matchesConfirmWord(" XOA "),
               "Xác nhận chấp nhận XOÁ, xóa, XOA")
        expect(!ConfirmSheet.matchesConfirmWord("xo") && !ConfirmSheet.matchesConfirmWord(""), "Xác nhận từ chối chữ khác")

        let brokenSource = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/donmay-missing-\(UUID().uuidString)")
        let brokenItem = CleanItem(id: "b", app: .zen, name: "nén lỗi", reason: "", displayPath: "", size: 1, lastUsed: nil,
                                   risk: .warn, undo: .backup, growth24: 0, growth7: 0, action: .files([brokenSource.path]), regenerateHint: "")
        let brokenDone = DispatchSemaphore(value: 0)
        var brokenSession: HistorySession?
        Task.detached {
            brokenSession = await Cleaner.clean([brokenItem], backups: ["b"]) { _, _ in }
            brokenDone.signal()
        }
        brokenDone.wait()
        if let session = brokenSession {
            let folder = AppFolders.backups.appendingPathComponent(session.id.uuidString)
            let leftovers = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            expect(session.entries.first?.outcome == .failed && leftovers.isEmpty, "Nén hỏng thì không để lại tệp .aar dở")
            try? fm.removeItem(at: folder)
        }

        print(ok ? "Tất cả đạt" : "Có mục hỏng")
        return ok
    }
}
