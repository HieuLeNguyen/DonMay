// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DonMay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DonMay",
            path: "Sources/DonMay",
            resources: [.copy("Resources/AppIcon.png")],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
    ]
)
