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
    var lastScan: Date?

    var selection = Set<String>()
    var backupChoices = Set<String>()
    var filter: Risk?
    var query = ""

    var history: [HistorySession] = HistoryStore.load()
    var isCleaning = false
    var cleanProgress = 0.0
    var cleanStep = ""
    var confirming = false
    var confirmingTrash = false
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

    var selectedItems: [CleanItem] { items.filter { selection.contains($0.id) } }

    func keepsBackup(_ item: CleanItem) -> Bool { item.undo == .backup && backupChoices.contains(item.id) }

    var selectedKeptSize: Int64 { selectedItems.filter(keepsBackup).reduce(0) { $0 + $1.estimatedPackedSize } }
    var selectedFreedSize: Int64 { size(selectedItems) - selectedKeptSize }

    var archivesInUse: Int64 { history.reduce(0) { $0 + $1.keptArchiveSize } }
    var backupBudget: Int64 { BackupPolicy.budget(free: diskFree) }

    func toggle(_ item: CleanItem) {
        guard item.risk != .keep else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectSafe(in app: AppKind? = nil) {
        items.filter { $0.risk == .safe && (app == nil || $0.app == app) }.forEach { selection.insert($0.id) }
    }

    // MARK: - Quét

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        let found = await Scanner.scan { value in
            Task { @MainActor in self.scanProgress = value }
        }
        items = found
        let ids = Set(found.map(\.id))
        selection.formIntersection(ids)
        var room = backupBudget - archivesInUse
        backupChoices = Set(found.filter { $0.undo == .backup }.sorted { $0.size < $1.size }.compactMap { item in
            guard item.estimatedPackedSize <= room else { return nil }
            room -= item.estimatedPackedSize
            return item.id
        })
        diskFree = SystemMetrics.diskFree()
        trashSize = Cleaner.trashSize()
        lastScan = Date()
        isScanning = false
    }

    // MARK: - Dọn

    func cleanSelected() async {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        confirming = false
        isCleaning = true
        let before = SystemMetrics.diskFree()
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
        isCleaning = false
        let failed = session.entries.filter { $0.outcome == .failed }
        let gained = SystemMetrics.diskFree() - before
        notice = "Đã lấy lại \(Format.bytes(max(gained, 0)))." + (failed.isEmpty ? "" : " \(failed.count) mục không dọn được, xem Lịch sử dọn.")
        route = .history
        await scan()
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
