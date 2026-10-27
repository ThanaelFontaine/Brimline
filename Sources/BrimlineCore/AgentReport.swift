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

    enum CodingKeys: String, CodingKey {
        case kind, model, percent
        case currentPercent = "current_percent"
        case resetsAt = "resets_at"
        case resetsInSeconds = "resets_in_seconds"
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
    }

    init(_ limit: UsageLimit, now: Date) {
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
    public var folder: String
    public var hidden: Bool
    public var status: String
    public var message: String?
    public var fetchedAt: String?
    public var ageSeconds: Int?
    public var stale: Bool
    public var noGlobalWeeklyLimit: Bool
    public var limits: [AgentLimit]

    enum CodingKeys: String, CodingKey {
        case id, provider, email, organization, label, folder, hidden, status, message, stale, limits
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
        try c.encode(folder, forKey: .folder)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(status, forKey: .status)
        try c.encode(message, forKey: .message)
        try c.encode(fetchedAt, forKey: .fetchedAt)
        try c.encode(ageSeconds, forKey: .ageSeconds)
        try c.encode(stale, forKey: .stale)
        try c.encode(noGlobalWeeklyLimit, forKey: .noGlobalWeeklyLimit)
        try c.encode(limits, forKey: .limits)
    }

    public init(_ usage: AccountUsage, settings: BrimlineSettings, now: Date) {
        let account = usage.account
        id = account.id
        provider = account.provider.rawValue
        email = account.email
        organization = account.organization
        label = settings.label(for: account.id)
        folder = account.source
        hidden = settings.isHidden(account.id)
        status = usage.status.rawValue
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
                includeHidden: Bool = true) {
        schemaVersion = UsageSnapshot.currentSchemaVersion
        self.source = source
        generatedAt = ISODate.format(snapshot.generatedAt)
        ageSeconds = max(0, Int(now.timeIntervalSince(snapshot.generatedAt)))
        accounts = snapshot.accounts
            .filter { includeHidden || !settings.isHidden($0.account.id) }
            .map { AgentAccount($0, settings: settings, now: now) }
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
