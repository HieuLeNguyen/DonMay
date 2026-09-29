import Foundation
import Observation

enum Route: Hashable {
    case overview, history, performance
    case app(AppKind)
}

@MainActor
@Observable
final class AppState {
    var route: Route = .overview
    var items: [CleanItem] = []
    var isScanning = false
    var scanProgress = 0.0
    var scanFinding: AppKind?
    var scanStep = ""
    var scanPlanned: [AppKind: Int] = [:]
    var scanDone: [AppKind: Int] = [:]
    var scanFound: [AppKind: Int64] = [:]
    var hasFullDiskAccess = Permissions.hasFullDiskAccess
    var detailItem: CleanItem?
    var lastScan: Date?

    var selection = Set<String>()
    /// Mục chỉ dọn một phần: những đường dẫn con được chọn và tổng dung lượng của chúng.
    var partial: [String: PartialChoice] = [:]
    var showingMachineInfo = false
    var backupChoices = Set<String>()
    private var decidedBackups = Set<String>()
    var filter: Risk?
    var query = ""
    var sort: ItemSort = .size

    var history: [HistorySession] = HistoryStore.load()
    var isCleaning = false
    var purgeRemaining = 0
    private var purgeTask: Task<Void, Never>?
    var cleanProgress = 0.0
    var cleanStep = ""
    var confirming = false
    var confirmingTrash = false
    var showingTrash = false
    var notice: String?

    var diskFree = SystemMetrics.diskFree()
    var diskTotal = SystemMetrics.diskTotal()
    var trashSize: Int64?

    var memory = SystemMetrics.memory()
    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var processes: [ProcessSample] = []
    private let cpuMeter = CPUMeter()
    private var metricsTask: Task<Void, Never>?

    init() {
        let dropped = Cleaner.purge(&history)
        if dropped > 0 {
            HistoryStore.save(history)
            notice = "Đã xoá \(dropped) bản nén hết hạn hoặc vượt mức cho phép."
        }
        drainPurge()
    }

    // MARK: - Tổng hợp

    func items(of app: AppKind) -> [CleanItem] { items.filter { $0.app == app } }
    func size(of app: AppKind) -> Int64 { items(of: app).reduce(0) { $0 + $1.size } }
    func size(_ list: [CleanItem]) -> Int64 { list.reduce(0) { $0 + $1.size } }
    func size(of risk: Risk) -> Int64 { size(items.filter { $0.risk == risk }) }

    func level(of app: AppKind) -> GrowthLevel { items(of: app).map(\.level).max() ?? .flat }

    var growing: [CleanItem] {
        items.filter { $0.level != .flat }.sorted { ($0.level, $0.growth7) > ($1.level, $1.growth7) }
    }

    /// Mục sẽ dọn thật: mục chỉ chọn một phần được thay bằng đúng các đường dẫn con đã chọn.
    var selectedItems: [CleanItem] {
        items.filter { selection.contains($0.id) }.map { item in
            guard let choice = partial[item.id] else { return item }
            var part = item
            part.action = .files(choice.paths.sorted())
            part.size = choice.size
            part.name = "\(item.name) · \(choice.paths.count) phần"
            return part
        }
    }

    func choose(_ item: CleanItem, parts: Set<String>?, size: Int64) {
        guard item.risk != .keep else { return }
        if let parts, parts.isEmpty {
            selection.remove(item.id)
            partial[item.id] = nil
            return
        }
        selection.insert(item.id)
        partial[item.id] = parts.map { PartialChoice(paths: $0, size: size) }
    }

    func keepsBackup(_ item: CleanItem) -> Bool { item.undo == .backup && backupChoices.contains(item.id) }

    var selectedKeptSize: Int64 { selectedItems.filter(keepsBackup).reduce(0) { $0 + $1.estimatedPackedSize } }
    var selectedFreedSize: Int64 { size(selectedItems) - selectedKeptSize }

    var archivesInUse: Int64 { history.reduce(0) { $0 + $1.keptArchiveSize } }
    var backupBudget: Int64 { BackupPolicy.budget(free: diskFree) }

    func toggle(_ item: CleanItem) {
        guard item.risk != .keep else { return }
        partial[item.id] = nil
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectSafe(in app: AppKind? = nil) {
        items.filter { $0.risk == .safe && (app == nil || $0.app == app) }.forEach { selection.insert($0.id) }
    }

    func deselect(in app: AppKind) {
        for item in items(of: app) {
            selection.remove(item.id)
            partial[item.id] = nil
        }
    }

    // MARK: - Quét

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        scanFinding = nil
        scanStep = ""
        scanPlanned = [:]
        scanDone = [:]
        scanFound = [:]
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        let found = await Scanner.scan { event in
            Task { @MainActor in self.apply(event) }
        }
        items = found
        let ids = Set(found.map(\.id))
        selection = selection.intersection(Set(found.filter { $0.risk != .keep }.map(\.id)))
        partial = partial.filter { selection.contains($0.key) }
        backupChoices.formIntersection(ids)
        var room = backupBudget - archivesInUse - found.filter { backupChoices.contains($0.id) }.reduce(0) { $0 + $1.estimatedPackedSize }
        for item in found.filter({ $0.undo == .backup && !decidedBackups.contains($0.id) }).sorted(by: { $0.size < $1.size }) {
            decidedBackups.insert(item.id)
            guard item.estimatedPackedSize <= room else { continue }
            room -= item.estimatedPackedSize
            backupChoices.insert(item.id)
        }
        diskFree = SystemMetrics.diskFree()
        trashSize = Cleaner.trashSize()
        lastScan = Date()
        isScanning = false
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case let .finding(app):
            scanFinding = app
            scanStep = "Đang tìm các vị trí của \(app.title)"
        case let .planned(counts):
            scanFinding = nil
            scanPlanned = counts
        case let .measuring(app, name):
            scanStep = "\(app.title) · \(name)"
        case let .measured(app, item):
            scanDone[app, default: 0] += 1
            scanFound[app, default: 0] += item?.size ?? 0
            let total = scanPlanned.values.reduce(0, +)
            scanProgress = total > 0 ? Double(scanDone.values.reduce(0, +)) / Double(total) : 0
        }
    }

    var scanPlannedTotal: Int { scanPlanned.values.reduce(0, +) }
    var scanDoneTotal: Int { scanDone.values.reduce(0, +) }

    // MARK: - Dọn

    func cleanSelected() async {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        confirming = false
        isCleaning = true
        let session = await Cleaner.clean(targets, backups: backupChoices) { value, step in
            Task { @MainActor in
                self.cleanProgress = value
                self.cleanStep = step
            }
        }
        history.insert(session, at: 0)
        _ = Cleaner.purge(&history)
        HistoryStore.save(history)
        selection.removeAll()
        partial.removeAll()
        isCleaning = false
        let failed = session.entries.filter { $0.outcome == .failed }
        notice = "Đã dời \(session.entries.count - failed.count) mục ra khỏi chỗ cũ, đang giải phóng dung lượng ở nền."
            + (failed.isEmpty ? "" : " \(failed.count) mục không dọn được, xem Lịch sử dọn.")
        route = .history
        drainPurge()
        await scan()
    }

    /// Xoá thật những gì đã dời vào thư mục chờ — chạy nền, không chặn thao tác.
    func drainPurge() {
        guard purgeTask == nil, Cleaner.hasPendingPurge else { return }
        let before = SystemMetrics.diskFree()
        purgeRemaining = AppFolders.purge.children().count
        purgeTask = Task {
            let failed = await Cleaner.drainPurge { remaining in
                Task { @MainActor in self.purgeRemaining = remaining }
            }
            purgeRemaining = 0
            purgeTask = nil
            diskFree = SystemMetrics.diskFree()
            let gained = max(diskFree - before, 0)
            notice = "Đã giải phóng \(Format.bytes(gained))."
                + (failed > 0 ? " \(failed) mục chưa xoá được, sẽ thử lại lần mở sau." : "")
        }
    }

    func restore(session: HistorySession.ID, entry: HistoryEntry.ID) {
        update(session, entry) { entry in
            do {
                let restored = try Cleaner.restore(entry)
                notice = "Đã khôi phục \(entry.name)."
                return restored
            } catch {
                notice = error.localizedDescription
                return entry
            }
        }
    }

    func restoreAll(in session: HistorySession.ID) {
        guard let s = history.first(where: { $0.id == session }) else { return }
        for entry in s.entries where entry.outcome == .packed { restore(session: session, entry: entry.id) }
    }

    func dropArchive(session: HistorySession.ID, entry: HistoryEntry.ID) {
        update(session, entry) { Cleaner.dropArchive($0) }
    }

    func dropAllArchives() {
        for s in history.indices {
            for e in history[s].entries.indices where history[s].entries[e].outcome == .packed {
                history[s].entries[e] = Cleaner.dropArchive(history[s].entries[e])
            }
        }
        HistoryStore.save(history)
        diskFree = SystemMetrics.diskFree()
    }

    private func update(_ session: HistorySession.ID, _ entry: HistoryEntry.ID, _ change: (HistoryEntry) -> HistoryEntry) {
        guard let s = history.firstIndex(where: { $0.id == session }),
              let e = history[s].entries.firstIndex(where: { $0.id == entry }) else { return }
        history[s].entries[e] = change(history[s].entries[e])
        HistoryStore.save(history)
        diskFree = SystemMetrics.diskFree()
    }

    func emptyTrash() {
        confirmingTrash = false
        do {
            try Cleaner.emptyTrash()
            trashSize = Cleaner.trashSize()
            diskFree = SystemMetrics.diskFree()
            notice = "Đã dọn Thùng rác."
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Dời vào thư mục chờ rồi xoá ở nền, như khi dọn các mục khác.
    func removeFromTrash(_ paths: [String]) {
        let failed = paths.filter { path in
            (try? Safety.check(path)).flatMap { try? Cleaner.moveToPurge(URL(fileURLWithPath: path)) } == nil
        }
        trashSize = Cleaner.trashSize()
        if !failed.isEmpty { notice = "\(failed.count) mục trong Thùng rác không xoá được." }
        drainPurge()
    }

    // MARK: - Hiệu năng

    func startMetrics() {
        guard metricsTask == nil else { return }
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleMetrics()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func sampleMetrics() {
        memory = SystemMetrics.memory()
        append(&cpuHistory, cpuMeter.sample())
        append(&gpuHistory, SystemMetrics.gpuUtilization() ?? 0)
        append(&memoryHistory, Double(memory.used) / Double(max(memory.total, 1)))
        diskFree = SystemMetrics.diskFree()
        guard route == .performance else { return }
        Task {
            let top = await Task.detached { SystemMetrics.topProcesses() }.value
            processes = top
        }
    }

    private func append(_ series: inout [Double], _ value: Double) {
        series.append(value)
        if series.count > 60 { series.removeFirst(series.count - 60) }
    }
}

enum ItemSort: String, CaseIterable {
    case size, growth, oldest, name

    var title: String {
        switch self {
        case .size: "Dung lượng lớn nhất"
        case .growth: "Tăng nhanh nhất"
        case .oldest: "Lâu chưa dùng nhất"
        case .name: "Tên A–Z"
        }
    }

    func sorted(_ items: [CleanItem]) -> [CleanItem] {
        switch self {
        case .size: items.sorted { $0.size > $1.size }
        case .growth: items.sorted { ($0.growth7, $0.size) > ($1.growth7, $1.size) }
        case .oldest: items.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .name: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}

struct PartialChoice {
    var paths: Set<String>
    var size: Int64
}
