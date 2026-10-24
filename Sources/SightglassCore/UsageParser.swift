import Foundation

/// Turns the usage answer into Sightglass limits.
///
/// The `limits` list is preferred: one entry per window, with `kind` session, weekly_all or
/// weekly_scoped (one per model). When it is missing, `five_hour` and `seven_day` are used.
/// Every other key of the answer is ignored.
public enum UsageParser {
    public enum ParseError: Error, Equatable {
        case notJSON
        case noKnownLimit
    }

    public static func parse(_ data: Data) throws(ParseError) -> [UsageLimit] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { throw .notJSON }

        var limits: [UsageLimit] = []
        if let list = root["limits"] as? [[String: Any]] {
            for entry in list {
                guard let kind = entry["kind"] as? String,
                      let percent = number(entry["percent"]) else { continue }
                let resets = date(entry["resets_at"])
                switch kind {
                case "session":
                    limits.append(UsageLimit(kind: .session, percent: percent, resetsAt: resets))
                case "weekly_all":
                    limits.append(UsageLimit(kind: .weekly, percent: percent, resetsAt: resets))
                case "weekly_scoped":
                    let scope = entry["scope"] as? [String: Any]
                    let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                    guard let model, !model.isEmpty else { continue }
                    limits.append(UsageLimit(kind: .weeklyModel, model: model, percent: percent, resetsAt: resets))
                default:
                    continue
                }
            }
        }

        // Fallback on the older fields, only for the windows the list did not give.
        if !limits.contains(where: { $0.kind == .session }),
           let window = root["five_hour"] as? [String: Any], let percent = number(window["utilization"]) {
            limits.append(UsageLimit(kind: .session, percent: percent, resetsAt: date(window["resets_at"])))
        }
        if root["limits"] == nil || root["limits"] is NSNull,
           let window = root["seven_day"] as? [String: Any], let percent = number(window["utilization"]) {
            limits.append(UsageLimit(kind: .weekly, percent: percent, resetsAt: date(window["resets_at"])))
        }

        guard !limits.isEmpty else { throw .noKnownLimit }
        return sorted(limits)
    }

    /// Session first, then the weekly limit, then the per model limits by name.
    static func sorted(_ limits: [UsageLimit]) -> [UsageLimit] {
        func rank(_ l: UsageLimit) -> Int {
            switch l.kind { case .session: 0; case .weekly: 1; case .weeklyModel: 2 }
        }
        return limits.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : (a.model ?? "") < (b.model ?? "")
        }
    }

    static func number(_ value: Any?) -> Double? {
        // JSONSerialization gives NSNumber; true and false are CFBoolean and are not numbers here.
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        return nil
    }

    /// Reset times are rounded to the nearest second: the cache stores whole seconds, and the
    /// API sends times such as 02:59:59.98 for a reset at 03:00, which must not show as 02:59.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, let date = ISODate.parse(text) else { return nil }
        return Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
    }
}

/// ISO 8601 dates, with or without fractional seconds (the API sends up to six digits).
public enum ISODate {
    public static func parse(_ text: String) -> Date? {
        if let d = try? Date(text, strategy: .iso8601) { return d }
        // Fractional seconds: keep at most three digits, which the parser accepts.
        let pattern = /^(.*T\d{2}:\d{2}:\d{2})\.(\d+)(.*)$/
        if let m = text.wholeMatch(of: pattern) {
            let fraction = String(m.2.prefix(3))
            let trimmed = "\(m.1).\(fraction)\(m.3)"
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: trimmed) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: "\(m.1)\(m.3)")
        }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
