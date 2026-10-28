import Foundation
import Testing
@testable import BrimlineCore

/// The Menu Bar tab (QUOTA-73): which apps are listed, and what happens when System Settings refuses the address.
@Suite("Menu Bar tab: the apps and System Settings")
struct MenuBarTidyTests {
    func url(_ name: String) -> URL { URL(fileURLWithPath: "/Applications/\(name).app", isDirectory: true) }

    @Test("an app is found by its bundle identifier, and the order is the one of the providers")
    func appsAreFoundByIdentifier() {
        let all = [
            "com.todesktop.230313mzl4w4u92": url("Cursor"),
            "com.anthropic.claudefordesktop": url("Claude"),
            "com.openai.codex": url("ChatGPT"),
        ]
        let found = MenuBarTidy.installed(locate: { all[$0] })
        #expect(found.map(\.app) == [.claude, .chatgpt, .cursor])
        #expect(found.map(\.url) == [url("Claude"), url("ChatGPT"), url("Cursor")])
    }

    @Test("only the installed apps are listed")
    func onlyInstalledApps() {
        let found = MenuBarTidy.installed(locate: { $0 == "com.openai.codex" ? url("ChatGPT") : nil })
        #expect(found.map(\.app) == [.chatgpt])
        #expect(MenuBarTidy.installed(locate: { _ in nil }).isEmpty)
    }

    @Test("the bundle identifiers are the ones read on the installed apps")
    func identifiers() {
        #expect(MenuBarApp.claude.bundleIdentifier == "com.anthropic.claudefordesktop")
        #expect(MenuBarApp.chatgpt.bundleIdentifier == "com.openai.codex")
        #expect(MenuBarApp.cursor.bundleIdentifier == "com.todesktop.230313mzl4w4u92")
    }

    @Test("System Settings is asked for the Menu Bar page first")
    func menuBarPageFirst() {
        var asked: [URL] = []
        var apps: [String] = []
        let outcome = MenuBarTidy.openSystemSettings(openURL: { asked.append($0); return true },
                                                     openApp: { apps.append($0); return true })
        #expect(outcome == .menuBarPage)
        #expect(asked == [URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!])
        #expect(apps.isEmpty)
    }

    @Test("when the address is refused, System Settings opens on its own")
    func fallsBackToTheApp() {
        var apps: [String] = []
        let outcome = MenuBarTidy.openSystemSettings(openURL: { _ in false }, openApp: { apps.append($0); return true })
        #expect(outcome == .homePage)
        #expect(apps == ["com.apple.systempreferences"])
    }

    @Test("when nothing opens, the outcome says so")
    func nothingOpens() {
        let outcome = MenuBarTidy.openSystemSettings(openURL: { _ in false }, openApp: { _ in false })
        #expect(outcome == .failed)
    }

    @Test("every text exists in both languages, and Cursor's switch stays in English")
    func texts() {
        for language in Language.allCases {
            let s = Strings(language)
            for app in MenuBarApp.allCases {
                #expect(!s.menuBarTurnOff(app).isEmpty)
                #expect(!s.menuBarSettingPath(app).isEmpty)
                #expect(s.menuBarOpenApp(app).contains(app.displayName))
                #expect(s.menuBarRowSpoken(app).hasPrefix(app.displayName))
            }
            #expect(s.menuBarTurnOff(.cursor).contains("Menu Bar Icon"))
            #expect(!s.menuBarTitle.contains("\u{2014}") && !s.menuBarIntro.contains("\u{2013}"))
        }
        #expect(Strings(.fr).menuBarTurnOff(.claude) == "Coupez « Barre de menus »")
        #expect(Strings(.en).menuBarTurnOff(.chatgpt) == "Turn off “Show in menu bar”")
        #expect(Strings(.en).menuBarSettingPath(.claude) == "In Settings › System")
        #expect(Strings(.fr).menuBarSettingPath(.claude) == "Dans Paramètres › Système")
    }
}
