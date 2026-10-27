import Foundation
import Testing
@testable import BrimlineCore

/// What `brimline status` prints, read from the text itself (QUOTA-35, the real try of 27/10/2026).
@Suite("brimline status: the text of each card")
struct StatusTextTests {
    let now = date("2026-10-27T18:00:00Z")

    func lines(_ usage: AccountUsage, language: Language = .en, settings: BrimlineSettings = BrimlineSettings()) -> [String] {
        StatusText.lines(for: usage, settings: settings, strings: Strings(language),
                         time: TimeFormatter(language: language, timeZone: TimeZone(identifier: "UTC")!), now: now,
                         refreshMinutes: 5)
    }

    func cursor() -> AccountUsage {
        let end = date("2026-11-21T00:00:00Z")
        let month = 2_678_400
        let account = Account(provider: .cursor, source: "/tmp/someone/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                              email: nil, organization: nil, seatTier: nil, keychainService: nil)
        return AccountUsage(account: account, status: .ok, limits: [
            UsageLimit(kind: .monthly, percent: 0, resetsAt: end, windowSeconds: month, label: "free"),
            UsageLimit(kind: .model, model: "Auto", percent: 0, resetsAt: end, windowSeconds: month),
            UsageLimit(kind: .model, model: "API", percent: 0, resetsAt: end, windowSeconds: month),
        ], fetchedAt: now, checkedAt: now)
    }

    @Test("Cursor's pools of a month are \"Month · Auto\" and \"Month · API\", never \"Week\"")
    func cursorPoolsSayMonth() {
        let text = lines(cursor()).joined(separator: "\n")
        #expect(text.contains("Month · Auto") && text.contains("Month · API"))
        #expect(!text.contains("Week"))
        let fr = lines(cursor(), language: .fr).joined(separator: "\n")
        #expect(fr.contains("Mois · Auto") && fr.contains("Mois · API") && !fr.contains("Semaine"))
    }

    @Test("Cursor Free, read from the skeleton of a real answer, says Month for its three limits")
    func cursorFromTheRealShape() throws {
        let reading = try CursorUsageParser.parse(try fixture("cursor-usage-summary-free"))
        let account = Account(provider: .cursor, source: "/tmp/someone/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                              email: nil, organization: nil, seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .ok, limits: reading.limits, fetchedAt: now, checkedAt: now)
        let text = lines(usage)
        #expect(text.filter { $0.contains("Month") }.count == 3)
        #expect(!text.joined().contains("Week"))
    }

    @Test("Claude's model limits keep their week: the provider changes nothing for a week")
    func claudeKeepsItsWeek() {
        let account = Account(provider: .claude, source: "/tmp/someone/.claude", email: "your@claude.ai", organization: nil,
                              seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .ok, limits: [
            UsageLimit(kind: .model, model: "Fable", percent: 12, resetsAt: date("2026-10-30T10:00:00Z"), windowSeconds: 604_800),
            UsageLimit(kind: .model, model: "Opus", percent: 3, resetsAt: nil),
        ], fetchedAt: now, checkedAt: now)
        let text = lines(usage).joined(separator: "\n")
        #expect(text.contains("Week · Fable"))
        #expect(text.contains("Week · Opus"))
    }
}
