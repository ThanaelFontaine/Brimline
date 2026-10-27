import Foundation
import Testing
@testable import BrimlineCore

/// Cases found by hand mutation of the multi-provider base: each fails when the line it guards is removed.
@Suite("Multi-provider base: ranking and agent output edge cases")
struct ProviderGapsTests {
    static let now = date("2026-10-27T10:00:00Z")
    static let later = date("2026-10-28T10:00:00Z")

    static func usage(_ name: String, provider: Provider = .claude, status: AccountStatus,
                      percent: Double, fetched: Bool = true) -> AccountUsage {
        let account = Account(provider: provider, source: "/opt/box/you/.\(name)", email: "\(name)@example.com",
                              organization: nil, seatTier: nil, keychainService: provider == .claude ? "svc-\(name)" : nil)
        return AccountUsage(account: account, status: status,
                            limits: [UsageLimit(kind: .session, percent: percent, resetsAt: later)],
                            fetchedAt: fetched ? now.addingTimeInterval(-60) : nil)
    }

    @Test("An account that became not readable keeps its old numbers but is never ranked")
    func notReadableWithOldNumbers() {
        let stale = Self.usage("stale", status: .notReadable, percent: 0)
        let good = Self.usage("good", status: .ok, percent: 80)
        let ranking = Ranking.rank([stale, good], window: .any, model: nil, now: Self.now)
        #expect(ranking.map(\.usage.account.email) == ["good@example.com"])
    }

    @Test("format_changed accounts come after the ones that read fine, like unavailable ones")
    func formatChangedRanksLast() {
        let doubtful = Self.usage("doubtful", status: .formatChanged, percent: 0)
        let fine = Self.usage("fine", status: .ok, percent: 90)
        let ranking = Ranking.rank([doubtful, fine], window: .any, model: nil, now: Self.now)
        #expect(ranking.map(\.usage.account.email) == ["fine@example.com", "doubtful@example.com"])
    }

    @Test("In the agent report, folder is the Claude folder only: null for every other provider")
    func folderIsClaudeOnly() throws {
        let snapshot = UsageSnapshot(generatedAt: Self.now, accounts: [
            Self.usage("claude", status: .ok, percent: 10),
            Self.usage("codex", provider: .chatgpt, status: .ok, percent: 10),
        ])
        let report = AgentUsageReport(snapshot: snapshot, settings: allOn, source: "cache", now: Self.now,
                                      home: URL(fileURLWithPath: "/opt/box/you"))
        #expect(report.accounts[0].folder == "/opt/box/you/.claude")
        #expect(report.accounts[0].source == "~/.claude")
        #expect(report.accounts[1].folder == nil)
        #expect(report.accounts[1].source == "~/.codex")
        let text = report.jsonString()
        #expect(text.contains("\"folder\" : null"))
    }

    @Test("Every provider has a window list that starts with any, and a Claude window is never offered to Gemini")
    func windowTable() {
        for provider in Provider.allCases {
            #expect(provider.windows.first == .any)
        }
        #expect(!Provider.gemini.windows.contains(.session))
        #expect(!Provider.cursor.windows.contains(.week))
        #expect(Provider.claude.windows == [.any, .session, .week])
    }
}
