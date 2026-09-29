import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            VStack(spacing: 0) {
                if let notice = state.notice {
                    NoticeBar(text: notice) { state.notice = nil }
                }
                if state.isCleaning || state.purgeRemaining > 0 {
                    CleanBanner()
                } else if state.isScanning && !state.items.isEmpty {
                    ScanBanner()
                }
                ScrollView {
                    Group {
                        switch state.route {
                        case .overview: OverviewView()
                        case .history: HistoryView()
                        case .performance: PerformanceView()
                        case let .app(app): ItemListView(app: app)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 1100, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay {
                    if state.items.isEmpty && state.isScanning { ScanningView() }
                }
                BottomBar()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await state.scan() }
                } label: {
                    Label(state.isScanning ? L("Đang quét…", "Scanning…") : L("Quét lại", "Rescan"), systemImage: "arrow.clockwise")
                }
                .disabled(state.isScanning || state.isCleaning)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { openSettings() } label: {
                    Label(L("Cài đặt", "Settings"), systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Dọn Máy")
        .navigationSubtitle(state.lastScan.map { L("Quét lúc \(Format.dateTime($0))", "Scanned \(Format.dateTime($0))") } ?? "")
        .sheet(isPresented: $state.confirming) { ConfirmSheet() }
        .sheet(item: $state.detailItem) { item in ItemDetailSheet(item: item) }
        .sheet(isPresented: $state.showingMachineInfo) { MachineInfoSheet() }
        .sheet(isPresented: $state.showingTrash) { TrashSheet() }
        .confirmationDialog(L("Dọn Thùng rác?", "Empty Trash?"), isPresented: $state.confirmingTrash) {
            Button(L("Dọn Thùng rác", "Empty Trash"), role: .destructive) { state.emptyTrash() }
        } message: {
            Text(L("Mọi thứ trong Thùng rác bị xoá hẳn, không hoàn tác được. Bản nén trong Lịch sử dọn không bị ảnh hưởng.", "Everything in the Trash is permanently deleted and can't be undone. Backups in Cleanup History aren't affected."))
        }
        .id(Preferences.shared.language)
        .task {
            state.startMetrics()
            await state.scan()
        }
    }
}

struct NoticeBar: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
            Text(text)
            Spacer()
            Button(L("Đóng", "Close"), action: close).buttonStyle(.borderless)
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
    }
}

/// Dọn không chặn thao tác: dải mảnh ở đầu màn, vừa lúc dời mục vừa lúc xoá thật ở nền.
struct CleanBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(state.isCleaning
                 ? (state.cleanStep.isEmpty ? L("Đang dọn…", "Cleaning…") : L("Đang dọn · \(state.cleanStep)", "Cleaning · \(state.cleanStep)"))
                 : L("Đang giải phóng dung lượng ở nền · còn \(state.purgeRemaining) mục", "Freeing space in the background · \(state.purgeRemaining) left"))
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if state.isCleaning {
                ProgressView(value: state.cleanProgress).frame(width: 180)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(Palette.accent.opacity(0.08))
    }
}

struct BottomBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L("Lấy lại", "Reclaim")).foregroundStyle(.secondary)
                    Text(Format.bytes(state.selectedFreedSize)).font(.title2.weight(.semibold)).monospacedDigit()
                    if !state.selection.isEmpty { Text(L("· \(state.selection.count) mục", "· \(state.selection.count) items")).foregroundStyle(.secondary) }
                }
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Bỏ chọn", "Deselect")) { state.selection.removeAll() }
                .disabled(state.selection.isEmpty)
            Button(L("Dọn các mục đã chọn", "Clean Selected")) { state.confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .controlSize(.large)
                .disabled(cannotClean)
                .opacity(cannotClean ? 0.45 : 1)
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var cannotClean: Bool { state.selection.isEmpty || state.isCleaning || state.isScanning }

    private var note: String {
        let items = state.selectedItems
        guard !items.isEmpty else { return L("Chọn mục để dọn.", "Select items to clean.") }
        let warn = items.filter { $0.risk == .warn }.count
        let irreversible = items.filter { $0.undo == .irreversible }.count
        let parts = [
            state.selectedKeptSize > 0 ? L("Giữ bản nén \(Format.bytes(state.selectedKeptSize))", "Keeps \(Format.bytes(state.selectedKeptSize)) of backups") : nil,
            warn > 0 ? L("\(warn) mục cần cân nhắc", "\(warn) need review") : nil,
            irreversible > 0 ? L("\(irreversible) mục không hoàn tác được", "\(irreversible) can't be undone") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? L("Toàn bộ là mục an toàn.", "All items are safe.") : parts.joined(separator: " · ")
    }
}
