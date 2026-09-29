import AppKit

enum Brand {
    static let logo: NSImage? = Bundle.module.url(forResource: "AppIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}
