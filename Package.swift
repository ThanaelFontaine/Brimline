// swift-tools-version:6.0
// Sightglass: one Swift package, built with the Command Line Tools only (no Xcode project).
//
// Targets:
// - SightglassCore: account discovery, Keychain read through /usr/bin/security, usage API,
//   normalization, cache, ranking, formatting, MCP server. No UI.
// - SightglassCLI: the `sightglass` command (status, accounts, mcp).
// - SightglassUI: the SwiftUI views and the app model, shared by the app and the snapshots.
// - SightglassApp: the menu bar app itself (assembled into Sightglass.app by scripts/build_app.sh).
// - SightglassSnapshots: renders the README and QA images into docs/images/.
import Foundation
import PackageDescription

// Swift Testing with the Command Line Tools (Swift 6.4): when a test file is compiled again in an
// existing build folder, the compiler sometimes stops finding the TestingMacros plugin ("plugin for
// module 'TestingMacros' not found"), one build out of two. Giving it the plugin folder explicitly
// makes every build pass. Only added when that folder exists, so other toolchains are untouched.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])]
    : []

let package = Package(
    name: "Sightglass",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sightglass", targets: ["SightglassCLI"]),
        .executable(name: "SightglassApp", targets: ["SightglassApp"]),
        .executable(name: "sightglass-snapshots", targets: ["SightglassSnapshots"]),
        .library(name: "SightglassCore", targets: ["SightglassCore"]),
    ],
    targets: [
        .target(name: "SightglassCore"),
        .executableTarget(name: "SightglassCLI", dependencies: ["SightglassCore"]),
        .target(name: "SightglassUI", dependencies: ["SightglassCore"]),
        .executableTarget(name: "SightglassApp", dependencies: ["SightglassCore", "SightglassUI"]),
        .executableTarget(name: "SightglassSnapshots", dependencies: ["SightglassCore", "SightglassUI"]),
        .testTarget(
            name: "SightglassCoreTests",
            dependencies: ["SightglassCore"],
            // The repository keeps every test under tests/ (the Python ones too): explicit path,
            // so the package also builds on a case-sensitive file system.
            path: "tests/SightglassCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: testSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
