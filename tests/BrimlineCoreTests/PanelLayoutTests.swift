import Foundation
import Testing
@testable import BrimlineCore

@Suite("Panel layout: groups by provider and the menu bar glyph")
struct PanelLayoutTests {
    static let now = date("2026-10-27T11:20:00Z")

    static func account(_ provider: Provider, _ name: String) -> Account {
        Account(provider: provider, source: "/tmp/someone/\(name)", email: nil, organization: nil, seatTier: nil,
                keychainService: nil)
    }

    static func usage(_ provider: Provider, _ name: String, percent: Double? = nil, status: AccountStatus = .ok) -> AccountUsage {
        let limits = percent.map { [UsageLimit(kind: .session, percent: $0, resetsAt: now.addingTimeInterval(3600))] } ?? []
        return AccountUsage(account: account(provider, name), status: status, limits: limits,
                            fetchedAt: percent == nil ? nil : now, checkedAt: now)
    }

    @Test("The order lists every provider once: those with numbers first, Gemini (a sentence only) last")
    func order() {
        #expect(Set(PanelLayout.providerOrder) == Set(Provider.allCases))
        #expect(PanelLayout.providerOrder.count == Provider.allCases.count)
        #expect(PanelLayout.providerOrder.last == .gemini)
        #expect(PanelLayout.providerOrder.first == .claude)
    }

    @Test("One group per provider, in the panel's order, and an account keeps its place inside its group")
    func groups() {
        let usages = [Self.usage(.gemini, "g"), Self.usage(.chatgpt, "b"), Self.usage(.claude, "a"),
                      Self.usage(.chatgpt, "a"), Self.usage(.grok, "x")]
        let groups = PanelLayout.groups(usages, enabled: Set(Provider.allCases))
        // Cursor is on but has no account: its group is still there, empty (its card says so).
        #expect(groups.map(\.provider) == [.claude, .chatgpt, .grok, .cursor, .gemini])
        #expect(groups[1].usages.map(\.account.source) == ["/tmp/someone/b", "/tmp/someone/a"])
        #expect(groups[3].usages.isEmpty)
    }

    @Test("A provider that is off and has no account has no group; one that has accounts keeps its group")
    func offProviders() {
        let usages = [Self.usage(.claude, "a"), Self.usage(.grok, "x")]
        #expect(PanelLayout.groups(usages, enabled: [.claude]).map(\.provider) == [.claude, .grok])
        #expect(PanelLayout.groups([], enabled: [.claude]).map(\.provider) == [.claude])
        #expect(PanelLayout.groups([], enabled: []).isEmpty)
        #expect(PanelLayout.groups(usages, enabled: [.claude, .grok, .cursor]).map(\.provider) == [.claude, .grok, .cursor])
    }

    @Test("The hint about other providers shows only while Claude is the single provider on, until dismissed")
    func hint() {
        #expect(PanelLayout.showsProviderHint(enabled: [.claude], dismissed: false))
        #expect(!PanelLayout.showsProviderHint(enabled: [.claude], dismissed: true))
        #expect(!PanelLayout.showsProviderHint(enabled: [.claude, .chatgpt], dismissed: false))
        #expect(!PanelLayout.showsProviderHint(enabled: [], dismissed: false))
        #expect(!PanelLayout.showsProviderHint(enabled: [.chatgpt], dismissed: false))
    }

    @Test("The glyph follows the most loaded up-to-date account, whatever the provider")
    func glyphAcrossProviders() throws {
        let usages = [Self.usage(.claude, "a", percent: 34), Self.usage(.chatgpt, "b", percent: 71),
                      Self.usage(.grok, "c", percent: 46)]
        let top = try #require(PanelLayout.glyph(usages, providers: [.claude, .chatgpt, .grok], unread: [], now: Self.now))
        #expect(top.usage.account.provider == .chatgpt && top.percent == 71 && !top.dimmed)
        // A provider that is off never sets the glyph.
        let claudeOnly = try #require(PanelLayout.glyph(usages, providers: [.claude], unread: [], now: Self.now))
        #expect(claudeOnly.percent == 34)
        #expect(PanelLayout.glyph(usages, providers: [], unread: [], now: Self.now) == nil)
    }

    @Test("An expired, unread or doubtful account counts only when no account is up to date, and then the glyph is dimmed")
    func glyphDimmed() throws {
        let fresh = Self.usage(.claude, "a", percent: 20)
        let expired = Self.usage(.chatgpt, "b", percent: 95, status: .expired)
        let unavailable = Self.usage(.grok, "c", percent: 90, status: .unavailable)
        let changed = Self.usage(.cursor, "d", percent: 85, status: .formatChanged)
        let all: Set<Provider> = [.claude, .chatgpt, .grok, .cursor]

        let withFresh = try #require(PanelLayout.glyph([fresh, expired, unavailable, changed], providers: all, unread: [], now: Self.now))
        #expect(withFresh.percent == 20 && !withFresh.dimmed)

        // The one up-to-date account is marked "Do not read": it is no longer fresh.
        let unreadFresh = try #require(PanelLayout.glyph([fresh, expired], providers: all, unread: [fresh.id], now: Self.now))
        #expect(unreadFresh.percent == 95 && unreadFresh.dimmed)

        let onlyOld = try #require(PanelLayout.glyph([expired, unavailable, changed], providers: all, unread: [], now: Self.now))
        #expect(onlyOld.percent == 95 && onlyOld.dimmed)
        #expect(PanelLayout.glyph([], providers: all, unread: [], now: Self.now) == nil)
    }

    @Test("Only sentences, no number: the glyph is empty, nothing is made up")
    func glyphWithoutNumbers() {
        let sentence = AccountUsage(account: Self.account(.gemini, "g"), status: .notReadable, reason: .consumerPlan)
        #expect(PanelLayout.glyph([sentence], providers: [.gemini], unread: [], now: Self.now) == nil)
    }

    @Test("The setting of the hint is saved, and a file written before it has it undismissed")
    func hintSetting() throws {
        var settings = BrimlineSettings()
        #expect(!settings.providerHintDismissed)
        settings.providerHintDismissed = true
        let data = try JSONCoding.encoder().encode(settings)
        #expect(try JSONCoding.decoder().decode(BrimlineSettings.self, from: data).providerHintDismissed)
        let older = try JSONCoding.decoder().decode(BrimlineSettings.self, from: Data(#"{"refreshMinutes": 10}"#.utf8))
        #expect(!older.providerHintDismissed && older.refreshMinutes == 10)
    }
}
