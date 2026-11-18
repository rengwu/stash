// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "xsaves",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "xsaves",
            path: "Sources/XSaves",
            linkerSettings: [.linkedFramework("AVKit"), .linkedFramework("WebKit")]
        ),
    ]
)
