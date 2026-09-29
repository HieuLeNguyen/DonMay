import SwiftUI

struct MachineInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var info: MachineInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                if let logo = Brand.logo { Image(nsImage: logo).resizable().frame(width: 56, height: 56) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.modelName ?? L("Máy Mac này", "This Mac")).font(.title2.weight(.bold))
                    Text(info.map { "\($0.chip) · \($0.memory) · \($0.modelIdentifier)" } ?? L("Đang đọc thông tin…", "Reading information…"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let info {
                section(L("Hệ điều hành", "Operating system")) {
                    line(L("Phiên bản", "Version"), info.osVersion)
                }
                section(L("Ổ đĩa", "Disk")) {
                    let used = info.diskTotal - info.diskFree
                    line(L("Dung lượng", "Capacity"), Format.bytes(info.diskTotal))
                    line(L("Đã dùng", "Used"), "\(Format.bytes(used)) · \(Format.percent(Double(used) / Double(max(info.diskTotal, 1))))")
                    line(L("Còn trống", "Free"), Format.bytes(info.diskFree))
                    MeterBar(segments: [.init(value: Double(used) / Double(max(info.diskTotal, 1)),
                                              color: Double(info.diskFree) / Double(max(info.diskTotal, 1)) < 0.1 ? Palette.alert : Palette.accent)],
                             height: 8)
                }
                section(L("Thời gian chạy", "Uptime")) {
                    line(L("Khởi động lúc", "Booted"), info.bootTime.map(Format.dateTime) ?? L("Không rõ", "Unknown"))
                    line(L("Chạy liên tục", "Running for"), info.uptime.map(Self.duration) ?? L("Không rõ", "Unknown"))
                    line(L("Tắt máy gần nhất", "Last shutdown"), info.lastShutdown.map(Format.dateTime) ?? L("Không có trong nhật ký", "Not in the logs"))
                    if let uptime = info.uptime, uptime > 7 * 86_400 {
                        Label(L("Máy chạy hơn 7 ngày chưa khởi động lại. Khởi động lại giải phóng bộ nhớ swap và tệp tạm của hệ thống.", "This Mac has run over 7 days without a restart. Restarting frees swap and system temporary files."),
                              systemImage: "arrow.clockwise.circle")
                            .font(.callout).foregroundStyle(Palette.warn)
                    }
                }
                updates(info.updates)
            } else {
                HStack { ProgressView().controlSize(.small); Text(L("Đang đọc thông tin máy…", "Reading Mac information…")).foregroundStyle(.secondary) }
            }
            HStack {
                Spacer()
                Button(L("Đóng", "Close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .task { info = await Task.detached { MachineInfoReader.read() }.value }
    }

    private func updates(_ u: UpdateInfo) -> some View {
        section(L("Cập nhật macOS", "macOS updates")) {
            line(L("Tự tải bản cập nhật", "Download updates automatically"), flag(u.automaticDownload))
            line(L("Tự cài bản macOS mới", "Install macOS updates automatically"), flag(u.automaticInstallMacOS))
            line(L("Kiểm tra gần nhất", "Last checked"), u.lastCheck.map(Format.dateTime) ?? L("Không rõ", "Unknown"))
            line(L("Đã tải về máy", "Downloaded"), u.downloadedSize >= .mb ? Format.bytes(u.downloadedSize) : L("Không có", "None"))
            if !u.installers.isEmpty {
                line(L("Bộ cài macOS", "macOS installers"), u.installers.map { "\($0.name) (\(Format.bytes($0.size)))" }.joined(separator: ", "))
            }
            line(L("Đang chờ cài", "Pending install"), u.pending.isEmpty ? L("Không có", "None") : u.pending.joined(separator: "\n"))
            if u.automaticDownload == true || u.automaticInstallMacOS == true || u.downloadedSize >= 500 * .mb {
                Label(L("macOS đang tự tải bản cập nhật về máy. Mỗi bản có thể chiếm 5–15 GB mà không báo trước.", "macOS downloads updates automatically. Each one can take 5–15 GB without notice."), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Palette.warn)
            }
            Button(L("Mở Cài đặt › Cập nhật phần mềm", "Open Settings › Software Update")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func flag(_ value: Bool?) -> String {
        switch value {
        case .some(true): L("Bật", "On")
        case .some(false): L("Tắt", "Off")
        case .none: L("Mặc định của macOS", "macOS default")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400, hours = total % 86_400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return L("\(days) ngày \(hours) giờ", "\(days) d \(hours) h") }
        if hours > 0 { return L("\(hours) giờ \(minutes) phút", "\(hours) h \(minutes) min") }
        return L("\(minutes) phút", "\(minutes) min")
    }
}
