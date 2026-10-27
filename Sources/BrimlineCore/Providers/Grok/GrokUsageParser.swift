import Foundation

/// Turns the answer of `billing?format=credits` into a Brimline limit.
///
/// `config.creditUsagePercent` is the share of the included credits used in the current period
/// (0 to 100) and `config.currentPeriod` says which period: its `type` (`USAGE_PERIOD_TYPE_WEEKLY` or
/// `..._MONTHLY`), its `start` and its `end` (RFC 3339). It is one `period` limit, whose length is
/// `end - start` and whose reset time is `end`. The percentage is absent early in a period (the
/// server leaves out what is zero): that is "no number yet", never a 0 %. The older answer
/// (`monthlyLimit` and `used` in cents, `billingPeriodStart` and `billingPeriodEnd`) is read when the
/// new field is not there. Every other key (on-demand credits, prepaid balance, history, tier, usage
/// per product) is ignored.
///
/// An answer with no percentage and no allowance (a free account: no `creditUsagePercent`, no `monthlyLimit`) says
/// that xAI gives no credit limit for the account: `hasCap` is false and the reader says so, with no figure
/// promised. An allowance with no use yet (`monthlyLimit` above zero, no `used`) is a cap whose number is not
/// there yet: `hasCap` is true.
public enum GrokUsageParser {
    public enum ParseError: Error, Equatable {
        case notJSON
        /// JSON, but not the answer this parser knows: no `config` key.
        case unrecognized
    }

    /// What one answer says: the limit (none while there is no number yet) and whether the credits are
    /// a pool shared by the Grok products.
    public struct Reading: Equatable, Sendable {
        public var limits: [UsageLimit]
        public var sharedPool: Bool
        /// Whether the answer gives an allowance of credits (`monthlyLimit` above zero).
        public var hasCap: Bool
    }

    static let weekSeconds = 604_800

    public static func parse(_ data: Data) throws(ParseError) -> Reading {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { throw .notJSON }
        guard let rawConfig = root["config"], rawConfig is [String: Any] || rawConfig is NSNull else { throw .unrecognized }
        // `config: null` is an answer the CLI accepts: an account with no credits configuration.
        guard let config = rawConfig as? [String: Any] else { return Reading(limits: [], sharedPool: false, hasCap: false) }

        let shared = isTrue(config["isUnifiedBillingUser"])
        let allowance = cents(config["monthlyLimit"]) ?? 0
        var percent = UsageParser.number(config["creditUsagePercent"])
        let period = config["currentPeriod"] as? [String: Any]
        var start = UsageParser.date(period?["start"])
        var end = UsageParser.date(period?["end"])
        var type = period?["type"] as? String

        if percent == nil, allowance > 0, let used = cents(config["used"]) {
            percent = used / allowance * 100
            start = start ?? UsageParser.date(config["billingPeriodStart"])
            end = end ?? UsageParser.date(config["billingPeriodEnd"])
            type = type ?? "USAGE_PERIOD_TYPE_MONTHLY"
        }
        guard let percent, percent.isFinite else { return Reading(limits: [], sharedPool: shared, hasCap: allowance > 0) }

        return Reading(limits: [UsageLimit(kind: .period, percent: percent, resetsAt: end,
                                           windowSeconds: windowSeconds(start: start, end: end, type: type))],
                       sharedPool: shared, hasCap: allowance > 0)
    }

    private static func isTrue(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    /// A `Cent` is `{"val": 1234}`, and `{}` for zero (proto3 JSON leaves out what is zero).
    private static func cents(_ value: Any?) -> Double? {
        guard let object = value as? [String: Any] else { return nil }
        return object.isEmpty ? 0 : UsageParser.number(object["val"])
    }

    /// The length of the period: `end - start` when both are there and make sense, else a week for a
    /// weekly period, nothing for any other.
    private static func windowSeconds(start: Date?, end: Date?, type: String?) -> Int? {
        if let start, let end {
            let length = end.timeIntervalSince(start)
            if length.isFinite, length > 0, length < 1e8 { return Int(length.rounded()) }
        }
        return type == "USAGE_PERIOD_TYPE_WEEKLY" ? weekSeconds : nil
    }
}
