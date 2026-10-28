import Foundation
import Testing
@testable import BrimlineCore

/// The colors of accounts (QUOTA-72, lot L2): the palette, the contrast, the distance between colors, the default
/// color given and kept, and the settings file.
@Suite("Account colors")
struct AccountColorsTests {
    func acct(_ provider: Provider, _ name: String) -> Account {
        Account(provider: provider, source: "/tmp/colors/\(name)", email: nil, organization: nil, seatTier: nil,
                keychainService: nil)
    }

    func slot(_ color: AccountColor?) -> Int? {
        if case .palette(let s)? = color { return s }
        return nil
    }

    // MARK: Palette

    @Test("The palette has ten colors, the first five being the providers'")
    func shape() {
        #expect(AccountPalette.entries.count == 10)
        for (provider, slot) in AccountPalette.providerSlot {
            #expect(AccountPalette.entries[slot].token == "provider" + provider.rawValue.capitalized)
        }
        #expect(Set(AccountPalette.providerSlot.values) == [0, 1, 2, 3, 4])
        #expect(AccountPalette.freeOrder == [5, 6, 7, 8, 9])
    }

    @Test("Every color has at least 3:1 on the track, light and dark")
    func contrastOnTrack() {
        for entry in AccountPalette.entries {
            #expect(ColorMath.contrastRatio(entry.light, AccountPalette.trackLight) >= AccountPalette.minContrast, "\(entry.token) light")
            #expect(ColorMath.contrastRatio(entry.dark, AccountPalette.trackDark) >= AccountPalette.minContrast, "\(entry.token) dark")
        }
    }

    @Test("Two colors of the palette are at least 15 apart (CIEDE2000), light and dark")
    func distance() {
        let colors = AccountPalette.entries
        for i in colors.indices {
            for j in colors.indices where j > i {
                #expect(ColorMath.ciede2000(colors[i].light, colors[j].light) >= AccountPalette.minDeltaE, "\(colors[i].token) / \(colors[j].token) light")
                #expect(ColorMath.ciede2000(colors[i].dark, colors[j].dark) >= AccountPalette.minDeltaE, "\(colors[i].token) / \(colors[j].token) dark")
            }
        }
    }

    struct TokensUnreadable: Error, CustomStringConvertible { var description: String }

    /// The slots of `accountPalette` and the colors of `design/tokens.json`; nil only when the file has no
    /// `accountPalette` key. A key that is there but unreadable throws, so the check never passes on nothing.
    func paletteTokens(_ data: Data) throws -> (slots: [[String: Any]], color: [String: [String: Any]])? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokensUnreadable(description: "tokens.json is not an object")
        }
        guard let palette = root["accountPalette"] else { return nil }
        guard let palette = palette as? [String: Any], let slots = palette["slots"] as? [[String: Any]],
              let color = root["color"] as? [String: [String: Any]] else {
            throw TokensUnreadable(description: "accountPalette, its slots or color cannot be read")
        }
        return (slots, color)
    }

    @Test("The palette matches design/tokens.json when the board's tokens are there")
    func matchesTokens() throws {
        let tokens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("design/tokens.json")
        guard let data = try? Data(contentsOf: tokens), let (slots, color) = try paletteTokens(data) else { return }
        func value(_ mode: String, _ token: String) -> UInt32? {
            guard let entry = color[mode]?[token] as? [String: Any], let hex = entry["value"] as? String else { return nil }
            return UInt32(hex.dropFirst(), radix: 16)
        }
        #expect(slots.count == AccountPalette.entries.count)
        for (index, slot) in slots.enumerated() {
            let token = try #require(slot["token"] as? String)
            let entry = AccountPalette.entries[index]
            #expect(entry.token == token)
            #expect(entry.light == value("light", token), "\(token) light")
            #expect(entry.dark == value("dark", token), "\(token) dark")
        }
    }

    @Test("The tokens check passes only when accountPalette is absent: a key that cannot be read fails")
    func tokensCheckIsNotVacuous() throws {
        func data(_ json: String) -> Data { Data(json.utf8) }
        #expect(try paletteTokens(data(#"{"color": {}}"#)) == nil, "no key: nothing to compare")
        #expect(try paletteTokens(data(#"{"accountPalette": {"slots": []}, "color": {}}"#))?.slots.isEmpty == true)
        for broken in [#"{"accountPalette": 3}"#, #"{"accountPalette": {}, "color": {}}"#,
                       #"{"accountPalette": {"slots": "x"}, "color": {}}"#, #"{"accountPalette": {"slots": []}}"#, "[]"] {
            #expect(throws: TokensUnreadable.self, "\(broken)") { try paletteTokens(data(broken)) }
        }
        // The real file: the key is there and readable.
        let tokens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("design/tokens.json")
        let real = try #require(try? Data(contentsOf: tokens), "design/tokens.json must be there")
        #expect(try paletteTokens(real) != nil)
    }

    // MARK: Color arithmetic

    @Test("Contrast: black on white is 21, a color on itself is 1")
    func contrastReference() {
        #expect(abs(ColorMath.contrastRatio(0x000000, 0xFFFFFF) - 21) < 1e-9)
        #expect(abs(ColorMath.contrastRatio(0x7445D6, 0x7445D6) - 1) < 1e-12)
        #expect(abs(ColorMath.contrastRatio(0x777777, 0xFFFFFF) - 4.48) < 0.01)
        // The value written in design/tokens.json for the Claude violet on the light page.
        #expect(abs(ColorMath.contrastRatio(0x7445D6, 0xF5F6F7) - 5.44) < 0.01)
    }

    @Test("CIEDE2000 gives the reference values of Sharma, Wu and Dalal (2005)")
    func sharma() {
        let pairs: [(ColorMath.Lab, ColorMath.Lab, Double)] = [
            ((50.0000, 2.6772, -79.7751), (50.0000, 0.0000, -82.7485), 2.0425),
            ((50.0000, 3.1571, -77.2803), (50.0000, 0.0000, -82.7485), 2.8615),
            ((50.0000, 2.8361, -74.0200), (50.0000, 0.0000, -82.7485), 3.4412),
            ((50.0000, -1.3802, -84.2814), (50.0000, 0.0000, -82.7485), 1.0000),
            ((50.0000, 0.0000, 0.0000), (50.0000, -1.0000, 2.0000), 2.3669),
            ((50.0000, 2.5000, 0.0000), (73.0000, 25.0000, -18.0000), 27.1492),
            ((50.0000, 2.5000, 0.0000), (61.0000, -5.0000, 29.0000), 22.8977),
            ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
            ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
            ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
        ]
        for (first, second, expected) in pairs {
            #expect(abs(ColorMath.ciede2000(first, second) - expected) < 0.0001, "\(first) / \(second)")
            #expect(abs(ColorMath.ciede2000(second, first) - expected) < 0.0001, "symmetric")
        }
    }

    @Test("The same color is at 0, black and white are far apart")
    func labSanity() {
        #expect(ColorMath.ciede2000(0x7445D6, 0x7445D6) == 0)
        #expect(ColorMath.ciede2000(0x000000, 0xFFFFFF) > 90)
        let white = ColorMath.lab(0xFFFFFF)
        #expect(abs(white.l - 100) < 0.01 && abs(white.a) < 0.01 && abs(white.b) < 0.01)
    }

    // MARK: Hex and the stored value

    @Test("A free color is exactly six hexadecimal digits")
    func hex() {
        for good in ["7445D6", "7445d6", "000000", "FFFFFF"] { #expect(AccountColor.isValidHex(good), "\(good)") }
        for bad in ["", "7445D", "7445D6F", "#7445D6", "7445G6", " 7445D6", "7445D6\n", "７４４５Ｄ６", "0x7445D6"] {
            #expect(!AccountColor.isValidHex(bad), "\(bad)")
        }
        #expect(AccountColor.custom(hex: "7445d6") == .custom("7445D6"))
        #expect(AccountColor.custom(hex: "#7445d6") == .custom("7445D6"))
        #expect(AccountColor.custom(hex: "zzz") == nil)
        #expect(AccountColor.custom("1D3270").rgb(dark: false) == 0x1D3270 && AccountColor.custom("1D3270").rgb(dark: true) == 0x1D3270)
        #expect(AccountColor.palette(7).rgb(dark: true) == 0xB9CAFE && AccountColor.palette(7).rgb(dark: false) == 0x1D3270)
    }

    @Test("A free color under 3:1 on the track is flagged, a palette color is not")
    func trackContrast() {
        #expect(AccountColor.custom("EEEEEE").trackContrast < AccountPalette.minContrast)
        #expect(AccountColor.custom("1D3270").trackContrast < AccountPalette.minContrast, "dark on the dark track")
        #expect(AccountColor.palette(0).trackContrast >= AccountPalette.minContrast)
        #expect(AccountPalette.entries.indices.allSatisfy { AccountColor.palette($0).trackContrast >= AccountPalette.minContrast })
    }

    // MARK: Default color

    @Test("The first account of a provider takes its provider's color")
    func providerColors() {
        let accounts = [acct(.claude, "a"), acct(.chatgpt, "b"), acct(.gemini, "c"), acct(.grok, "d"), acct(.cursor, "e")]
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: accounts)
        #expect(accounts.map { slot(settings.accountColors[$0.id]) } == [0, 1, 2, 3, 4])
    }

    @Test("Four Claude accounts get four different colors, the first one the violet")
    func fourClaude() {
        let accounts = ["personal", "work", "client", "side"].map { acct(.claude, $0) }
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: accounts)
        let slots = accounts.map { slot(settings.accountColors[$0.id]) }
        #expect(slots == [0, 5, 6, 7])
        #expect(Set(slots.compactMap { $0 }).count == 4)
    }

    @Test("The next accounts take the free slots in order, then the colors of providers with no account")
    func order() {
        let accounts = (0..<10).map { acct(.claude, "c\($0)") }
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: accounts)
        // Claude's violet, the five of the palette's own, then the colors of ChatGPT, Gemini, Grok and Cursor.
        #expect(accounts.map { slot(settings.accountColors[$0.id]) } == [0, 5, 6, 7, 8, 9, 1, 2, 3, 4])
    }

    @Test("A provider that has an account keeps its color for it: it is not given to another provider's second account")
    func providerColorIsKept() {
        let accounts = (0..<7).map { acct(.claude, "c\($0)") } + [acct(.chatgpt, "g")]
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: accounts)
        #expect(slot(settings.accountColors[accounts[7].id]) == 1)
        #expect(!accounts.dropLast().contains { slot(settings.accountColors[$0.id]) == 1 }, "ChatGPT's blue stays free for it")
    }

    @Test("More than ten accounts: no failure, the least used slot is shared")
    func moreThanTen() {
        let accounts = (0..<13).map { acct(.claude, "c\($0)") }
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: accounts)
        let slots = accounts.map { slot(settings.accountColors[$0.id]) }
        #expect(slots.allSatisfy { ($0 ?? -1) >= 0 && ($0 ?? 99) < 10 })
        #expect(Set(slots.compactMap { $0 }).count == 10)
        // The first ten as before; then each next account takes the least used slot, the lowest number on a tie.
        #expect(slots == [0, 5, 6, 7, 8, 9, 1, 2, 3, 4, 0, 1, 2])
    }

    @Test("A color given is kept when an account appears before the others")
    func keptWhenAnotherAppears() {
        let first = acct(.claude, "first"), second = acct(.claude, "second")
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: [first, second])
        let given = settings.accountColors
        // A new Claude account is discovered, ahead of both in the list: nothing moves, it gets the next free slot.
        let newcomer = acct(.claude, "aaa")
        settings.assignDefaultColors(to: [newcomer, first, second])
        #expect(settings.accountColors[first.id] == given[first.id] && settings.accountColors[second.id] == given[second.id])
        #expect(slot(settings.accountColors[newcomer.id]) == 6)
        // A provider appears: it takes its own color, and the others stay.
        let chatgpt = acct(.chatgpt, "g")
        settings.assignDefaultColors(to: [newcomer, first, second, chatgpt])
        #expect(slot(settings.accountColors[chatgpt.id]) == 1)
        #expect(settings.accountColors[first.id] == given[first.id])
    }

    @Test("A color the user chose is never replaced by assignDefaultColors")
    func chosenIsKept() {
        let a = acct(.claude, "a"), b = acct(.claude, "b")
        var settings = BrimlineSettings()
        settings.accountColors[a.id] = .custom("112233")
        settings.accountColors[b.id] = .palette(3)
        settings.assignDefaultColors(to: [a, b])
        #expect(settings.accountColors[a.id] == .custom("112233") && settings.accountColors[b.id] == .palette(3))
    }

    @Test("A color already used by another account of the Mac is not given again")
    func noDuplicateAtStart() {
        let a = acct(.claude, "a"), b = acct(.claude, "b")
        var settings = BrimlineSettings()
        settings.accountColors[a.id] = .palette(5)
        settings.assignDefaultColors(to: [a, b])
        #expect(slot(settings.accountColors[b.id]) == 6, "a holds slot 5: b, a second account, takes the next free slot")
        #expect(settings.accountColors[a.id] == .palette(5))
    }

    @Test("Back to default gives the color the rule gives now, and keeps it")
    func reset() {
        let a = acct(.claude, "a"), b = acct(.claude, "b"), c = acct(.claude, "c")
        let accounts = [a, b, c]
        var settings = BrimlineSettings()
        settings.assignDefaultColors(to: accounts)
        #expect(slot(settings.accountColors[b.id]) == 5)
        settings.accountColors[b.id] = .custom("445566")
        settings.resetColor(for: b, accounts: accounts)
        #expect(slot(settings.accountColors[b.id]) == 5, "its own default slot is free again")
        settings.accountColors[a.id] = .palette(5)
        settings.resetColor(for: b, accounts: accounts)
        #expect(slot(settings.accountColors[b.id]) == 7, "slot 5 now belongs to a, and 6 to c")
        #expect(settings.accountColors[b.id] != settings.accountColors[a.id] && settings.accountColors[b.id] != settings.accountColors[c.id])
    }

    // MARK: Close colors

    @Test("Two accounts of the same color are close; two palette colors never are")
    func closePairs() {
        let same = AccountPalette.closePairs([("a", .palette(0)), ("b", .custom("7445D6")), ("c", .palette(1))])
        #expect(same.count == 1 && same[0].first == "a" && same[0].second == "b" && same[0].deltaE < 10)
        let all = AccountPalette.entries.indices.map { (id: "s\($0)", color: AccountColor.palette($0)) }
        #expect(AccountPalette.closePairs(all).isEmpty)
    }

    @Test("A pair that is close in the dark appearance only is flagged, the closest first")
    func closeInOneAppearance() {
        // Light values far apart, dark values nearly the same: the smaller distance counts.
        let a = AccountColor.custom("B48CFF"), b = AccountColor.palette(0)
        #expect(ColorMath.ciede2000(a.rgb(dark: false), b.rgb(dark: false)) > 10)
        #expect(ColorMath.ciede2000(a.rgb(dark: true), b.rgb(dark: true)) == 0)
        #expect(AccountPalette.closePairs([("a", a), ("b", b)]).count == 1)
        let ranked = AccountPalette.closePairs([("a", .custom("7445D6")), ("b", .custom("7445D7")), ("c", .custom("7746D6"))])
        #expect(ranked.count == 3 && ranked[0].deltaE <= ranked[1].deltaE && ranked[1].deltaE <= ranked[2].deltaE)
    }
}

/// The colors in settings.json: written, read back, and tolerant (QUOTA-72).
@Suite("Account colors in settings.json")
struct AccountColorsSettingsTests {
    func decode(_ json: String) throws -> BrimlineSettings {
        try JSONDecoder().decode(BrimlineSettings.self, from: Data(json.utf8))
    }

    @Test("A file of an earlier version, without the key, reads as before and has no colors")
    func fileWithoutTheKey() throws {
        let settings = try decode(#"{"schemaVersion":1,"refreshMinutes":10,"labels":{"claude:/a":"Work"},"enabledProviders":["claude"]}"#)
        #expect(settings.accountColors.isEmpty && settings.schemaVersion == 1 && settings.refreshMinutes == 10)
        #expect(settings.label(for: "claude:/a") == "Work")
    }

    @Test("A complete settings.json of an earlier version (every key it wrote) reads without losing a value, and stays the same once saved")
    func completeFileOfVersion020() throws {
        let json = """
        {"schemaVersion":1,"extraFolders":["/tmp/qa/.claude-x"],"extraCodexFolders":["/tmp/qa/.codex-y"],
         "hiddenAccounts":["claude:/tmp/qa/h"],"labels":{"claude:/tmp/qa/a":"Work","chatgpt:/tmp/qa/b":"Perso"},
         "refreshMinutes":15,"showPercentInMenuBar":true,"enabledProviders":["claude","chatgpt","gemini"],
         "unreadAccounts":["chatgpt:/tmp/qa/u"],"providerHintDismissed":true}
        """
        let settings = try decode(json)
        #expect(settings.schemaVersion == 1)
        #expect(settings.extraFolders == ["/tmp/qa/.claude-x"] && settings.extraCodexFolders == ["/tmp/qa/.codex-y"])
        #expect(settings.hiddenAccounts == ["claude:/tmp/qa/h"] && settings.unreadAccounts == ["chatgpt:/tmp/qa/u"])
        #expect(settings.labels == ["claude:/tmp/qa/a": "Work", "chatgpt:/tmp/qa/b": "Perso"])
        #expect(settings.refreshMinutes == 15 && settings.showPercentInMenuBar && settings.providerHintDismissed)
        #expect(settings.enabledProviders == ["claude", "chatgpt", "gemini"] && settings.accountColors.isEmpty)
        // Saved and read again, nothing moves, and assigning colors changes only the colors.
        let home = try TemporaryHome()
        let store = SettingsStore(file: home.url.appendingPathComponent("settings.json"))
        try store.save(settings)
        #expect(store.load() == settings)
        var colored = store.load()
        colored.assignDefaultColors(to: [Account(provider: .claude, source: "/tmp/qa/a", email: nil, organization: nil,
                                                 seatTier: nil, keychainService: nil)])
        var expected = settings
        expected.accountColors = colored.accountColors
        #expect(colored == expected && colored.accountColors.count == 1)
    }

    @Test("Colors are written and read back through SettingsStore, and the schema stays at 1")
    func roundTrip() throws {
        let home = try TemporaryHome()
        let store = SettingsStore(file: home.url.appendingPathComponent("settings.json"))
        var settings = BrimlineSettings()
        settings.accountColors = ["claude:/a": .palette(5), "chatgpt:/b": .custom("1D3270"), "claude:/c": .palette(0)]
        try store.save(settings)
        let loaded = store.load()
        #expect(loaded == settings && loaded.accountColors == settings.accountColors && loaded.schemaVersion == 1)
        let text = try String(contentsOf: store.file, encoding: .utf8)
        #expect(text.contains("\"slot\" : 5") && text.contains("\"hex\" : \"1D3270\""))
    }

    @Test("A color that is not valid is dropped one by one, the valid ones and the rest of the file stay")
    func invalidIgnored() throws {
        let json = """
        {"refreshMinutes":15,"accountColors":{
          "a":{"slot":3},
          "b":{"hex":"ZZZZZZ"},
          "c":{"slot":42},
          "d":{"slot":-1},
          "e":{"hex":"12345"},
          "f":{"hex":"#1d3270"},
          "g":{"hex":"112233","slot":2},
          "h":"7445D6",
          "i":{},
          "j":{"slot":"3"},
          "k":null,
          "l":{"hex":"AABBCC"}
        }}
        """
        let settings = try decode(json)
        #expect(settings.refreshMinutes == 15)
        #expect(settings.accountColors == ["a": .palette(3), "f": .custom("1D3270"), "g": .palette(2), "l": .custom("AABBCC")])
    }

    @Test("A key that is not an object at all gives no colors, and no error")
    func wrongShape() throws {
        #expect(try decode(#"{"accountColors":[1,2]}"#).accountColors.isEmpty)
        #expect(try decode(#"{"accountColors":"red","refreshMinutes":2}"#).refreshMinutes == 2)
        #expect(try decode(#"{"accountColors":null}"#).accountColors.isEmpty)
    }

    @Test("A color is only a slot or six digits: nothing else can be written")
    func nothingElseIsWritten() throws {
        var settings = BrimlineSettings()
        settings.accountColors = ["claude:/a": .custom("7445D6")]
        let data = try JSONCoding.encoder().encode(settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colors = try #require(object["accountColors"] as? [String: [String: Any]])
        #expect(colors["claude:/a"]?.keys.sorted() == ["hex"])
    }
}
