import Foundation

/// Turns the answer of `wham/usage` into Brimline limits.
///
/// `rate_limit` holds the Codex windows (`primary_window`, `secondary_window`); a window is named by
/// its length, not by its position: 18000 seconds is the 5 hour session, 604800 the week, anything
/// else a period with its length. A plan with no 5 hour window (Pro) simply has no session limit.
/// `additional_rate_limits` holds the limits of one model or feature, kept as `model` limits.
/// Every other key (credits, spend control, reached type) is ignored.
public enum ChatGPTUsageParser {
    public enum ParseError: Error, Equatable {
        case notJSON
        /// JSON, but not the answer this parser knows: neither `plan_type` nor `rate_limit` is there.
        case unrecognized
    }

    static let sessionSeconds = 18_000
    static let weekSeconds = 604_800

    public static func parse(_ data: Data, now: Date) throws(ParseError) -> [UsageLimit] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { throw .notJSON }
        guard root["plan_type"] is String || root["rate_limit"] is [String: Any] else { throw .unrecognized }

        var limits: [UsageLimit] = []
        for window in windows(of: root["rate_limit"], now: now) {
            limits.append(UsageLimit(kind: kind(of: window.seconds), percent: window.percent,
                                     resetsAt: window.resetsAt, windowSeconds: window.seconds))
        }
        if let extra = root["additional_rate_limits"] as? [[String: Any]] {
            for entry in extra {
                let rawName = (entry["limit_name"] as? String) ?? (entry["metered_feature"] as? String)
                guard let name = ProviderText.label(rawName) else { continue }
                for window in windows(of: entry["rate_limit"], now: now) {
                    limits.append(UsageLimit(kind: .model, model: name, percent: window.percent,
                                             resetsAt: window.resetsAt, windowSeconds: window.seconds,
                                             label: label(name: name, seconds: window.seconds)))
                }
            }
        }
        return sorted(limits)
    }

    private struct Window {
        var percent: Double
        var seconds: Int?
        var resetsAt: Date?
    }

    private static func windows(of details: Any?, now: Date) -> [Window] {
        guard let details = details as? [String: Any] else { return [] }
        return ["primary_window", "secondary_window"].compactMap { key in
            guard let window = details[key] as? [String: Any],
                  let percent = UsageParser.number(window["used_percent"]) else { return nil }
            let seconds = UsageParser.number(window["limit_window_seconds"])
                .flatMap { $0.isFinite && $0 > 0 && $0 < 1e9 ? Int($0) : nil }
            var resets: Date?
            // `reset_at` (Unix seconds) first; the delay only when the date is not there. An absurd
            // date is not replaced by the delay: `ProviderText.resetDate` drops it later.
            if let at = UsageParser.number(window["reset_at"]) {
                if at.isFinite, at > 0, at < 1e12 { resets = Date(timeIntervalSince1970: at.rounded()) }
            } else if let after = UsageParser.number(window["reset_after_seconds"]), after.isFinite, after >= 0, after < 1e9 {
                resets = Date(timeIntervalSince1970: (now.timeIntervalSince1970 + after).rounded())
            }
            return Window(percent: percent, seconds: seconds, resetsAt: resets)
        }
    }

    private static func kind(of seconds: Int?) -> LimitKind {
        switch seconds {
        case sessionSeconds: return .session
        case weekSeconds: return .weekly
        default: return .period
        }
    }

    /// A weekly limit of a model reads "Week · <model>" by itself; any other window says its length
    /// (`<model> 5 h`), the model name cut so that the whole stays within the 64 characters of a label.
    private static func label(name: String, seconds: Int?) -> String? {
        if seconds == weekSeconds { return nil }
        guard let seconds else { return name }
        let length = seconds % 86_400 == 0 && seconds >= 2 * 86_400 ? "\(seconds / 86_400) d"
            : seconds % 3600 == 0 ? "\(seconds / 3600) h" : "\(seconds / 60) min"
        let room = ProviderText.maxLabelLength - length.count - 1
        let shown = name.count > room ? String(name.prefix(room)).trimmingCharacters(in: .whitespaces) : name
        return "\(shown) \(length)"
    }

    /// Session, week, other windows, then the limits of models by name and window length.
    static func sorted(_ limits: [UsageLimit]) -> [UsageLimit] {
        func rank(_ l: UsageLimit) -> Int {
            switch l.kind { case .session: 0; case .weekly: 1; case .model: 3; default: 2 }
        }
        return limits.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.kind == .model, (a.model ?? "") != (b.model ?? "") { return (a.model ?? "") < (b.model ?? "") }
            return (a.windowSeconds ?? 0) < (b.windowSeconds ?? 0)
        }
    }
}
