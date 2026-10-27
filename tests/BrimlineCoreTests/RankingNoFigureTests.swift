import Foundation
import Testing
@testable import BrimlineCore

/// An account that was read but has no number yet (Grok, "No number yet for this period.") must never be
/// ranked: with no limit it would read as 100% room and `best_account` would recommend it over a measured account.
@Suite("Ranking leaves out an account with no number")
struct RankingNoFigureTests {
    let now = date("2026-10-27T10:00:00Z")

    @Test("An ok account with no limit is not ranked, a measured account is")
    func noFigureIsNeverRanked() {
        let empty = AccountUsage(account: Account(provider: .grok, source: "/h/.grok/auth.json", email: nil, organization: nil,
                                                  seatTier: nil, keychainService: nil),
                                 status: .ok, fetchedAt: now, note: .noFigureYet)
        let measured = AccountUsage(account: Account(provider: .grok, source: "/h/.grok-b/auth.json", email: nil, organization: nil,
                                                     seatTier: nil, keychainService: nil),
                                    status: .ok,
                                    limits: [UsageLimit(kind: .period, percent: 40, resetsAt: now.addingTimeInterval(3600))],
                                    fetchedAt: now)
        #expect(Ranking.rank([empty], window: .any, model: nil, now: now).isEmpty)
        #expect(Ranking.rank([empty, measured], window: .any, model: nil, now: now).map(\.headroom) == [60])
    }
}
