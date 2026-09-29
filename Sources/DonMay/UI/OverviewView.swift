import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !state.hasFullDiskAccess { FullDiskAccessHint() }
            disk
            actions
            if !state.growing.isEmpty { growing }
            groups
        }
    }

    // MARK: - Ổ đĩa

    private var disk: some View {
        let total = Double(max(state.diskTotal, 1))
        let safe = state.size(of: .safe), warn = state.size(of: .warn)
        let used = state.diskTotal - state.diskFree
        let nearlyFull = Double(state.diskFree) / total < 0.1
        return VStack(alignment: .leading, spacing: 10) {
            Text(nearlyFull ? "Ổ đĩa gần đầy" : "Dung lượng ổ đĩa").font(.largeTitle.weight(.bold))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.bytes(state.diskFree)).font(.system(size: 36, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(nearlyFull ? Palette.alert : .primary)
                Text("còn trống trên \(Format.bytes(state.diskTotal))").foregroundStyle(.secondary)
            }
            MeterBar(segments: [
                .init(value: Double(safe) / total, color: Palette.safe),
                .init(value: Double(warn) / total, color: Palette.warn),
                .init(value: Double(max(used - safe - warn, 0)) / total, color: Color.secondary.opacity(0.45)),
            ], height: 14)
            HStack(spacing: 18) {
                LegendDot(color: Palette.safe, text: "Dọn an toàn · \(Format.bytes(safe))")
                LegendDot(color: Palette.warn, text: "Cần cân nhắc · \(Format.bytes(warn))")
                LegendDot(color: Color.secondary.opacity(0.45), text: "Hệ thống và dữ liệu của Ngài")
            }
        }
    }

    // MARK: - Ba việc nên làm

    private var actions: some View {
        let safeItems = state.items.filter { $0.risk == .safe }
        let warnItems = state.items.filter { $0.risk == .warn }
        let spikes = state.growing.filter { $0.level == .spike }
        return Grid(horizontalSpacing: 14) {
            GridRow {
                ActionCard(color: Palette.safe, title: "Dọn an toàn", value: Format.bytes(state.size(safeItems)),
                           detail: "Bộ nhớ đệm và dữ liệu build. Công cụ gốc tự tạo lại, Ngài không mất gì.",
                           button: "Chọn \(safeItems.count) mục", prominent: true) { state.selectSafe() }
                ActionCard(color: Palette.alert, title: "Đang phình to", value: "\(spikes.count) chỗ",
                           detail: "Ghi thêm \(Format.bytes(state.growing.reduce(0) { $0 + $1.growth7 })) trong 7 ngày qua.",
                           button: nil, prominent: false) {}
                ActionCard(color: Palette.warn, title: "Cần Ngài quyết", value: Format.bytes(state.size(warnItems)),
                           detail: "Xoá được, nhưng mất thời gian tải lại hoặc mất ít dữ liệu.",
                           button: "Xem \(warnItems.count) mục", prominent: false) {
                    let top = AppKind.allCases.max { state.size(state.items(of: $0).filter { $0.risk == .warn }) < state.size(state.items(of: $1).filter { $0.risk == .warn }) }
                    if let top { state.route = .app(top); state.filter = .warn }
                }
            }
        }
    }

    // MARK: - Đang phình to

    private var growing: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Chỗ đang phình to", hint: "Dung lượng tệp được ghi mới trong 7 ngày qua")
            RowsContainer {
                ForEach(Array(state.growing.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    GrowingRow(item: item)
                }
            }
        }
    }

    // MARK: - Theo nhóm

    private var groups: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Theo nhóm")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(AppKind.allCases) { app in
                    GroupCard(app: app)
                }
            }
        }
    }
}

private struct ActionCard: View {
    let color: Color
    let title: String
    let value: String
    let detail: String
    let button: String?
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 9, height: 9)
                    Text(title).fontWeight(.semibold).foregroundStyle(.secondary)
                }
                Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let button {
                    if prominent {
                        Button(button, action: action).buttonStyle(.borderedProminent).tint(color)
                    } else {
                        Button(button, action: action)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct GrowingRow: View {
    @Environment(AppState.self) private var state
    let item: CleanItem

    var body: some View {
        let color = Palette.color(item.level)
        let newShare = min(Double(item.growth7) / Double(max(item.size, 1)), 1)
        HStack(spacing: 16) {
            AppLogo(app: item.app, size: 36, level: item.level)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                    Text("· \(item.app.title)").foregroundStyle(.secondary).fixedSize()
                }
                Text(item.reason).font(.callout).foregroundStyle(.secondary)
                MeterBar(segments: [.init(value: 1 - newShare, color: Color.secondary.opacity(0.3)),
                                    .init(value: newShare, color: color)], height: 5)
                    .frame(maxWidth: 340)
                    .padding(.top, 4)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("+\(Format.bytes(item.growth7))").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                Text("\(Format.percent(newShare)) là mới").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 120, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(item.size)).font(.title3.weight(.semibold)).monospacedDigit()
                Text("tổng").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .trailing)
            Group {
                if item.risk == .keep {
                    RiskChip(risk: .keep)
                } else if state.selection.contains(item.id) {
                    Button { state.toggle(item) } label: { Label("Đã chọn", systemImage: "checkmark") }
                        .tint(Palette.safe).buttonStyle(.bordered)
                } else {
                    Button("Chọn để dọn") { state.toggle(item) }
                }
            }
            .frame(width: 120, alignment: .trailing)
        }
        .rowSurface()
        .contentShape(Rectangle())
        .onTapGesture { state.detailItem = item }
        .help("Bấm để xem chi tiết")
    }
}

private struct GroupCard: View {
    @Environment(AppState.self) private var state
    let app: AppKind

    var body: some View {
        let list = state.items(of: app)
        let total = Double(max(state.size(list), 1))
        let safe = state.size(list.filter { $0.risk == .safe })
        let warn = state.size(list.filter { $0.risk == .warn })
        let level = state.level(of: app)
        Button {
            state.route = .app(app)
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        AppLogo(app: app, size: 36, level: level)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.title).fontWeight(.semibold)
                            if level == .flat {
                                Text(level.title).font(.caption).foregroundStyle(.secondary)
                            } else {
                                GrowthIcon(level: level, size: 13)
                            }
                        }
                        Spacer()
                        Text(Format.bytes(state.size(list))).font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    MeterBar(segments: [.init(value: Double(safe) / total, color: Palette.safe),
                                        .init(value: Double(warn) / total, color: Palette.warn)], height: 6)
                    HStack(spacing: 14) {
                        Text("An toàn \(Format.bytes(safe))")
                        Text("Cân nhắc \(Format.bytes(warn))")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
