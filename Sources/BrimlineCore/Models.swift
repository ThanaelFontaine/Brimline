import Foundation

/// A provider of AI subscriptions. Which ones Brimline reads is the registry's business
/// (`Providers.all`); which ones it may read for this user is `BrimlineSettings.enabledProviders`.
public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude
    case chatgpt
    case gemini
    case grok
    case cursor

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        case .cursor: return "Cursor"
        }
    }
}

/// One account found on the Mac. It holds no secret: only where the official tool keeps the
/// account, its public identity, and (for Claude) the name of its Keychain item.
public struct Account: Codable, Sendable, Hashable, Identifiable {
    /// Stable identifier: the provider and the absolute path of the connection.
    public var id: String
    public var provider: Provider
    /// Absolute path of the exact place the official tool keeps this connection (for Claude, the
    /// Claude Code configuration folder), without a trailing slash.
    public var source: String
    public var email: String?
    public var organization: String?
    public var seatTier: String?
    /// Name of the Keychain item (generic password) that holds the account's sign-in. Only Claude
    /// uses the Keychain: no other provider's Keychain item is ever read.
    public var keychainService: String?
    /// True when the folder was added by hand in the settings.
    public var addedByHand: Bool

    public init(provider: Provider = .claude, source: String, email: String?, organization: String?,
                seatTier: String?, keychainService: String?, addedByHand: Bool = false) {
        self.id = "\(provider.rawValue):\(source)"
        self.provider = provider
        self.source = source
        self.email = email
        self.organization = organization
        self.seatTier = seatTier
        self.keychainService = keychainService
        self.addedByHand = addedByHand
    }

    /// The name shown when no address is known.
    public var folderName: String { (source as NSString).lastPathComponent }
}

/// The kind of a limit, normalized across providers.
public enum LimitKind: String, Codable, Sendable {
    /// The rolling five hour session window.
    case session
    /// The weekly window that covers every model.
    case weekly
    /// A limit that covers one model or one pool only (Claude: a model's week), named in `model`.
    case model
    /// A window that resets every day.
    case daily
    /// A window that resets every month (a billing cycle).
    case monthly
    /// Any other window: its length is in `windowSeconds`.
    case period
}

public struct UsageLimit: Codable, Sendable, Hashable {
    public var kind: LimitKind
    /// Model name for a `model` limit (for example "Fable"), nil otherwise.
    public var model: String?
    /// Share of the limit used, from 0 to 100.
    public var percent: Double
    public var resetsAt: Date?
    /// Length of the window in seconds, when the provider says it.
    public var windowSeconds: Int?
    /// A name for the limit when the kind does not say enough (filtered, see `ProviderText`).
    public var label: String?

    public init(kind: LimitKind, model: String? = nil, percent: Double, resetsAt: Date?,
                windowSeconds: Int? = nil, label: String? = nil) {
        self.kind = kind
        self.model = model
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowSeconds = windowSeconds
        self.label = label
    }

    /// The percentage that still applies at `now`: a window whose reset time has passed is back to 0.
    public func effectivePercent(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 0 }
        return min(max(percent, 0), 100)
    }
}

/// Where an account stands, as far as Brimline knows.
public enum AccountStatus: String, Codable, Sendable, CaseIterable {
    /// The last request succeeded.
    case ok
    /// The access token has expired: the official tool renews it the next time it is used.
    case expired
    /// The provider refused the token (HTTP 401): the account must sign in again.
    case reconnect
    /// The provider did not answer usefully (rate limit, server error, network, unknown answer).
    case unavailable
    /// No sign-in was found in the Keychain for this account.
    case signedOut = "signed_out"
    /// This account has no limit Brimline can read, by design: see `AccountUsage.reason`.
    case notReadable = "not_readable"
    /// The provider answered with something Brimline does not recognize (its format changed).
    case formatChanged = "format_changed"
    /// Not checked yet.
    case pending
}

/// The usage of one account: the last known numbers and the state of the last attempt.
public struct AccountUsage: Codable, Sendable, Identifiable {
    public var account: Account
    public var status: AccountStatus
    /// Last known limits (kept when a later attempt fails, so they can be shown with their age).
    public var limits: [UsageLimit]
    /// When `limits` were read from the provider.
    public var fetchedAt: Date?
    /// When Brimline last tried to read this account.
    public var checkedAt: Date?
    /// Consecutive failures, used for the growing retry delay.
    public var failureCount: Int
    /// No new request before this date (growing delay after failures).
    public var retryAfter: Date?
    /// Short technical detail of the last failure (an HTTP code, never a token).
    public var detail: String?
    /// Why the account cannot be read, when `status` is `notReadable`.
    public var reason: NotReadableReason?
    /// Fingerprint of the keys of the last answer (SHA-256, no value in it): a change of it is a
    /// change of the provider's format.
    public var responseShape: String?

    public var id: String { account.id }

    public init(account: Account, status: AccountStatus = .pending, limits: [UsageLimit] = [],
                fetchedAt: Date? = nil, checkedAt: Date? = nil, failureCount: Int = 0,
                retryAfter: Date? = nil, detail: String? = nil, reason: NotReadableReason? = nil,
                responseShape: String? = nil) {
        self.account = account
        self.status = status
        self.limits = limits
        self.fetchedAt = fetchedAt
        self.checkedAt = checkedAt
        self.failureCount = failureCount
        self.retryAfter = retryAfter
        self.detail = detail
        self.reason = reason
        self.responseShape = responseShape
    }

    public var sessionLimit: UsageLimit? { limits.first { $0.kind == .session } }
    public var weeklyLimit: UsageLimit? { limits.first { $0.kind == .weekly } }
    public var modelLimits: [UsageLimit] { limits.filter { $0.kind == .model } }

    /// True for Claude team seats and other plans that have no weekly limit across all models.
    /// Other providers have no such notion: their windows are what they are.
    public var hasNoGlobalWeeklyLimit: Bool { account.provider == .claude && fetchedAt != nil && weeklyLimit == nil }

    /// Highest share used among the limits, as it applies at `now`.
    public func highestPercent(at now: Date) -> Double? {
        limits.map { $0.effectivePercent(at: now) }.max()
    }

    /// Age of the numbers in seconds, nil when nothing was ever read.
    public func age(at now: Date) -> TimeInterval? {
        fetchedAt.map { max(0, now.timeIntervalSince($0)) }
    }
}

/// Everything Brimline knows at one moment. This is what the cache file holds.
public struct UsageSnapshot: Codable, Sendable {
    /// 2 since the providers: limits of more kinds, `source`, `reason`, `responseShape`. An older cache is
    /// not read (the app writes a new one at once).
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var generatedAt: Date
    public var accounts: [AccountUsage]

    public init(generatedAt: Date, accounts: [AccountUsage]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.accounts = accounts
    }

    public func usage(for accountID: String) -> AccountUsage? {
        accounts.first { $0.account.id == accountID }
    }
}
