import AppKit
import SwiftUI

/// Chi tiết một mục: vì sao xếp mức này, dọn thì mất gì, và phần nào bên trong chiếm nhiều nhất.
struct ItemDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let item: CleanItem
    @State private var parts: [Part]?

    struct Part: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let size: Int64
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            facts
            Divider()
            locations
            breakdown
            footer
        }
        .padding(24)
        .frame(width: 620)
        .frame(minHeight: 520, alignment: .top)
        .task { parts = await Self.largestParts(of: item) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppLogo(app: item.app, size: 48, level: item.level)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.title2.weight(.bold)).lineLimit(2)
                HStack(spacing: 8) {
                    Text(item.app.title).foregroundStyle(.secondary)
                    RiskChip(risk: item.risk)
                    if item.level != .flat {
                        Chip(text: item.level.title, color: Palette.color(item.level),
                             systemImage: item.level == .spike ? "chevron.up.2" : "arrow.up")
                    }
                }
            }
            Spacer()
            Text(Format.bytes(item.size)).font(.system(size: 26, weight: .semibold)).monospacedDigit()
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            row("Vì sao", item.reason)
            row("Ghi mới", "+\(Format.bytes(item.growth24)) trong 24 giờ · +\(Format.bytes(item.growth7)) trong 7 ngày")
            row("Dùng lần cuối", item.lastUsed.map { "\(Format.dateTime($0)) (\(Format.ago($0)))" } ?? "Không rõ")
            row("Khi dọn", undoText)
            if !item.regenerateHint.isEmpty && item.undo != .backup { row("Tạo lại", item.regenerateHint) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var undoText: String {
        if item.risk == .keep { return "Công cụ không dọn mục này" }
        switch item.undo {
        case .regenerate: return "Xoá hẳn, không giữ bản sao. Công cụ gốc tự tạo lại khi cần."
        case .irreversible: return "Xoá bằng xcrun simctl. Không hoàn tác được, phải gõ XOÁ để xác nhận."
        case .backup:
            return state.backupChoices.contains(item.id)
                ? "Nén thành ~\(Format.bytes(item.estimatedPackedSize)) rồi mới xoá. Khôi phục được trong \(BackupPolicy.keepDays) ngày."
                : "Xoá không sao lưu (Ngài đã bỏ tick Sao lưu nén)."
        }
    }

    @ViewBuilder
    private var locations: some View {
        if !item.paths.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.paths.count == 1 ? "Vị trí" : "Vị trí · \(item.paths.count) mục").font(.headline)
                ForEach(item.paths.prefix(6), id: \.self) { path in
                    HStack {
                        Text(Format.abbreviatingHome(path)).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Hiện trong Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                            .buttonStyle(.borderless)
                    }
                }
                if item.paths.count > 6 { Text("và \(item.paths.count - 6) mục khác").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chiếm nhiều nhất bên trong").font(.headline)
            if let parts {
                if parts.isEmpty {
                    Text("Không có thành phần con để liệt kê.").foregroundStyle(.secondary)
                } else {
                    let largest = Double(max(parts.first?.size ?? 1, 1))
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(parts) { part in
                                HStack(spacing: 10) {
                                    Text(part.name).lineLimit(1).truncationMode(.middle).frame(width: 240, alignment: .leading)
                                    MeterBar(segments: [.init(value: Double(part.size) / largest, color: Palette.color(item.risk).opacity(0.8))], height: 6)
                                    Text(Format.bytes(part.size)).monospacedDigit().frame(width: 72, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { NSWorkspace.shared.selectFile(part.path, inFileViewerRootedAtPath: "") }
                                .help("Nhấp đúp để hiện trong Finder")
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang đo từng thành phần…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            if item.risk != .keep {
                let selected = state.selection.contains(item.id)
                Button(selected ? "Bỏ chọn" : "Chọn để dọn") { state.toggle(item) }
                    .buttonStyle(.borderedProminent)
                    .tint(selected ? .secondary : Palette.safe)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Một thư mục: 12 thư mục/tệp con lớn nhất. Nhiều tệp rời: chính các tệp đó.
    static func largestParts(of item: CleanItem) async -> [Part] {
        await Task.detached(priority: .userInitiated) {
            let urls = item.paths.map(URL.init(fileURLWithPath:))
            let targets: [URL] = urls.count == 1 && urls[0].isDirectory ? urls[0].children() : urls
            return targets.map { url in
                Part(name: url.lastPathComponent, path: url.path, size: FileSizer.measure(url).size)
            }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(12)
            .map { $0 }
        }.value
    }
}
