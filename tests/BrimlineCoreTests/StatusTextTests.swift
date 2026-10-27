import Foundation
import Testing
@testable import BrimlineCore

/// What `brimline status` prints, read from the text itself (QUOTA-35, the real try of 27/10/2026).
@Suite("brimline status: the text of each card")
struct StatusTextTests {
    let now = date("2026-10-27T18:00:00Z")

    let home = URL(fileURLWithPath: "/tmp/someone", isDirectory: true)

    func lines(_ usage: AccountUsage, among: [AccountUsage]? = nil, language: Language = .en,
               settings: BrimlineSettings = BrimlineSettings()) -> [String] {
        StatusText.lines(for: usage, among: among ?? [usage], settings: settings, strings: Strings(language),
                         time: TimeFormatter(language: language, timeZone: TimeZone(identifier: "UTC")!), now: now,
                         home: home, refreshMinutes: 5)
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

    func card(_ provider: Provider, _ path: String, tier: String? = nil, email: String? = nil) -> AccountUsage {
        let account = Account(provider: provider, source: "/tmp/someone/" + path, email: email, organization: nil,
                              seatTier: tier, keychainService: nil)
        return AccountUsage(account: account, status: .ok, limits: [UsageLimit(kind: .period, percent: 0, resetsAt: nil)],
                            fetchedAt: now, checkedAt: now)
    }

    @Test("The titles are the panel's: the provider and its plan, never the name of the folder or of the file")
    func titles() {
        let chatgpt = card(.chatgpt, ".codex", tier: "plus", email: "someone@example.org")
        let grok = card(.grok, ".grok/auth.json")
        let cursor = card(.cursor, "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        #expect(lines(chatgpt)[0] == "ChatGPT Plus")
        #expect(lines(grok)[0] == "Grok")
        #expect(lines(cursor)[0] == "Cursor")
        let claude = card(.claude, ".claude", email: "your@claude.ai")
        #expect(lines(claude)[0] == "your@claude.ai")
        for text in [lines(chatgpt), lines(grok)].flatMap({ $0 }) {
            #expect(!text.contains(".codex") && !text.contains("auth.json") && !text.contains("example.org"))
        }
    }

    @Test("A label the user gave comes first, the provider and plan after it; several accounts of one provider say where")
    func labelsAndSiblings() {
        let work = card(.chatgpt, "codex-work", tier: "pro")
        let plain = card(.chatgpt, ".codex")
        var settings = BrimlineSettings()
        settings.labels = [work.account.id: "Codex work"]
        #expect(lines(work, among: [work, plain], settings: settings)[0] == "Codex work · ChatGPT Pro")
        #expect(lines(plain, among: [work, plain], settings: settings)[0] == "ChatGPT · ~/.codex")
        #expect(lines(plain, among: [plain], settings: settings)[0] == "ChatGPT")
    }
}
