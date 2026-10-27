import Foundation
import Testing
@testable import BrimlineCore

/// What the settings say under the color of an account (QUOTA-72, lot L5): the system picker's value as six digits,
/// the contrast on the track, the close pairs, and the sentences in both languages.
@Suite("Colors of the accounts: the picker, the warnings and their sentences")
struct AccountColorWarningsTests {
    // MARK: The system picker

    @Test("The three channels of the picker give the six digits of the same color")
    func pickerToHex() {
        #expect(AccountColor.custom(red: 0x74 / 255.0, green: 0x45 / 255.0, blue: 0xD6 / 255.0) == .custom("7445D6"))
        #expect(AccountColor.custom(red: 0, green: 0, blue: 0) == .custom("000000"))
        #expect(AccountColor.custom(red: 1, green: 1, blue: 1) == .custom("FFFFFF"))
        // A leading zero is kept: six digits, always.
        #expect(AccountColor.custom(red: 0, green: 0, blue: 15 / 255.0) == .custom("00000F"))
    }

    @Test("A channel outside 0 to 1, or not a number, is brought back: the result is always a valid color")
    func pickerOutOfRange() {
        #expect(AccountColor.custom(red: 1.4, green: -0.2, blue: 0.5) == .custom("FF0080"))
        #expect(AccountColor.custom(red: .nan, green: .infinity, blue: -.infinity) == .custom("000000"))
        for value in [AccountColor.custom(red: 0.3, green: 2, blue: -1), .custom(red: .nan, green: .nan, blue: .nan)] {
            guard case .custom(let hex) = value else { Issue.record("not a free color"); continue }
            #expect(AccountColor.isValidHex(hex) && hex == hex.uppercased())
        }
    }

    @Test("What the picker gave is what is written to settings.json and read back")
    func pickerRoundTrip() throws {
        let color = AccountColor.custom(red: 0.25, green: 0.5, blue: 0.75)
        let data = try JSONEncoder().encode(["a": color])
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":{"hex":"4080BF"}}"#)
        #expect(try JSONDecoder().decode([String: AccountColor].self, from: data) == ["a": color])
    }

    // MARK: Contrast

    @Test("A free color too pale for the light track is flagged in the light appearance, with its ratio under 3")
    func paleColor() throws {
        let low = try #require(AccountColor.custom("D9DEE3").lowContrast)
        #expect(low.dark == false)
        #expect(low.ratio < AccountPalette.minContrast && low.ratio >= 1)
    }

    @Test("A free color too dark for the dark track is flagged in the dark appearance")
    func darkColor() throws {
        let low = try #require(AccountColor.custom("1D3270").lowContrast)
        #expect(low.dark == true)
        #expect(low.ratio < AccountPalette.minContrast)
    }

    @Test("A ratio just under 3 is never written as 3.0, and a palette color has no warning")
    func truncation() {
        // Scan the grey ramp: whenever there is a warning, the ratio written is strictly under the threshold.
        var flagged = 0
        for level in 0...255 {
            let grey = AccountColor.custom(red: Double(level) / 255, green: Double(level) / 255, blue: Double(level) / 255)
            if let low = grey.lowContrast {
                flagged += 1
                #expect(low.ratio < AccountPalette.minContrast && low.ratio >= 1)
            } else {
                #expect(grey.trackContrast >= AccountPalette.minContrast)
            }
        }
        #expect(flagged > 0 && flagged < 256, "the ramp has greys on both sides of the threshold")
        for slot in AccountPalette.entries.indices { #expect(AccountColor.palette(slot).lowContrast == nil) }
    }

    // MARK: Warnings

    private let violet = AccountColor.palette(0)
    private let nearViolet = AccountColor.custom("9870E6")
    private let pine = AccountColor.palette(5)

    @Test("A color close to another visible account's is flagged on both, naming the other")
    func closeIsFlaggedOnBoth() {
        let visible: [(id: String, color: AccountColor)] = [("a", violet), ("b", nearViolet), ("c", pine)]
        #expect(AccountPalette.warnings(for: "a", color: violet, visible: visible).contains(.close(accountID: "b")))
        #expect(AccountPalette.warnings(for: "b", color: nearViolet, visible: visible).contains(.close(accountID: "a")))
        #expect(AccountPalette.warnings(for: "c", color: pine, visible: visible).isEmpty)
    }

    @Test("A hidden account has no close pair: it is not in the visible list, so nobody is warned about it")
    func hiddenIsNotCompared() {
        let visible: [(id: String, color: AccountColor)] = [("a", violet), ("c", pine)]
        #expect(AccountPalette.warnings(for: "a", color: violet, visible: visible).isEmpty)
        #expect(AccountPalette.warnings(for: "b", color: nearViolet, visible: visible).isEmpty)
    }

    @Test("Close pairs come first, then the contrast; a color can have both")
    func order() {
        let pale = AccountColor.custom("D9DEE3")
        let almostPale = AccountColor.custom("DCE1E6")
        let visible: [(id: String, color: AccountColor)] = [("a", pale), ("b", almostPale)]
        let warnings = AccountPalette.warnings(for: "a", color: pale, visible: visible)
        #expect(warnings.count == 2)
        #expect(warnings.first == .close(accountID: "b"))
        if case .lowContrast(let dark, _)? = warnings.last { #expect(dark == false) } else { Issue.record("no contrast warning") }
    }

    @Test("The ten colors of the palette, given to ten accounts, raise no warning at all")
    func paletteIsQuiet() {
        let visible = AccountPalette.entries.indices.map { (id: "\($0)", color: AccountColor.palette($0)) }
        for entry in visible { #expect(AccountPalette.warnings(for: entry.id, color: entry.color, visible: visible).isEmpty) }
    }

    // MARK: Sentences

    @Test("Every color of the palette has its own name in French and in English")
    func names() {
        for language in Language.allCases {
            let strings = Strings(language)
            let names = AccountPalette.entries.indices.map { strings.colorName(.palette($0)) }
            #expect(Set(names).count == 10 && names.allSatisfy { !$0.isEmpty })
            #expect(strings.colorName(.custom("123456")) == strings.customColorName)
        }
        #expect(Strings(.fr).colorName(.palette(5)) == "Sapin" && Strings(.en).colorName(.palette(5)) == "Pine")
        // A slot out of the palette (a corrupted file read by an older reader) is brought back, never a crash.
        #expect(!Strings(.en).colorName(.palette(99)).isEmpty && !Strings(.en).colorName(.palette(-3)).isEmpty)
    }

    @Test("The sentences of the warnings, French and English, with the decimal comma in French")
    func sentences() {
        let name: (String) -> String = { _ in "Asso" }
        let fr = Strings(.fr), en = Strings(.en)
        #expect(fr.colorWarning(.close(accountID: "x"), account: name)
            == "Proche de la couleur de Asso : leurs deux parts se distinguent mal dans la jauge.")
        #expect(en.colorWarning(.close(accountID: "x"), account: name)
            == "Close to Asso's color: their two shares are hard to tell apart in the gauge.")
        #expect(fr.colorWarning(.lowContrast(dark: false, ratio: 1.4), account: name)
            == "Peu visible en mode clair : contraste de 1,4:1 sur la jauge, 3:1 conseillé.")
        #expect(en.colorWarning(.lowContrast(dark: true, ratio: 2.5), account: name)
            == "Hard to see in dark mode: 2.5:1 contrast on the gauge, 3:1 recommended.")
        #expect(fr.colorWarning(.lowContrast(dark: true, ratio: 2.5), account: name).contains("mode sombre"))
    }

    @Test("The group read by VoiceOver names the account, and the labels of the line are written in both languages")
    func labels() {
        #expect(Strings(.en).colorGroup("Claude Agency") == "Color of Claude Agency")
        #expect(Strings(.fr).colorGroup("Claude Agence") == "Couleur de Claude Agence")
        #expect(Strings(.fr).otherColor == "Autre couleur…" && Strings(.en).otherColor == "Other color…")
        #expect(Strings(.fr).resetColor == "Revenir au défaut" && Strings(.en).resetColor == "Reset to default")
        #expect(Strings(.fr).defaultColor == "Couleur par défaut" && Strings(.en).defaultColor == "Default color")
        #expect(Strings(.fr).colorRow == "Couleur" && Strings(.en).colorRow == "Color")
        #expect(Strings(.fr).colorsIntro.contains("pastille") && Strings(.en).colorsIntro.contains("dot"))
    }
}
