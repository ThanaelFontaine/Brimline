import Foundation

/// Turns the answer of `usage-summary` into Brimline limits.
///
/// Shape (the `CursorUsageSummary` of CodexBar, `CursorStatusProbe.swift` at commit `5f93dc3`, and
/// the way its `CursorStatusProbe+UsageSummary.swift` reads it): `billingCycleStart` and
/// `billingCycleEnd` bound the cycle, `membershipType` names the plan (kept as the label of the total when it is one or two short words), `isUnlimited` says there is
/// no cap, and `individualUsage.plan` holds `totalPercentUsed`, `autoPercentUsed` and `apiPercentUsed`
/// (already in points of percent, even under 1: 0.36 is 0.36 %, never 36 %) and `used` and `limit` in
/// cents. The total is one `monthly` limit that resets at the end of the cycle; `Auto` and `API` are
/// the limits of the two model pools, when Cursor gives them.
///
/// Without `totalPercentUsed` the total is `used` over `limit` when the limit is above zero. A member
/// of a team has no `plan` but may have `individualUsage.overall` (the same cents): that is read the
/// same way. Anything else leaves no figure: "no number yet", never a 0 %. Every other key (on-demand
/// spend, the team's pool, display messages, dates of the history) is ignored.
public enum CursorUsageParser {
    public enum ParseError: Error, Equatable {
        case notJSON
        /// JSON, but not the answer this parser knows (none of its keys, or an account whose usage
        /// is in a place this parser does not read).
        case unrecognized
    }

    /// What one answer says: the limits (none while there is no number yet) and whether the plan has no cap.
    public struct Reading: Equatable, Sendable {
        public var limits: [UsageLimit]
        public var unlimited: Bool
    }

    /// An answer that has none of these is not a `usage-summary`.
    static let knownKeys: Set<String> = ["billingCycleStart", "billingCycleEnd", "membershipType", "isUnlimited",
                                         "individualUsage", "teamUsage"]

    public static func parse(_ data: Data) throws(ParseError) -> Reading {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { throw .notJSON }
        guard !knownKeys.isDisjoint(with: root.keys) else { throw .unrecognized }

        if isTrue(root["isUnlimited"]) { return Reading(limits: [], unlimited: true) }

        let individual = root["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let overall = individual?["overall"] as? [String: Any]
        // No `plan` and no `overall`: the usage of this account is somewhere this parser does not read.
        guard plan != nil || overall != nil else { throw .unrecognized }

        let end = UsageParser.date(root["billingCycleEnd"])
        let window = windowSeconds(start: UsageParser.date(root["billingCycleStart"]), end: end)

        var limits: [UsageLimit] = []
        if let total = totalPercent(plan: plan, overall: overall) {
            limits.append(UsageLimit(kind: .monthly, percent: total, resetsAt: end, windowSeconds: window,
                                     label: planName(root["membershipType"])))
        }
        for (key, name) in [("autoPercentUsed", "Auto"), ("apiPercentUsed", "API")] {
            if let percent = percent(plan?[key]) {
                limits.append(UsageLimit(kind: .model, model: name, percent: percent, resetsAt: end, windowSeconds: window))
            }
        }
        return Reading(limits: limits, unlimited: false)
    }

    /// `totalPercentUsed`, else the cents of the plan, else the cents of `overall`.
    private static func totalPercent(plan: [String: Any]?, overall: [String: Any]?) -> Double? {
        if let total = percent(plan?["totalPercentUsed"]) { return total }
        return fromCents(plan) ?? fromCents(overall)
    }

    /// `used` over `limit` (cents), when both are there and the limit is above zero.
    private static func fromCents(_ object: [String: Any]?) -> Double? {
        guard let used = UsageParser.number(object?["used"]), let limit = UsageParser.number(object?["limit"]),
              used.isFinite, limit.isFinite, limit > 0 else { return nil }
        return used * 100 / limit
    }

    /// The plan, as the label of the total: one or two words of at most 24 letters, digits, `_` and `-`
    /// (`pro`, `enterprise`, `free_trial`). A sentence from the provider is never a plan name.
    static func planName(_ value: Any?) -> String? {
        guard let text = ProviderText.label(value as? String) else { return nil }
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count <= 2, words.allSatisfy({ (1...24).contains($0.count) }),
              !text.contains(".") else { return nil }
        return text
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let number = UsageParser.number(value), number.isFinite else { return nil }
        return number
    }

    private static func isTrue(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    /// The length of the cycle: `end - start` when both are there and make sense.
    private static func windowSeconds(start: Date?, end: Date?) -> Int? {
        guard let start, let end else { return nil }
        let length = end.timeIntervalSince(start)
        return length.isFinite && length > 0 && length < 1e8 ? Int(length.rounded()) : nil
    }
}
