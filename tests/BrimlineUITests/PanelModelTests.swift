import AppKit
import Foundation
import SwiftUI
import Testing
import BrimlineCore
@testable import BrimlineUI

private let now = ISODate.parse("2026-10-27T11:20:00Z")!
private let home = URL(fileURLWithPath: "/tmp/someone", isDirectory: true)

private func account(_ provider: Provider, _ path: String, email: String? = nil, tier: String? = nil,
                     byHand: Bool = false) -> Account {
    Account(provider: provider, source: home.appendingPathComponent(path).path, email: email, organization: nil,
            seatTier: tier, keychainService: nil, addedByHand: byHand)
}

private func ok(_ account: Account, _ limits: [UsageLimit], note: AccountNote? = nil) -> AccountUsage {
    AccountUsage(account: account, status: .ok, limits: limits, fetchedAt: now, checkedAt: now, note: note)
}

@MainActor
private func model(_ usages: [AccountUsage], enabled: [Provider] = Provider.allCases, language: Language = .en,
                   configure: (inout BrimlineSettings) -> Void = { _ in }) -> AppModel {
    var settings = BrimlineSettings()
    settings.enabledProviders = enabled.map(\.rawValue)
    settings.providerHintDismissed = true
    configure(&settings)
    return AppModel(preview: UsageSnapshot(generatedAt: now, accounts: usages), settings: settings, now: now,
                    language: language, timeZone: TimeZone(identifier: "UTC")!, home: home)
}

@MainActor
@Suite("The panel: names, groups and the glyph")
struct PanelModelTests {
    @Test("Claude is named by its address; another provider by its name and plan, never by an address")
    func titles() {
        let claude = account(.claude, ".claude", email: "your@claude.ai")
        let plus = account(.chatgpt, ".codex", email: "someone@example.org", tier: "plus")
        let grok = account(.grok, ".grok/auth.json")
        let m = model([ok(claude, []), ok(plus, []), ok(grok, [])])
        #expect(m.title(for: claude) == "your@claude.ai")
        #expect(m.title(for: plus) == "ChatGPT Plus")
        #expect(m.title(for: grok) == "Grok")
        #expect(m.identity(for: plus) == "ChatGPT Plus")
    }

    @Test("A custom label wins; the provider and plan then go under it, and Claude's address too")
    func labels() {
        let claude = account(.claude, ".claude", email: "team@claude.ai")
        let work = account(.chatgpt, "codex-work", tier: "pro", byHand: true)
        let m = model([ok(claude, []), ok(work, [])]) { $0.labels = [claude.id: "Research lab", work.id: "Codex work"] }
        #expect(m.title(for: claude) == "Research lab")
        #expect(m.subtitle(for: claude) == "team@claude.ai")
        #expect(m.title(for: work) == "Codex work")
        #expect(m.subtitle(for: work) == "ChatGPT Pro")
    }

    @Test("Several accounts of one provider are told apart by the place of their connection")
    func siblings() {
        let a = account(.chatgpt, ".codex"), b = account(.chatgpt, "codex-work", byHand: true)
        let m = model([ok(a, []), ok(b, [])])
        #expect(m.subtitle(for: a) == "~/.codex")
        #expect(m.subtitle(for: b) == "~/codex-work")
        // A single account needs no second line.
        #expect(model([ok(a, [])]).subtitle(for: a) == nil)
    }

    @Test("The groups follow the panel's order and hidden accounts leave their group")
    func groups() {
        let claude = account(.claude, ".claude", email: "a@claude.ai"), second = account(.claude, ".claude-b", email: "b@claude.ai")
        let grok = account(.grok, ".grok/auth.json"), gemini = account(.gemini, ".gemini")
        let m = model([ok(grok, []), ok(gemini, []), ok(second, []), ok(claude, [])]) { $0.hiddenAccounts = [second.id] }
        // Every provider is on: ChatGPT and Cursor have no account, their group says so.
        #expect(m.groups.map(\.provider) == [.claude, .chatgpt, .grok, .cursor, .gemini])
        #expect(m.groups.first?.usages.map(\.account.id) == [claude.id])
    }

    @Test("The glyph names whose number it shows, and dims when the only numbers are old")
    func glyph() {
        let claude = account(.claude, ".claude", email: "your@claude.ai")
        let codex = account(.chatgpt, ".codex")
        var expired = ok(codex, [UsageLimit(kind: .weekly, percent: 80, resetsAt: now.addingTimeInterval(86_400))])
        expired.status = .expired
        let fresh = ok(claude, [UsageLimit(kind: .session, percent: 30, resetsAt: now.addingTimeInterval(3_600))])

        let both = model([fresh, expired]).menuBarLevel
        #expect(both.percent == 30 && !both.dimmed && both.provider == .claude && both.account == "your@claude.ai")

        let onlyExpired = model([expired]).menuBarLevel
        #expect(onlyExpired.percent == 80 && onlyExpired.dimmed && onlyExpired.provider == .chatgpt)

        let none = model([]).menuBarLevel
        #expect(none.percent == nil && none.provider == nil)

        // "Do not read": the fresh account no longer counts as up to date.
        let unread = model([fresh, expired]) { $0.unreadAccounts = [fresh.id] }.menuBarLevel
        #expect(unread.percent == 80 && unread.dimmed)
    }

    @Test("The hint is dismissed once, and the setting stays")
    func hint() {
        let claude = account(.claude, ".claude", email: "a@claude.ai")
        let m = model([ok(claude, [])], enabled: [.claude]) { $0.providerHintDismissed = false }
        #expect(m.showsProviderHint)
        m.dismissProviderHint()
        #expect(!m.showsProviderHint && m.settings.providerHintDismissed)
        // Turning another provider on ends the hint by itself.
        let other = model([ok(claude, [])], enabled: [.claude, .grok]) { $0.providerHintDismissed = false }
        #expect(!other.showsProviderHint)
    }

    @Test("\"Learn more\" opens and closes the rest of a sentence, per account")
    func learnMore() {
        let gemini = account(.gemini, ".gemini")
        let m = model([AccountUsage(account: gemini, status: .notReadable, reason: .consumerPlan)])
        #expect(!m.expandedNotes.contains(gemini.id))
        m.toggleNote(accountID: gemini.id)
        #expect(m.expandedNotes.contains(gemini.id))
        m.toggleNote(accountID: gemini.id)
        #expect(m.expandedNotes.isEmpty)
    }

    @Test("A Codex folder is added by hand and taken away again, apart from the Claude folders")
    func codexFolders() {
        let m = model([])
        m.addCodexFolder(URL(fileURLWithPath: "/tmp/someone/codex-work/"))
        #expect(m.settings.extraCodexFolders == ["/tmp/someone/codex-work"])
        #expect(m.settings.extraFolders.isEmpty)
        m.addCodexFolder(URL(fileURLWithPath: "/tmp/someone/codex-work"))
        #expect(m.settings.extraCodexFolders.count == 1)
        m.removeAddedFolder(of: account(.chatgpt, "codex-work", byHand: true))
        #expect(m.settings.extraCodexFolders.isEmpty)
    }

    @Test("The footer says when Brimline last looked, even if no account gave a number")
    func lastUpdate() {
        let gemini = account(.gemini, ".gemini")
        let m = model([AccountUsage(account: gemini, status: .notReadable, checkedAt: now, reason: .consumerPlan)])
        #expect(m.lastUpdate == now)
    }
}

@MainActor
@Suite("An account card: its rows and its notes")
struct AccountCardTests {
    private func card(_ usage: AccountUsage, in model: AppModel) -> AccountCard { AccountCard(usage: usage, model: model) }

    @Test("A model limit is a sub-limit, and its reset is written only when it differs from the line above")
    func subLimits() {
        let claude = account(.claude, ".claude", email: "a@claude.ai")
        let week = now.addingTimeInterval(2 * 86_400)
        let usage = ok(claude, [
            UsageLimit(kind: .session, percent: 34, resetsAt: now.addingTimeInterval(7_800)),
            UsageLimit(kind: .weekly, percent: 58, resetsAt: week),
            UsageLimit(kind: .model, model: "Fable", percent: 12, resetsAt: week),
            UsageLimit(kind: .model, model: "Sonnet", percent: 5, resetsAt: week.addingTimeInterval(86_400)),
        ])
        let rows = card(usage, in: model([usage])).rows
        guard rows.count == 4,
              case .limit(_, let s0, let r0) = rows[0], case .limit(_, let s1, let r1) = rows[1],
              case .limit(_, let s2, let r2) = rows[2], case .limit(_, let s3, let r3) = rows[3] else {
            Issue.record("expected four limit rows")
            return
        }
        #expect([s0, s1, s2, s3] == [false, false, true, true])
        #expect([r0, r1, r2, r3] == [true, true, false, true])
    }

    @Test("A team seat has the sentence about the week right after the session")
    func teamSeat() {
        let claude = account(.claude, ".claude-lab", email: "team@claude.ai")
        let usage = ok(claude, [
            UsageLimit(kind: .session, percent: 91, resetsAt: now.addingTimeInterval(2_880)),
            UsageLimit(kind: .model, model: "Fable", percent: 74, resetsAt: now.addingTimeInterval(86_400 * 3)),
        ])
        let rows = card(usage, in: model([usage])).rows
        #expect(rows.count == 3)
        #expect(rows[1] == .noGlobalWeekly)
    }

    @Test("Another provider never gets the team seat sentence")
    func noSeatSentenceElsewhere() {
        let codex = account(.chatgpt, ".codex")
        let usage = ok(codex, [UsageLimit(kind: .session, percent: 10, resetsAt: now.addingTimeInterval(3_600), windowSeconds: 18_000)])
        #expect(!card(usage, in: model([usage])).rows.contains(.noGlobalWeekly))
    }

    @Test("An account with no readable limit is a sentence card, until it is marked \"Do not read\"")
    func sentenceOnly() {
        let gemini = account(.gemini, ".gemini")
        let usage = AccountUsage(account: gemini, status: .notReadable, reason: .consumerPlan)
        #expect(card(usage, in: model([usage])).isSentenceOnly)
        #expect(card(usage, in: model([usage])).stateNote == nil)
        let off = model([usage]) { $0.unreadAccounts = [gemini.id] }
        #expect(!card(usage, in: off).isSentenceOnly)
        #expect(card(usage, in: off).stateNote == "Reading turned off in Settings")
        #expect(card(usage, in: off).noteSymbol == "pause.circle")
    }

    @Test("The shared pool is said under the title, the missing number in the card")
    func grokNotes() {
        let grok = account(.grok, ".grok/auth.json")
        let pooled = ok(grok, [UsageLimit(kind: .period, percent: 46, resetsAt: now.addingTimeInterval(86_400), windowSeconds: 604_800)],
                        note: .sharedPool)
        #expect(card(pooled, in: model([pooled])).stateNote == nil)
        let early = ok(grok, [], note: .noFigureYet)
        #expect(card(early, in: model([early])).stateNote == "No number yet for this period.")
        #expect(card(early, in: model([early])).noteSymbol == "info.circle")
    }

    @Test("Each provider's own sentence reaches its card")
    func sentences() {
        let cases: [(Account, NotReadableReason, String)] = [
            (account(.gemini, ".gemini"), .consumerPlan, "Google does not publish Gemini limits in a form Brimline can read."),
            (account(.grok, ".grok/auth.json"), .noCLI, "xAI only publishes Grok limits for the Grok CLI."),
            (account(.chatgpt, ".codex"), .apiKey, "Codex is signed in with an API key: there is no subscription limit to show."),
        ]
        for (acct, reason, first) in cases {
            let usage = AccountUsage(account: acct, status: .notReadable, reason: reason)
            let m = model([usage])
            let full = m.strings.message(for: usage) ?? ""
            #expect(Strings.splitSentence(full).first == first)
            #expect(card(usage, in: m).isSentenceOnly)
        }
    }

    @Test("Expired Codex and a changed format keep their numbers in grey with their note")
    func mutedStates() {
        let codex = account(.chatgpt, ".codex")
        var expired = ok(codex, [UsageLimit(kind: .weekly, percent: 40, resetsAt: now.addingTimeInterval(86_400))])
        expired.status = .expired
        let m = model([expired])
        #expect(card(expired, in: m).stateNote == "Open Codex to refresh the sign-in.")
        var changed = expired
        changed.status = .formatChanged
        #expect(card(changed, in: m).stateNote == "The provider changed its answer: update Brimline.")
        #expect(card(changed, in: m).noteSymbol == "exclamationmark.triangle")
    }
}

@MainActor
@Suite("The images: every state of the board is drawn")
struct DrawingTests {
    /// Hosts a view in an off-screen window, as the snapshots do, and checks that it lays out to a real size.
    private func fittingSize<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        return host.fittingSize
    }

    @Test("The panel and the settings draw for every provider and state, in both languages")
    func draws() {
        let states: [AccountUsage] = [
            AccountUsage(account: account(.gemini, ".gemini"), status: .notReadable, reason: .consumerPlan),
            AccountUsage(account: account(.grok, ".grok/auth.json"), status: .notReadable, reason: .noCLI),
            AccountUsage(account: account(.chatgpt, ".codex"), status: .notReadable, reason: .apiKey),
            AccountUsage(account: account(.chatgpt, ".codex"), status: .expired,
                         limits: [UsageLimit(kind: .weekly, percent: 40, resetsAt: now.addingTimeInterval(86_400))], fetchedAt: now),
            AccountUsage(account: account(.cursor, "cursor"), status: .formatChanged,
                         limits: [UsageLimit(kind: .monthly, percent: 63, resetsAt: now.addingTimeInterval(86_400 * 12), windowSeconds: 2_592_000),
                                  UsageLimit(kind: .model, model: "API", percent: 88, resetsAt: now.addingTimeInterval(86_400 * 12), windowSeconds: 2_592_000)],
                         fetchedAt: now),
            AccountUsage(account: account(.grok, ".grok/auth.json"), status: .unavailable,
                         limits: [UsageLimit(kind: .period, percent: 46, resetsAt: now.addingTimeInterval(86_400), windowSeconds: 604_800)],
                         fetchedAt: now, retryAfter: now.addingTimeInterval(600), detail: "HTTP 429"),
            AccountUsage(account: account(.chatgpt, ".codex"), status: .pending),
        ]
        for language in Language.allCases {
            for usage in states {
                let m = model([usage], language: language)
                let size = fittingSize(PanelView(model: m, opaqueBackground: true))
                #expect(size.width == SGTheme.windowWidth && size.height > 100, "\(usage.status) \(usage.account.provider)")
            }
            let all = model(states, language: language)
            #expect(fittingSize(PanelView(model: all, opaqueBackground: true, maxCardsHeight: 4000)).height > 400)
            #expect(fittingSize(SettingsView(model: all)).width == SettingsView.size.width)
        }
    }

    @Test("A provider that is on but has no account still draws its group")
    func emptyGroup() {
        let m = model([], enabled: [.chatgpt])
        #expect(m.groups.map(\.provider) == [.chatgpt])
        #expect(fittingSize(PanelView(model: m, opaqueBackground: true)).height > 100)
    }
}
