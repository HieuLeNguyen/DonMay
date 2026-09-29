import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Lịch sử dọn", "Cleaning history")).font(.largeTitle.weight(.bold))
                Text(L("Công cụ không dùng Thùng rác, vì tệp trong Thùng rác vẫn chiếm nguyên dung lượng. Mỗi mục được xử lý theo một trong ba cách.", "Dọn Máy skips the Trash, because files in the Trash still take up space. Each item is handled in one of three ways."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Grid(horizontalSpacing: 12) {
                GridRow {
                    rule(Chip(text: L("Xoá hẳn", "Deleted"), color: .secondary), L("Mục tự tạo lại", "Regenerated items"),
                         L("Bộ nhớ đệm, dữ liệu build, gói tải về. Không giữ bản sao. Lịch sử ghi lại cách tạo lại.", "Caches, build data, downloaded packages. No copy is kept; history notes how to regenerate them."))
                    rule(Chip(text: L("Sao lưu nén", "Compressed backup"), color: Palette.safe), L("Chỉ khi thật cần", "Only when needed"),
                         L("Dữ liệu không tự tạo lại được. Nén LZFSE xong mới xoá bản gốc, giữ \(BackupPolicy.keepDays) ngày.", "Data that can't be regenerated. Compressed with LZFSE before deleting the original, kept \(BackupPolicy.keepDays) days."))
                    rule(Chip(text: L("Không hoàn tác", "Irreversible"), color: Palette.alert), L("Hỏi trước khi xoá", "Asks before deleting"),
                         L("Máy ảo và runtime xoá bằng simctl. Phải gõ xác nhận.", "Simulators and runtimes are deleted with simctl. Requires typed confirmation."))
                }
            }
            budget
            if state.history.isEmpty {
                Text(L("Chưa dọn lần nào.", "Nothing cleaned yet.")).foregroundStyle(.secondary)
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
                    Text(L("Bản nén đang giữ", "Kept backups")).fontWeight(.semibold)
                    Spacer()
                    Text(L("\(Format.bytes(state.archivesInUse)) / \(Format.bytes(state.backupBudget)) cho phép", "\(Format.bytes(state.archivesInUse)) of \(Format.bytes(state.backupBudget)) allowed")).monospacedDigit()
                }
                MeterBar(segments: [.init(value: Double(state.archivesInUse) / Double(max(state.backupBudget, 1)), color: Palette.accent)], height: 8)
                Text(L("Mức cho phép là 10% dung lượng trống, tối đa 2 GB. Khi ổ còn dưới \(Format.bytes(BackupPolicy.lowDiskFree)), bản nén cũ hơn \(BackupPolicy.graceHours) giờ bị xoá trước, bản cũ nhất đi trước.", "The limit is 10% of free space, up to 2 GB. When free space drops below \(Format.bytes(BackupPolicy.lowDiskFree)), backups older than \(BackupPolicy.graceHours) hours are removed, oldest first."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L("Xoá mọi bản nén · lấy lại \(Format.bytes(state.archivesInUse))", "Delete all backups · free \(Format.bytes(state.archivesInUse))")) { state.dropAllArchives() }
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
                Text(L("Đã lấy lại \(Format.bytes(session.freed))", "Freed \(Format.bytes(session.freed))") + (session.keptArchiveSize > 0 ? L(" · giữ bản nén \(Format.bytes(session.keptArchiveSize))", " · kept backup \(Format.bytes(session.keptArchiveSize))") : ""))
                    .foregroundStyle(.secondary)
                Spacer()
                if session.keptArchiveSize > 0 {
                    Button(L("Khôi phục lần này", "Restore this session")) { state.restoreAll(in: session.id) }
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
                            Text(L("nén còn \(Format.bytes(archive))", "backup \(Format.bytes(archive))")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 110, alignment: .trailing)
                    outcome(entry).frame(width: 190, alignment: .trailing)
                    if entry.outcome == .packed {
                        Button(L("Khôi phục", "Restore")) { state.restore(session: session.id, entry: entry.id) }
                        Button(L("Xoá bản nén", "Delete backup")) { state.dropArchive(session: session.id, entry: entry.id) }
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
        case .regenerated: Chip(text: L("Đã xoá · tự tạo lại", "Deleted · regenerates"), color: .secondary)
        case .irreversible: Chip(text: L("Đã xoá · không hoàn tác", "Deleted · irreversible"), color: .secondary)
        case .packed:
            Chip(text: L("Bản nén · còn \(daysLeft(entry.expiresAt)) ngày", "Backup · \(daysLeft(entry.expiresAt)) days left"), color: Palette.safe)
        case .restored: Chip(text: L("Đã khôi phục", "Restored"), color: .secondary)
        case .expired: Chip(text: L("Bản nén đã xoá", "Backup deleted"), color: .secondary)
        case .failed: Chip(text: L("Không dọn được", "Failed"), color: Palette.alert)
        }
    }

    private func daysLeft(_ date: Date?) -> Int {
        guard let date else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSinceNow / 86_400)))
    }
}
