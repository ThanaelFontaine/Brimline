import Foundation

/// The session of the Cursor app, as the web call needs it: the access token itself, and the user id
/// that goes with it in the cookie.
///
/// The token is a JWT. It is decoded without checking the signature, for two claims only: `exp`, so
/// that an expired token is never sent, and `sub`, whose last segment after `|` (`auth0|user_...`) is
/// the user id of the cookie. The id must be a short plain identifier: anything else (a `;`, a `%`, a
/// space, a line break) would let the token's content shape the header, so such a token is not used.
/// The value lives in memory for one request and is never written, logged or returned.
struct CursorToken {
    /// The user id is at most this long.
    static let maxUserIDLength = 128

    let value: String
    let userID: String
    /// When the token stops being valid, nil when it says nothing.
    let expiry: Date?

    /// Nil when the token cannot go in a header as it is, or has no usable `sub`.
    init?(jwt: String) {
        guard ProviderText.isHeaderToken(jwt), let claims = JWTExpiry.claims(of: jwt),
              let subject = claims["sub"] as? String,
              let id = subject.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init),
              Self.isUserID(id) else { return nil }
        value = jwt
        userID = id
        expiry = JWTExpiry.expiry(of: jwt)
    }

    /// Letters, digits, `.`, `_` and `-`, at most 128 characters.
    static func isUserID(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= maxUserIDLength && text.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
                || $0 == 0x2E || $0 == 0x5F || $0 == 0x2D
        }
    }
}
