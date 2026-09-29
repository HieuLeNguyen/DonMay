import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

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
                    Label(state.isScanning ? "Đang quét…" : "Quét lại", systemImage: "arrow.clockwise")
                }
                .disabled(state.isScanning || state.isCleaning)
            }
        }
        .navigationTitle("Dọn Máy")
        .navigationSubtitle(state.lastScan.map { "Quét lúc \(Format.dateTime($0))" } ?? "")
        .sheet(isPresented: $state.confirming) { ConfirmSheet() }
        .confirmationDialog("Dọn Thùng rác?", isPresented: $state.confirmingTrash) {
            Button("Dọn Thùng rác", role: .destructive) { state.emptyTrash() }
        } message: {
            Text("Mọi thứ trong Thùng rác bị xoá hẳn, không hoàn tác được. Bản nén trong Lịch sử dọn không bị ảnh hưởng.")
        }
        .overlay {
            if state.isCleaning { CleaningView() }
        }
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
            Button("Đóng", action: close).buttonStyle(.borderless)
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
    }
}

struct ScanningView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: state.scanProgress).frame(width: 280)
            Text("Đang đo dung lượng từng vị trí…").foregroundStyle(.secondary)
            Text("Nếu macOS hỏi quyền truy cập Desktop, Documents hoặc Downloads, hãy bấm Cho phép. Việc quét chờ tới khi Ngài trả lời.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

struct CleaningView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: state.cleanProgress).frame(width: 320)
            Text(state.cleanStep.isEmpty ? "Đang dọn…" : "Đang dọn: \(state.cleanStep)")
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25))
    }
}

struct BottomBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Lấy lại").foregroundStyle(.secondary)
                    Text(Format.bytes(state.selectedFreedSize)).font(.title2.weight(.semibold)).monospacedDigit()
                    if !state.selection.isEmpty { Text("· \(state.selection.count) mục").foregroundStyle(.secondary) }
                }
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Bỏ chọn") { state.selection.removeAll() }
                .disabled(state.selection.isEmpty)
            Button("Dọn các mục đã chọn") { state.confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(Palette.safe)
                .controlSize(.large)
                .disabled(state.selection.isEmpty || state.isCleaning || state.isScanning)
        }
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var note: String {
        let items = state.selectedItems
        guard !items.isEmpty else { return "Chọn mục để dọn." }
        let warn = items.filter { $0.risk == .warn }.count
        let irreversible = items.filter { $0.undo == .irreversible }.count
        let parts = [
            state.selectedKeptSize > 0 ? "Giữ bản nén \(Format.bytes(state.selectedKeptSize))" : nil,
            warn > 0 ? "\(warn) mục cần cân nhắc" : nil,
            irreversible > 0 ? "\(irreversible) mục không hoàn tác được" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "Toàn bộ là mục an toàn." : parts.joined(separator: " · ")
    }
}
