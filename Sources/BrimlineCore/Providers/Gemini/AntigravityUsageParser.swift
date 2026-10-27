import Foundation

/// Turns the text `agy --print /usage` prints into Brimline limits.
///
/// Google documents the command (`/usage`, alias `/quota`, https://antigravity.google/docs/cli/commands/usage/
/// and https://antigravity.google/docs/cli/headless/) but not the format of its text. This is the real one,
/// seen on Antigravity CLI 1.4.8 on 27/10/2026 (values and dates replaced here):
///
///     Gemini Models<TAB>Weekly Limit Remaining<TAB>100%<TAB>2026-11-03T18:10:18Z
///     Gemini Models<TAB>Five Hour Limit Remaining<TAB>100%<TAB>2026-10-27T23:10:18Z
///     Claude and GPT models<TAB>Weekly Limit Remaining<TAB>100%<TAB>2026-11-03T18:10:18Z
///     Gemini 4 Argon<TAB>Gemini 4 Argon Weekly Limit<TAB>100%<TAB>2026-11-03T18:10:18Z
///
/// No header line. One line per limit, four columns separated by tabs: the group (a family of models, or one
/// model), the name of the limit, the percentage **remaining** (100 % is nothing used: Brimline keeps the share
/// used, 100 minus it) and the reset time in ISO 8601. The name of the limit says its window: `Five Hour`
/// (5 hours) or `Weekly` (a week). A limit is kept as the limit of the group, in the window of its name.
///
/// The text is data, never an instruction: it is read strictly. Every line must have exactly this form (a
/// percentage from 0 to 100 followed by `%`, a valid ISO 8601 date, a group and a name that pass
/// `ProviderText.label`, a window Brimline knows); one line that does not, a control character, an invalid
/// UTF-8 sequence, more than 50 lines, no line at all, or a group and window given twice makes the whole text
/// `unrecognized`, never a number. Nothing else of the text is kept.
public enum AntigravityUsageParser {
    public enum ParseError: Error, Equatable {
        case unrecognized
    }

    static let maxLines = 50
    static let fiveHours = 18_000
    static let week = 604_800

    /// One limit per group and window, in the order of the text.
    public static func parse(_ data: Data) throws(ParseError) -> [UsageLimit] {
        guard let text = String(data: data, encoding: .utf8),
              !text.unicodeScalars.contains(where: isForbidden) else { throw .unrecognized }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.allSatisfy { $0 == " " || $0 == "\t" } }
        guard !lines.isEmpty, lines.count <= maxLines else { throw .unrecognized }

        var limits: [UsageLimit] = []
        var seen = Set<String>()
        for line in lines {
            guard let limit = limitLine(line), let model = limit.model, let window = limit.windowSeconds,
                  seen.insert("\(model)\t\(window)").inserted else { throw .unrecognized }
            limits.append(limit)
        }
        return limits
    }

    /// A control character (the line breaks and the tab apart) cannot be part of a report: an escape
    /// sequence or a NUL is a sign that the output is not the one expected.
    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\r" || scalar == "\t" { return false }
        return scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
    }

    private static func limitLine(_ line: Substring) -> UsageLimit? {
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count == 4,
              let group = ProviderText.label(String(columns[0])),
              let name = ProviderText.label(String(columns[1])),
              let window = window(of: name),
              let remaining = percent(columns[2].trimmingCharacters(in: .whitespaces)),
              let resetsAt = ISODate.parse(columns[3].trimmingCharacters(in: .whitespaces)) else { return nil }
        // The text gives what is left: the card shows what is used.
        return UsageLimit(kind: .model, model: group, percent: 100 - remaining, resetsAt: resetsAt,
                          windowSeconds: window)
    }

    /// The window a limit name says: "Five Hour Limit Remaining", "Weekly Limit Remaining" or, for one
    /// model, "<model> Weekly Limit". A name that says neither is not one Brimline knows.
    private static func window(of name: String) -> Int? {
        var rest = Substring(name)
        for suffix in [" Limit Remaining", " Limit"] where rest.hasSuffix(suffix) {
            rest = rest.dropLast(suffix.count)
            break
        }
        if rest == "Five Hour" || rest.hasSuffix(" Five Hour") { return fiveHours }
        if rest == "Weekly" || rest.hasSuffix(" Weekly") { return week }
        return nil
    }

    /// `42%`, `7.5%`: from 0 to 100, the sign `%` right after the number.
    private static func percent(_ text: String) -> Double? {
        guard text.hasSuffix("%"), let match = text.dropLast().wholeMatch(of: /\d{1,3}(\.\d{1,4})?/),
              let value = Double(match.0), value >= 0, value <= 100 else { return nil }
        return value
    }
}
