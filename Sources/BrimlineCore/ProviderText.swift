import Foundation

/// Everything a provider sends is data, never an instruction: a model name or a plan name can end
/// up in the context of an agent, so each text, number and date is filtered before it is kept.
public enum ProviderText {
    public static let maxLabelLength = 64

    private static let labelCharacters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._ -")

    /// A short name from a provider: at most 64 characters among letters, digits, `.`, `_`, `-` and the
    /// space. Anything else (a sentence, a line break, a symbol) is not shortened but dropped: nil.
    public static func label(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxLabelLength, trimmed.allSatisfy(labelCharacters.contains) else { return nil }
        return trimmed
    }

    private static let identityPunctuation: Set<Unicode.Scalar> = Set(" .,'\u{2019}&()_-+@".unicodeScalars)

    /// A name that says who an account is (an organization, a plan, a name the user gave): at most 64
    /// characters, made of letters of any alphabet, marks, digits and a few signs (`.`, `,`, `'`, `&`, `(`, `)`,
    /// `_`, `-`, `+`, `@` and the plain space). Control characters (category Cc, a line break or an ESC
    /// sequence), format characters (Cf: right to left marks and overrides, zero width characters), separators,
    /// symbols, private use and unassigned characters are refused. Anything else is not shortened but dropped:
    /// nil. The text is data for an agent or a terminal, never an instruction.
    public static func identity(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= maxLabelLength,
              trimmed.unicodeScalars.allSatisfy(isIdentityScalar) else { return nil }
        return trimmed
    }

    private static func isIdentityScalar(_ scalar: Unicode.Scalar) -> Bool {
        if identityPunctuation.contains(scalar) { return true }
        // Invisible whatever their category: variation selectors, U+034F, hangul fillers... (a hidden channel).
        if scalar.properties.isDefaultIgnorableCodePoint { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// An address for an agent or a terminal: the one the account has when it is a plain address
    /// (`ClaudeReportEmail.normalize`), as written; nil otherwise.
    public static func address(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudeReportEmail.normalize(trimmed) == nil ? nil : trimmed
    }

    /// A share used, from 0 to 100. A value that is not a number (NaN, infinity) is refused: nil.
    public static func percent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }

    /// A reset time that makes sense: from one day before `now` to 400 days after. Otherwise nil.
    public static func resetDate(_ date: Date?, now: Date) -> Date? {
        guard let date else { return nil }
        let low = now.addingTimeInterval(-24 * 3600), high = now.addingTimeInterval(400 * 24 * 3600)
        return date >= low && date <= high ? date : nil
    }

    /// True for a value that can go in an HTTP header as it is: printable ASCII, no space, no line
    /// break, at most 4096 characters (a token).
    public static func isHeaderToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4096 && value.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7F }
    }

    /// True for an identifier that can go in an HTTP header: letters, digits and `-`, at most 64.
    public static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64
            && value.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D }
    }

    /// The limits of a reading, filtered: no non-number, percentages from 0 to 100, plausible reset
    /// times, names that pass `label` (a `model` limit with no usable name is dropped).
    public static func sanitize(_ limits: [UsageLimit], now: Date) -> [UsageLimit] {
        limits.compactMap { limit in
            guard let percent = percent(limit.percent) else { return nil }
            var clean = limit
            clean.percent = percent
            clean.resetsAt = resetDate(limit.resetsAt, now: now)
            clean.model = label(limit.model)
            clean.label = label(limit.label)
            if clean.kind == .model && clean.model == nil && clean.label == nil { return nil }
            if let seconds = clean.windowSeconds, seconds <= 0 { clean.windowSeconds = nil }
            return clean
        }
    }
}
