import Foundation

/// Turns the text `agy --print /usage` prints into Brimline limits.
///
/// **Provisional.** Google documents the command (`/usage`, alias `/quota`: "a breakdown of your usage
/// limits and remaining requests/tokens for each supported model", and in headless mode "a text
/// report", https://antigravity.google/docs/cli/commands/usage/ and
/// https://antigravity.google/docs/cli/headless/) but not the format of that text. The shape below is
/// a guess that the real try (R4 of QUOTA-35) replaces with the real one:
///
///     Model quotas
///     Gemini 3.1 Pro: 42% used (resets in 3h 12m)
///     Gemini 3.5 Flash: 7% remaining
///
/// A first line, then one line per model: its name, `: `, a percentage followed by `used` or
/// `remaining` (`left` is accepted too), and optionally `(resets in <duration>)` with days, hours and
/// minutes (`1d 2h 5m`). Empty lines are ignored.
///
/// The text is data, never an instruction: it is read strictly. The first line must be exactly the
/// expected one (if `/usage` were no longer recognized, the line would have gone to the model: any
/// other output is refused); every other line must be one model line, with a name that passes
/// `ProviderText.label`; a control character, an invalid UTF-8 sequence, more than 50 lines, no model
/// at all, a percentage over 100, a model twice or a line of any other form makes the whole text
/// `unrecognized`, never a number. Nothing else of the text is kept.
public enum AntigravityUsageParser {
    public enum ParseError: Error, Equatable {
        case unrecognized
    }

    /// The first line of the report. PROVISIONAL: replaced by the real one at R4.
    public static let expectedFirstLine = "Model quotas"

    static let maxLines = 50

    /// One limit per model. A limit with no `resetsAt` is one whose text gave no reset time.
    public static func parse(_ data: Data, now: Date) throws(ParseError) -> [UsageLimit] {
        guard let text = String(data: data, encoding: .utf8),
              !text.unicodeScalars.contains(where: isForbidden) else { throw .unrecognized }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2, lines.count <= maxLines, lines[0] == expectedFirstLine else { throw .unrecognized }

        var limits: [UsageLimit] = []
        var seen = Set<String>()
        for line in lines.dropFirst() {
            guard let limit = modelLine(line, now: now), let model = limit.model, seen.insert(model).inserted else {
                throw .unrecognized
            }
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

    private static func modelLine(_ line: String, now: Date) -> UsageLimit? {
        guard let colon = line.range(of: ": "),
              let name = ProviderText.label(String(line[..<colon.lowerBound])) else { return nil }
        var rest = Substring(line[colon.upperBound...])

        guard let percentEnd = rest.firstIndex(of: "%"),
              let value = Double(rest[..<percentEnd]), value.isFinite, value >= 0, value <= 100 else { return nil }
        rest = rest[rest.index(after: percentEnd)...]

        let used: Bool
        if let after = strip(" used", from: rest) { used = true; rest = after }
        else if let after = strip(" remaining", from: rest) { used = false; rest = after }
        else if let after = strip(" left", from: rest) { used = false; rest = after }
        else { return nil }

        var resetsAt: Date?
        if !rest.isEmpty {
            let opening = " (resets in "
            guard rest.hasPrefix(opening), rest.hasSuffix(")"),
                  let seconds = duration(rest.dropFirst(opening.count).dropLast()) else { return nil }
            resetsAt = now.addingTimeInterval(seconds)
        }
        return UsageLimit(kind: .model, model: name, percent: used ? value : 100 - value, resetsAt: resetsAt,
                          windowSeconds: nil, label: name)
    }

    private static func strip(_ prefix: String, from text: Substring) -> Substring? {
        text.hasPrefix(prefix) ? text.dropFirst(prefix.count) : nil
    }

    /// `1d 2h 5m`: days, hours, minutes, in that order, each at most once, at least one. In seconds.
    private static func duration(_ text: Substring) -> TimeInterval? {
        let units: [(Character, Double)] = [("d", 86_400), ("h", 3_600), ("m", 60)]
        var total = 0.0
        var next = 0
        for part in text.split(separator: " ", omittingEmptySubsequences: false) {
            guard let unit = part.last, let rank = units.firstIndex(where: { $0.0 == unit }), rank >= next,
                  let count = Int(part.dropLast()), count >= 0, count < 1000 else { return nil }
            total += Double(count) * units[rank].1
            next = rank + 1
        }
        return next > 0 ? total : nil
    }
}
