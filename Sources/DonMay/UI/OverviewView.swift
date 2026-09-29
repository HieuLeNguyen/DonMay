import SwiftUI

/// Tổng quan kiểu "Theo dõi": ổ đĩa và nút dọn an toàn, cái gì ghi thêm nhiều nhất trong 7 ngày,
/// từng nhóm đang ra sao, và danh sách cảnh báo bấm vào được.
struct OverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Grid(horizontalSpacing: 20) {
                GridRow {
                    DiskCard().frame(width: 300)
                    GrowthCard()
                }
            }
            HStack(alignment: .top, spacing: 20) {
                GroupGrid()
                AlertList().frame(width: 360)
            }
        }
    }
}

// MARK: - Ổ đĩa

private struct DiskCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let total = Double(max(state.diskTotal, 1))
        let usedRatio = Double(state.diskTotal - state.diskFree) / total
        let low = Double(state.diskFree) / total < 0.1
        let safeItems = state.items.filter { $0.risk == .safe }
        Card {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 16)
                    Circle().trim(from: 0, to: usedRatio)
                        .stroke(low ? Palette.alert : Palette.safe, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(Format.bytes(state.diskFree)).font(.system(size: 28, weight: .bold)).monospacedDigit()
                            .foregroundStyle(low ? Palette.alert : .primary)
                        Text("còn trống").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 170, height: 170)
                Text("\(Format.bytes(state.diskTotal - state.diskFree)) / \(Format.bytes(state.diskTotal)) đã dùng")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Button {
                    state.selectSafe()
                } label: {
                    Text("Chọn dọn an toàn \(Format.bytes(state.size(safeItems)))").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Palette.safe).controlSize(.large)
                .disabled(safeItems.isEmpty)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Ghi mới 7 ngày

private struct GrowthCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let rows = AppKind.allCases
            .map { app in (app, state.items(of: app).reduce(Int64(0)) { $0 + $1.growth7 }, state.level(of: app)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(7)
        let total = state.items.reduce(Int64(0)) { $0 + $1.growth7 }
        let largest = Double(max(rows.first?.1 ?? 1, 1))
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Ghi mới 7 ngày qua").font(.title3.weight(.semibold))
                    Text(Format.bytes(total)).font(.system(size: 24, weight: .bold)).monospacedDigit().foregroundStyle(Palette.warn)
                    Text("theo ngày sửa tệp").font(.callout).foregroundStyle(.secondary)
                }
                if rows.isEmpty {
                    Text("Chưa có vị trí nào được ghi thêm trong 7 ngày.").foregroundStyle(.secondary)
                }
                ForEach(Array(rows), id: \.0) { app, growth, level in
                    Button { state.route = .app(app) } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                AppLogo(app: app, size: 22)
                                Text(app.title).lineLimit(1)
                            }
                            .frame(width: 150, alignment: .leading)
                            MeterBar(segments: [.init(value: Double(growth) / largest, color: barColor(level))], height: 12)
                            HStack(spacing: 4) {
                                GrowthIcon(level: level, size: 10)
                                Text("+\(Format.bytes(growth))").fontWeight(.semibold).monospacedDigit()
                                    .foregroundStyle(barColor(level))
                            }
                            .frame(width: 100, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func barColor(_ level: GrowthLevel) -> Color {
        level == .flat ? Color.secondary : Palette.color(level)
    }
}

// MARK: - Theo nhóm

private struct GroupGrid: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theo nhóm").font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(AppKind.allCases.sorted { state.size(of: $0) > state.size(of: $1) }) { app in
                    GroupCard(app: app)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GroupCard: View {
    @Environment(AppState.self) private var state
    let app: AppKind

    var body: some View {
        let list = state.items(of: app)
        let totalSize = state.size(list)
        let total = Double(max(totalSize, 1))
        let safe = state.size(list.filter { $0.risk == .safe })
        let warn = state.size(list.filter { $0.risk == .warn })
        let level = state.level(of: app)
        Button { state.route = .app(app) } label: {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        AppLogo(app: app, size: 30)
                        Text(app.title).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 0)
                        if level == .flat {
                            Text("Ổn định").font(.caption).foregroundStyle(.secondary)
                        } else {
                            GrowthIcon(level: level, size: 12)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Palette.color(level).opacity(0.15)))
                        }
                    }
                    Text(Format.bytes(totalSize)).font(.title2.weight(.bold)).monospacedDigit()
                    MeterBar(segments: [.init(value: Double(safe) / total, color: Palette.safe),
                                        .init(value: Double(warn) / total, color: Palette.warn)], height: 6)
                    Text("An toàn \(Format.bytes(safe)) · Cân nhắc \(Format.bytes(warn))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cảnh báo

private struct AlertList: View {
    @Environment(AppState.self) private var state

    struct Alert: Identifiable {
        let id: String
        let color: Color
        let title: String
        let body: String
        var item: CleanItem?
        var action: (() -> Void)?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cảnh báo").font(.title3.weight(.semibold))
            let alerts = self.alerts
            if alerts.isEmpty {
                Card { Label("Không có gì đáng lo.", systemImage: "checkmark.circle").foregroundStyle(Palette.safe) }
            }
            ForEach(alerts) { alert in
                Button {
                    if let item = alert.item { state.detailItem = item } else { alert.action?() }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(alert.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.title).fontWeight(.semibold).lineLimit(2)
                            Text(alert.body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if alert.item != nil || alert.action != nil {
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var alerts: [Alert] {
        var list: [Alert] = []
        let total = Double(max(state.diskTotal, 1))
        let safe = state.size(state.items.filter { $0.risk == .safe })
        if Double(state.diskFree) / total < 0.1 {
            list.append(Alert(id: "disk", color: Palette.alert, title: "Ổ đĩa còn \(Format.bytes(state.diskFree))",
                              body: "Xcode có thể không build được. Dọn an toàn lấy lại \(Format.bytes(safe)).",
                              action: { state.selectSafe() }))
        }
        for item in state.growing.prefix(3) {
            list.append(Alert(id: item.id, color: Palette.color(item.level), title: "\(item.name) +\(Format.bytes(item.growth7))",
                              body: "\(Format.percent(min(Double(item.growth7) / Double(max(item.size, 1)), 1))) dung lượng là mới trong 7 ngày. \(item.reason).",
                              item: item))
        }
        if !state.hasFullDiskAccess {
            list.append(Alert(id: "fda", color: Palette.warn, title: "Chưa có Full Disk Access",
                              body: "Đang bỏ qua bản cài lên iPhone thật của Xcode và Thùng rác.",
                              action: { Permissions.openFullDiskAccessSettings() }))
        }
        if let boot = MachineInfoReader.bootTime(), Date().timeIntervalSince(boot) > 7 * 86_400 {
            let days = Int(Date().timeIntervalSince(boot) / 86_400)
            list.append(Alert(id: "uptime", color: Palette.warn, title: "Máy chạy \(days) ngày chưa khởi động lại",
                              body: "Khởi động lại giải phóng bộ nhớ swap và tệp tạm của hệ thống.",
                              action: { state.showingMachineInfo = true }))
        }
        return list
    }
}
