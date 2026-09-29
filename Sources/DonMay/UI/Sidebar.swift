import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            Button { state.showingMachineInfo = true } label: {
                HStack(spacing: 10) {
                    if let logo = Brand.logo { Image(nsImage: logo).resizable().frame(width: 34, height: 34) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Dọn Máy").font(.headline)
                        Text("Thông tin máy này").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Xem phiên bản máy, dung lượng, thời gian chạy và cập nhật macOS")
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
            List(selection: Binding(get: { state.route }, set: { if let r = $0 { state.route = r; state.filter = nil; state.query = "" } })) {
                Section {
                    Label("Tổng quan", systemImage: "chart.pie").tag(Route.overview)
                    HStack {
                        Label("Lịch sử dọn", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        if state.archivesInUse > 0 { size(state.archivesInUse) }
                    }
                    .tag(Route.history)
                    Label("Hiệu năng", systemImage: "waveform.path.ecg").tag(Route.performance)
                }
                ForEach(AppGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(AppKind.allCases.filter { $0.group == group }) { app in
                            HStack(spacing: 8) {
                                AppLogo(app: app, size: 20)
                                Text(app.title)
                                if state.level(of: app) == .spike {
                                    Circle().fill(Palette.alert).frame(width: 7, height: 7).help(GrowthLevel.spike.title)
                                }
                                Spacer()
                                size(state.size(of: app))
                            }
                            .tag(Route.app(app))
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            TrashCard()
                .padding(12)
        }
    }

    private func size(_ value: Int64) -> some View {
        Text(Format.bytes(value)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
}

struct TrashCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(named: state.trashSize == 0 ? NSImage.trashEmptyName : NSImage.trashFullName) ?? NSImage())
                    .resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thùng rác").fontWeight(.semibold)
                    Text(state.trashSize.map(Format.bytes) ?? "Cần quyền Full Disk Access để đo")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Dọn Thùng rác") { state.confirmingTrash = true }
                .frame(maxWidth: .infinity)
                .disabled(state.trashSize == 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}
