import AppKit
import SwiftUI

@main
struct DonMayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state: AppState
    @Bindable private var prefs = Preferences.shared

    init() {
        SelfCheck.runIfRequested()
        _state = State(initialValue: AppState())
    }

    var body: some Scene {
        Window("Dọn Máy", id: "main") {
            RootView()
                .environment(state)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView().environment(state)
        }

        MenuBarExtra(isInserted: $prefs.showsMenuBarItem) {
            MenuBarView().environment(state)
        } label: {
            Image(systemName: "internaldrive")
            Text(Format.bytes(state.diskFree))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let logo = Brand.logo { NSApp.applicationIconImage = logo }
        Preferences.shared.applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Preferences.shared.showsMenuBarItem
    }
}
