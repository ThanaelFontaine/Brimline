import Foundation
import Testing
@testable import BrimlineCore

/// The example of docs/agents.md ("Two providers, one question"): the numbers the page prints are the ones
/// these calls give, so the page cannot drift from the server.
@Suite("Agents: the two provider example of the documentation")
struct AgentsDocExampleTests {
    static let now = date("2026-10-27T10:00:00Z")
    static let homeURL = URL(fileURLWithPath: "/opt/box/you")

    static var snapshot: UsageSnapshot {
        let claude = AccountUsage(
            account: account("your@claude.ai", dir: "/opt/box/you/.claude"), status: .ok,
            limits: [UsageLimit(kind: .session, percent: 34, resetsAt: now.addingTimeInterval(7_800)),
                     UsageLimit(kind: .weekly, percent: 42, resetsAt: now.addingTimeInterval(183_600))],
            fetchedAt: now.addingTimeInterval(-42))
        let codex = AccountUsage(
            account: Account(provider: .chatgpt, source: "/opt/box/you/.codex", email: nil, organization: nil,
                             seatTier: nil, keychainService: nil),
            status: .ok,
            limits: [UsageLimit(kind: .session, percent: 22, resetsAt: now.addingTimeInterval(11_100), windowSeconds: 18_000),
                     UsageLimit(kind: .weekly, percent: 71, resetsAt: now.addingTimeInterval(367_200), windowSeconds: 604_800)],
            fetchedAt: now.addingTimeInterval(-42))
        return UsageSnapshot(generatedAt: now.addingTimeInterval(-42), accounts: [claude, codex])
    }

    func best(_ arguments: String) throws -> [String: Any] {
        let server = MCPServer(version: "0.0.0", load: { (Self.snapshot, allOn) }, now: { Self.now }, home: Self.homeURL)
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"best_account","arguments":\#(arguments)}}"#))
        let answer = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let result = try #require(answer["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        return try #require(result["structuredContent"] as? [String: Any])
    }

    @Test("Claude for the week: your@claude.ai, 58 % room, the week at 42 %")
    func claudeWeek() throws {
        let answer = try best(#"{"provider":"claude","window":"week"}"#)
        let best = try #require(answer["best"] as? [String: Any])
        #expect(answer["provider"] as? String == "claude")
        #expect(best["email"] as? String == "your@claude.ai")
        #expect(best["source"] as? String == "~/.claude")
        #expect(best["headroom_percent"] as? Double == 58)
        let binding = try #require(best["binding_limit"] as? [String: Any])
        #expect(binding["kind"] as? String == "weekly")
        #expect(binding["percent"] as? Double == 42)
        #expect(binding["resets_in_seconds"] as? Int == 183_600)
    }

    @Test("ChatGPT for the week: the Codex account, 29 % room, the week at 71 %")
    func chatgptWeek() throws {
        let answer = try best(#"{"provider":"chatgpt","window":"week"}"#)
        let best = try #require(answer["best"] as? [String: Any])
        #expect(answer["provider"] as? String == "chatgpt")
        #expect(best["source"] as? String == "~/.codex")
        #expect(best["email"] is NSNull)
        #expect(best["headroom_percent"] as? Double == 29)
        let binding = try #require(best["binding_limit"] as? [String: Any])
        #expect(binding["kind"] as? String == "weekly")
        #expect(binding["percent"] as? Double == 71)
        #expect(binding["resets_in_seconds"] as? Int == 367_200)
    }
}
