import AppKit
import SwiftUI

@main
struct DonMayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state: AppState

    init() {
        SelfCheck.runIfRequested()
        _state = State(initialValue: AppState())
    }

    var body: some Scene {
        WindowGroup("Dọn Máy") {
            RootView()
                .environment(state)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
