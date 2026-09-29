import AppKit
import SwiftUI

/// Xem Thùng rác trước khi xoá hẳn: chọn từng mục để xoá, hoặc dọn toàn bộ.
struct TrashSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [TrashEntry]?
    @State private var checked = Set<String>()
    @State private var sort: TrashSort = .size
    @State private var confirmingSelected = false

    private var rows: [TrashEntry] { sort.sorted(entries ?? []) }
    private var checkedSize: Int64 { (entries ?? []).filter { checked.contains($0.id) }.reduce(0) { $0 + $1.size } }
    private var totalSize: Int64 { (entries ?? []).reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.trashFullName) ?? NSImage()).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thùng rác").font(.title2.weight(.bold))
                    Text(entries.map { "\($0.count) mục · \(Format.bytes(totalSize))" } ?? "Đang đo…").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sắp xếp", selection: $sort) {
                    ForEach(TrashSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
            }
            if let entries, !entries.isEmpty {
                HStack {
                    Text("\(checked.count)/\(entries.count) mục · \(Format.bytes(checkedSize))").foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Chọn tất cả") { checked = Set(entries.map(\.id)) }.disabled(checked.count == entries.count)
                    Button("Bỏ chọn tất cả") { checked.removeAll() }.disabled(checked.isEmpty)
                }
            }
            list
            Text("Nhấp đúp một dòng để mở trong Finder. Xoá ở đây là xoá hẳn, không hoàn tác được.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Mở Thùng rác trong Finder") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                Spacer()
                Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Dọn toàn bộ") { dismiss(); state.confirmingTrash = true }
                    .disabled(entries?.isEmpty ?? true)
                Button(checked.isEmpty ? "Xoá hẳn mục đã chọn" : "Xoá hẳn \(checked.count) mục · \(Format.bytes(checkedSize))") {
                    confirmingSelected = true
                }
                .buttonStyle(.borderedProminent).tint(Palette.alert)
                .disabled(checked.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 720, height: 560, alignment: .top)
        .task { await load() }
        .confirmationDialog("Xoá hẳn \(checked.count) mục?", isPresented: $confirmingSelected) {
            Button("Xoá hẳn", role: .destructive) {
                state.removeFromTrash(Array(checked))
                dismiss()
            }
        } message: {
            Text("\(Format.bytes(checkedSize)) bị xoá hẳn, không hoàn tác được.")
        }
    }

    @ViewBuilder
    private var list: some View {
        if let entries {
            if entries.isEmpty {
                Text("Thùng rác trống.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let largest = Double(max(entries.map(\.size).max() ?? 1, 1))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            row(entry, largest: largest)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            }
        } else if state.trashSize == nil {
            Text("Cần quyền Full Disk Access để xem Thùng rác.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang đo từng mục…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ entry: TrashEntry, largest: Double) -> some View {
        let isOn = checked.contains(entry.id)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isOn }, set: { on in
                if on { checked.insert(entry.id) } else { checked.remove(entry.id) }
            }))
            .toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.id)).resizable().frame(width: 20, height: 20)
            Text(entry.name).lineLimit(1).truncationMode(.middle).frame(width: 260, alignment: .leading)
            MeterBar(segments: [.init(value: Double(entry.size) / largest,
                                      color: (isOn ? Palette.alert : Color.secondary).opacity(0.7))], height: 6)
            Text(entry.trashed.map { "bỏ \(Format.ago($0))" } ?? "").font(.caption).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(Format.bytes(entry.size)).monospacedDigit().frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(isOn ? Palette.alert.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.selectFile(entry.id, inFileViewerRootedAtPath: "") }
        .onTapGesture { if isOn { checked.remove(entry.id) } else { checked.insert(entry.id) } }
    }

    private func load() async {
        entries = await Task.detached(priority: .userInitiated) { TrashEntry.list() }.value
    }
}

struct TrashEntry: Identifiable {
    let id: String
    let name: String
    let size: Int64
    let trashed: Date?

    static func list() -> [TrashEntry]? {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: [.addedToDirectoryDateKey]) else {
            return nil
        }
        return urls.filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }.map { url in
            TrashEntry(id: url.path, name: url.lastPathComponent, size: FileSizer.measure(url).size,
                       trashed: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate)
        }
    }
}

enum TrashSort: CaseIterable {
    case size, newest, oldest, name

    var title: String {
        switch self {
        case .size: "Dung lượng lớn nhất"
        case .newest: "Mới bỏ vào"
        case .oldest: "Bỏ vào lâu nhất"
        case .name: "Tên A–Z"
        }
    }

    func sorted(_ entries: [TrashEntry]) -> [TrashEntry] {
        switch self {
        case .size: entries.sorted { $0.size > $1.size }
        case .newest: entries.sorted { ($0.trashed ?? .distantPast) > ($1.trashed ?? .distantPast) }
        case .oldest: entries.sorted { ($0.trashed ?? .distantPast) < ($1.trashed ?? .distantPast) }
        case .name: entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
