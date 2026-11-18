// swift-tools-version: 6.2
import PackageDescription
import Foundation

// The CLT build planner can omit the bundled Swift Testing macro on incremental builds.
let testingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugin)
    ? [.unsafeFlags(["-Xfrontend", "-load-plugin-library", "-Xfrontend", testingPlugin])]
    : []

let package = Package(
    name: "xsaves",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "XSavesCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "xsaves",
            dependencies: ["XSavesCore"],
            path: "Sources/XSaves",
            linkerSettings: [.linkedFramework("AVKit"), .linkedFramework("WebKit")]
        ),
        .testTarget(name: "XSavesCoreTests", dependencies: ["XSavesCore"], swiftSettings: testSettings),
    ]
)
