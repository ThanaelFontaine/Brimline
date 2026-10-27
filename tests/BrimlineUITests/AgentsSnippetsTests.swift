import AppKit
import Foundation
import Testing
import BrimlineCore
@testable import BrimlineUI

@MainActor
@Suite("Agents tab snippets")
struct AgentsSnippetsTests {
    func model(home: String) -> AppModel {
        AppModel(preview: nil, settings: BrimlineSettings(), now: Date(timeIntervalSince1970: 0),
                 language: .en, timeZone: TimeZone(identifier: "UTC")!,
                 home: URL(fileURLWithPath: home, isDirectory: true))
    }

    @Test("the Claude Code command is added for the user, so every project sees the server")
    func mcpAddCommandIsUserScoped() {
        let m = model(home: "/tmp/someone")
        #expect(m.mcpAddCommand == "claude mcp add --scope user brimline -- /tmp/someone/.local/bin/brimline mcp")
    }

    @Test("a path with a space is quoted, after the scope")
    func mcpAddCommandQuotesThePath() {
        let m = model(home: "/tmp/some one")
        #expect(m.mcpAddCommand == "claude mcp add --scope user brimline -- '/tmp/some one/.local/bin/brimline' mcp")
    }
}

@MainActor
@Suite("Accounts tab")
struct AccountsTabTests {
    @Test("a Gemini account is never described as a Claude account")
    func geminiAccountKeepsItsOwnName() {
        let account = Account(provider: .gemini, source: "/tmp/someone/.gemini", email: nil,
                              organization: nil, seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .notReadable)
        let line = AccountSettingsRow.details(for: usage, strings: Strings(.en))
        #expect(line.hasPrefix("Gemini"))
        #expect(!line.contains("Claude"))
    }
}

@MainActor
@Suite("Menu Bar tab")
struct MenuBarTabTests {
    func model(installed: [String], opens: Bool = true, systemURLWorks: Bool = true,
               opened: Box = Box()) -> AppModel {
        let m = AppModel(preview: nil, settings: BrimlineSettings(), now: Date(timeIntervalSince1970: 0),
                         language: .en, timeZone: TimeZone(identifier: "UTC")!,
                         home: URL(fileURLWithPath: "/tmp/someone", isDirectory: true))
        m.menuBar = MenuBarEnvironment(
            locate: { installed.contains($0) ? URL(fileURLWithPath: "/Applications/\($0).app") : nil },
            icon: { _ in NSImage(size: NSSize(width: 1, height: 1)) },
            openApp: { url in opened.apps.append(url); return opens },
            openURL: { opened.urls.append($0); return systemURLWorks },
            openBundle: { opened.bundles.append($0); return true })
        return m
    }

    @MainActor final class Box { var apps: [URL] = []; var urls: [URL] = []; var bundles: [String] = [] }

    @Test("the tab sits between General and Agents")
    func tabOrder() {
        #expect(SettingsTab.allCases == [.accounts, .general, .menuBar, .agents, .about])
    }

    @Test("reading the tab lists the installed apps only, each with its icon")
    func listsInstalledApps() {
        let m = model(installed: ["com.openai.codex", "com.anthropic.claudefordesktop"])
        m.refreshMenuBarApps()
        #expect(m.menuBarApps.map(\.app) == [.claude, .chatgpt])
        #expect(m.menuBarIcons.keys.sorted() == ["chatgpt", "claude"])
    }

    @Test("an app that does not open leaves a note, and the next try that works clears it")
    func appFailureNote() async throws {
        let opened = Box()
        let m = model(installed: ["com.openai.codex"], opens: false, opened: opened)
        m.refreshMenuBarApps()
        m.openMenuBarApp(.chatgpt)
        try await Task.sleep(for: .milliseconds(100))
        #expect(m.menuBarAppFailed == .chatgpt)
        #expect(opened.apps == [URL(fileURLWithPath: "/Applications/com.openai.codex.app")])
        m.refreshMenuBarApps()
        #expect(m.menuBarAppFailed == nil)
    }

    @Test("an app that is not listed is never opened")
    func unlistedAppIsNotOpened() async throws {
        let opened = Box()
        let m = model(installed: [], opened: opened)
        m.refreshMenuBarApps()
        m.openMenuBarApp(.cursor)
        try await Task.sleep(for: .milliseconds(50))
        #expect(opened.apps.isEmpty)
    }

    @Test("System Settings: the Menu Bar page when the address works, its home page with a note when it does not")
    func systemSettings() {
        let ok = Box()
        let a = model(installed: [], opened: ok)
        a.openSystemMenuBarSettings()
        #expect(a.menuBarSystemOutcome == .menuBarPage)
        #expect(ok.bundles.isEmpty)

        let refused = Box()
        let b = model(installed: [], systemURLWorks: false, opened: refused)
        b.openSystemMenuBarSettings()
        #expect(b.menuBarSystemOutcome == .homePage)
        #expect(refused.bundles == ["com.apple.systempreferences"])
        b.refreshMenuBarApps()
        #expect(b.menuBarSystemOutcome == nil)
    }
}
