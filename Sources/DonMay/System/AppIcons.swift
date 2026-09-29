import AppKit

@MainActor
enum AppIcons {
    private static var cache: [AppKind: NSImage] = [:]

    static func icon(for app: AppKind) -> NSImage? {
        if let cached = cache[app] { return cached }
        let workspace = NSWorkspace.shared
        var image: NSImage?
        if let bundleID = app.bundleID, let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            image = workspace.icon(forFile: url.path)
        } else if let folder = app.folder {
            image = workspace.icon(forFile: folder.path)
        }
        cache[app] = image
        return image
    }

    static func isRunning(_ app: AppKind) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
