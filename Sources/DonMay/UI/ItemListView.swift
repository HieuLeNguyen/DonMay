import AppKit
import SwiftUI

struct ItemListView: View {
    @Environment(AppState.self) private var state
    let app: AppKind

    var body: some View {
        @Bindable var state = state
        let all = state.items(of: app)
        let rows = all.filter { item in
            (state.filter == nil || item.risk == state.filter)
                && (state.query.isEmpty || item.name.localizedCaseInsensitiveContains(state.query)
                    || item.displayPath.localizedCaseInsensitiveContains(state.query))
        }
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
                    Chip(text: "\(app.title) đang mở · nên thoát trước khi dọn", color: Palette.warn, systemImage: "exclamationmark.triangle.fill")
                }
            }
            HStack(spacing: 10) {
                Picker("Lọc", selection: $state.filter) {
                    Text("Tất cả").tag(Risk?.none)
                    ForEach(Risk.allCases, id: \.self) { Text($0.title).tag(Risk?.some($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)
                TextField("Tìm mục", text: $state.query).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Button("Chọn mục an toàn") { state.selectSafe(in: app) }
            }
            if rows.isEmpty {
                Text(all.isEmpty ? "Không có gì để dọn ở đây." : "Không có mục nào khớp bộ lọc.")
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
                    Button("Hiện trong Finder") { NSWorkspace.shared.selectFile(first, inFileViewerRootedAtPath: "") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.bytes(item.size)).font(.title3.weight(.semibold)).monospacedDigit()
                Text("dùng \(Format.ago(item.lastUsed))").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
            Group {
                if item.level == .flat {
                    Chip(text: "Ổn định", color: .secondary)
                } else {
                    Chip(text: "+\(Format.bytes(item.growth7)) / 7 ngày", color: Palette.color(item.level),
                         systemImage: item.level == .spike ? "chevron.up.2" : "arrow.up")
                }
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                RiskChip(risk: item.risk)
                undo
            }
            .frame(width: 190, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .rowSurface()
        .contentShape(Rectangle())
        .onTapGesture { state.detailItem = item }
        .help("Bấm để xem chi tiết. Tick ô bên trái để chọn dọn.")
    }

    @ViewBuilder
    private var undo: some View {
        if item.risk == .keep {
            Text("Không dọn").font(.caption).foregroundStyle(.secondary)
        } else {
            switch item.undo {
            case .regenerate:
                Text("Xoá hẳn · tự tạo lại").font(.caption).foregroundStyle(.secondary)
            case .irreversible:
                Text("Không hoàn tác được").font(.caption).foregroundStyle(Palette.alert)
            case .backup:
                Toggle(isOn: Binding(get: { state.backupChoices.contains(item.id) },
                                     set: { keep in
                                         if keep { state.backupChoices.insert(item.id) } else { state.backupChoices.remove(item.id) }
                                     })) {
                    Text("Sao lưu nén (~\(Format.bytes(item.estimatedPackedSize)))").font(.caption)
                }
                .toggleStyle(.checkbox)
                if item.estimatedPackedSize > state.backupBudget - state.archivesInUse {
                    Text("Vượt mức sao lưu cho phép").font(.caption).foregroundStyle(Palette.alert)
                }
            }
        }
    }
}
