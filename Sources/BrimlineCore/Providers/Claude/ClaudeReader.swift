import Foundation

/// Claude Code: the sign-in from the Keychain, then the usage endpoint of Anthropic.
///
/// Rules: an expired token is never sent and never renewed; a refused token asks to sign in
/// again; every other failure is `unavailable`, which the service retries with a growing delay.
public struct ClaudeReader: ProviderReader {
    public var credentials: any CredentialReading
    public var http: any HTTPClient

    public init(credentials: any CredentialReading = SecurityToolCredentialReader(),
                http: any HTTPClient = URLSessionHTTPClient()) {
        self.credentials = credentials
        self.http = http
    }

    public var provider: Provider { .claude }

    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        AccountDiscovery(home: home, extraFolders: settings.extraFolders).discover()
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        guard let service = account.keychainService else {
            return .failure(status: .signedOut, detail: "no Keychain item", retryAfter: nil)
        }
        let credential: ClaudeCredential
        do throws(CredentialError) {
            credential = try await Self.read(credentials, service: service)
        } catch {
            switch error {
            case .notFound:
                return .failure(status: .signedOut, detail: "no Keychain item", retryAfter: nil)
            case .unreadable:
                return .failure(status: .signedOut, detail: "unreadable Keychain item", retryAfter: nil)
            case .toolFailed(let code):
                return .failure(status: .unavailable, detail: "security exited with \(code)", retryAfter: nil)
            }
        }

        if credential.isExpired(at: now) { return .expired }

        do {
            let (data, response) = try await http.send(ClaudeUsageAPI.request(accessToken: credential.accessToken))
            switch response.statusCode {
            case 200:
                do {
                    return .limits(try UsageParser.parse(data), shape: "")
                } catch {
                    return .failure(status: .unavailable, detail: "unknown answer", retryAfter: nil)
                }
            case 401:
                return .failure(status: .reconnect, detail: "HTTP 401", retryAfter: nil)
            case 429:
                var wait: TimeInterval?
                if let header = response.value(forHTTPHeaderField: "Retry-After"),
                   let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds > 0 {
                    wait = min(seconds, 3600)
                }
                return .failure(status: .unavailable, detail: "HTTP 429", retryAfter: wait)
            default:
                return .failure(status: .unavailable, detail: "HTTP \(response.statusCode)", retryAfter: nil)
            }
        } catch {
            return .failure(status: .unavailable, detail: "network", retryAfter: nil)
        }
    }

    /// Runs the blocking Keychain read off the caller's thread.
    private static func read(_ reader: any CredentialReading, service: String) async throws(CredentialError) -> ClaudeCredential {
        let result: Result<ClaudeCredential, CredentialError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do throws(CredentialError) {
                    continuation.resume(returning: .success(try reader.readCredential(service: service)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        return try result.get()
    }
}
