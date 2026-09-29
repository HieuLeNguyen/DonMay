import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Picker(L("Ngôn ngữ", "Language"), selection: $prefs.language) {
                ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker(L("Giao diện", "Appearance"), selection: $prefs.appearance) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle(L("Hiện trên thanh menu", "Show in menu bar"), isOn: $prefs.showsMenuBarItem)
            Toggle(L("Mở cùng máy khi đăng nhập", "Open at login"),
                   isOn: Binding(get: { prefs.launchesAtLogin }, set: { prefs.setLaunchesAtLogin($0) }))
            if let error = prefs.loginItemError {
                Text(error).font(.caption).foregroundStyle(Palette.alert)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .id(prefs.language)
        .onChange(of: prefs.language) { Task { await state.scan() } }
    }
}
