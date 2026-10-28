import Foundation
import Testing
@testable import BrimlineCore

/// The rules of the menu bar gauge (QUOTA-70, lot L2): which accounts count, the part of each, the alert.
@Suite("Menu bar gauge")
struct MenuBarGaugeTests {
    let now = date("2026-10-27T18:00:00Z")
    let later = date("2026-10-28T00:00:00Z")
    let earlier = date("2026-10-27T10:00:00Z")

    func acct(_ name: String) -> Account { acct(.claude, name) }

    func acct(_ provider: Provider, _ name: String) -> Account {
        Account(provider: provider, source: "/tmp/gauge/\(name)", email: nil, organization: nil, seatTier: nil,
                keychainService: nil)
    }

    func read(_ account: Account, _ percent: Double, status: AccountStatus = .ok, resets: Date? = nil) -> AccountUsage {
        AccountUsage(account: account, status: status,
                     limits: [UsageLimit(kind: .session, percent: percent, resetsAt: resets ?? later)],
                     fetchedAt: now, checkedAt: now)
    }

    func gauge(_ usages: [AccountUsage], settings: BrimlineSettings = allOn, providers: Set<Provider>? = nil) -> GaugeModel {
        MenuBarGauge.model(usages, settings: settings, providers: providers ?? Set(Provider.allCases), now: now)
    }

    @Test("No account: an empty gauge")
    func empty() {
        let g = gauge([])
        #expect(g.segments.isEmpty && g.total == 0 && g.mostLoaded == nil && g.alerts.isEmpty && g.withoutFigure.isEmpty)
    }

    @Test("One account: its part is its percentage")
    func one() {
        let a = acct("a")
        let g = gauge([read(a, 42)])
        #expect(g.segments.count == 1)
        #expect(g.segments[0].percent == 42 && abs(g.segments[0].share - 0.42) < 1e-12)
        #expect(abs(g.total - 0.42) < 1e-12 && g.mostLoaded?.accountID == a.id)
    }

    @Test("Three accounts: each part is its percentage over three, the total is the average")
    func three() {
        let usages = [read(acct("a"), 60), read(acct(.chatgpt, "b"), 30), read(acct(.grok, "c"), 0)]
        let g = gauge(usages)
        #expect(g.segments.map(\.percent) == [60, 30, 0])
        #expect(abs(g.segments[0].share - 0.2) < 1e-12 && abs(g.segments[1].share - 0.1) < 1e-12 && g.segments[2].share == 0)
        #expect(abs(g.total - 0.3) < 1e-12)
    }

    @Test("Ten accounts at 100 % fill the gauge exactly, never more")
    func ten() {
        let usages = (0..<10).map { read(acct("a\($0)"), 100) }
        let g = gauge(usages)
        #expect(g.segments.count == 10 && g.total <= 1 && abs(g.total - 1) < 1e-9)
        #expect(g.segments.allSatisfy { abs($0.share - 0.1) < 1e-12 })
    }

    @Test("Percentages of 0, 0.4, 50, 100 and 140 (never over 100)", arguments: [0.0, 0.4, 50, 100, 140])
    func percentages(p: Double) {
        let g = gauge([read(acct("a"), p), read(acct("b"), 20)])
        let expected = min(p, 100)
        #expect(g.segments[0].percent == expected)
        #expect(abs(g.segments[0].share - expected / 200) < 1e-12)
        #expect(g.total <= 1)
    }

    @Test("The sum of the parts never goes over 1, for 1 to 10 accounts at any value (fixed seed)")
    func sumProperty() {
        var generator = SplitMix64(seed: 20_261_027)
        for _ in 0..<500 {
            let count = Int(generator.next() % 10) + 1
            let usages = (0..<count).map { i in
                read(acct("p\(i)"), Double(generator.next() % 20_000) / 100 - 10)
            }
            let g = gauge(usages)
            #expect(g.total <= 1 && g.total >= 0)
            #expect(g.segments.allSatisfy { $0.share >= 0 && $0.share <= 1 / Double(count) + 1e-12 })
            #expect(abs(g.total - g.segments.reduce(0) { $0 + $1.share }) < 1e-9)
        }
    }

    @Test("A hidden account, a \"Do not read\" account and an account of a provider that is off do not count")
    func notCounted() {
        let hidden = acct("h"), unread = acct("u"), off = acct(.chatgpt, "o"), kept = acct("k")
        var settings = allOn
        settings.hiddenAccounts = [hidden.id]
        settings.unreadAccounts = [unread.id]
        let g = gauge([read(hidden, 90), read(unread, 90), read(off, 90), read(kept, 20)], settings: settings,
                      providers: [.claude])
        #expect(g.segments.map(\.accountID) == [kept.id] && g.withoutFigure.isEmpty && g.alerts.isEmpty)
        #expect(abs(g.total - 0.2) < 1e-12)
    }

    @Test("An account without a number stays out of N and of the gauge, and is named apart")
    func withoutFigure() {
        let numbered = acct("n"), sentence = acct(.gemini, "g"), noLimit = acct(.cursor, "c"), noCredit = acct(.grok, "k"),
            noYet = acct(.chatgpt, "y"), signedOut = acct("s")
        let usages = [
            read(numbered, 50),
            AccountUsage(account: sentence, status: .ok, fetchedAt: now, checkedAt: now),
            AccountUsage(account: noLimit, status: .ok, fetchedAt: now, checkedAt: now, note: .noLimit),
            AccountUsage(account: noCredit, status: .ok, fetchedAt: now, checkedAt: now, note: .noCreditLimit),
            AccountUsage(account: noYet, status: .ok, fetchedAt: now, checkedAt: now, note: .noFigureYet),
            AccountUsage(account: signedOut, status: .signedOut),
        ]
        let g = gauge(usages)
        #expect(g.segments.map(\.accountID) == [numbered.id])
        #expect(abs(g.segments[0].share - 0.5) < 1e-12, "N is 1: the others do not dilute")
        // The panel's order: Claude, ChatGPT, Grok, Cursor, Gemini.
        #expect(g.withoutFigure == [signedOut.id, noYet.id, noCredit.id, noLimit.id, sentence.id])
    }

    @Test("A last known value counts, and is marked stale")
    func lastKnown() {
        let expired = read(acct("e"), 40, status: .expired)
        let unavailable = read(acct("u"), 30, status: .unavailable)
        let reconnect = read(acct("r"), 20, status: .reconnect)
        let changed = read(acct("c"), 10, status: .formatChanged)
        let fresh = read(acct("f"), 60)
        let g = gauge([expired, unavailable, reconnect, changed, fresh])
        #expect(g.segments.map(\.stale) == [true, true, true, true, false])
        #expect(g.segments.count == 5 && abs(g.total - 0.32) < 1e-12)
    }

    @Test("The written percentage follows the most loaded account, up-to-date accounts first")
    func mostLoaded() {
        let stale = read(acct("s"), 95, status: .expired), fresh = read(acct("f"), 30), other = read(acct(.chatgpt, "o"), 70)
        #expect(gauge([stale, fresh, other]).mostLoaded?.accountID == other.id)
        #expect(gauge([stale]).mostLoaded?.accountID == stale.id)
        let tie = gauge([read(acct("a"), 50), read(acct("b"), 50)])
        #expect(tie.mostLoaded?.accountID == acct("a").id, "equal: the first of the panel's order")
    }

    @Test("A window whose reset time has passed counts as 0")
    func resetPassed() {
        let g = gauge([read(acct("a"), 80, resets: earlier), read(acct("b"), 20)])
        #expect(g.segments.map(\.percent) == [0, 20])
        #expect(g.alerts.isEmpty)
    }

    @Test("The tightest limit of the account is the one that counts")
    func tightest() {
        let a = acct("a")
        let usage = AccountUsage(account: a, status: .ok, limits: [
            UsageLimit(kind: .session, percent: 10, resetsAt: later),
            UsageLimit(kind: .weekly, percent: 65, resetsAt: later),
            UsageLimit(kind: .model, model: "Fable", percent: 40, resetsAt: later),
        ], fetchedAt: now, checkedAt: now)
        #expect(gauge([usage]).segments[0].percent == 65)
    }

    @Test("The alert starts at 90 %, not at 89.9 %, whatever the average is")
    func alert() {
        #expect(gauge([read(acct("a"), 89.9), read(acct("b"), 0)]).alerts.isEmpty)
        let g = gauge([read(acct("a"), 90), read(acct("b"), 0), read(acct("c"), 0)])
        #expect(g.alerts.map(\.accountID) == [acct("a").id])
        #expect(g.total < 0.31, "the average is low and the alert is there")
        #expect(MenuBarGauge.alertThreshold == 90)
    }

    @Test("Alerts are listed from the highest to the lowest, the panel's order for equal ones")
    func alertOrder() {
        let a = acct("a"), b = acct("b"), c = acct(.chatgpt, "c"), d = acct(.chatgpt, "d")
        let g = gauge([read(a, 92), read(b, 99), read(c, 92), read(d, 10)])
        #expect(g.alerts.map(\.accountID) == [b.id, a.id, c.id])
    }

    @Test("The order is the panel's, never by size, and it is stable")
    func order() {
        let cursor = acct(.cursor, "c"), claude2 = acct("z"), claude1 = acct("a"), chatgpt = acct(.chatgpt, "x"), grok = acct(.grok, "g")
        let usages = [read(cursor, 90), read(claude2, 5), read(claude1, 60), read(chatgpt, 30), read(grok, 80)]
        let ids = gauge(usages).segments.map(\.accountID)
        #expect(ids == [claude2.id, claude1.id, chatgpt.id, grok.id, cursor.id])
        #expect(gauge(usages).segments.map(\.accountID) == ids)
        var changed = usages
        changed[0] = read(cursor, 1)
        #expect(gauge(changed).segments.map(\.accountID) == ids, "a new number does not move a part")
    }
}

/// A small deterministic generator, so a "random" test gives the same values on every run.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
