import Foundation

/// Why an account cannot be read at all, as opposed to a read that failed. Claude is always readable
/// or fails; ChatGPT answers `apiKey` or `keychainOrSignedOut`, Gemini `consumerPlan`. The other
/// reasons come with their readers.
public enum NotReadableReason: String, Codable, Sendable, CaseIterable {
    case apiKey = "api_key"
    case keychainOrSignedOut = "keychain_or_signed_out"
    case consumerPlan = "consumer_plan"
    case protectedSignIn = "protected_sign_in"
    case noCLI = "no_cli"
}

/// What one reading of one account gave. The service turns it into an `AccountUsage`: it keeps the
/// last known numbers on a failure and owns the growing delay, so a reader only reports.
public enum ProviderReading: Sendable {
    /// The provider answered: the limits, and a fingerprint of the answer's shape (no value in it,
    /// empty until a provider needs it).
    case limits([UsageLimit], shape: String)
    /// This account cannot be read, by design (not a failure, no retry delay).
    case notReadable(reason: NotReadableReason)
    /// The official tool's sign-in has expired: Brimline never sends it nor renews it.
    case expired
    /// The read failed. `.unavailable` backs off and retries; any other status waits for the user.
    /// `retryAfter` is a wait asked by the provider, in seconds, applied when longer than the backoff.
    case failure(status: AccountStatus, detail: String?, retryAfter: TimeInterval?)
}

/// One provider's way to find its accounts on the Mac and read their limits.
public protocol ProviderReader: Sendable {
    var provider: Provider { get }
    /// The closed list of URLs this reader may call, whole (see `AllowListHTTPClient`). Nothing else
    /// is ever requested, with a token or without.
    var allowedURLs: [URL] { get }
    /// The accounts of this provider, from exact places on disk. Reads no secret.
    func discover(home: URL, settings: BrimlineSettings) -> [Account]
    /// Reads one account. Never throws: every outcome is a `ProviderReading`.
    func read(account: Account, now: Date) async -> ProviderReading
}
