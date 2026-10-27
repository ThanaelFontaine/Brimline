import Foundation

/// The JSON that agents read, from `brimline status --json` and from the MCP server.
/// Keys are snake_case, texts are English, and every answer carries the age of its numbers.
/// It is built from the cache types, which hold no token.
public struct AgentLimit: Codable, Sendable, Equatable {
    public var kind: String
    public var model: String?
    /// Share used as the provider last reported it, 0 to 100.
    public var percent: Double
    /// Share that applies now: 0 once the reset time has passed.
    public var currentPercent: Double
    public var resetsAt: String?
    public var resetsInSeconds: Int?
    /// Length of the window in seconds when the provider says it.
    public var windowSeconds: Int?
    /// A name for the limit when its kind does not say enough.
    public var label: String?

    enum CodingKeys: String, CodingKey {
        case kind, model, percent, label
        case currentPercent = "current_percent"
        case resetsAt = "resets_at"
        case resetsInSeconds = "resets_in_seconds"
        case windowSeconds = "window_seconds"
    }

    /// Absent values are written as null, so every key is always there for agents.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(model, forKey: .model)
        try c.encode(percent, forKey: .percent)
        try c.encode(currentPercent, forKey: .currentPercent)
        try c.encode(resetsAt, forKey: .resetsAt)
        try c.encode(resetsInSeconds, forKey: .resetsInSeconds)
        try c.encode(windowSeconds, forKey: .windowSeconds)
        try c.encode(label, forKey: .label)
    }

    init(_ limit: UsageLimit, now: Date) {
        windowSeconds = limit.windowSeconds
        label = limit.label
        kind = limit.kind.rawValue
        model = limit.model
        percent = limit.percent
        currentPercent = limit.effectivePercent(at: now)
        resetsAt = limit.resetsAt.map(ISODate.format)
        resetsInSeconds = limit.resetsAt.map { max(0, Int($0.timeIntervalSince(now))) }
    }
}

public struct AgentAccount: Codable, Sendable, Equatable {
    public var id: String
    public var provider: String
    public var email: String?
    public var organization: String?
    public var label: String?
    /// Where the official tool keeps the connection, written from the home folder (`~/.claude-work`).
    public var source: String
    /// The Claude Code configuration folder, absolute. Claude accounts only (null for the others):
    /// `source` says the same thing for every provider.
    public var folder: String?
    public var hidden: Bool
    public var status: String
    /// Why the account has no readable limit, when `status` is `not_readable`.
    public var reason: String?
    public var message: String?
    public var fetchedAt: String?
    public var ageSeconds: Int?
    public var stale: Bool
    public var noGlobalWeeklyLimit: Bool
    public var limits: [AgentLimit]

    enum CodingKeys: String, CodingKey {
        case id, provider, email, organization, label, source, folder, hidden, status, reason, message, stale, limits
        case fetchedAt = "fetched_at"
        case ageSeconds = "age_seconds"
        case noGlobalWeeklyLimit = "no_global_weekly_limit"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(provider, forKey: .provider)
        try c.encode(email, forKey: .email)
        try c.encode(organization, forKey: .organization)
        try c.encode(label, forKey: .label)
        try c.encode(source, forKey: .source)
        try c.encode(folder, forKey: .folder)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(status, forKey: .status)
        try c.encode(reason, forKey: .reason)
        try c.encode(message, forKey: .message)
        try c.encode(fetchedAt, forKey: .fetchedAt)
        try c.encode(ageSeconds, forKey: .ageSeconds)
        try c.encode(stale, forKey: .stale)
        try c.encode(noGlobalWeeklyLimit, forKey: .noGlobalWeeklyLimit)
        try c.encode(limits, forKey: .limits)
    }

    public init(_ usage: AccountUsage, settings: BrimlineSettings, now: Date,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let account = usage.account
        id = account.id
        provider = account.provider.rawValue
        email = account.email
        organization = account.organization
        label = settings.label(for: account.id)
        source = AgentPath.display(account.source, home: home)
        folder = account.provider == .claude ? account.source : nil
        hidden = settings.isHidden(account.id)
        status = usage.status.rawValue
        reason = usage.status == .notReadable ? usage.reason?.rawValue : nil
        message = Strings(.en).statusMessage(usage.status)
        fetchedAt = usage.fetchedAt.map(ISODate.format)
        ageSeconds = usage.age(at: now).map { Int($0) }
        let staleAfter = TimeInterval(settings.refreshMinutes * 60 * 2 + 60)
        stale = usage.status != .ok || (usage.age(at: now).map { $0 > staleAfter } ?? true)
        noGlobalWeeklyLimit = usage.hasNoGlobalWeeklyLimit
        limits = usage.limits.map { AgentLimit($0, now: now) }
    }
}

public struct AgentUsageReport: Codable, Sendable {
    public var schemaVersion: Int
    /// "cache" (numbers written by the app) or "live" (read just now).
    public var source: String
    public var generatedAt: String
    public var ageSeconds: Int
    public var accounts: [AgentAccount]

    enum CodingKeys: String, CodingKey {
        case source, accounts
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case ageSeconds = "age_seconds"
    }

    public init(snapshot: UsageSnapshot, settings: BrimlineSettings, source: String, now: Date,
                includeHidden: Bool = true, provider: Provider? = nil,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        schemaVersion = UsageSnapshot.currentSchemaVersion
        self.source = source
        generatedAt = ISODate.format(snapshot.generatedAt)
        ageSeconds = max(0, Int(now.timeIntervalSince(snapshot.generatedAt)))
        accounts = snapshot.accounts
            .filter { includeHidden || !settings.isHidden($0.account.id) }
            .filter { provider == nil || $0.account.provider == provider }
            .map { AgentAccount($0, settings: settings, now: now, home: home) }
    }
}

public enum AgentPath {
    /// A path as people write it: `~/.claude-work` for a folder of the home. Agents get this form,
    /// never the user name that the absolute path carries.
    public static func display(_ path: String, home: URL) -> String {
        let h = KeychainServiceName.normalize(home.path)
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}

enum AgentJSON {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func object<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [String: Any]() }
        return object
    }
}

extension AgentUsageReport {
    public func jsonString() -> String { AgentJSON.encode(self) }
}
