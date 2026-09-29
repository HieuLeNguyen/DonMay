import AppKit
import SwiftUI

/// Chi tiết một mục: vì sao xếp mức này, dọn thì mất gì, và chọn đúng những phần bên trong muốn dọn.
struct ItemDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let item: CleanItem
    @State private var parts: [Part]?
    @State private var checked = Set<String>()

    struct Part: Identifiable {
        var id: String { path }
        let name: String
        let path: String
        let size: Int64
        let modified: Date?
    }

    private var canPick: Bool { item.risk != .keep && item.undo != .irreversible && !item.paths.isEmpty }
    private var checkedSize: Int64 { (parts ?? []).filter { checked.contains($0.path) }.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            facts
            Divider()
            breakdown
            footer
        }
        .padding(24)
        .frame(width: 680)
        .frame(minHeight: 600, alignment: .top)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppLogo(app: item.app, size: 48, level: item.level)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.title2.weight(.bold)).lineLimit(2)
                HStack(spacing: 8) {
                    Text(item.app.title).foregroundStyle(.secondary)
                    RiskChip(risk: item.risk)
                    GrowthIcon(level: item.level, size: 15)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(item.size)).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text(item.paths.count == 1 ? Format.abbreviatingHome(item.paths[0]) : item.displayPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 260, alignment: .trailing)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            row("Vì sao", item.reason)
            row("Ghi mới", "+\(Format.bytes(item.growth24)) trong 24 giờ · +\(Format.bytes(item.growth7)) trong 7 ngày")
            row("Dùng lần cuối", item.lastUsed.map { "\(Format.dateTime($0)) (\(Format.ago($0)))" } ?? "Không rõ")
            row("Khi dọn", undoText)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var undoText: String {
        if item.risk == .keep { return "Công cụ không dọn mục này." }
        switch item.undo {
        case .regenerate: return "Xoá hẳn, không giữ bản sao. \(item.regenerateHint)."
        case .irreversible: return "Xoá bằng xcrun simctl. Không hoàn tác được, phải gõ XOÁ để xác nhận."
        case .backup:
            return state.backupChoices.contains(item.id)
                ? "Nén thành ~\(Format.bytes(item.estimatedPackedSize)) rồi mới xoá. Khôi phục được trong \(BackupPolicy.keepDays) ngày."
                : "Xoá không sao lưu (ô Sao lưu nén đang tắt)."
        }
    }

    // MARK: - Từng phần bên trong

    @ViewBuilder
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(canPick ? "Chọn phần muốn dọn" : "Chiếm nhiều nhất bên trong").font(.headline)
                if let parts, canPick, !parts.isEmpty {
                    Text("\(checked.count)/\(parts.count) phần · \(Format.bytes(checkedSize))")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Chọn tất cả") { checked = Set(parts.map(\.path)) }.disabled(checked.count == parts.count)
                    Button("Bỏ chọn tất cả") { checked.removeAll() }.disabled(checked.isEmpty)
                }
            }
            if let parts {
                if parts.isEmpty {
                    Text(item.undo == .irreversible ? "Máy ảo và runtime được xoá nguyên cả khối." : "Không có thành phần con để liệt kê.")
                        .foregroundStyle(.secondary)
                } else {
                    partList(parts)
                    if canPick {
                        Text("Phần bỏ tick được giữ lại khi dọn. Nhấp đúp một dòng để mở trong Finder.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang đo từng thành phần…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func partList(_ parts: [Part]) -> some View {
        let largest = Double(max(parts.first?.size ?? 1, 1))
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(parts) { part in
                    let isOn = checked.contains(part.path)
                    HStack(spacing: 10) {
                        if canPick {
                            Toggle("", isOn: Binding(get: { isOn }, set: { on in
                                if on { checked.insert(part.path) } else { checked.remove(part.path) }
                            }))
                            .toggleStyle(.checkbox).labelsHidden()
                        }
                        Text(part.name).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(canPick && !isOn ? .secondary : .primary)
                            .frame(width: 250, alignment: .leading)
                        MeterBar(segments: [.init(value: Double(part.size) / largest,
                                                  color: (canPick && !isOn ? Color.secondary : Palette.color(item.risk)).opacity(0.8))], height: 6)
                        Text(Format.ago(part.modified)).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                        Text(Format.bytes(part.size)).monospacedDigit().frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 6)
                    .background(canPick && isOn ? Palette.color(item.risk).opacity(0.07) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { NSWorkspace.shared.selectFile(part.path, inFileViewerRootedAtPath: "") }
                    .onTapGesture {
                        guard canPick else { return }
                        if isOn { checked.remove(part.path) } else { checked.insert(part.path) }
                    }
                }
            }
        }
        .frame(maxHeight: 260)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    private var footer: some View {
        HStack {
            if item.paths.count == 1 {
                Button("Hiện trong Finder") { NSWorkspace.shared.selectFile(item.paths[0], inFileViewerRootedAtPath: "") }
            }
            Spacer()
            Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            if item.risk != .keep {
                primaryButton
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let total = parts?.count ?? 0
        if canPick && total > 0 {
            let title = checked.isEmpty ? "Không dọn mục này"
                : checked.count == total ? "Chọn dọn cả \(Format.bytes(item.size))"
                : "Chọn dọn \(checked.count) phần · \(Format.bytes(checkedSize))"
            Button(title) {
                state.choose(item, parts: checked.count == total ? nil : checked, size: checkedSize)
                dismiss()
            }
            .buttonStyle(.borderedProminent).tint(checked.isEmpty ? .secondary : Palette.safe)
            .keyboardShortcut(.defaultAction)
        } else {
            let selected = state.selection.contains(item.id)
            Button(selected ? "Bỏ chọn" : "Chọn để dọn") { state.toggle(item); dismiss() }
                .buttonStyle(.borderedProminent).tint(selected ? .secondary : Palette.safe)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Nạp

    private func load() async {
        let loaded = await Self.parts(of: item)
        parts = loaded
        if let chosen = state.partial[item.id] {
            checked = chosen.paths.intersection(Set(loaded.map(\.path)))
        } else {
            checked = Set(loaded.map(\.path))
        }
    }

    /// Một thư mục: mọi thứ ngay bên trong. Nhiều đường dẫn rời: chính các đường dẫn đó.
    static func parts(of item: CleanItem) async -> [Part] {
        await Task.detached(priority: .userInitiated) {
            let urls = item.paths.map(URL.init(fileURLWithPath:))
            let targets: [URL] = urls.count == 1 && urls[0].isDirectory ? urls[0].children() : urls
            return targets.map { url in
                let m = FileSizer.measure(url)
                return Part(name: url.lastPathComponent, path: url.path, size: m.size, modified: m.lastModified)
            }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
        }.value
    }
}
