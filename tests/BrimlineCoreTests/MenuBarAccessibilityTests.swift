import Foundation
import Testing
@testable import BrimlineCore

/// What VoiceOver reads for the gauge of the menu bar (QUOTA-70, CA4), in English and in French.
@Suite("Menu bar gauge: the VoiceOver sentence")
struct MenuBarAccessibilityTests {
    let now = date("2026-10-27T18:00:00Z")
    let later = date("2026-10-28T00:00:00Z")

    func acct(_ provider: Provider, _ name: String) -> Account {
        Account(provider: provider, source: "/tmp/voice/\(name)", email: nil, organization: nil, seatTier: nil, keychainService: nil)
    }

    func read(_ account: Account, _ percent: Double, status: AccountStatus = .ok) -> AccountUsage {
        AccountUsage(account: account, status: status, limits: [UsageLimit(kind: .session, percent: percent, resetsAt: later)],
                     fetchedAt: now, checkedAt: now)
    }

    func sentence(_ usages: [AccountUsage], names: [String: String], language: Language) -> String {
        let gauge = MenuBarGauge.model(usages, settings: allOn, providers: Set(Provider.allCases), now: now)
        return Strings(language).menuBarAccessibility(gauge) { id in names[id] ?? id }
    }

    let agency = Account(provider: .claude, source: "/tmp/voice/agency", email: nil, organization: nil, seatTier: nil, keychainService: nil)
    var names: [String: String] {
        ["claude:/tmp/voice/agency": "Claude Agency", "claude:/tmp/voice/main": "Claude", "chatgpt:/tmp/voice/gpt": "ChatGPT",
         "gemini:/tmp/voice/gem": "Gemini"]
    }

    @Test("English: the alert first, then the average and each account, then the accounts with no figure")
    func english() {
        let usages = [read(agency, 94), read(acct(.claude, "main"), 8), read(acct(.chatgpt, "gpt"), 10),
                      AccountUsage(account: acct(.gemini, "gem"), status: .ok, fetchedAt: now, checkedAt: now)]
        #expect(sentence(usages, names: names, language: .en)
                == "Alert: Claude Agency at 94%. Brimline, 37% used on average across 3 accounts: Claude Agency 94%, Claude 8%, ChatGPT 10%. Gemini: no figure.")
    }

    @Test("French: l'alerte d'abord, puis la moyenne et chaque compte, puis les comptes sans chiffre")
    func french() {
        let usages = [read(agency, 94), read(acct(.claude, "main"), 8), read(acct(.chatgpt, "gpt"), 10),
                      AccountUsage(account: acct(.gemini, "gem"), status: .ok, fetchedAt: now, checkedAt: now)]
        #expect(sentence(usages, names: names, language: .fr)
                == "Alerte : Claude Agency à 94 %. Brimline, utilisé 37 % en moyenne sur 3 comptes : Claude Agency 94 %, Claude 8 %, ChatGPT 10 %. Gemini : pas de chiffre.")
    }

    @Test("No alert, no sentence about one: the average comes first, a single account is singular")
    func noAlertAndSingular() {
        let one = [read(acct(.claude, "main"), 42)]
        #expect(sentence(one, names: names, language: .en) == "Brimline, 42% used on average across 1 account: Claude 42%.")
        #expect(sentence(one, names: names, language: .fr) == "Brimline, utilisé 42 % en moyenne sur 1 compte : Claude 42 %.")
    }

    @Test("Several alerts are listed from the highest")
    func severalAlerts() {
        let usages = [read(acct(.claude, "main"), 91), read(acct(.chatgpt, "gpt"), 99)]
        let text = sentence(usages, names: names, language: .en)
        #expect(text.hasPrefix("Alert: ChatGPT at 99%, Claude at 91%. Brimline, 95% used"))
        #expect(sentence(usages, names: names, language: .fr).hasPrefix("Alerte : ChatGPT à 99 %, Claude à 91 %. Brimline"))
    }

    @Test("A last known value says so")
    func stale() {
        let usages = [read(acct(.claude, "main"), 40, status: .expired)]
        #expect(sentence(usages, names: names, language: .en).contains("Claude 40% (last known value)"))
        #expect(sentence(usages, names: names, language: .fr).contains("Claude 40 % (dernière valeur connue)"))
    }

    @Test("No account with a figure: Brimline alone, then the accounts with no figure; nothing at all: Brimline")
    func nothingToCount() {
        #expect(sentence([], names: names, language: .en) == "Brimline.")
        let gemini = [AccountUsage(account: acct(.gemini, "gem"), status: .ok, fetchedAt: now, checkedAt: now)]
        #expect(sentence(gemini, names: names, language: .en) == "Brimline. Gemini: no figure.")
        #expect(sentence(gemini, names: names, language: .fr) == "Brimline. Gemini : pas de chiffre.")
    }

    @Test("The sentence has no dash of any length")
    func noDash() {
        let usages = [read(agency, 94), read(acct(.chatgpt, "gpt"), 10), AccountUsage(account: acct(.gemini, "gem"), status: .ok)]
        for language in [Language.en, .fr] {
            let text = sentence(usages, names: names, language: language)
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
        }
    }

    @Test("The tooltip: the average, then the alerts after a middle dot, in English and in French")
    func tooltip() {
        let usages = [read(agency, 94), read(acct(.claude, "main"), 8), read(acct(.chatgpt, "gpt"), 10),
                      AccountUsage(account: acct(.gemini, "gem"), status: .ok, fetchedAt: now, checkedAt: now)]
        let gauge = MenuBarGauge.model(usages, settings: allOn, providers: Set(Provider.allCases), now: now)
        let name: (String) -> String = { names[$0] ?? $0 }
        #expect(Strings(.en).menuBarTooltip(gauge, names: name) == "Average 37% across 3 accounts · Claude Agency at 94%")
        #expect(Strings(.fr).menuBarTooltip(gauge, names: name) == "Moyenne 37 % sur 3 comptes · Claude Agency à 94 %")
        let calm = MenuBarGauge.model([read(acct(.claude, "main"), 42)], settings: allOn, providers: Set(Provider.allCases), now: now)
        #expect(Strings(.en).menuBarTooltip(calm, names: name) == "Average 42% across 1 account")
        #expect(Strings(.en).menuBarTooltip(GaugeModel(), names: name) == "Brimline")
    }
}
