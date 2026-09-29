import AppKit
import SwiftUI

/// Bảng nhỏ trên thanh menu: ổ còn trống, thứ đang tăng, và lối tắt tới các việc hay làm.
struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            disk
            Divider()
            HStack {
                Text(L("Dọn an toàn được", "Safe to clean"))
                Spacer()
                Text(Format.bytes(state.size(of: .safe))).monospacedDigit().fontWeight(.semibold)
            }
            if !state.growing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Đang tăng", "Growing")).font(.caption).foregroundStyle(.secondary)
                    ForEach(state.growing.prefix(3)) { item in
                        HStack(spacing: 8) {
                            AppLogo(app: item.app, size: 18)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("+\(Format.bytes(item.growth7))").font(.caption).monospacedDigit().foregroundStyle(Palette.color(item.level))
                        }
                    }
                }
            }
            HStack {
                Image(systemName: "trash").foregroundStyle(.secondary)
                Text(L("Thùng rác", "Trash"))
                Spacer()
                Text(state.trashSize.map(Format.bytes) ?? "—").monospacedDigit().foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 6) {
                action(state.isScanning ? L("Đang quét…", "Scanning…") : L("Quét lại", "Rescan"), "arrow.clockwise") {
                    Task { await state.scan() }
                }
                .disabled(state.isScanning || state.isCleaning)
                action(L("Chọn mục an toàn để dọn", "Select safe items to clean"), "checkmark.circle") {
                    state.selectSafe()
                    state.route = .overview
                    show()
                    state.confirming = !state.selection.isEmpty
                }
                .disabled(state.size(of: .safe) == 0 || state.isCleaning)
                action(L("Xem Thùng rác", "Review Trash"), "trash") {
                    show()
                    state.showingTrash = true
                }
                .disabled(state.trashSize == nil || state.trashSize == 0)
                action(L("Mở Dọn Máy", "Open Dọn Máy"), "macwindow") { show() }
                action(L("Cài đặt…", "Settings…"), "gearshape") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                action(L("Thoát", "Quit"), "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .id(Preferences.shared.language)
    }

    private var disk: some View {
        let used = max(state.diskTotal - state.diskFree, 0)
        let ratio = Double(used) / Double(max(state.diskTotal, 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Còn trống", "Free")).foregroundStyle(.secondary)
                Text(Format.bytes(state.diskFree)).font(.title2.weight(.semibold)).monospacedDigit()
                Spacer()
                Text(L("trên \(Format.bytes(state.diskTotal))", "of \(Format.bytes(state.diskTotal))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            MeterBar(segments: [.init(value: ratio, color: ratio > 0.9 ? Palette.alert : Palette.accent)], height: 6)
        }
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
