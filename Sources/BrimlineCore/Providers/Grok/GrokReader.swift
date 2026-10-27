import Foundation

/// Grok, through the Grok CLI: the sign-in the CLI keeps in `~/.grok/auth.json`, then the billing call
/// the CLI itself makes for its credits.
///
/// Rules: the file is `~/.grok/auth.json` and nothing else of the CLI is opened (no `config.toml`, no
/// Keychain item, no program launched; `GROK_HOME`, `GROK_AUTH_PATH` and `XAI_API_KEY` are never read
/// from the environment); only the sign-in of an xAI account is decoded (see `GrokAuth`); an expired
/// token is never sent and never renewed (the CLI renews it when it runs); a refused token asks to
/// sign in again; every other failure is `unavailable`, which the service retries with a growing delay.
public struct GrokReader: ProviderReader {
    public var http: any HTTPClient

    /// How long before its expiry a token is no longer sent.
    static let expiryMargin: TimeInterval = 60

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    public var provider: Provider { .grok }
    public var allowedURLs: [URL] { [GrokUsageAPI.url] }

    /// One card when `~/.grok` is a folder (the CLI was installed): its sign-in file is the account. The
    /// folder is only looked for, nothing in it is opened here.
    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        let folder = KeychainServiceName.normalize(home.appendingPathComponent(".grok").path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        return [Account(provider: .grok, source: folder + "/auth.json", email: nil, organization: nil,
                        seatTier: nil, keychainService: nil)]
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        let auth: GrokAuth
        do throws(SecretFile.Failure) {
            auth = try SecretFile.readJSON(GrokAuth.self, url: URL(fileURLWithPath: account.source))
        } catch {
            switch error {
            case .notFound:
                return .notReadable(reason: .noCLI)
            case .malformed, .unreadable:
                // The CLI may be rewriting the file right now: try again, never "signed out".
                return .failure(status: .unavailable, detail: "sign-in file unreadable", retryAfter: nil)
            case .notRegularFile, .wrongOwner, .tooLarge:
                return .failure(status: .unavailable, detail: "sign-in file refused", retryAfter: nil)
            }
        }

        guard let session = auth.session, let token = session.token else {
            return .notReadable(reason: auth.hasAPIKey ? .apiKey : .noCLI)
        }

        if let expiry = session.expiry, expiry <= now.addingTimeInterval(Self.expiryMargin) {
            return .expired
        }
        // A token or an id that cannot go in a header as it is (a line break, a space) is never sent.
        guard ProviderText.isHeaderToken(token) else {
            return .failure(status: .reconnect, detail: "unusable token", retryAfter: nil)
        }
        if let id = session.userId, !ProviderText.isIdentifier(id) {
            return .failure(status: .reconnect, detail: "unusable user id", retryAfter: nil)
        }

        do {
            let client = http.restricted(to: allowedURLs)
            let (data, response) = try await client.send(GrokUsageAPI.request(token: token, userId: session.userId))
            switch response.statusCode {
            case 200:
                let shape = ResponseShape.fingerprint(of: data)
                do {
                    let reading = try GrokUsageParser.parse(data)
                    if reading.limits.isEmpty { return .annotated([], shape: shape, note: .noFigureYet) }
                    if reading.sharedPool { return .annotated(reading.limits, shape: shape, note: .sharedPool) }
                    return .limits(reading.limits, shape: shape)
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
