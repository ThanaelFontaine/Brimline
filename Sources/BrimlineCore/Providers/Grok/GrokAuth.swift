import Foundation

/// The only part of the Grok CLI's `auth.json` that Brimline decodes: the sign-in of an xAI account.
///
/// The file maps a scope to a sign-in. The scope of a sign-in with an xAI account is the issuer
/// `https://auth.x.ai`, `::` and the OAuth client id (`xai-grok-login`, `config.rs`, `auth_scope`);
/// an API key is stored under `xai::api_key`; an enterprise login provider, or a devbox, under
/// another scope. Only the first kind is read, and only its `key`, `user_id`, `expires_at` and
/// `create_time` are decoded: the refresh token, the e-mail, the team and every other scope are never
/// decoded into a field (the decoder skips them whatever they hold), and the `key` of an API key or
/// of another issuer is not even looked at.
struct GrokAuth: Decodable {
    /// The issuer of a sign-in with an xAI account.
    static let issuer = "https://auth.x.ai"
    static let apiKeyScope = "xai::api_key"

    /// One sign-in of an xAI account.
    struct Session: Decodable {
        var key: String?
        var userId: String?
        /// RFC 3339 (the CLI writes nanoseconds), absent when the server gave none.
        var expiresAt: String?
        var createTime: String?

        enum CodingKeys: String, CodingKey {
            case key
            case userId = "user_id"
            case expiresAt = "expires_at"
            case createTime = "create_time"
        }

        /// When the token stops being valid. The CLI gives a token with no server expiry a 30 day
        /// lifetime from the day it was minted (its authentication guide).
        var expiry: Date? {
            if let expiresAt { return ISODate.parse(expiresAt) }
            if let createTime, let date = ISODate.parse(createTime) { return date.addingTimeInterval(30 * 86_400) }
            return nil
        }

        var token: String? {
            guard let key, !key.isEmpty else { return nil }
            return key
        }
    }

    /// The sign-in with an xAI account, when the file has one: the one that lasts longest if the CLI
    /// keeps several (one per OAuth client).
    var session: Session?
    /// The file has a sign-in by API key.
    var hasAPIKey = false

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Looks at the names of the scopes, and decodes the entries of an xAI account only.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var best: Session?
        for key in container.allKeys {
            let name = key.stringValue
            if name == Self.apiKeyScope {
                hasAPIKey = true
            } else if name == Self.issuer || name.hasPrefix(Self.issuer + "::") {
                let candidate = try container.decode(Session.self, forKey: key)
                guard candidate.token != nil else { continue }
                if best == nil || (candidate.expiry ?? .distantPast) > (best?.expiry ?? .distantPast) { best = candidate }
            }
        }
        session = best
    }
}
