import Foundation

/// One color of the palette of accounts, with its value on a light and on a dark appearance (sRGB, `0xRRGGBB`).
public struct PaletteColor: Sendable, Equatable {
    /// The token of `design/tokens.json`.
    public var token: String
    public var nameEN: String
    public var nameFR: String
    public var light: UInt32
    public var dark: UInt32
}

/// The color of an account: a slot of Brimline's palette, or a free color chosen with the system picker.
public enum AccountColor: Sendable, Equatable, Hashable, Codable {
    case palette(Int)
    /// Six hexadecimal digits, `RRGGBB`, uppercase, no `#`. One value for both appearances.
    case custom(String)

    private enum CodingKeys: String, CodingKey { case slot, hex }

    /// Reads a color written in `settings.json`. A value that is not one of ours (slot out of the palette, hex
    /// that is not six digits) throws: `BrimlineSettings` drops it and the account gets its default color.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let slot = try c.decodeIfPresent(Int.self, forKey: .slot) {
            guard AccountPalette.entries.indices.contains(slot) else {
                throw DecodingError.dataCorruptedError(forKey: .slot, in: c, debugDescription: "slot out of the palette")
            }
            self = .palette(slot)
        } else if let hex = try c.decodeIfPresent(String.self, forKey: .hex) {
            guard let color = AccountColor.custom(hex: hex) else {
                throw DecodingError.dataCorruptedError(forKey: .hex, in: c, debugDescription: "not a color")
            }
            self = color
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no color"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .palette(let slot): try c.encode(slot, forKey: .slot)
        case .custom(let hex): try c.encode(hex, forKey: .hex)
        }
    }

    /// A free color from six hexadecimal digits (a leading `#` is tolerated), nil when they are not valid.
    public static func custom(hex: String) -> AccountColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard isValidHex(digits) else { return nil }
        return .custom(digits.uppercased())
    }

    /// Exactly six hexadecimal digits, `RRGGBB`: no `#`, no space, no other length.
    public static func isValidHex(_ text: String) -> Bool {
        text.utf8.count == 6 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }
    }

    /// The value on a light or on a dark appearance, `0xRRGGBB`.
    public func rgb(dark: Bool) -> UInt32 {
        switch self {
        case .palette(let slot):
            let entry = AccountPalette.entries[min(max(slot, 0), AccountPalette.entries.count - 1)]
            return dark ? entry.dark : entry.light
        case .custom(let hex):
            return UInt32(hex, radix: 16) ?? 0
        }
    }

    /// The lowest contrast ratio of this color on the empty track of a gauge, in the light and in the dark
    /// appearance: under `AccountPalette.minContrast`, the settings warn (never refuse).
    public var trackContrast: Double {
        min(ColorMath.contrastRatio(rgb(dark: false), AccountPalette.trackLight),
            ColorMath.contrastRatio(rgb(dark: true), AccountPalette.trackDark))
    }
}

/// Two accounts whose colors are too close in one of the two appearances.
public struct ClosePair: Sendable, Equatable {
    public var first: String
    public var second: String
    /// The smaller of the two CIEDE2000 distances (light, dark).
    public var deltaE: Double
}

/// The ten colors Brimline gives to accounts, and the rules that choose and check them (QUOTA-72).
///
/// The values are those of `design/tokens.json` (`accountPalette`, the board of lot D); a test reads that file and
/// fails when the two differ.
public enum AccountPalette {
    /// The slots 0 to 9. The first five are the colors of the providers; the next five are Brimline's own.
    public static let entries: [PaletteColor] = [
        PaletteColor(token: "providerClaude", nameEN: "Violet", nameFR: "Violet", light: 0x7445D6, dark: 0xB48CFF),
        PaletteColor(token: "providerChatgpt", nameEN: "Blue", nameFR: "Bleu", light: 0x1C68C9, dark: 0x62AEF5),
        PaletteColor(token: "providerGemini", nameEN: "Magenta", nameFR: "Magenta", light: 0xB03A86, dark: 0xF08BCB),
        PaletteColor(token: "providerGrok", nameEN: "Olive", nameFR: "Olive", light: 0x5E7A12, dark: 0xB3CC5C),
        PaletteColor(token: "providerCursor", nameEN: "Ink", nameFR: "Encre", light: 0x15191D, dark: 0xECEFF2),
        PaletteColor(token: "accountPine", nameEN: "Pine", nameFR: "Sapin", light: 0x1B6B4C, dark: 0x5CCB98),
        PaletteColor(token: "accountGold", nameEN: "Gold", nameFR: "Or", light: 0x8C7400, dark: 0xF4D63A),
        PaletteColor(token: "accountNavy", nameEN: "Navy", nameFR: "Marine", light: 0x1D3270, dark: 0xB9CAFE),
        PaletteColor(token: "accountCocoa", nameEN: "Cocoa", nameFR: "Cacao", light: 0x703821, dark: 0xCA9678),
        PaletteColor(token: "accountLilac", nameEN: "Lilac", nameFR: "Lilas", light: 0x7A6A96, dark: 0xE9C6F6),
    ]

    /// The slot of each provider's own color.
    public static let providerSlot: [Provider: Int] = [.claude: 0, .chatgpt: 1, .gemini: 2, .grok: 3, .cursor: 4]
    /// The slots handed to the next accounts, in this order, before the providers' colors that no account uses.
    public static let freeOrder = [5, 6, 7, 8, 9]

    /// The empty track of a gauge (`track` in `design/tokens.json`).
    public static let trackLight: UInt32 = 0xE7EAED
    public static let trackDark: UInt32 = 0x2B3035
    /// The least contrast of a color on the track, and the least CIEDE2000 distance between two colors of the palette.
    public static let minContrast = 3.0
    public static let minDeltaE = 15.0
    /// Two visible accounts closer than this (in either appearance) get a warning in the settings.
    public static let closeWarningDeltaE = 10.0
    /// The opacity of a part that shows a last known value.
    public static let staleOpacity = 0.45

    /// The color an account receives now: the color of its provider when it is the first account of that provider
    /// and the slot is free; otherwise the first free slot of `freeOrder`, then the color of a provider that has no
    /// account here, then the first slot no account uses; with all ten in use, the least used slot.
    ///
    /// - Parameters:
    ///   - among: every account of the Mac, in order.
    ///   - assigned: the colors already given (`BrimlineSettings.accountColors`); the account's own entry is ignored.
    public static func defaultColor(for account: Account, among accounts: [Account],
                                    assigned: [String: AccountColor]) -> AccountColor {
        var usage = [Int: Int]()
        for other in accounts where other.id != account.id {
            if case .palette(let slot)? = assigned[other.id] { usage[slot, default: 0] += 1 }
        }
        func free(_ slot: Int) -> Bool { usage[slot] == nil }
        let firstOfProvider = accounts.first { $0.provider == account.provider }?.id == account.id
        if firstOfProvider, let own = providerSlot[account.provider], free(own) { return .palette(own) }
        if let slot = freeOrder.first(where: free) { return .palette(slot) }
        let providersInUse = Set(accounts.map(\.provider))
        let unusedProviderSlots = providerSlot.filter { !providersInUse.contains($0.key) }.map(\.value).sorted()
        if let slot = unusedProviderSlots.first(where: free) { return .palette(slot) }
        if let slot = entries.indices.first(where: free) { return .palette(slot) }
        return .palette(entries.indices.min { (usage[$0] ?? 0, $0) < (usage[$1] ?? 0, $1) } ?? 0)
    }

    /// The pairs of accounts whose colors are closer than `threshold` (CIEDE2000) in the light or in the dark
    /// appearance, the closest first. The input is the colors of the visible accounts, in the panel's order.
    public static func closePairs(_ colors: [(id: String, color: AccountColor)],
                                  threshold: Double = closeWarningDeltaE) -> [ClosePair] {
        var pairs: [ClosePair] = []
        for i in colors.indices {
            for j in colors.indices where j > i {
                let a = colors[i].color, b = colors[j].color
                let distance = min(ColorMath.ciede2000(a.rgb(dark: false), b.rgb(dark: false)),
                                   ColorMath.ciede2000(a.rgb(dark: true), b.rgb(dark: true)))
                if distance < threshold { pairs.append(ClosePair(first: colors[i].id, second: colors[j].id, deltaE: distance)) }
            }
        }
        return pairs.sorted { $0.deltaE < $1.deltaE }
    }
}

/// Color arithmetic with no system framework: WCAG 2.2 contrast and CIEDE2000.
public enum ColorMath {
    private static func linear(_ channel: UInt32) -> Double {
        let c = Double(channel) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func linearRGB(_ rgb: UInt32) -> (Double, Double, Double) {
        (linear((rgb >> 16) & 0xFF), linear((rgb >> 8) & 0xFF), linear(rgb & 0xFF))
    }

    /// Relative luminance (WCAG 2.2).
    public static func luminance(_ rgb: UInt32) -> Double {
        let (r, g, b) = linearRGB(rgb)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Contrast ratio of two sRGB colors, from 1 to 21 (WCAG 2.2).
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    public typealias Lab = (l: Double, a: Double, b: Double)

    /// CIELAB (D65 white) of an sRGB color.
    public static func lab(_ rgb: UInt32) -> Lab {
        let (r, g, b) = linearRGB(rgb)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    public static func ciede2000(_ a: UInt32, _ b: UInt32) -> Double { ciede2000(lab(a), lab(b)) }

    /// CIEDE2000 colour difference (Sharma, Wu and Dalal, 2005), `kL = kC = kH = 1`.
    public static func ciede2000(_ p: Lab, _ q: Lab) -> Double {
        func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
        func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
        func hue(_ b: Double, _ a: Double) -> Double {
            if b == 0 && a == 0 { return 0 }
            let h = degrees(atan2(b, a))
            return h >= 0 ? h : h + 360
        }
        let c1 = hypot(p.a, p.b), c2 = hypot(q.a, q.b)
        let cBar = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cBar, 7) / (pow(cBar, 7) + pow(25.0, 7))))
        let a1 = (1 + g) * p.a, a2 = (1 + g) * q.a
        let cp1 = hypot(a1, p.b), cp2 = hypot(a2, q.b)
        let hp1 = hue(p.b, a1), hp2 = hue(q.b, a2)
        let dL = q.l - p.l
        let dC = cp2 - cp1
        var dh = 0.0
        if cp1 * cp2 != 0 {
            dh = hp2 - hp1
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        }
        let dH = 2 * sqrt(cp1 * cp2) * sin(radians(dh / 2))
        let lBar = (p.l + q.l) / 2
        let cpBar = (cp1 + cp2) / 2
        var hBar = hp1 + hp2
        if cp1 * cp2 != 0 {
            if abs(hp1 - hp2) > 180 { hBar += hp1 + hp2 < 360 ? 360 : -360 }
            hBar /= 2
        }
        let t = 1 - 0.17 * cos(radians(hBar - 30)) + 0.24 * cos(radians(2 * hBar))
            + 0.32 * cos(radians(3 * hBar + 6)) - 0.20 * cos(radians(4 * hBar - 63))
        let dTheta = 30 * exp(-pow((hBar - 275) / 25, 2))
        let rC = 2 * sqrt(pow(cpBar, 7) / (pow(cpBar, 7) + pow(25.0, 7)))
        let sL = 1 + 0.015 * pow(lBar - 50, 2) / sqrt(20 + pow(lBar - 50, 2))
        let sC = 1 + 0.045 * cpBar
        let sH = 1 + 0.015 * cpBar * t
        let rT = -sin(radians(2 * dTheta)) * rC
        let x = dL / sL, y = dC / sC, z = dH / sH
        return sqrt(x * x + y * y + z * z + rT * y * z)
    }
}
