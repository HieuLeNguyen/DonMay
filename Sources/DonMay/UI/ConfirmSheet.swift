import SwiftUI

struct ConfirmSheet: View {
    @Environment(AppState.self) private var state
    @State private var typed = ""
    private var confirmWord: String { L("XOÁ", "DELETE") }

    var body: some View {
        let items = state.selectedItems
        let warn = items.filter { $0.risk == .warn }
        let backups = items.filter(state.keepsBackup)
        let noBackup = items.filter { $0.undo == .backup && !state.keepsBackup($0) }
        let irreversible = items.filter { $0.undo == .irreversible }
        let running = Set(items.map(\.app)).filter { $0.shouldQuitBeforeCleaning && AppIcons.isRunning($0) }

        VStack(alignment: .leading, spacing: 16) {
            Text(L("Dọn \(items.count) mục?", "Clean \(items.count) items?")).font(.title2.weight(.bold))
            HStack(spacing: 10) {
                figure(L("Lấy lại ngay", "Freed now"), state.selectedFreedSize)
                figure(L("Giữ bản nén", "Kept as backup"), state.selectedKeptSize)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !running.isEmpty {
                        group(Chip(text: L("Nên thoát trước", "Quit first"), color: Palette.warn),
                              running.map { L("\($0.title) đang mở, bộ nhớ đệm có thể bị ghi lại ngay khi đang xoá", "\($0.title) is open; it may rewrite its cache while it is being deleted") })
                    }
                    group(Chip(text: L("Cần cân nhắc", "Review first"), color: Palette.warn), warn.map { "\($0.name): \($0.reason)" })
                    group(Chip(text: L("Sao lưu nén trước khi xoá", "Compressed backup before deleting"), color: Palette.safe),
                          backups.map { "\($0.name): \(Format.bytes($0.size)) → ~\(Format.bytes($0.estimatedPackedSize))" })
                    group(Chip(text: L("Xoá không sao lưu", "Deleted without backup"), color: Palette.warn), noBackup.map(\.name))
                    group(Chip(text: L("Không hoàn tác được", "Cannot be undone"), color: Palette.alert), irreversible.map(\.name))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)

            if !irreversible.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Gõ \(confirmWord) để xác nhận xoá \(irreversible.count) mục không hoàn tác được", "Type \(confirmWord) to confirm deleting \(irreversible.count) items that cannot be undone")).font(.callout)
                    TextField(confirmWord, text: $typed).textFieldStyle(.roundedBorder).frame(width: 160)
                }
            }
            HStack {
                Spacer()
                Button(L("Huỷ", "Cancel")) { state.confirming = false }.keyboardShortcut(.cancelAction)
                Button(L("Dọn và ghi vào Lịch sử", "Clean and record in History")) { Task { await state.cleanSelected() } }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!irreversible.isEmpty && !Self.matchesConfirmWord(typed))
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    static func matchesConfirmWord(_ text: String) -> Bool {
        ["xoa", "delete"].contains(text.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    private func figure(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.bytes(value)).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private func group(_ chip: Chip, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                chip
                ForEach(lines, id: \.self) { line in
                    Text("• " + line).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
