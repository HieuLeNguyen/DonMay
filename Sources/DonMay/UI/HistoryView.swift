import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lịch sử dọn").font(.largeTitle.weight(.bold))
                Text("Công cụ không dùng Thùng rác, vì tệp trong Thùng rác vẫn chiếm nguyên dung lượng. Mỗi mục được xử lý theo một trong ba cách.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Grid(horizontalSpacing: 12) {
                GridRow {
                    rule(Chip(text: "Xoá hẳn", color: .secondary), "Mục tự tạo lại",
                         "Bộ nhớ đệm, dữ liệu build, gói tải về. Không giữ bản sao. Lịch sử ghi lại cách tạo lại.")
                    rule(Chip(text: "Sao lưu nén", color: Palette.safe), "Chỉ khi thật cần",
                         "Dữ liệu không tự tạo lại được. Nén LZFSE xong mới xoá bản gốc, giữ \(BackupPolicy.keepDays) ngày.")
                    rule(Chip(text: "Không hoàn tác", color: Palette.alert), "Hỏi trước khi xoá",
                         "Máy ảo và runtime xoá bằng simctl. Phải gõ xác nhận.")
                }
            }
            budget
            if state.history.isEmpty {
                Text("Chưa dọn lần nào.").foregroundStyle(.secondary)
            }
            ForEach(state.history) { session in
                SessionCard(session: session)
            }
        }
    }

    private func rule(_ chip: Chip, _ title: String, _ text: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                chip
                Text(title).fontWeight(.semibold)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var budget: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bản nén đang giữ").fontWeight(.semibold)
                    Spacer()
                    Text("\(Format.bytes(state.archivesInUse)) / \(Format.bytes(state.backupBudget)) cho phép").monospacedDigit()
                }
                MeterBar(segments: [.init(value: Double(state.archivesInUse) / Double(max(state.backupBudget, 1)), color: Palette.accent)], height: 8)
                Text("Mức cho phép là 10% dung lượng trống, tối đa 2 GB. Khi ổ còn dưới \(Format.bytes(BackupPolicy.lowDiskFree)), bản nén cũ hơn \(BackupPolicy.graceHours) giờ bị xoá trước, bản cũ nhất đi trước.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Xoá mọi bản nén · lấy lại \(Format.bytes(state.archivesInUse))") { state.dropAllArchives() }
                    .disabled(state.archivesInUse == 0)
            }
        }
    }
}

private struct SessionCard: View {
    @Environment(AppState.self) private var state
    let session: HistorySession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(Format.dateTime(session.date)).fontWeight(.semibold)
                Text("Đã lấy lại \(Format.bytes(session.freed))" + (session.keptArchiveSize > 0 ? " · giữ bản nén \(Format.bytes(session.keptArchiveSize))" : ""))
                    .foregroundStyle(.secondary)
                Spacer()
                if session.keptArchiveSize > 0 {
                    Button("Khôi phục lần này") { state.restoreAll(in: session.id) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))
            ForEach(session.entries) { entry in
                Divider()
                HStack(spacing: 12) {
                    AppLogo(app: entry.app, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).fontWeight(.medium)
                        if let error = entry.error {
                            Text(error).font(.caption).foregroundStyle(Palette.alert)
                        } else if !entry.regenerateHint.isEmpty && entry.outcome != .packed {
                            Text(entry.regenerateHint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Format.bytes(entry.size)).monospacedDigit()
                        if let archive = entry.archiveSize, entry.outcome == .packed {
                            Text("nén còn \(Format.bytes(archive))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 110, alignment: .trailing)
                    outcome(entry).frame(width: 190, alignment: .trailing)
                    if entry.outcome == .packed {
                        Button("Khôi phục") { state.restore(session: session.id, entry: entry.id) }
                        Button("Xoá bản nén") { state.dropArchive(session: session.id, entry: entry.id) }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }

    private func outcome(_ entry: HistoryEntry) -> Chip {
        switch entry.outcome {
        case .regenerated: Chip(text: "Đã xoá · tự tạo lại", color: .secondary)
        case .irreversible: Chip(text: "Đã xoá · không hoàn tác", color: .secondary)
        case .packed:
            Chip(text: "Bản nén · còn \(daysLeft(entry.expiresAt)) ngày", color: Palette.safe)
        case .restored: Chip(text: "Đã khôi phục", color: .secondary)
        case .expired: Chip(text: "Bản nén đã xoá", color: .secondary)
        case .failed: Chip(text: "Không dọn được", color: Palette.alert)
        }
    }

    private func daysLeft(_ date: Date?) -> Int {
        guard let date else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSinceNow / 86_400)))
    }
}
