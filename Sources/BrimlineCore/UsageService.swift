import Foundation

/// Reads the usage of every account: each account goes to the reader of its provider.
///
/// The same code serves the app (every few minutes) and `brimline status --live`.
/// The readers only report what they saw. The rules live here: the last known numbers are kept
/// on a failure, and an `unavailable` account waits longer before each new attempt.
public struct UsageService: Sendable {
    public var readers: [any ProviderReader]

    public init(readers: [any ProviderReader] = Providers.all) {
        self.readers = readers
    }

    /// The Claude reader with its Keychain and network replaced (tests).
    public init(credentials: any CredentialReading, http: any HTTPClient = URLSessionHTTPClient()) {
        self.init(readers: Providers.make(credentials: credentials, http: http))
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

        guard let reader = readers.first(where: { $0.provider == account.provider }) else {
            return failed(usage, status: .unavailable, detail: "no reader for \(account.provider.rawValue)",
                          now: now, backoff: false)
        }

        switch await reader.read(account: account, now: now) {
        case .limits(let limits, _):
            usage.limits = limits
            usage.status = .ok
            usage.fetchedAt = now
            usage.failureCount = 0
            usage.retryAfter = nil
            usage.detail = nil
            return usage
        case .expired:
            return failed(usage, status: .expired, detail: nil, now: now, backoff: false)
        case .notReadable:
            // No provider reports this yet; the status for it comes with the next lot.
            return failed(usage, status: .unavailable, detail: "not readable", now: now, backoff: false)
        case .failure(let status, let detail, let wait):
            var result = failed(usage, status: status, detail: detail, now: now, backoff: status == .unavailable)
            if let wait {
                let candidate = now.addingTimeInterval(wait)
                if candidate > (result.retryAfter ?? now) { result.retryAfter = candidate }
            }
            return result
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
}
