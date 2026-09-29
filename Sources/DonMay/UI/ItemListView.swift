import AppKit
import SwiftUI

struct ItemListView: View {
    @Environment(AppState.self) private var state
    let app: AppKind

    var body: some View {
        @Bindable var state = state
        let all = state.items(of: app)
        let rows = state.sort.sorted(all.filter { item in
            (state.filter == nil || item.risk == state.filter)
                && (state.query.isEmpty || item.name.localizedCaseInsensitiveContains(state.query)
                    || item.displayPath.localizedCaseInsensitiveContains(state.query))
        })
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AppLogo(app: app, size: 44, level: state.level(of: app))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(app.title) · \(Format.bytes(state.size(all)))").font(.largeTitle.weight(.bold))
                    Text(app.detail).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                ForEach(Risk.allCases, id: \.self) { risk in
                    LegendDot(color: Palette.color(risk), text: "\(risk.title) \(Format.bytes(state.size(all.filter { $0.risk == risk })))")
                }
                if AppIcons.isRunning(app) && app.shouldQuitBeforeCleaning {
                    Chip(text: L("\(app.title) đang mở · nên thoát trước khi dọn", "\(app.title) is open · quit it before cleaning"), color: Palette.warn, systemImage: "exclamationmark.triangle.fill")
                }
            }
            HStack(spacing: 10) {
                Picker(L("Lọc", "Filter"), selection: $state.filter) {
                    Text(L("Tất cả", "All")).tag(Risk?.none)
                    ForEach(Risk.allCases, id: \.self) { Text($0.title).tag(Risk?.some($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)
                Picker(L("Sắp xếp", "Sort"), selection: $state.sort) {
                    ForEach(ItemSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                TextField(L("Tìm mục", "Search items"), text: $state.query).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Button(L("Chọn mục an toàn", "Select Safe Items")) { state.selectSafe(in: app) }
                Button(L("Bỏ chọn trong mục này", "Deselect All Here")) { state.deselect(in: app) }
                    .disabled(!all.contains { state.selection.contains($0.id) })
            }
            if rows.isEmpty {
                Text(all.isEmpty ? L("Không có gì để dọn ở đây.", "Nothing to clean here.") : L("Không có mục nào khớp bộ lọc.", "No items match the filter."))
                    .foregroundStyle(.secondary).rowSurface()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RowsContainer {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        ItemRow(item: item)
                    }
                }
            }
        }
    }
}

private struct ItemRow: View {
    @Environment(AppState.self) private var state
    let item: CleanItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Toggle("", isOn: Binding(get: { state.selection.contains(item.id) }, set: { _ in state.toggle(item) }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(item.risk == .keep)
            AppLogo(app: item.app, size: 36, level: item.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).fontWeight(.semibold).lineLimit(2)
                Text(item.reason).font(.callout).foregroundStyle(.secondary)
                Text(item.displayPath).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    .help(item.displayPath)
            }
            .contextMenu {
                if case let .files(paths) = item.action, let first = paths.first {
                    Button(L("Hiện trong Finder", "Show in Finder")) { NSWorkspace.shared.selectFile(first, inFileViewerRootedAtPath: "") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(item.size)).font(.title3.weight(.semibold)).monospacedDigit()
                Text(L("dùng \(Format.ago(item.lastUsed))", "used \(Format.ago(item.lastUsed))")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
            Group {
                if item.level == .flat {
                    Chip(text: L("Ổn định", "Stable"), color: .secondary)
                } else {
                    Chip(text: L("+\(Format.bytes(item.growth7)) / 7 ngày", "+\(Format.bytes(item.growth7)) / 7 days"), color: Palette.color(item.level),
                         systemImage: item.level.symbol)
                }
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                RiskChip(risk: item.risk)
                if let choice = state.partial[item.id] {
                    Chip(text: L("Dọn \(choice.paths.count) phần · \(Format.bytes(choice.size))", "Clean \(choice.paths.count) parts · \(Format.bytes(choice.size))"), color: Palette.safe, systemImage: "checklist")
                }
                undo
            }
            .frame(width: 190, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .rowSurface()
        .contentShape(Rectangle())
        .onTapGesture { state.detailItem = item }
        .help(L("Bấm để xem chi tiết. Tick ô bên trái để chọn dọn.", "Click for details. Tick the box on the left to select for cleaning."))
    }

    @ViewBuilder
    private var undo: some View {
        if item.risk == .keep {
            Text(L("Không dọn", "Not cleaned")).font(.caption).foregroundStyle(.secondary)
        } else {
            switch item.undo {
            case .regenerate:
                Text(L("Xoá hẳn · tự tạo lại", "Deleted · regenerates")).font(.caption).foregroundStyle(.secondary)
            case .irreversible:
                Text(L("Không hoàn tác được", "Can't be undone")).font(.caption).foregroundStyle(Palette.alert)
            case .backup:
                Toggle(isOn: Binding(get: { state.backupChoices.contains(item.id) },
                                     set: { keep in
                                         if keep { state.backupChoices.insert(item.id) } else { state.backupChoices.remove(item.id) }
                                     })) {
                    Text(L("Sao lưu nén (~\(Format.bytes(item.estimatedPackedSize)))", "Compressed backup (~\(Format.bytes(item.estimatedPackedSize)))")).font(.caption)
                }
                .toggleStyle(.checkbox)
                if item.estimatedPackedSize > state.backupBudget - state.archivesInUse {
                    Text(L("Vượt mức sao lưu cho phép", "Exceeds backup allowance")).font(.caption).foregroundStyle(Palette.alert)
                }
            }
        }
    }
}
