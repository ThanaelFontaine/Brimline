import Foundation
import Testing
@testable import BrimlineCore
@testable import BrimlineUI

/// The link between the core of the gauge (lot L2) and the app: one threshold, and a color for every account.
@Suite("Gauge and colors in the app model")
@MainActor
struct GaugeColorsModelTests {
    @Test("The alert threshold of the core is the critical threshold of the gauges")
    func threshold() {
        #expect(abs(MenuBarGauge.alertThreshold - SGTheme.critThreshold * 100) < 1e-9)
    }

    private func temporaryHome(claudeFolders: [String]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("brimline-ui-\(UUID().uuidString)", isDirectory: true)
        for name in claudeFolders {
            let folder = home.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let json = #"{"oauthAccount":{"emailAddress":"\#(name)@example.com"}}"#
            try Data(json.utf8).write(to: folder.appendingPathComponent(".claude.json"))
        }
        return home
    }

    @Test("A rescan gives every account a color, saves it, and keeps it at the next rescan and the next launch")
    func rescanAssignsAndKeeps() throws {
        let home = try temporaryHome(claudeFolders: [".claude-a", ".claude-b"])
        defer { try? FileManager.default.removeItem(at: home) }
        let model = AppModel(home: home)
        model.rescan()
        let ids = model.accounts.map(\.id)
        #expect(ids.count == 2)
        let given = model.settings.accountColors
        #expect(Set(given.keys) == Set(ids) && Set(given.values).count == 2)
        // On disk, so the next launch finds them.
        let stored = SettingsStore(file: BrimlinePaths(home: home).settingsFile).load()
        #expect(stored.accountColors == given)
        // A third account appears: the two first colors do not move.
        let third = home.appendingPathComponent(".claude-c", isDirectory: true)
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
        try Data(#"{"oauthAccount":{"emailAddress":"c@example.com"}}"#.utf8).write(to: third.appendingPathComponent(".claude.json"))
        model.rescan()
        #expect(model.accounts.count == 3)
        for id in ids { #expect(model.settings.accountColors[id] == given[id]) }
        #expect(Set(model.settings.accountColors.values).count == 3)
        let relaunched = AppModel(home: home)
        #expect(relaunched.settings.accountColors == model.settings.accountColors)
    }

    @Test("The model gives the gauge of the menu bar and the name of each account for its sentences")
    func menuBarGaugeOfTheModel() {
        let a = Account(provider: .claude, source: "/tmp/gauge/a", email: "a@example.com", organization: nil, seatTier: nil, keychainService: nil)
        let b = Account(provider: .claude, source: "/tmp/gauge/b", email: "b@example.com", organization: nil, seatTier: nil, keychainService: nil)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func usage(_ account: Account, _ percent: Double) -> AccountUsage {
            AccountUsage(account: account, status: .ok, limits: [UsageLimit(kind: .session, percent: percent, resetsAt: now.addingTimeInterval(3600))],
                         fetchedAt: now, checkedAt: now)
        }
        var settings = BrimlineSettings()
        settings.labels = [b.id: "Client"]
        let model = AppModel(preview: UsageSnapshot(generatedAt: now, accounts: [usage(a, 20), usage(b, 94)]), settings: settings,
                             now: now, language: .en, timeZone: TimeZone(identifier: "Europe/Paris")!, home: URL(fileURLWithPath: "/tmp/gauge"),
                             launchAtLogin: false)
        let gauge = model.menuBarGauge
        #expect(gauge.segments.map(\.accountID) == [a.id, b.id])
        #expect(gauge.alerts.map(\.accountID) == [b.id])
        #expect(abs(gauge.total - 0.57) < 1e-9)
        #expect(model.gaugeName(forAccountID: b.id) == model.title(for: b))
        #expect(model.strings.menuBarAccessibility(gauge) { model.gaugeName(forAccountID: $0) }.hasPrefix("Alert: "))
        // The bar uses the colors of the panel's dots, even for an account whose color is not kept yet.
        let colors = model.menuBarColors(for: gauge)
        #expect(colors[a.id] == model.color(for: a) && colors[b.id] == model.color(for: b))
        #expect(colors[a.id] != colors[b.id])
        // Hiding an account takes its part out of the gauge.
        model.setHidden(true, accountID: a.id)
        #expect(model.menuBarGauge.segments.map(\.accountID) == [b.id])
    }
}
