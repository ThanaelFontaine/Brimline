import Foundation

/// Reads the usage of every account: the sign-in from the Keychain, then the provider's answer.
///
/// The same code serves the app (every few minutes) and `brimline status --live`.
/// Rules: an expired token is never sent and never renewed; a refused token asks to sign in
/// again; a failure keeps the last known numbers and waits longer before the next attempt.
public struct UsageService: Sendable {
    public var credentials: any CredentialReading
    public var http: any HTTPClient

    public init(credentials: any CredentialReading = SecurityToolCredentialReader(),
                http: any HTTPClient = URLSessionHTTPClient()) {
        self.credentials = credentials
        self.http = http
    }

    /// Growing delay after consecutive failures: 2, 4, 8, 16, 32, then 60 minutes.
    public static func retryDelay(afterFailures count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        let minutes = min(60, 2 * pow(2, Double(min(count, 6) - 1)))
        return minutes * 60
    }

    /// Reads every account. `previous` gives the last known numbers; `force` ignores the retry delay.
    public func refresh(accounts: [Account], previous: UsageSnapshot?, now: Date = Date(),
                        force: Bool = false) async -> UsageSnapshot {
        var results: [AccountUsage] = []
        await withTaskGroup(of: (Int, AccountUsage).self) { group in
            for (index, account) in accounts.enumerated() {
                let old = previous?.usage(for: account.id)
                group.addTask {
                    (index, await self.refresh(account: account, previous: old, now: now, force: force))
                }
            }
            var collected: [(Int, AccountUsage)] = []
            for await item in group { collected.append(item) }
            results = collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return UsageSnapshot(generatedAt: now, accounts: results)
    }

    public func refresh(account: Account, previous: AccountUsage?, now: Date = Date(),
                        force: Bool = false) async -> AccountUsage {
        var usage = previous ?? AccountUsage(account: account)
        usage.account = account // the identity may have changed (new address, new label)

        if !force, let retryAfter = usage.retryAfter, retryAfter > now, usage.status == .unavailable {
            return usage
        }
        usage.checkedAt = now

        let credential: ClaudeCredential
        do throws(CredentialError) {
            credential = try await Self.read(credentials, service: account.keychainService)
        } catch {
            switch error {
            case .notFound:
                return failed(usage, status: .signedOut, detail: "no Keychain item", now: now, backoff: false)
            case .unreadable:
                return failed(usage, status: .signedOut, detail: "unreadable Keychain item", now: now, backoff: false)
            case .toolFailed(let code):
                return failed(usage, status: .unavailable, detail: "security exited with \(code)", now: now, backoff: true)
            }
        }

        if credential.isExpired(at: now) {
            return failed(usage, status: .expired, detail: nil, now: now, backoff: false)
        }

        do {
            let (data, response) = try await http.send(ClaudeUsageAPI.request(accessToken: credential.accessToken))
            switch response.statusCode {
            case 200:
                do {
                    usage.limits = try UsageParser.parse(data)
                } catch {
                    return failed(usage, status: .unavailable, detail: "unknown answer", now: now, backoff: true)
                }
                usage.status = .ok
                usage.fetchedAt = now
                usage.failureCount = 0
                usage.retryAfter = nil
                usage.detail = nil
                return usage
            case 401:
                return failed(usage, status: .reconnect, detail: "HTTP 401", now: now, backoff: false)
            default:
                var result = failed(usage, status: .unavailable, detail: "HTTP \(response.statusCode)", now: now, backoff: true)
                if response.statusCode == 429,
                   let header = response.value(forHTTPHeaderField: "Retry-After"),
                   let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds > 0 {
                    let candidate = now.addingTimeInterval(min(seconds, 3600))
                    if candidate > (result.retryAfter ?? now) { result.retryAfter = candidate }
                }
                return result
            }
        } catch {
            return failed(usage, status: .unavailable, detail: "network", now: now, backoff: true)
        }
    }

    private func failed(_ usage: AccountUsage, status: AccountStatus, detail: String?, now: Date,
                        backoff: Bool) -> AccountUsage {
        var u = usage
        u.status = status
        u.detail = detail
        if backoff {
            u.failureCount += 1
            u.retryAfter = now.addingTimeInterval(Self.retryDelay(afterFailures: u.failureCount))
        } else {
            u.failureCount = 0
            u.retryAfter = nil
        }
        return u
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
