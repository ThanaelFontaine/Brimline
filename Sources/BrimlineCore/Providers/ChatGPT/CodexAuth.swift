import Foundation

/// The only part of Codex's `auth.json` that Brimline decodes: the sign-in mode, the access token and
/// the ChatGPT account id.
///
/// The file also holds a refresh token, the id token and an API key. They are not declared here, so
/// they are never decoded into a field: the decoder skips them whatever they hold. The value lives in
/// memory for one request only.
struct CodexAuth: Decodable {
    struct Tokens: Decodable {
        var accessToken: String?
        var accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }

    /// `chatgpt` for a ChatGPT sign-in, `apikey` for an API key (Codex writes it in lower case).
    var authMode: String?
    var tokens: Tokens?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case tokens
    }

    /// Codex is signed in with an API key: it has no subscription limit to show.
    var isAPIKey: Bool {
        guard let mode = authMode?.lowercased() else { return false }
        return mode == "apikey" || mode == "api_key"
    }

    var accessToken: String? {
        guard let token = tokens?.accessToken, !token.isEmpty else { return nil }
        return token
    }

    var accountId: String? {
        guard let id = tokens?.accountId, !id.isEmpty else { return nil }
        return id
    }
}

/// The expiry of a JWT access token: its `exp` claim, read without checking the signature. It is only
/// used so that an expired token is never sent; nothing else in the token is looked at.
enum JWTExpiry {
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = decode(String(parts[1])),
              let claims = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let exp = UsageParser.number(claims["exp"]), exp.isFinite, exp > 0 else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Base64url, with or without padding.
    private static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
