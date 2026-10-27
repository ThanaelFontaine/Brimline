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
