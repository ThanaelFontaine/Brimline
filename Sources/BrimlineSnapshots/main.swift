import AppKit
import BrimlineCore
import BrimlineUI
import SwiftUI

// Renders the images of the README and of the visual QA into docs/images/, from fictitious data:
// the menu bar window and each settings tab, light and dark, English (and the panel, its states and
// the Accounts tab in French), and the panel with one account per provider (grouped by provider, the board's
// variant A) with sheets of every state.
//
//   swift run brimline-snapshots [--with-percent] [output folder]     (default: docs/images)
//
// By default the settings are the app's defaults for the menu bar (icon only, no percentage);
// --with-percent turns the percentage on, for the older image.
//
// Views are hosted in an off-screen window and drawn with cacheDisplay at 2x. SwiftUI's
// ImageRenderer cannot draw the AppKit-backed controls of the settings (switches, text fields,
// pickers, tabs): it leaves placeholders, so it is not used here.

let arguments = Array(CommandLine.arguments.dropFirst())
let withPercent = arguments.contains("--with-percent")
let output = URL(fileURLWithPath: arguments.first { $0 != "--with-percent" } ?? "docs/images", isDirectory: true)
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

// A fixed moment: Monday 27 October 2026, 12:20 in Paris.
let paris = TimeZone(identifier: "Europe/Paris")!
let now = ISODate.parse("2026-10-26T11:20:00Z")!

func minutes(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }

// A fictitious home folder: the images show "~/.claude-team", never a real path. Built in two parts
// because the text check flags any literal home path; "you" is not a real user.
let home = URL(fileURLWithPath: "/Users", isDirectory: true).appendingPathComponent("you")

func account(_ email: String, _ folder: String, org: String?, seat: String?, byHand: Bool = false) -> Account {
    let dir = home.appendingPathComponent(folder).path
    return Account(source: dir, email: email, organization: org, seatTier: seat,
                   keychainService: KeychainServiceName.forConfigDir(dir, isDefault: folder == ".claude"),
                   addedByHand: byHand)
}

let you = account("your@claude.ai", ".claude", org: "Example", seat: "max")
let team = account("team@claude.ai", ".claude-team", org: "Example Team", seat: "team")
let long = account("firstname.lastname.with-a-very-long-address@claude.ai", ".claude-research",
                   org: "Example University Research Laboratory", seat: "team")
let expired = account("weekend@claude.ai", ".claude-weekend", org: nil, seat: "pro")
let unavailable = account("ops@claude.ai", ".claude-ops", org: "Example Ops", seat: "max", byHand: true)

let mainAccounts: [AccountUsage] = [
    AccountUsage(account: you, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 34, resetsAt: minutes(130)),
        UsageLimit(kind: .weekly, percent: 58, resetsAt: minutes(60 * 24 * 2 + 40)),
        UsageLimit(kind: .model, model: "Fable", percent: 12, resetsAt: minutes(60 * 24 * 2 + 40)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: team, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 100, resetsAt: minutes(39)),
        UsageLimit(kind: .model, model: "Fable", percent: 74, resetsAt: minutes(60 * 24 * 3 + 15)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: long, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 91, resetsAt: minutes(48)),
        UsageLimit(kind: .weekly, percent: 0.4, resetsAt: minutes(60 * 24 * 5)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
]

let stateAccounts: [AccountUsage] = [
    AccountUsage(account: team, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 48, resetsAt: minutes(100)),
        UsageLimit(kind: .model, model: "Fable", percent: 0, resetsAt: minutes(60 * 24 + 30)),
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

// One account per provider and every state: the panel grouped by provider (QUOTA-35, board D, variant A).
// The readers keep neither the address nor the plan of these providers, so the cards carry neither.
func provider(_ provider: Provider, _ path: String, byHand: Bool = false) -> Account {
    Account(provider: provider, source: home.appendingPathComponent(path).path, email: nil, organization: nil,
            seatTier: nil, keychainService: nil, addedByHand: byHand)
}

let lab = account("team@claude.ai", ".claude-lab", org: nil, seat: "team")
let weekend = account("weekend@claude.ai", ".claude-weekend", org: nil, seat: "pro")
let codexPlus = provider(.chatgpt, ".codex")
let codexWork = provider(.chatgpt, "codex-work", byHand: true)
let codexKey = provider(.chatgpt, "codex-key", byHand: true)
let grok = provider(.grok, ".grok/auth.json")
let cursor = provider(.cursor, "Library/Application Support/Cursor")
let gemini = provider(.gemini, ".gemini")

let monthSeconds = 30 * 86_400

let providerAccounts: [AccountUsage] = [
    AccountUsage(account: you, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 34, resetsAt: minutes(130)),
        UsageLimit(kind: .weekly, percent: 58, resetsAt: minutes(60 * 24 * 2 + 40)),
        UsageLimit(kind: .model, model: "Fable", percent: 12, resetsAt: minutes(60 * 24 * 2 + 40)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    // A team seat: no weekly limit across all models, and a model limit that resets on its own day.
    AccountUsage(account: lab, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 91, resetsAt: minutes(48)),
        UsageLimit(kind: .model, model: "Fable", percent: 74, resetsAt: minutes(60 * 24 * 3 + 15)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: codexPlus, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 22, resetsAt: minutes(185), windowSeconds: 18_000),
        UsageLimit(kind: .weekly, percent: 71, resetsAt: minutes(60 * 24 * 4 + 120), windowSeconds: 604_800),
        UsageLimit(kind: .model, model: "codex-mini", percent: 9, resetsAt: minutes(80), windowSeconds: 18_000),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: codexWork, status: .expired, limits: [
        UsageLimit(kind: .weekly, percent: 40, resetsAt: minutes(60 * 24 * 4 + 120), windowSeconds: 604_800),
    ], fetchedAt: minutes(-60 * 24 * 3), checkedAt: minutes(-2)),
    // What the real try of 27/10/2026 gave on a free Grok account: no credit limit, so no gauge and no number.
    AccountUsage(account: grok, status: .ok, fetchedAt: minutes(-2), checkedAt: minutes(-2), note: .noCreditLimit),
    AccountUsage(account: cursor, status: .ok, limits: [
        UsageLimit(kind: .monthly, percent: 63, resetsAt: minutes(60 * 24 * 12), windowSeconds: monthSeconds),
        UsageLimit(kind: .model, model: "Auto", percent: 41, resetsAt: minutes(60 * 24 * 12), windowSeconds: monthSeconds),
        UsageLimit(kind: .model, model: "API", percent: 88, resetsAt: minutes(60 * 24 * 12), windowSeconds: monthSeconds),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    // Gemini read through Antigravity: the limits of `agy --print /usage`, per group of models and window.
    AccountUsage(account: gemini, status: .ok, limits: [
        UsageLimit(kind: .model, model: "Gemini Models", percent: 18, resetsAt: minutes(210), windowSeconds: 18_000),
        UsageLimit(kind: .model, model: "Gemini Models", percent: 33, resetsAt: minutes(60 * 24 * 5 + 90), windowSeconds: 604_800),
        UsageLimit(kind: .model, model: "Claude and GPT models", percent: 0, resetsAt: minutes(300), windowSeconds: 18_000),
        UsageLimit(kind: .model, model: "Claude and GPT models", percent: 6, resetsAt: minutes(60 * 24 * 5 + 90), windowSeconds: 604_800),
        UsageLimit(kind: .model, model: "Gemini 4 Argon", percent: 12, resetsAt: minutes(60 * 24 * 5 + 90), windowSeconds: 604_800),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
]

/// The sentence a Gemini card gives when Antigravity is not installed.
let geminiWithoutAntigravity = AccountUsage(account: gemini, status: .notReadable, checkedAt: minutes(-2), reason: .consumerPlan)

/// Each state of the board, one account each (the key is the name of the image).
let providerStates: [(name: String, usage: AccountUsage)] = [
    ("expired-codex", providerAccounts[3]),
    ("format-changed", AccountUsage(account: cursor, status: .formatChanged, limits: [
        UsageLimit(kind: .monthly, percent: 63, resetsAt: minutes(60 * 24 * 12), windowSeconds: monthSeconds),
        UsageLimit(kind: .model, model: "API", percent: 88, resetsAt: minutes(60 * 24 * 12), windowSeconds: monthSeconds),
    ], fetchedAt: minutes(-120), checkedAt: minutes(-2), detail: "unknown answer")),
    ("do-not-read", AccountUsage(account: weekend, status: .ok, limits: [
        UsageLimit(kind: .weekly, percent: 37, resetsAt: minutes(60 * 24 * 5)),
    ], fetchedAt: minutes(-60 * 48), checkedAt: minutes(-60 * 48))),
    ("sentence-gemini", geminiWithoutAntigravity),
    ("sentence-grok-no-cli", AccountUsage(account: grok, status: .notReadable, checkedAt: minutes(-2), reason: .noCLI)),
    ("sentence-codex-api-key", AccountUsage(account: codexKey, status: .notReadable, checkedAt: minutes(-2), reason: .apiKey)),
    ("sentence-codex-keychain", AccountUsage(account: codexPlus, status: .notReadable, checkedAt: minutes(-2), reason: .keychainOrSignedOut)),
    ("no-figure-grok", AccountUsage(account: grok, status: .ok, fetchedAt: minutes(-2), checkedAt: minutes(-2), note: .noFigureYet)),
    ("unavailable-grok", AccountUsage(account: grok, status: .unavailable, limits: [
        UsageLimit(kind: .period, percent: 46, resetsAt: minutes(60 * 24 * 3 + 240), windowSeconds: 604_800),
    ], fetchedAt: minutes(-12), checkedAt: minutes(-2), failureCount: 2, retryAfter: minutes(15), detail: "HTTP 429")),
    ("pending-codex", AccountUsage(account: codexPlus, status: .pending)),
]

var settings = BrimlineSettings()
settings.extraFolders = [unavailable.source]
settings.labels = [long.id: "Research lab"]
// The images of the README show the panel as it is once the hint about other providers has been dismissed.
settings.providerHintDismissed = true
if withPercent { settings.showPercentInMenuBar = true }
// The default captures follow the app's default: no percentage in the menu bar.
precondition(withPercent || !settings.showPercentInMenuBar, "default captures must have the percentage off")

let icon = NSImage(contentsOf: root.appendingPathComponent("design/icons/AppIcon.icns"))

/// The settings of the images with the providers: every provider on, a label on the team seat and on the
/// work Codex folder, and one account marked "Do not read".
var providerSettings: BrimlineSettings {
    var s = settings
    s.enabledProviders = Provider.allCases.map(\.rawValue)
    s.labels[lab.id] = "Research lab"
    s.labels[codexWork.id] = "Codex work"
    s.unreadAccounts = [weekend.id]
    s.extraCodexFolders = [codexWork.source, codexKey.source]
    return s
}

@MainActor
func model(_ accounts: [AccountUsage], language: Language, settings: BrimlineSettings = settings) -> AppModel {
    let m = AppModel(preview: UsageSnapshot(generatedAt: minutes(-2), accounts: accounts), settings: settings,
                     now: now, language: language, timeZone: paris, home: home, launchAtLogin: true)
    m.appIcon = icon
    m.menuBar = fakeMenuBar()
    m.refreshMenuBarApps()
    return m
}

/// The Menu Bar tab of the images: the three apps "installed", each with a neutral tile and its first letters,
/// never the icon of the real app (no third-party logo in the repository), and nothing is opened.
@MainActor
func fakeMenuBar() -> MenuBarEnvironment {
    MenuBarEnvironment(
    locate: { URL(fileURLWithPath: "/Applications/\($0).app", isDirectory: true) },
    icon: { url in
        let id = url.deletingPathExtension().lastPathComponent
        guard let app = MenuBarApp.allCases.first(where: { $0.bundleIdentifier == id }) else { return nil }
        let letters = String(app.displayName.prefix(2))
        return NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            NSColor.white.setFill()
            tile.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            tile.lineWidth = 0.5
            tile.stroke()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.black,
            ]
            let size = letters.size(withAttributes: attributes)
            letters.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
            return true
        }
    },
    openApp: { _ in true }, openURL: { _ in true }, openBundle: { _ in true })
}

/// Brimline's bar in the images: it answers what the image needs, and puts nothing in the real menu bar.
@MainActor
final class PictureBar: MenuBarSeparating {
    var answer: MenuBarHiding.Decision
    var onRecheck: ((MenuBarHiding.Decision) -> Void)?
    var onClick: (() -> Void)?
    init(_ answer: MenuBarHiding.Decision) { self.answer = answer }
    func setPresent(_ present: Bool) {}
    func hide() -> MenuBarHiding.Decision { answer }
    func show() {}
}

/// A model with hiding on (QUOTA-73), its icons hidden or not (maybe partly), or refused for `refusal`.
@MainActor
func hidingModel(_ accounts: [AccountUsage], language: Language, hidden: Bool = false, partial: Bool = false,
                 refusal: MenuBarHiding.Refusal? = nil) -> AppModel {
    var s = settings
    s.menuBarHiding.enabled = true
    let m = model(accounts, language: language, settings: s)
    m.attachSeparator(PictureBar(refusal.map { .refuse($0) } ?? .hide(length: 921, partial: partial)))
    if hidden || partial || refusal != nil { m.hideMenuBarIcons() }
    return m
}

/// The picture of the one gesture, for the guide: before, after the Command-drag, hidden.
/// Neutral tiles with first letters, never the logo of another app.
struct HidingGesturePicture: View {
    var strings: Strings
    static let tile: CGFloat = 22
    static let gap: CGFloat = 8
    static let names = ["Cl", "Ch", "Cu", "Ge"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(strings.menuBarHidingPictureBefore) {
                VStack(alignment: .leading, spacing: 2) {
                    dragArrow
                    strip { bar; tiles(); rest }
                }
            }
            step(strings.menuBarHidingPictureAfter) { strip { tiles(); bar; rest } }
            step(strings.menuBarHidingPictureHidden) { strip { arrow; rest } }
        }
        .padding(20)
        .frame(width: 600, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func step<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func tiles() -> some View {
        HStack(spacing: Self.gap) {
            ForEach(Self.names, id: \.self) { name in
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: Self.tile, height: Self.tile)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.13)))
            }
        }
    }

    private var bar: some View {
        Capsule().fill(SGTheme.accent).frame(width: 2.5, height: 20)
    }

    /// The bar while the icons are hidden: an arrow, beside the icons that stay.
    private var arrow: some View {
        Image(systemName: "chevron.left.2").font(.system(size: 12, weight: .semibold)).foregroundStyle(SGTheme.accent)
    }

    private var rest: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi")
            Image(systemName: "magnifyingglass")
            Image(nsImage: BrimlineGlyph.image(level: 0.58))
            Text("12:20").monospacedDigit()
        }
    }

    /// An arrow from the tiles to the left of the bar, with the Command key.
    private var dragArrow: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Path { p in
                    // From above the tiles (their middle is 12 + 2.5 + 12 + 49 pt from the left of the strip) to the left of the bar.
                    p.move(to: CGPoint(x: 75, y: 22))
                    p.addQuadCurve(to: CGPoint(x: 8, y: 22), control: CGPoint(x: 42, y: -6))
                    p.move(to: CGPoint(x: 8, y: 22))
                    p.addLine(to: CGPoint(x: 6, y: 13))
                    p.move(to: CGPoint(x: 8, y: 22))
                    p.addLine(to: CGPoint(x: 16, y: 17))
                }
                .stroke(SGTheme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 90, height: 26)
            Text("⌘")
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary.opacity(0.25), lineWidth: 0.5)))
            Text(strings.menuBarHidingPictureDrag)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
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

/// The settings of the Accounts images: Claude, ChatGPT and Gemini on, Grok off (and Cursor, off by default).
var accountsTabSettings: BrimlineSettings {
    var s = providerSettings
    s.enabledProviders = [Provider.claude, .chatgpt, .gemini].map(\.rawValue)
    s.unreadAccounts = [codexWork.id]
    return s
}

let accountsTabUsages = [providerAccounts[0], providerAccounts[1], providerAccounts[2], providerAccounts[3], providerAccounts[6]]

// Four Claude accounts of one person (QUOTA-72): the dots of the panel and the colors in the settings. Work has a
// free violet close to Personal's (in the dark appearance), Side project a free grey too pale for the light mode, to show both warnings.
let personal = account("you@claude.ai", ".claude", org: "Example", seat: "max")
let work = account("work@claude.ai", ".claude-work", org: "Example Team", seat: "max")
let client = account("client@claude.ai", ".claude-client", org: "Example Client", seat: "max")
let side = account("side@claude.ai", ".claude-side", org: "Example Side", seat: "max")

let fourClaude: [AccountUsage] = [
    AccountUsage(account: personal, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 34, resetsAt: minutes(130)),
        UsageLimit(kind: .weekly, percent: 58, resetsAt: minutes(60 * 24 * 2 + 40)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: work, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 12, resetsAt: minutes(130)),
        UsageLimit(kind: .weekly, percent: 22, resetsAt: minutes(60 * 24 * 2 + 40)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: client, status: .ok, limits: [
        UsageLimit(kind: .session, percent: 94, resetsAt: minutes(38)),
        UsageLimit(kind: .weekly, percent: 61, resetsAt: minutes(60 * 24 * 2 + 40)),
    ], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    AccountUsage(account: side, status: .expired, limits: [
        UsageLimit(kind: .weekly, percent: 9, resetsAt: minutes(60 * 24 * 4)),
    ], fetchedAt: minutes(-180), checkedAt: minutes(-2)),
]

/// The settings of the images of the colors: Claude, ChatGPT and Gemini on, the four accounts named.
var colorsSettings: BrimlineSettings {
    var s = BrimlineSettings()
    s.providerHintDismissed = true
    s.enabledProviders = [Provider.claude, .chatgpt, .gemini].map(\.rawValue)
    s.labels = [personal.id: "Personal", work.id: "Work", client.id: "Client", side.id: "Side project"]
    return s
}

/// The same, in French.
var colorsSettingsFR: BrimlineSettings {
    var s = colorsSettings
    s.labels = [personal.id: "Perso", work.id: "Travail", client.id: "Client", side.id: "Projet perso"]
    return s
}

/// With the two warnings: Work's free violet is close to Personal's, Side project's free grey is too pale for light mode.
func withWarnings(_ settings: BrimlineSettings) -> BrimlineSettings {
    var s = settings
    s.accountColors = [work.id: .custom("9870E6"), side.id: .custom("D9DEE3")]
    return s
}

/// A panel with the accounts of the providers in `enabled` only, for the sheets of states.
@MainActor
func statePanel(_ usages: [AccountUsage], enabled: [Provider], language: Language, hint: Bool = false,
                unread: [String] = [], expand: [String] = []) -> AnyView {
    var s = providerSettings
    s.enabledProviders = enabled.map(\.rawValue)
    s.providerHintDismissed = !hint
    s.unreadAccounts = unread
    let m = model(usages, language: language, settings: s)
    for id in expand { m.toggleNote(accountID: id) }
    return AnyView(PanelFrame(content: PanelView(model: m, opaqueBackground: true)))
}

/// Panels side by side, aligned at the top.
@MainActor
func sheet(_ panels: [AnyView]) -> some View {
    HStack(alignment: .top, spacing: 0) {
        ForEach(0..<panels.count, id: \.self) { panels[$0] }
    }
}

@MainActor
func stateUsage(_ name: String) -> AccountUsage { providerStates.first { $0.name == name }!.usage }

@MainActor
func statePanel(named name: String, language: Language, unread: [String] = [], expand: Bool = false) -> AnyView {
    let usage = stateUsage(name)
    return statePanel([usage], enabled: [usage.account.provider], language: language, unread: unread,
                      expand: expand ? [usage.account.id] : [])
}

// MARK: Menu bar element (QUOTA-70, lot L4)

/// One row of the menu bar sheet: a caption, and the gauge for fictitious accounts.
struct BarCase {
    var caption: String
    var usages: [AccountUsage]
    var colors: [String: AccountColor]
}

/// A Claude account (one per folder) that has read a given percentage of its tightest limit.
func claudeUsage(_ index: Int, _ percent: Double, status: AccountStatus = .ok) -> AccountUsage {
    let acct = account("account\(index)@claude.ai", ".claude-\(index)", org: nil, seat: "max")
    return AccountUsage(account: acct, status: status,
                        limits: [UsageLimit(kind: .session, percent: percent, resetsAt: minutes(100))],
                        fetchedAt: minutes(status == .ok ? -2 : -200), checkedAt: minutes(-2))
}

func barCases() -> [BarCase] {
    func colored(_ usages: [AccountUsage]) -> [String: AccountColor] {
        Dictionary(uniqueKeysWithValues: usages.enumerated().map { ($1.account.id, AccountColor.palette($0)) })
    }
    let one = [claudeUsage(0, 34)]
    // The example of the request: Gemini pink, Claude mauve, ChatGPT blue, and two more accounts.
    let three = [
        AccountUsage(account: provider(.claude, ".claude"), status: .ok, limits: [UsageLimit(kind: .weekly, percent: 58, resetsAt: minutes(300))], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
        AccountUsage(account: provider(.chatgpt, ".codex"), status: .ok, limits: [UsageLimit(kind: .weekly, percent: 22, resetsAt: minutes(300))], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
        AccountUsage(account: provider(.gemini, ".gemini"), status: .ok, limits: [UsageLimit(kind: .weekly, percent: 33, resetsAt: minutes(300))], fetchedAt: minutes(-2), checkedAt: minutes(-2)),
    ]
    let threeColors: [String: AccountColor] = Dictionary(uniqueKeysWithValues: three.map {
        ($0.account.id, AccountColor.palette(AccountPalette.providerSlot[$0.account.provider]!))
    })
    let ten = (0..<10).map { claudeUsage($0, [58, 22, 9, 41, 3, 67, 0.4, 15, 80, 28][$0]) }
    let alert = [claudeUsage(0, 58), claudeUsage(1, 22), claudeUsage(2, 94), claudeUsage(3, 9), claudeUsage(4, 41)]
    let stale = [claudeUsage(0, 58), claudeUsage(1, 62, status: .expired), claudeUsage(2, 30)]
    return [
        BarCase(caption: "1 account", usages: one, colors: colored(one)),
        BarCase(caption: "3 accounts", usages: three, colors: threeColors),
        BarCase(caption: "10 accounts", usages: ten, colors: colored(ten)),
        BarCase(caption: "Alert (one account at 94 %)", usages: alert, colors: colored(alert)),
        BarCase(caption: "Last known value (dimmed)", usages: stale, colors: colored(stale)),
        BarCase(caption: "No counted account", usages: [], colors: [:]),
    ]
}

/// The menu bar element on a simulated bar, light and dark, drawn at 2x and at 1x with real pixels
/// and enlarged without smoothing (6 px per point) to be read. One sheet per appearance.
@MainActor
func renderMenuBarSheet(dark: Bool, name: String) throws {
    let enlarge = 6, bar = 24, margin = 10
    let cases = barCases()
    let barWidth = 74 + 2 * margin
    let captionWidth = 200
    let rowHeight = bar * enlarge + 2 * margin
    let width = captionWidth + 2 * (barWidth * enlarge) + 3 * margin * 2
    let height = rowHeight * cases.count + 56
    let barColor: UInt32 = dark ? 0x2B2D31 : 0xE6E7EA
    let labelRGB: UInt32 = dark ? 0xF2F2F4 : 0x1D1D1F
    let page: UInt32 = dark ? 0x1C1C1E : 0xFFFFFF
    func cg(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let sheet = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    sheet.setFillColor(cg(page))
    sheet.fill(CGRect(x: 0, y: 0, width: width, height: height))

    func text(_ string: String, x: Int, yTop: Int, size: CGFloat, weight: NSFont.Weight = .regular) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: NSColor(cgColor: cg(labelRGB))!]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
        NSAttributedString(string: string, attributes: attributes).draw(at: NSPoint(x: x, y: height - yTop - Int(size * 1.3)))
        NSGraphicsContext.restoreGraphicsState()
    }
    text("Menu bar element, \(dark ? "dark" : "light") bar: 2x (left) and 1x (right), pixels enlarged \(enlarge)x",
         x: margin, yTop: 14, size: 15, weight: .semibold)

    for (row, item) in barCases().enumerated() {
        let top = 56 + row * rowHeight
        text(item.caption, x: margin, yTop: top + rowHeight / 2 - 8, size: 15)
        let gauge = MenuBarGauge.model(item.usages, settings: settings, providers: Set(Provider.allCases), now: now)
        for (column, scale) in [2, 1].enumerated() {
            let itemWidth = Int(MenuBarGaugeImage.width(accounts: gauge.segments.count))
            let pxW = barWidth * scale, pxH = bar * scale
            guard let small = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            small.setFillColor(cg(barColor))
            small.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
            small.translateBy(x: CGFloat(((barWidth - itemWidth) / 2) * scale), y: CGFloat(3 * scale))   // centered in the 24 pt bar
            small.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            if gauge.segments.isEmpty {
                BrimlineGlyph.draw(level: nil, in: small, scale: CGFloat(scale), color: cg(labelRGB))
            } else {
                MenuBarGaugeImage.draw(gauge, colors: item.colors, in: small,
                                       size: CGSize(width: itemWidth, height: 18), scale: CGFloat(scale), dark: dark, label: cg(labelRGB))
            }
            guard let image = small.makeImage() else { throw CocoaError(.fileWriteUnknown) }
            let x = captionWidth + margin * 2 + column * (barWidth * enlarge + margin * 2)
            sheet.saveGState()
            sheet.interpolationQuality = .none
            sheet.draw(image, in: CGRect(x: x, y: height - top - bar * enlarge - margin, width: barWidth * enlarge, height: bar * enlarge))
            sheet.restoreGState()
        }
    }
    guard let cgImage = sheet.makeImage(),
          let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    let url = output.appendingPathComponent(name + ".png")
    try png.write(to: url)
    print("wrote \(url.path) (\(width)x\(height) px)")
}

@MainActor
func run() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    for dark in [false, true] {
        let suffix = dark ? "dark" : "light"
        try renderMenuBarSheet(dark: dark, name: "menubar-gauge-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(mainAccounts, language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(stateAccounts, language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-states-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(mainAccounts, language: .fr), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-fr-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(stateAccounts, language: .fr), opaqueBackground: true)),
                   size: nil, dark: dark, name: "panel-states-fr-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model([], language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "qa-panel-empty-\(suffix)")
        try render(PanelFrame(content: PanelView(model: model(mainAccounts + stateAccounts.dropFirst(), language: .en), opaqueBackground: true)),
                   size: nil, dark: dark, name: "qa-panel-many-\(suffix)")

        // One account per provider and every state (QUOTA-35, board D, variant A: grouped by provider).
        for language in [Language.en, .fr] {
            let fr = language == .fr ? "-fr" : ""
            try render(PanelFrame(content: PanelView(model: model(providerAccounts, language: language, settings: providerSettings),
                                                     opaqueBackground: true, maxCardsHeight: 4000)),
                       size: nil, dark: dark, name: "panel-providers\(fr)-\(suffix)")
        }
        let wk = weekend.id
        try render(sheet([statePanel(named: "expired-codex", language: .en), statePanel(named: "format-changed", language: .en),
                          statePanel(named: "do-not-read", language: .en, unread: [wk]),
                          statePanel(named: "sentence-gemini", language: .en)]),
                   size: nil, dark: dark, name: "qa-panel-provider-states-1-\(suffix)")
        try render(sheet([statePanel(named: "sentence-gemini", language: .en, expand: true),
                          statePanel(named: "sentence-grok-no-cli", language: .en),
                          statePanel(named: "sentence-codex-api-key", language: .en),
                          statePanel(named: "sentence-codex-keychain", language: .en)]),
                   size: nil, dark: dark, name: "qa-panel-provider-states-2-\(suffix)")
        try render(sheet([statePanel(named: "no-figure-grok", language: .en), statePanel(named: "unavailable-grok", language: .en),
                          statePanel(named: "pending-codex", language: .en),
                          statePanel([], enabled: [.chatgpt], language: .en)]),
                   size: nil, dark: dark, name: "qa-panel-provider-states-3-\(suffix)")
        try render(sheet([statePanel([providerAccounts[0]], enabled: [.claude], language: .en, hint: true)]),
                   size: nil, dark: dark, name: "qa-panel-provider-hint-\(suffix)")
        try render(sheet([statePanel(named: "expired-codex", language: .fr), statePanel(named: "do-not-read", language: .fr, unread: [wk]),
                          statePanel(named: "sentence-gemini", language: .fr, expand: true),
                          statePanel([providerAccounts[0]], enabled: [.claude], language: .fr, hint: true)]),
                   size: nil, dark: dark, name: "qa-panel-provider-states-fr-\(suffix)")

        // The dots of the accounts in the panel and the color line in the settings (QUOTA-72), in both languages.
        for language in [Language.en, .fr] {
            let fr = language == .fr ? "-fr" : ""
            let base = language == .fr ? colorsSettingsFR : colorsSettings
            let usages = fourClaude + [providerAccounts[2], geminiWithoutAntigravity]
            try render(PanelFrame(content: PanelView(model: model(usages, language: language, settings: base),
                                                     opaqueBackground: true, maxCardsHeight: 4000)),
                       size: nil, dark: dark, name: "panel-accounts\(fr)-\(suffix)")
            let m = model(fourClaude, language: language, settings: withWarnings(base))
            m.settingsTab = .accounts
            let height: CGFloat = 1280
            try render(WindowFrame(title: m.strings.settingsTitle, content: SettingsView(model: m, height: height)),
                       size: CGSize(width: SettingsView.size.width + 24, height: height + 31 + 24),
                       dark: dark, name: "settings-colors\(fr)-\(suffix)")
        }

        for tab in SettingsTab.allCases {
            let m = model(accountsTabUsages + [stateAccounts[2]], language: .en, settings: accountsTabSettings)
            m.settingsTab = tab
            let size = CGSize(width: SettingsView.size.width + 24, height: SettingsView.size.height + 31 + 24)
            try render(WindowFrame(title: m.strings.settingsTitle, content: SettingsView(model: m)),
                       size: size, dark: dark, name: "settings-\(tab.rawValue)-\(suffix)")
        }
        // The Accounts, Menu Bar and Agents tabs scroll in the window: these images show them whole, for the QA.
        for tab in [SettingsTab.accounts, .menuBar, .agents] {
            let m = model(accountsTabUsages + [stateAccounts[2]], language: .en, settings: accountsTabSettings)
            m.settingsTab = tab
            let height: CGFloat = 1180
            try render(WindowFrame(title: m.strings.settingsTitle, content: SettingsView(model: m, height: height)),
                       size: CGSize(width: SettingsView.size.width + 24, height: height + 31 + 24),
                       dark: dark, name: "qa-settings-\(tab.rawValue)-full-\(suffix)")
        }
        let fr = model(accountsTabUsages, language: .fr, settings: accountsTabSettings)
        fr.settingsTab = .accounts
        try render(WindowFrame(title: fr.strings.settingsTitle, content: SettingsView(model: fr)),
                   size: CGSize(width: SettingsView.size.width + 24, height: SettingsView.size.height + 31 + 24),
                   dark: dark, name: "settings-accounts-fr-\(suffix)")
        let frMenuBar = model(accountsTabUsages, language: .fr, settings: accountsTabSettings)
        frMenuBar.settingsTab = .menuBar
        try render(WindowFrame(title: frMenuBar.strings.settingsTitle, content: SettingsView(model: frMenuBar, height: 880)),
                   size: CGSize(width: SettingsView.size.width + 24, height: 880 + 31 + 24),
                   dark: dark, name: "settings-menuBar-fr-\(suffix)")

        // Hiding the icons left of Brimline's bar (QUOTA-73): the section turned on, the drawing of the one gesture,
        // and the button of the window in its three states.
        for language in [Language.en, .fr] {
            let lang = language == .fr ? "-fr" : ""
            let on = hidingModel([], language: language)
            try render(WindowFrame(title: on.strings.settingsTitle,
                                   content: Form { MenuBarHidingSection(model: on) }.formStyle(.grouped)
                                       .frame(width: SettingsView.size.width, height: 400)),
                       size: CGSize(width: SettingsView.size.width + 24, height: 400 + 31 + 24),
                       dark: dark, name: "settings-menuBar-hiding\(lang)-\(suffix)")
            try render(PanelFrame(content: HidingGesturePicture(strings: on.strings)),
                       size: nil, dark: dark, name: "menubar-hiding-gesture\(lang)-\(suffix)")
            try render(sheet([
                AnyView(PanelFrame(content: PanelView(model: hidingModel(mainAccounts, language: language), opaqueBackground: true))),
                AnyView(PanelFrame(content: PanelView(model: hidingModel(mainAccounts, language: language, hidden: true), opaqueBackground: true))),
                AnyView(PanelFrame(content: PanelView(model: hidingModel(mainAccounts, language: language, partial: true),
                                                      opaqueBackground: true))),
                AnyView(PanelFrame(content: PanelView(model: hidingModel(mainAccounts, language: language, refusal: .brimlineLeftOfBar),
                                                      opaqueBackground: true))),
            ]), size: nil, dark: dark, name: "qa-panel-menubar-hiding\(lang)-\(suffix)")
        }
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
