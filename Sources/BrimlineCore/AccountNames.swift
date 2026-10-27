import Foundation

/// How an account is named, for the panel and for `brimline status`: one place, so the two say the same thing.
///
/// Claude is named by its address; another provider by its name and plan ("ChatGPT Plus"), never by an address
/// (the readers do not keep it). A label the user gave wins; the provider and plan then go under it.
public enum AccountNames {
    /// The name of an account without its label.
    public static func identity(for account: Account) -> String {
        if account.provider == .claude { return account.email ?? account.folderName }
        return providerAndPlan(account)
    }

    public static func providerAndPlan(_ account: Account) -> String {
        [account.provider.displayName, account.seatTier?.capitalized].compactMap { $0 }.joined(separator: " ")
    }

    public static func title(for account: Account, settings: BrimlineSettings) -> String {
        settings.label(for: account.id) ?? identity(for: account)
    }

    /// What goes under the title: Claude's address under a label, or its organization and plan; for another
    /// provider, its name and plan under a label, or the place of the connection when several accounts of the
    /// provider are shown (`siblings`).
    public static func subtitle(for account: Account, settings: BrimlineSettings, siblings: Int, home: URL) -> String? {
        if account.provider == .claude {
            if settings.label(for: account.id) != nil, let email = account.email { return email }
            let parts = [account.organization, account.seatTier?.capitalized].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if settings.label(for: account.id) != nil { return providerAndPlan(account) }
        return siblings > 1 ? displayPath(account.source, home: home) : nil
    }

    /// A folder as people write it: "~/.claude-work" for a folder of the home.
    public static func displayPath(_ path: String, home: URL) -> String {
        let h = KeychainServiceName.normalize(home.path)
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}
