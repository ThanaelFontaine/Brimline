import Foundation

/// ChatGPT, through Codex: the sign-in Codex keeps in `auth.json`, then the usage endpoint Codex
/// itself calls.
///
/// Rules: the file is `<CODEX_HOME>/auth.json` and nothing else of Codex is opened (no
/// `config.toml`, no Keychain item, no program launched); an expired token is never sent and never
/// renewed (Codex renews it when it runs); the refresh token is never decoded; a refused token asks
/// to sign in again; every other failure is `unavailable`, which the service retries with a growing
/// delay. The folder is `~/.codex`, or one the user added by hand: `CODEX_HOME` is never read from
/// the environment.
public struct ChatGPTReader: ProviderReader {
    public var http: any HTTPClient

    /// How long before its expiry a token is no longer sent.
    static let expiryMargin: TimeInterval = 60

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public var provider: Provider { .chatgpt }
    public var allowedURLs: [URL] { [ChatGPTUsageAPI.url] }

    /// `~/.codex` and the folders added by hand, when they are folders: one card each. The folder
    /// is only looked for, nothing in it is opened here.
    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        var accounts: [Account] = []
        var seen = Set<String>()
        let candidates = [(home.appendingPathComponent(".codex").path, false)]
            + settings.extraCodexFolders.map { ($0, true) }
        for (path, byHand) in candidates {
            let folder = KeychainServiceName.normalize(path)
            var isDirectory: ObjCBool = false
            guard !seen.contains(folder),
                  FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue
            else { continue }
            seen.insert(folder)
            accounts.append(Account(provider: .chatgpt, source: folder, email: nil, organization: nil,
                                    seatTier: nil, keychainService: nil, addedByHand: byHand))
        }
        return accounts
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        let file = URL(fileURLWithPath: account.source).appendingPathComponent("auth.json")
        let auth: CodexAuth
        do throws(SecretFile.Failure) {
            auth = try SecretFile.readJSON(CodexAuth.self, url: file)
        } catch {
            switch error {
            case .notFound:
                return .notReadable(reason: .keychainOrSignedOut)
            case .malformed, .unreadable:
                // Codex may be rewriting the file right now: try again, never "signed out".
                return .failure(status: .unavailable, detail: "sign-in file unreadable", retryAfter: nil)
            case .notRegularFile, .wrongOwner, .tooLarge:
                return .failure(status: .unavailable, detail: "sign-in file refused", retryAfter: nil)
            }
        }

        if auth.isAPIKey { return .notReadable(reason: .apiKey) }
        guard let token = auth.accessToken else { return .notReadable(reason: .keychainOrSignedOut) }

        if let expiry = JWTExpiry.expiry(of: token), expiry <= now.addingTimeInterval(Self.expiryMargin) {
            return .expired
        }
        // A token or an id that cannot go in a header as it is (a line break, a space) is never sent.
        guard ProviderText.isHeaderToken(token) else {
            return .failure(status: .reconnect, detail: "unusable token", retryAfter: nil)
        }
        if let id = auth.accountId, !ProviderText.isIdentifier(id) {
            return .failure(status: .reconnect, detail: "unusable account id", retryAfter: nil)
        }

        do {
            let client = http.restricted(to: allowedURLs)
            let (data, response) = try await client.send(ChatGPTUsageAPI.request(accessToken: token,
                                                                                  accountId: auth.accountId))
            switch response.statusCode {
            case 200:
                do {
                    return .limits(try ChatGPTUsageParser.parse(data, now: now), shape: ResponseShape.fingerprint(of: data))
                } catch {
                    // JSON that is not the expected one, or a page: the format changed, never a number.
                    return .failure(status: .formatChanged, detail: "unknown answer", retryAfter: nil)
                }
            case 401:
                return .failure(status: .reconnect, detail: "HTTP 401", retryAfter: nil)
            case 429:
                return .failure(status: .unavailable, detail: "HTTP 429", retryAfter: response.retryAfterSeconds)
            default:
                return .failure(status: .unavailable, detail: "HTTP \(response.statusCode)", retryAfter: nil)
            }
        } catch {
            return .failure(status: .unavailable, detail: "network", retryAfter: nil)
        }
    }
}
