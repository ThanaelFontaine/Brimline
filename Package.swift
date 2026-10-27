// swift-tools-version:6.0
// Brimline: one Swift package, built with the Command Line Tools only (no Xcode project).
//
// Targets:
// - BrimlineCore: account discovery, Keychain read through /usr/bin/security, usage API,
//   normalization, cache, ranking, formatting, MCP server. No UI.
// - BrimlineCLI: the `brimline` command (status, accounts, mcp).
// - BrimlineUI: the SwiftUI views and the app model, shared by the app and the snapshots.
// - BrimlineApp: the menu bar app itself (assembled into Brimline.app by scripts/build_app.sh).
// - BrimlineSnapshots: renders the README and QA images into docs/images/.
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
    name: "Brimline",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "brimline", targets: ["BrimlineCLI"]),
        .executable(name: "BrimlineApp", targets: ["BrimlineApp"]),
        .executable(name: "brimline-snapshots", targets: ["BrimlineSnapshots"]),
        .library(name: "BrimlineCore", targets: ["BrimlineCore"]),
    ],
    targets: [
        .target(name: "BrimlineCore"),
        .executableTarget(name: "BrimlineCLI", dependencies: ["BrimlineCore"]),
        .target(name: "BrimlineUI", dependencies: ["BrimlineCore"]),
        .executableTarget(name: "BrimlineApp", dependencies: ["BrimlineCore", "BrimlineUI"]),
        .executableTarget(name: "BrimlineSnapshots", dependencies: ["BrimlineCore", "BrimlineUI"]),
        .testTarget(
            name: "BrimlineCoreTests",
            dependencies: ["BrimlineCore"],
            // The repository keeps every test under tests/ (the Python ones too): explicit path,
            // so the package also builds on a case-sensitive file system.
            path: "tests/BrimlineCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: testSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
