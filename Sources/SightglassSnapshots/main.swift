import AppKit
import SightglassCore
import SightglassUI
import SwiftUI

// Renders the images of the README and of the visual QA into docs/images/, from fictitious data:
// the menu bar window and each settings tab, light and dark, English (and the panel in French).
//
//   swift run sightglass-snapshots [output folder]     (default: docs/images)
//
// Views are hosted in an off-screen window and drawn with cacheDisplay at 2x. SwiftUI's
// ImageRenderer cannot draw the AppKit-backed controls of the settings (switches, text fields,
// pickers, tabs): it leaves placeholders, so it is not used here.

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images", isDirectory: true)
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

// A fixed moment: Monday 27 October 2026, 12:20 in Paris.
let paris = TimeZone(identifier: "Europe/Paris")!
let now = ISODate.parse("2026-10-26T11:20:00Z")!

func minutes(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }

// A fictitious home folder: the images show "~/.claude-team", never a real path.
let home = URL(fileURLWithPath: "/Volumes/Example/you")

func account(_ email: String, _ folder: String, org: String?, seat: String?, byHand: Bool = false) -> Account {
    let dir = home.appendingPathComponent(folder).path
    return Account(configDir: dir, email: email, organization: org, seatTier: seat,
                   keychainService: KeychainServiceName.forConfigDir(dir, isDefault: folder == ".claude"),
                   addedByHand: byHand)
}

let you = account("you@example.com", ".claude", org: "Example", seat: "max")
let team = account("team@example.org", ".claude-team", org: "Example Team", seat: "team")
let long = account("firstname.lastname.with-a-very-long-address@research.example-university.org", ".claude-research",
                   org: "Example University Research Laboratory", seat: "team")
let expired = account("weekend@example.net", ".claude-weekend", org: nil, seat: "pro")
let unavailable = account("ops@example.org", ".claude-ops", org: "Example Ops", seat: "max", byHand: true)

let mainAccounts: [AccountUsage] = [
    AccountUsage(account: you, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 34, resetsAt: minutes(130)),
        UsageLimit(kind: .weekly, percent: 58, resetsAt: minutes(60 * 24 * 2 + 40)),
        UsageLimit(kind: .weeklyModel, model: "Fable", percent: 12, resetsAt: minutes(60 * 24 * 2 + 40)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: team, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 100, resetsAt: minutes(39)),
        UsageLimit(kind: .weeklyModel, model: "Fable", percent: 74, resetsAt: minutes(60 * 24 * 3 + 15)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: long, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 91, resetsAt: minutes(48)),
        UsageLimit(kind: .weekly, percent: 0.4, resetsAt: minutes(60 * 24 * 5)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
]

let stateAccounts: [AccountUsage] = [
    AccountUsage(account: team, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 48, resetsAt: minutes(100)),
        UsageLimit(kind: .weeklyModel, model: "Fable", percent: 0, resetsAt: minutes(60 * 24 + 30)),
    ], fetchedAt: minutes(-25), checkedAt: minutes(-25)),
    AccountUsage(account: expired, status: .expired, limits: [
        UsageLimit(kind: .session, percent: 62, resetsAt: minutes(-20)),
        UsageLimit(kind: .weekly, percent: 81, resetsAt: minutes(60 * 30)),
    ], fetchedAt: minutes(-190), checkedAt: minutes(-2)),
    AccountUsage(account: unavailable, status: .unavailable, limits: [
        UsageLimit(kind: .session, percent: 20, resetsAt: minutes(200)),
        UsageLimit(kind: .weekly, percent: 30, resetsAt: minutes(60 * 40)),
    ], fetchedAt: minutes(-12), checkedAt: minutes(-2), failureCount: 2, retryAfter: minutes(6), detail: "HTTP 503"),
]

var settings = SightglassSettings()
settings.extraFolders = [unavailable.configDir]
settings.labels = [long.id: "Research lab"]
settings.showPercentInMenuBar = true

let icon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns"))

@MainActor
func model(_ accounts: [AccountUsage], language: Language, settings: SightglassSettings = settings) -> AppModel {
    let m = AppModel(preview: UsageSnapshot(generatedAt: minutes(-2), accounts: accounts), settings: settings,
                     now: now, language: language, timeZone: paris, home: home, launchAtLogin: true)
    m.appIcon = icon
    return m
}

@MainActor
func render<V: View>(_ view: V, size: CGSize?, dark: Bool, name: String) throws {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
    host.appearance = appearance
    let fitting = size ?? host.fittingSize
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: fitting),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.frame = CGRect(origin: .zero, size: fitting)
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    host.layoutSubtreeIfNeeded()
    host.display()

    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fitting.width * scale),
                                     pixelsHigh: Int(fitting.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { throw CocoaError(.fileWriteUnknown) }
    rep.size = fitting
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    let url = output.appendingPathComponent(name + ".png")
    try png.write(to: url)
    print("wrote \(url.path) (\(Int(fitting.width))x\(Int(fitting.height)) pt)")
}

/// The panel inside a rounded window outline, like the menu bar window.
struct PanelFrame<Content: View>: View {
    var content: Content
    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .padding(12)
    }
}

/// A settings tab inside a window outline with its title bar.
struct WindowFrame<Content: View>: View {
    var title: String
    var content: Content
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.primary.opacity(0.18)).frame(width: 12, height: 12) }
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        .padding(12)
    }
}

@MainActor
func run() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for dark in [false, true] {
        let suffix = dark ? "dark" : "light"
        try render(PanelFrame(content: PanelView(model: model(mainAccounts, language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(stateAccounts, language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-states-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(mainAccounts, language: .fr), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-fr-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model([], language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "qa-panel-empty-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(mainAccounts + stateAccounts.dropFirst(), language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "qa-panel-many-\(suffix)")

        for tab in SettingsTab.allCases {
            let m = model(mainAccounts + [stateAccounts[1], stateAccounts[2]], language: .en)
            m.settingsTab = tab
            let size = CGSize(width: SettingsView.size.width + 24, height: SettingsView.size.height + 31 + 24)
            try render(WindowFrame(title: m.strings.settingsTitle, content: SettingsView(model: m)),
                       size: size, dark: dark, name: "settings-\(tab.rawValue)-\(suffix)")
        }
        // The Accounts and Agents tabs scroll in the window: these images show them whole, for the QA.
        for tab in [SettingsTab.accounts, .agents] {
            let m = model(mainAccounts + [stateAccounts[1], stateAccounts[2]], language: .en)
            m.settingsTab = tab
            let height: CGFloat = 1180
            try render(WindowFrame(title: m.strings.settingsTitle, content: SettingsView(model: m, height: height)),
                       size: CGSize(width: SettingsView.size.width + 24, height: height + 31 + 24),
                       dark: dark, name: "qa-settings-\(tab.rawValue)-full-\(suffix)")
        }
        let fr = model(mainAccounts, language: .fr)
        fr.settingsTab = .accounts
        try render(WindowFrame(title: fr.strings.settingsTitle, content: SettingsView(model: fr)),
                   size: CGSize(width: SettingsView.size.width + 24, height: SettingsView.size.height + 31 + 24),
                   dark: dark, name: "settings-accounts-fr-\(suffix)")
    }
}

MainActor.assumeIsolated {
    do {
        try run()
    } catch {
        FileHandle.standardError.write(Data("snapshots: \(error)\n".utf8))
        exit(1)
    }
}
