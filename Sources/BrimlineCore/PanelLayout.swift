import Foundation

/// The accounts of one provider, as the panel groups them (variant A of the board: grouped by provider).
public struct ProviderGroup: Sendable, Identifiable {
    public var provider: Provider
    public var usages: [AccountUsage]
    public var id: String { provider.rawValue }

    public init(provider: Provider, usages: [AccountUsage]) {
        self.provider = provider
        self.usages = usages
    }
}

/// How the panel and the menu bar glyph read the accounts: pure functions, so the rules are tested
/// without drawing anything.
public enum PanelLayout {
    /// The order of the groups: the providers that give numbers first, in the order of the settings, then
    /// Gemini, which gives a sentence only.
    public static let providerOrder: [Provider] = [.claude, .chatgpt, .grok, .cursor, .gemini]

    /// One group per provider that is on or has accounts, in `providerOrder`; inside a group the accounts keep
    /// their order, so a card does not move from one refresh to the next. A provider that is on but has no
    /// account on this Mac still has its group (its card says so).
    public static func groups(_ usages: [AccountUsage], enabled: Set<Provider>) -> [ProviderGroup] {
        providerOrder.compactMap { provider in
            let own = usages.filter { $0.account.provider == provider }
            guard !own.isEmpty || enabled.contains(provider) else { return nil }
            return ProviderGroup(provider: provider, usages: own)
        }
    }

    /// The one-time hint that other providers exist: only while Claude is the single provider on, and until
    /// the user dismisses it.
    public static func showsProviderHint(enabled: Set<Provider>, dismissed: Bool) -> Bool {
        !dismissed && enabled == [.claude]
    }

    /// What the menu bar glyph shows: the limit closest to its ceiling among the accounts of the providers
    /// that are on. An account that is expired, "Do not read", unavailable or whose format changed counts only
    /// when no account is up to date, and the glyph is then dimmed.
    public static func glyph(_ accounts: [AccountUsage], providers: Set<Provider>, unread: Set<String>,
                             now: Date) -> (usage: AccountUsage, percent: Double, dimmed: Bool)? {
        let counted = accounts.filter { providers.contains($0.account.provider) }
        let fresh = counted.filter { $0.status == .ok && !unread.contains($0.id) }
        if let top = Ranking.mostLoaded(fresh, now: now) { return (top.usage, top.percent, false) }
        if let top = Ranking.mostLoaded(counted, now: now) { return (top.usage, top.percent, true) }
        return nil
    }
}
