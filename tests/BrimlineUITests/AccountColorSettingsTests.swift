import AppKit
import Foundation
import SwiftUI
import Testing
import BrimlineCore
@testable import BrimlineUI

private let now = ISODate.parse("2026-10-27T11:20:00Z")!
private let home = URL(fileURLWithPath: "/tmp/someone", isDirectory: true)

private func claude(_ folder: String, email: String) -> Account {
    Account(provider: .claude, source: home.appendingPathComponent(folder).path, email: email, organization: nil,
            seatTier: "max", keychainService: nil, addedByHand: false)
}

private func ok(_ account: Account) -> AccountUsage {
    AccountUsage(account: account, status: .ok, limits: [UsageLimit(kind: .session, percent: 30, resetsAt: now.addingTimeInterval(3600))],
                 fetchedAt: now, checkedAt: now)
}

@MainActor
private func model(_ accounts: [Account], language: Language = .en,
                   configure: (inout BrimlineSettings) -> Void = { _ in }) -> AppModel {
    var settings = BrimlineSettings()
    settings.providerHintDismissed = true
    configure(&settings)
    return AppModel(preview: UsageSnapshot(generatedAt: now, accounts: accounts.map(ok)), settings: settings, now: now,
                    language: language, timeZone: TimeZone(identifier: "UTC")!, home: home)
}

/// The colors in the panel and in the settings (QUOTA-72, lot L5): the dot of each account, the choice, the way back
/// to the default, the warnings, and that the choice is kept.
@MainActor
@Suite("Colors of the accounts in the panel and the settings")
struct AccountColorSettingsTests {
    private let a = claude(".claude", email: "a@example.com")
    private let b = claude(".claude-b", email: "b@example.com")
    private let c = claude(".claude-c", email: "c@example.com")

    @Test("Each account has its own color from the start; the first Claude takes the violet")
    func defaults() {
        let m = model([a, b, c])
        #expect(m.color(for: a) == .palette(0))
        #expect(Set([a, b, c].map { m.color(for: $0) }).count == 3)
        #expect(m.hasDefaultColor(a) && m.hasDefaultColor(b) && m.hasDefaultColor(c))
    }

    @Test("The color kept in the settings is the one shown: for the dot, and for the choice in the settings")
    func colorFollowsSettings() {
        let kept: [String: AccountColor] = [a.id: .palette(7), b.id: .custom("ABCDEF")]
        let m = model([a, b]) { $0.accountColors = kept }
        #expect(m.color(for: a) == .palette(7))
        #expect(m.color(for: b) == .custom("ABCDEF"))
        #expect(!m.hasDefaultColor(a) && !m.hasDefaultColor(b))
        // The dot is drawn with the two values of the palette slot: one per appearance.
        #expect(AccountColor.palette(7).rgb(dark: false) == 0x1D3270 && AccountColor.palette(7).rgb(dark: true) == 0xB9CAFE)
    }

    @Test("Choosing a color changes it for that account only, and \"Back to default\" gives the rule's color again")
    func chooseAndReset() {
        let m = model([a, b])
        let before = m.color(for: b)
        m.setColor(.palette(8), for: a)
        #expect(m.color(for: a) == .palette(8) && m.color(for: b) == before)
        #expect(!m.hasDefaultColor(a))
        m.resetColor(for: a)
        #expect(m.hasDefaultColor(a))
        #expect(m.color(for: a) != .palette(8))
        #expect(m.color(for: b) == before, "the other account did not move")
    }

    @Test("A free color is kept as chosen, and is not the default")
    func freeColor() {
        let m = model([a])
        m.setColor(.custom("123ABC"), for: a)
        #expect(m.color(for: a) == .custom("123ABC") && !m.hasDefaultColor(a))
        m.resetColor(for: a)
        #expect(m.color(for: a) == .palette(0) && m.hasDefaultColor(a))
    }

    @Test("The picker's value is converted to six sRGB digits, a wide-gamut color included")
    func pickerConversion() {
        #expect(SystemColorPicker.accountColor(from: Color(.sRGB, red: 0x74 / 255.0, green: 0x45 / 255.0, blue: 0xD6 / 255.0)) == .custom("7445D6"))
        #expect(SystemColorPicker.accountColor(from: Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))) == .custom("0000FF"))
        // A color the picker gives in another space (Display P3): it comes back as valid sRGB digits.
        let p3 = Color(nsColor: NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))
        if case .custom(let hex)? = SystemColorPicker.accountColor(from: p3) {
            #expect(AccountColor.isValidHex(hex) && hex == "FF0000")
        } else {
            Issue.record("a Display P3 color must be converted")
        }
        // The opacity is never kept: a half transparent color gives the same digits as the opaque one.
        #expect(SystemColorPicker.accountColor(from: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.4)) == .custom("FF0000"))
    }

    // MARK: Warnings

    @Test("Two visible accounts with close colors are warned, each naming the other by the name the panel gives it")
    func closeWarning() throws {
        let m = model([a, b, c]) {
            $0.labels = [a.id: "Personal", b.id: "Client"]
            $0.accountColors = [a.id: .palette(0), b.id: .custom("9870E6"), c.id: .palette(5)]
        }
        let forA = m.colorWarnings(for: a)
        #expect(forA == [.close(accountID: b.id)])
        #expect(m.text(for: try #require(forA.first)) == "Close to Client's color: their two shares are hard to tell apart in the gauge.")
        #expect(m.colorWarnings(for: b) == [.close(accountID: a.id)])
        #expect(m.text(for: try #require(m.colorWarnings(for: b).first)).contains("Personal"))
        #expect(m.colorWarnings(for: c).isEmpty)
    }

    @Test("The warning is in French when the interface is")
    func closeWarningInFrench() throws {
        let m = model([a, b], language: .fr) {
            $0.labels = [a.id: "Perso", b.id: "Client"]
            $0.accountColors = [a.id: .palette(0), b.id: .custom("9870E6")]
        }
        #expect(m.text(for: try #require(m.colorWarnings(for: a).first))
            == "Proche de la couleur de Client : leurs deux parts se distinguent mal dans la jauge.")
    }

    @Test("A hidden account, or one of a provider that is off, is not compared: the gauge does not show it")
    func hiddenAndOff() {
        let near: [String: AccountColor] = [a.id: .palette(0), b.id: .custom("9870E6")]
        let hidden = model([a, b]) { $0.accountColors = near; $0.hiddenAccounts = [b.id] }
        #expect(hidden.colorWarnings(for: a).isEmpty && hidden.colorWarnings(for: b).isEmpty)
        let off = model([a, b]) { $0.accountColors = near; $0.enabledProviders = [Provider.chatgpt.rawValue] }
        #expect(off.colorWarnings(for: a).isEmpty)
    }

    @Test("A free color too pale for the light mode says so, with its ratio, and nothing else")
    func contrastWarning() throws {
        let m = model([a, b]) { $0.accountColors = [a.id: .palette(0), b.id: .custom("D9DEE3")] }
        let warnings = m.colorWarnings(for: b)
        #expect(warnings.count == 1)
        let text = m.text(for: try #require(warnings.first))
        #expect(text.hasPrefix("Hard to see in light mode: ") && text.hasSuffix(":1 contrast on the gauge, 3:1 recommended."))
        #expect(m.colorWarnings(for: a).isEmpty)
    }

    @Test("The warning goes away when the color is changed or reset")
    func warningGoesAway() {
        let m = model([a, b]) { $0.accountColors = [a.id: .palette(0), b.id: .custom("9870E6")] }
        #expect(!m.colorWarnings(for: b).isEmpty)
        m.setColor(.palette(8), for: b)
        #expect(m.colorWarnings(for: a).isEmpty && m.colorWarnings(for: b).isEmpty)
        m.setColor(.custom("9870E6"), for: b)
        m.resetColor(for: b)
        #expect(m.colorWarnings(for: b).isEmpty)
    }

    // MARK: Kept across launches (CA8)

    @Test("A color chosen is written to settings.json and is still there, and still the one shown, at the next launch")
    func keptAtRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("brimline-l5-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in [".claude-a", ".claude-b"] {
            let dir = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(#"{"oauthAccount":{"emailAddress":"\#(name)@example.com"}}"#.utf8).write(to: dir.appendingPathComponent(".claude.json"))
        }
        let first = AppModel(home: folder)
        first.rescan()
        let (x, y) = (first.accounts[0], first.accounts[1])
        first.setColor(.palette(8), for: x)
        first.setColor(.custom("123ABC"), for: y)
        let second = AppModel(home: folder)
        second.rescan()
        #expect(second.color(for: second.accounts[0]) == .palette(8))
        #expect(second.color(for: second.accounts[1]) == .custom("123ABC"))
        // "Back to default" is kept as well.
        second.resetColor(for: second.accounts[1])
        let third = AppModel(home: folder)
        third.rescan()
        #expect(third.color(for: third.accounts[1]) == second.color(for: second.accounts[1]))
        #expect(third.color(for: third.accounts[0]) == .palette(8))
    }

    // MARK: Choice for VoiceOver

    @Test("The radio group of VoiceOver has one choice per palette color, and a free color has the one after")
    func voiceOverChoice() {
        #expect(AccountPalette.entries.indices.allSatisfy { AccountColorRow.choice(.palette($0)) == $0 })
        #expect(AccountColorRow.choice(.custom("123ABC")) == AccountPalette.entries.count)
    }
}
