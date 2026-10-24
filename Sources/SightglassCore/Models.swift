import Foundation

/// A provider of AI subscriptions. v0.1 reads Claude only; the others are listed as "coming soon".
public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude
    case chatgpt
    case gemini
    case grok

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        }
    }

    /// Providers that have a working plugin in this version.
    public var isSupported: Bool { self == .claude }
}

/// One account found on the Mac. It holds no secret: only where the official tool keeps the
/// account, its public identity, and the name of its Keychain item.
public struct Account: Codable, Sendable, Hashable, Identifiable {
    /// Stable identifier: the provider and the absolute configuration folder.
    public var id: String
    public var provider: Provider
    /// Absolute path of the Claude Code configuration folder, without a trailing slash.
    public var configDir: String
    public var email: String?
    public var organization: String?
    public var seatTier: String?
    /// Name of the Keychain item (generic password) that holds the account's sign-in.
    public var keychainService: String
    /// True when the folder was added by hand in the settings.
    public var addedByHand: Bool

    public init(provider: Provider = .claude, configDir: String, email: String?, organization: String?,
                seatTier: String?, keychainService: String, addedByHand: Bool = false) {
        self.id = "\(provider.rawValue):\(configDir)"
        self.provider = provider
        self.configDir = configDir
        self.email = email
        self.organization = organization
        self.seatTier = seatTier
        self.keychainService = keychainService
        self.addedByHand = addedByHand
    }

    /// The name shown when no address is known.
    public var folderName: String { (configDir as NSString).lastPathComponent }
}

/// The kind of a limit, normalized across the shapes of the usage answer.
public enum LimitKind: String, Codable, Sendable {
    /// The rolling five hour session window.
    case session
    /// The weekly window that covers every model.
    case weekly
    /// A weekly window that covers one model only.
    case weeklyModel = "weekly_model"
}

public struct UsageLimit: Codable, Sendable, Hashable {
    public var kind: LimitKind
    /// Model name for a `weeklyModel` limit (for example "Fable"), nil otherwise.
    public var model: String?
    /// Share of the limit used, from 0 to 100.
    public var percent: Double
    public var resetsAt: Date?

    public init(kind: LimitKind, model: String? = nil, percent: Double, resetsAt: Date?) {
        self.kind = kind
        self.model = model
        self.percent = percent
        self.resetsAt = resetsAt
    }

    /// The percentage that still applies at `now`: a window whose reset time has passed is back to 0.
    public func effectivePercent(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 0 }
        return min(max(percent, 0), 100)
    }
}

/// Where an account stands, as far as Sightglass knows.
public enum AccountStatus: String, Codable, Sendable {
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
    /// When Sightglass last tried to read this account.
    public var checkedAt: Date?
    /// Consecutive failures, used for the growing retry delay.
    public var failureCount: Int
    /// No new request before this date (growing delay after failures).
    public var retryAfter: Date?
    /// Short technical detail of the last failure (an HTTP code, never a token).
    public var detail: String?

    public var id: String { account.id }

    public init(account: Account, status: AccountStatus = .pending, limits: [UsageLimit] = [],
                fetchedAt: Date? = nil, checkedAt: Date? = nil, failureCount: Int = 0,
                retryAfter: Date? = nil, detail: String? = nil) {
        self.account = account
        self.status = status
        self.limits = limits
        self.fetchedAt = fetchedAt
        self.checkedAt = checkedAt
        self.failureCount = failureCount
        self.retryAfter = retryAfter
        self.detail = detail
    }

    public var sessionLimit: UsageLimit? { limits.first { $0.kind == .session } }
    public var weeklyLimit: UsageLimit? { limits.first { $0.kind == .weekly } }
    public var modelLimits: [UsageLimit] { limits.filter { $0.kind == .weeklyModel } }

    /// True for team seats and other plans that have no weekly limit across all models.
    public var hasNoGlobalWeeklyLimit: Bool { fetchedAt != nil && weeklyLimit == nil }

    /// Highest share used among the limits, as it applies at `now`.
    public func highestPercent(at now: Date) -> Double? {
        limits.map { $0.effectivePercent(at: now) }.max()
    }

    /// Age of the numbers in seconds, nil when nothing was ever read.
    public func age(at now: Date) -> TimeInterval? {
        fetchedAt.map { max(0, now.timeIntervalSince($0)) }
    }
}

/// Everything Sightglass knows at one moment. This is what the cache file holds.
public struct UsageSnapshot: Codable, Sendable {
    public static let currentSchemaVersion = 1

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
