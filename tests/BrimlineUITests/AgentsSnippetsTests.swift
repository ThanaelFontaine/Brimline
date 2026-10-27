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
        let m = model(home: "/Users/someone")
        #expect(m.mcpAddCommand == "claude mcp add --scope user brimline -- /Users/someone/.local/bin/brimline mcp")
    }

    @Test("a path with a space is quoted, after the scope")
    func mcpAddCommandQuotesThePath() {
        let m = model(home: "/Users/some one")
        #expect(m.mcpAddCommand == "claude mcp add --scope user brimline -- '/Users/some one/.local/bin/brimline' mcp")
    }
}
