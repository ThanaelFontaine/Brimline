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

    @Test("No em or en dash in any interface text")
    func noLongDashes() {
        let dashes: [Character] = ["\u{2014}", "\u{2013}"]
        for language in Language.allCases {
            let s = Strings(language)
            let texts = [s.session, s.week, s.noGlobalWeekly, s.expiredMessage, s.reconnectMessage,
                         s.unavailableMessage, s.signedOutMessage, s.accountsIntro, s.agentsIntro,
                         s.openAtLoginHelp, s.licenseLine, s.tagline, s.readOnlyNote, s.howToLink]
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
