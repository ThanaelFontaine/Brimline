import Foundation

/// Which window an agent cares about when it asks for the account with the most room.
public enum UsageWindow: String, Sendable, CaseIterable {
    /// Every limit that applies: the session, the week, and the model's week when a model is given.
    case any
    /// The five hour session only.
    case session
    /// The weekly limits only (all models, and the model's week when a model is given).
    case week
    /// The daily limits only.
    case day
    /// The monthly limits only (a billing cycle).
    case month
    /// The limits that have another window length.
    case period

    /// The windows an agent can ask for.
    public static let names = allCases.map(\.rawValue)
}

extension Provider {
    /// The windows that exist for this provider. `any` always does. Asking another provider's window
    /// (for example `session` of Grok) is an error, not an empty answer.
    public var windows: [UsageWindow] {
        switch self {
        case .claude: return [.any, .session, .week]
        case .chatgpt: return [.any, .session, .week, .period]
        case .gemini: return [.any, .day]
        case .grok: return [.any, .period]
        case .cursor: return [.any, .month]
        }
    }
}

public struct AccountChoice: Sendable {
    public var usage: AccountUsage
    /// Room left, from 0 to 100, on the tightest limit considered.
    public var headroom: Double
    /// The limit that sets `headroom`, nil when no limit applies.
    public var bindingLimit: UsageLimit?
}

public enum Ranking {
    /// The account closest to one of its limits (the menu bar glyph follows it), with its percentage.
    /// Only the providers in `providers` count (all of them when nil): a provider that is off never sets the glyph.
    public static func mostLoaded(_ accounts: [AccountUsage], providers: Set<Provider>? = nil,
                                  now: Date) -> (usage: AccountUsage, percent: Double)? {
        accounts
            .filter { providers?.contains($0.account.provider) ?? true }
            .compactMap { u in u.highestPercent(at: now).map { (usage: u, percent: $0) } }
            .max { $0.percent < $1.percent }
    }

    /// Statuses whose last numbers may be old: those accounts come after every other.
    private static func isDoubtful(_ status: AccountStatus) -> Bool { status == .unavailable || status == .formatChanged }

    /// Accounts ranked by room left for `window` and `model`, the best first.
    ///
    /// Only accounts with numbers are ranked. Accounts whose sign-in was refused or is missing
    /// are left out; an expired token stays in (the official tool renews it when it is used),
    /// with the age of its numbers. Unavailable accounts (their numbers may be old) come after
    /// every other account. An account that has none of the limits asked for is judged on its
    /// tightest limit, so a full session never reads as 100% room. Ties go to the freshest numbers.
    public static func rank(_ accounts: [AccountUsage], window: UsageWindow, model: String?,
                            now: Date) -> [AccountChoice] {
        let wanted = model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let choices: [AccountChoice] = accounts.compactMap { usage in
            guard usage.fetchedAt != nil, !usage.limits.isEmpty, usage.status != .reconnect,
                  usage.status != .signedOut, usage.status != .notReadable else { return nil }
            let considered = usage.limits.filter { limit in
                switch limit.kind {
                case .session: return window == .any || window == .session
                case .weekly: return window == .any || window == .week
                case .daily: return window == .any || window == .day
                case .monthly: return window == .any || window == .month
                case .period: return window == .any || window == .period
                case .model:
                    guard window != .session, let wanted, !wanted.isEmpty else { return false }
                    return limit.model?.lowercased() == wanted
                }
            }
            let pool = considered.isEmpty ? usage.limits : considered
            let binding = pool.max { $0.effectivePercent(at: now) < $1.effectivePercent(at: now) }
            let headroom = 100 - (binding?.effectivePercent(at: now) ?? 0)
            return AccountChoice(usage: usage, headroom: headroom, bindingLimit: binding)
        }
        return choices.sorted { a, b in
            let aUnavailable = Self.isDoubtful(a.usage.status), bUnavailable = Self.isDoubtful(b.usage.status)
            if aUnavailable != bUnavailable { return bUnavailable }
            if a.headroom != b.headroom { return a.headroom > b.headroom }
            return (a.usage.fetchedAt ?? .distantPast) > (b.usage.fetchedAt ?? .distantPast)
        }
    }
}
