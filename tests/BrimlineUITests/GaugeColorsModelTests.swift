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
}
