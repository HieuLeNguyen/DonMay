import Charts
import SwiftUI

/// Tổng quan kiểu "Theo dõi": ổ đĩa và nút dọn an toàn, cái gì ghi thêm nhiều nhất trong 7 ngày,
/// từng nhóm đang ra sao, và danh sách cảnh báo bấm vào được.
struct OverviewView: View {
    @Environment(AppState.self) private var state
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Grid(horizontalSpacing: 20) {
                GridRow {
                    DiskCard().frame(width: 300).entrance(appeared, order: 0)
                    GrowthCard().entrance(appeared, order: 1)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                GroupGrid()
                AlertList().frame(width: 360)
            }
        }
        .environment(\.overviewAppeared, appeared)
        .onAppear { appeared = true }
    }
}

private extension EnvironmentValues {
    @Entry var overviewAppeared = false
}

private extension View {
    func entrance(_ appeared: Bool, order: Int) -> some View {
        modifier(Entrance(appeared: appeared, delay: Double(order) * 0.06))
    }

    func hoverLift() -> some View {
        modifier(HoverLift())
    }
}

private struct Entrance: ViewModifier {
    let appeared: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .blur(radius: appeared || reduceMotion ? 0 : 4)
            .animation(.smooth(duration: 0.45).delay(reduceMotion ? 0 : delay), value: appeared)
    }
}

private struct HoverLift: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 10, y: 4)
            .animation(.snappy(duration: 0.2), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Ổ đĩa

/// Biểu đồ tròn cơ cấu ổ đĩa: phần dọn được nằm ngay cạnh phần còn trống, nên nhìn là thấy dọn xong ổ rộng ra bao nhiêu.
private struct DiskCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.overviewAppeared) private var appeared

    private struct Slice: Identifiable {
        let id: String
        let title: String
        let value: Int64
        let color: Color
    }

    var body: some View {
        let safe = state.size(of: .safe), warn = state.size(of: .warn)
        let used = state.diskTotal - state.diskFree
        let low = Double(state.diskFree) / Double(max(state.diskTotal, 1)) < 0.1
        let slices = [
            Slice(id: "free", title: L("Còn trống", "Free"), value: state.diskFree, color: low ? Palette.alert : Palette.accent),
            Slice(id: "safe", title: L("Dọn an toàn", "Safe to clean"), value: safe, color: Palette.safe),
            Slice(id: "warn", title: L("Cần cân nhắc", "Review first"), value: warn, color: Palette.warn),
            Slice(id: "other", title: L("Hệ thống và dữ liệu", "System and data"), value: max(used - safe - warn, 0), color: Palette.other),
        ]
        let sweep = appeared ? 1.0 : 0.0
        let shown = slices.map { max(Double($0.value), Double(state.diskTotal) * 0.004) }
        let rest = Slice(id: "rest", title: "", value: 0, color: .clear)
        Card {
            VStack(spacing: 14) {
                ZStack {
                    Chart(Array(zip(slices, shown)) + [(rest, shown.reduce(0, +) * (1 - sweep))], id: \.0.id) { slice, value in
                        SectorMark(angle: .value(slice.title, value * (slice.id == "rest" ? 1 : sweep)),
                                   innerRadius: .ratio(0.72), angularInset: slice.id == "rest" ? 0 : 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(slice.color)
                    }
                    .chartLegend(.hidden)
                    .animation(.smooth(duration: 0.8).delay(0.1), value: appeared)
                    VStack(spacing: 2) {
                        Text(Format.bytes(state.diskFree)).font(.system(size: 24, weight: .bold)).monospacedDigit()
                            .foregroundStyle(low ? Palette.alert : .primary)
                            .contentTransition(.numericText())
                            .animation(.smooth, value: state.diskFree)
                        Text(L("còn trống", "free")).font(.caption).foregroundStyle(.secondary)
                    }
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .animation(.smooth(duration: 0.45).delay(0.35), value: appeared)
                }
                .frame(width: 168, height: 168)
                VStack(spacing: 6) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(slice.color).frame(width: 10, height: 10)
                            Text(slice.title).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.bytes(slice.value)).monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.smooth, value: slice.value)
                        }
                        .font(.callout)
                    }
                }
                Button {
                    state.selectSafe()
                } label: {
                    Text(L("Chọn dọn an toàn \(Format.bytes(safe))", "Select safe items · \(Format.bytes(safe))")).fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.large)
                .disabled(safe == 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Ghi mới 7 ngày

private struct GrowthCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.overviewAppeared) private var appeared

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
                    Text(L("Ghi mới 7 ngày qua", "Written in the last 7 days")).font(.title3.weight(.semibold))
                    Text(Format.bytes(total)).font(.system(size: 24, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.smooth, value: total)
                    Text(L("theo ngày sửa tệp", "by file modification date")).font(.callout).foregroundStyle(.secondary)
                }
                if rows.isEmpty {
                    Text(L("Chưa có vị trí nào được ghi thêm trong 7 ngày.", "Nothing has grown in the last 7 days.")).foregroundStyle(.secondary)
                }
                ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                    let (app, growth, level) = row
                    Button { state.route = .app(app) } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                AppLogo(app: app, size: 22)
                                Text(app.title).lineLimit(1)
                            }
                            .frame(width: 150, alignment: .leading)
                            MeterBar(segments: [.init(value: Double(growth) / largest, color: Palette.accent.opacity(level == .flat ? 0.35 : 0.85))], height: 8,
                                     fill: appeared ? 1 : 0)
                                .animation(.smooth(duration: 0.6).delay(0.2 + Double(index) * 0.05), value: appeared)
                            HStack(spacing: 5) {
                                GrowthIcon(level: level, size: 10)
                                Text("+\(Format.bytes(growth))").fontWeight(.medium).monospacedDigit()
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
}

// MARK: - Theo nhóm

private struct GroupGrid: View {
    @Environment(AppState.self) private var state
    @Environment(\.overviewAppeared) private var appeared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Theo nhóm", "By group")).font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                let apps = AppKind.allCases.filter { state.size(of: $0) > 0 }.sorted { state.size(of: $0) > state.size(of: $1) }
                ForEach(Array(apps.enumerated()), id: \.element) { index, app in
                    GroupCard(app: app)
                        .hoverLift()
                        .entrance(appeared, order: 2 + min(index, 8))
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
                        GrowthIcon(level: level, size: 12)
                    }
                    Text(Format.bytes(totalSize)).font(.title2.weight(.bold)).monospacedDigit()
                    MeterBar(segments: [.init(value: Double(safe) / total, color: Palette.safe),
                                        .init(value: Double(warn) / total, color: Palette.warn)], height: 4)
                    Text(L("An toàn \(Format.bytes(safe)) · Cân nhắc \(Format.bytes(warn))", "Safe \(Format.bytes(safe)) · Review \(Format.bytes(warn))"))
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
    @Environment(\.overviewAppeared) private var appeared

    struct Alert: Identifiable {
        let id: String
        let color: Color
        let symbol: String
        let title: String
        let body: String
        var item: CleanItem?
        var action: (() -> Void)?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Cảnh báo", "Alerts")).font(.title3.weight(.semibold))
            let alerts = self.alerts
            if alerts.isEmpty {
                Card { Label(L("Không có gì đáng lo.", "Nothing to worry about."), systemImage: "checkmark.circle").foregroundStyle(Palette.safe) }
            }
            ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                Button {
                    if let item = alert.item { state.detailItem = item } else { alert.action?() }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: alert.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(alert.color)
                            .frame(width: 18).padding(.top, 2)
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
                .hoverLift()
                .entrance(appeared, order: 3 + index)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.smooth(duration: 0.35), value: alerts.map(\.id))
    }

    private var alerts: [Alert] {
        var list: [Alert] = []
        let total = Double(max(state.diskTotal, 1))
        let safe = state.size(state.items.filter { $0.risk == .safe })
        if Double(state.diskFree) / total < 0.1 {
            list.append(Alert(id: "disk", color: Palette.alert, symbol: "externaldrive.fill.badge.exclamationmark", title: L("Ổ đĩa còn \(Format.bytes(state.diskFree))", "Only \(Format.bytes(state.diskFree)) free"),
                              body: L("Xcode có thể không build được. Dọn an toàn lấy lại \(Format.bytes(safe)).", "Xcode may fail to build. Safe cleaning frees \(Format.bytes(safe))."),
                              action: { state.selectSafe() }))
        }
        for item in state.growing.prefix(3) {
            list.append(Alert(id: item.id, color: Palette.color(item.level), symbol: item.level.symbol, title: "\(item.name) +\(Format.bytes(item.growth7))",
                              body: L("\(Format.percent(min(Double(item.growth7) / Double(max(item.size, 1)), 1))) dung lượng là mới trong 7 ngày. \(item.reason).", "\(Format.percent(min(Double(item.growth7) / Double(max(item.size, 1)), 1))) of its size was written in the last 7 days. \(item.reason)."),
                              item: item))
        }
        if !state.hasFullDiskAccess {
            list.append(Alert(id: "fda", color: .secondary, symbol: "lock.shield", title: L("Chưa có Full Disk Access", "No Full Disk Access"),
                              body: L("Đang bỏ qua bản cài lên iPhone thật của Xcode và Thùng rác.", "Skipping Xcode's device install files and the Trash."),
                              action: { Permissions.openFullDiskAccessSettings() }))
        }
        if let boot = MachineInfoReader.bootTime(), Date().timeIntervalSince(boot) > 7 * 86_400 {
            let days = Int(Date().timeIntervalSince(boot) / 86_400)
            list.append(Alert(id: "uptime", color: .secondary, symbol: "clock.arrow.circlepath", title: L("Máy chạy \(days) ngày chưa khởi động lại", "Running \(days) days without a restart"),
                              body: L("Khởi động lại giải phóng bộ nhớ swap và tệp tạm của hệ thống.", "Restarting frees swap and system temporary files."),
                              action: { state.showingMachineInfo = true }))
        }
        return list
    }
}
