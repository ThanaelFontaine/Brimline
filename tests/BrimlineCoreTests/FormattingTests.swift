import Foundation
import Testing
@testable import BrimlineCore

@Suite("Time texts in French and English")
struct FormattingTests {
    let now = date("2026-10-25T12:20:00Z")

    @Test("French: repart dans 2 h 10 (14:30)")
    func french() {
        let f = TimeFormatter(language: .fr, timeZone: utc)
        #expect(f.reset(date("2026-10-25T14:30:00Z"), now: now) == "repart dans 2 h 10 (14:30)")
        #expect(f.reset(date("2026-10-25T13:05:00Z"), now: now) == "repart dans 45 min (13:05)")
        #expect(f.reset(date("2026-10-25T14:20:00Z"), now: now) == "repart dans 2 h (14:20)")
        // Past 6 days the reset says its date, a weekday alone would be ambiguous.
        #expect(f.reset(date("2026-11-08T12:20:00Z"), now: now) == "repart dans 14 j (dim. 8 nov.)")
        #expect(f.reset(date("2026-10-31T12:20:00Z"), now: now) == "repart dans 6 j (sam. 12:20)")
        #expect(f.reset(date("2026-10-27T12:00:00Z"), now: now) == "repart dans 1 j 23 h (mar. 12:00)")
        #expect(f.reset(date("2026-10-25T12:20:20Z"), now: now) == "repart dans 1 min (12:20)")
        #expect(f.reset(date("2026-10-25T12:00:00Z"), now: now) == "remis à zéro")
        #expect(f.age(25 * 60) == "il y a 25 min")
        #expect(f.age(10) == "il y a 1 min")
    }

    @Test("English: resets in 2 h 10 (14:30)")
    func english() {
        let f = TimeFormatter(language: .en, timeZone: utc)
        #expect(f.reset(date("2026-10-25T14:30:00Z"), now: now) == "resets in 2 h 10 (14:30)")
        #expect(f.reset(date("2026-10-25T12:25:00Z"), now: now) == "resets in 5 min (12:25)")
        #expect(f.reset(date("2026-10-27T12:00:00Z"), now: now) == "resets in 1 d 23 h (Tue 12:00)")
        #expect(f.reset(date("2026-10-25T10:00:00Z"), now: now) == "has reset")
        #expect(f.reset(date("2026-11-08T12:20:00Z"), now: now) == "resets in 14 d (Sun Nov 8)")
        #expect(f.reset(date("2026-11-01T12:20:00Z"), now: now) == "resets in 7 d (Sun Nov 1)")
        #expect(f.age(3 * 3600 + 5 * 60) == "3 h 05 ago")
        #expect(f.duration(0) == "less than a minute")
    }

    @Test("Percentages: 72% in English, 72 % in French")
    func percent() {
        #expect(Strings(.en).percentText(72.4) == "72%")
        #expect(Strings(.fr).percentText(72.4) == "72 %")
        #expect(Strings(.en).menuBarAccessibility(100) == "Brimline, 100%")
        #expect(Strings(.fr).accessibilityPercent(34, expired: true) == "34 %, expiré")
    }

    @Test("Time zones apply to the clock time")
    func timeZone() {
        let paris = TimeFormatter(language: .fr, timeZone: TimeZone(identifier: "Europe/Paris")!)
        #expect(paris.reset(date("2026-10-25T14:30:00Z"), now: now) == "repart dans 2 h 10 (15:30)")
    }

    @Test("Limit names and state messages exist in both languages")
    func strings() {
        let fr = Strings(.fr), en = Strings(.en)
        let fable = UsageLimit(kind: .model, model: "Fable", percent: 0, resetsAt: nil)
        #expect(fr.limitName(fable) == "Semaine · Fable")
        #expect(en.limitName(fable) == "Week · Fable")
        #expect(fr.session == "Session 5 h")
        #expect(fr.expiredMessage == "Session expirée : ouvrez Claude Code avec ce compte pour la reconnecter")
        #expect(fr.noGlobalWeekly == "Pas de limite hebdomadaire globale")
        for status in [AccountStatus.expired, .reconnect, .unavailable, .signedOut] {
            #expect(fr.statusMessage(status) != en.statusMessage(status))
        }
        #expect(fr.licenseLine == "Code source public sous licence PolyForm Shield 1.0.0")
    }

    @Test("The new kinds of limits and the new states have a name and a message in both languages")
    func newKindsAndStates() {
        let fr = Strings(.fr), en = Strings(.en)
        for kind in [LimitKind.daily, .monthly, .period] {
            let limit = UsageLimit(kind: kind, percent: 1, resetsAt: nil)
            #expect(!en.limitName(limit).isEmpty)
            #expect(fr.limitName(limit) != en.limitName(limit))
        }
        let named = UsageLimit(kind: .period, percent: 1, resetsAt: nil, label: "Credits")
        #expect(en.limitName(named) == "Credits")
        for status in AccountStatus.allCases where status != .ok {
            #expect(en.statusMessage(status) != nil)
            #expect(fr.statusMessage(status) != en.statusMessage(status))
            #expect(en.statusName(status) != fr.statusName(status) || status == .pending)
        }
        #expect(en.statusMessage(.formatChanged) == "The provider changed its answer: update Brimline.")
        #expect(fr.doNotRead == "Ne pas lire ce compte")
        #expect(en.doNotRead == "Don't read this account")
    }

    @Test("No em or en dash in any interface text")
    func noLongDashes() {
        let dashes: [Character] = ["\u{2014}", "\u{2013}"]
        for language in Language.allCases {
            let s = Strings(language)
            let texts = [s.session, s.week, s.noGlobalWeekly, s.expiredMessage, s.reconnectMessage,
                         s.unavailableMessage, s.signedOutMessage, s.accountsIntro, s.agentsIntro,
                         s.openAtLoginHelp, s.licenseLine, s.tagline, s.readOnlyNote, s.howToLink,
                         s.formatChangedMessage, s.notReadableMessage, s.doNotRead, s.doNotReadHelp,
                         s.learnMore, s.readingOffNote, s.readingOffStatus, s.providerHint, s.dismiss,
                         s.sharedPoolSubtitle, s.whatIsRead, s.addCodexFolder, s.chooseCodexFolderMessage]
                + Provider.allCases.flatMap { [s.providerCaption($0, on: true), s.providerCaption($0, on: false), s.noSignIn($0)] }
            for text in texts { #expect(!text.contains { dashes.contains($0) }) }
        }
    }

    @Test("The documentation links point to the docs folder")
    func links() {
        #expect(Links.accountsDoc(.en).absoluteString == "https://github.com/ThanaelFontaine/Brimline/blob/main/docs/accounts.md")
        #expect(Links.accountsDoc(.fr).absoluteString == "https://github.com/ThanaelFontaine/Brimline/blob/main/docs/accounts.fr.md")
    }
}

@Suite("Version")
struct VersionTests {
    @Test("The version in the code equals the VERSION file")
    func matchesFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
        #expect(file.trimmingCharacters(in: .whitespacesAndNewlines) == BrimlineVersion.source)
    }
}


@Suite("Limit names, sentences and provider texts of the panel")
struct PanelTextsTests {
    let en = Strings(.en), fr = Strings(.fr)

    @Test("A limit of one model reads window then model; a window is named by its length")
    func subLimitNames() {
        func model(_ name: String, _ seconds: Int?) -> UsageLimit {
            UsageLimit(kind: .model, model: name, percent: 1, resetsAt: nil, windowSeconds: seconds)
        }
        #expect(en.limitName(model("codex-mini", 18_000), provider: .chatgpt) == "5 h · codex-mini")
        #expect(fr.limitName(model("codex-mini", 18_000), provider: .chatgpt) == "5 h · codex-mini")
        #expect(en.limitName(model("Fable", 604_800), provider: .claude) == "Week · Fable")
        #expect(fr.limitName(model("Fable", 604_800), provider: .claude) == "Semaine · Fable")
        #expect(en.limitName(model("Auto", 2_592_000), provider: .cursor) == "Month · Auto")
        #expect(fr.limitName(model("API", 2_592_000), provider: .cursor) == "Mois · API")
        #expect(en.limitName(model("gemini-2.5-pro", 86_400), provider: .gemini) == "Day · gemini-2.5-pro")
        #expect(en.limitName(model("x", 3 * 86_400), provider: .chatgpt) == "3 d · x")
        #expect(fr.limitName(model("x", 3 * 86_400), provider: .chatgpt) == "3 j · x")
        #expect(en.limitName(model("x", 7_200), provider: .chatgpt) == "2 h · x")
        // Claude's own limit has no window length: the week, as before.
        #expect(en.limitName(model("Fable", nil), provider: .claude) == "Week · Fable")
    }

    @Test("Grok's credits and the other periods say their length")
    func periodNames() {
        func period(_ seconds: Int?, label: String? = nil) -> UsageLimit {
            UsageLimit(kind: .period, percent: 1, resetsAt: nil, windowSeconds: seconds, label: label)
        }
        #expect(en.limitName(period(604_800), provider: .grok) == "Credits · week")
        #expect(fr.limitName(period(604_800), provider: .grok) == "Crédits · semaine")
        #expect(en.limitName(period(2_678_400), provider: .grok) == "Credits · month")
        #expect(fr.limitName(period(2_678_400), provider: .grok) == "Crédits · mois")
        #expect(en.limitName(period(86_400 * 10), provider: .grok) == "Credits")
        #expect(en.limitName(period(nil), provider: .grok) == "Credits")
        #expect(en.limitName(period(30 * 86_400), provider: .chatgpt) == "30-day period")
        #expect(fr.limitName(period(30 * 86_400), provider: .chatgpt) == "Période de 30 j")
        #expect(en.limitName(period(12 * 3_600), provider: .chatgpt) == "12-hour period")
        #expect(en.limitName(period(604_800), provider: .chatgpt) == "Week")
        #expect(en.limitName(period(1_000), provider: .chatgpt) == "Period")
        #expect(en.limitName(period(nil, label: "Credits"), provider: .chatgpt) == "Credits")
        // The kinds that name themselves are the same with or without a provider.
        let session = UsageLimit(kind: .session, percent: 1, resetsAt: nil)
        #expect(en.limitName(session, provider: .chatgpt) == en.limitName(session))
        let month = UsageLimit(kind: .monthly, percent: 1, resetsAt: nil)
        #expect(en.limitName(month, provider: .cursor) == "Month")
    }

    @Test("A sentence is cut after its first full stop, and a single sentence has no rest")
    func splitSentence() {
        let gemini = Strings.splitSentence(en.geminiNotReadableMessage)
        #expect(gemini.first == "Google does not publish Gemini limits in a form Brimline can read.")
        #expect(gemini.rest == "They are in the Gemini app (Settings, Usage limits) and in Gemini CLI (/stats model).")
        let grok = Strings.splitSentence(fr.grokNoCLIMessage)
        #expect(grok.first == "xAI ne publie les limites de Grok que pour le CLI Grok.")
        #expect(grok.rest == "Sans lui, elles sont dans les réglages de votre compte Grok.")
        // Whole again, the two parts give back the sentence of the brief (C7): nothing is lost.
        #expect(gemini.first + " " + (gemini.rest ?? "") == en.geminiNotReadableMessage)
        #expect(Strings.splitSentence(en.chatgptAPIKeyMessage).rest == nil)
        #expect(Strings.splitSentence(en.chatgptSignedOutMessage).rest == nil)
        #expect(Strings.splitSentence("").rest == nil)
    }

    @Test("Every provider says what it reads, off and on, and what to do when none is found, in both languages")
    func providerTexts() {
        for provider in Provider.allCases {
            #expect(en.providerCaption(provider, on: true) != fr.providerCaption(provider, on: true))
            #expect(en.providerCaption(provider, on: false).hasPrefix("Off: Brimline reads nothing."))
            #expect(fr.providerCaption(provider, on: false).hasPrefix("Coupé : Brimline ne lit rien."))
            #expect(en.noSignIn(provider) != fr.noSignIn(provider))
        }
        #expect(en.providerCaption(.chatgpt, on: true) == "Reads ~/.codex/auth.json and asks chatgpt.com for usage.")
        #expect(en.providerCaption(.grok, on: true).contains("cli-chat-proxy.grok.com"))
        #expect(en.providerCaption(.gemini, on: true).hasPrefix("Launches Antigravity"))
        #expect(en.qualifier(for: .chatgpt) == "via Codex" && fr.qualifier(for: .chatgpt) == "par Codex")
        #expect(en.qualifier(for: .claude) == nil && en.qualifier(for: .grok) == nil)
        #expect(en.readProvider("Grok") == "Read Grok" && fr.readProvider("Grok") == "Lire Grok")
        #expect(en.noSignIn(.gemini) == en.geminiNotReadableMessage)
    }

    @Test("VoiceOver says whose number the menu bar shows")
    func menuBar() {
        #expect(en.menuBarAccessibility(91, provider: .claude, account: "Research lab") == "Brimline, 91%, Claude, Research lab")
        #expect(fr.menuBarAccessibility(91, provider: .grok, account: "Grok") == "Brimline, 91 %, Grok, Grok")
        #expect(en.menuBarAccessibility(nil, provider: .claude, account: "x") == "Brimline")
        #expect(en.menuBarAccessibility(40, provider: nil, account: nil) == "Brimline, 40%")
    }

    @Test("The documentation of what is read is in the docs folder")
    func providersDoc() {
        #expect(Links.providersDoc.absoluteString == "https://github.com/ThanaelFontaine/Brimline/blob/main/docs/providers.md")
    }
}
