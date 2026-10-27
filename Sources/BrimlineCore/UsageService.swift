import Foundation

/// Reads the usage of every account: each account goes to the reader of its provider.
///
/// The same code serves the app (every few minutes) and `brimline status --live`.
/// The readers only report what they saw. The rules live here: nothing is read for a provider
/// that is off or an account marked "Do not read" (before any file, `security` or request), the
/// last known numbers are kept on a failure, and an `unavailable` or `format_changed` account
/// waits longer before each new attempt.
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

    /// Statuses that wait longer before each new attempt.
    static func backsOff(_ status: AccountStatus) -> Bool { status == .unavailable || status == .formatChanged }

    /// Reads every account the settings allow. `previous` gives the last known numbers; `force`
    /// ignores the retry delay (never the consent).
    public func refresh(accounts: [Account], settings: BrimlineSettings, previous: UsageSnapshot?,
                        now: Date = Date(), force: Bool = false) async -> UsageSnapshot {
        var results: [AccountUsage] = []
        await withTaskGroup(of: (Int, AccountUsage).self) { group in
            for (index, account) in accounts.enumerated() {
                let old = previous?.usage(for: account.id)
                group.addTask {
                    (index, await self.refresh(account: account, settings: settings, previous: old, now: now,
                                               force: force))
                }
            }
            var collected: [(Int, AccountUsage)] = []
            for await item in group { collected.append(item) }
            results = collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return UsageSnapshot(generatedAt: now, accounts: results)
    }

    public func refresh(account: Account, settings: BrimlineSettings, previous: AccountUsage?,
                        now: Date = Date(), force: Bool = false) async -> AccountUsage {
        var usage = previous ?? AccountUsage(account: account)
        usage.account = account // the identity may have changed (new address, new label)

        // Consent first, before any reader runs: a provider that is off and an account marked
        // "Do not read" are left exactly as they were (last numbers kept, `checkedAt` untouched).
        guard settings.mayRead(account) else { return usage }

        if !force, let retryAfter = usage.retryAfter, retryAfter > now, Self.backsOff(usage.status) {
            return usage
        }
        let reader = readers.first(where: { $0.provider == account.provider })
        // A reader that launches a program is not asked twice in a short time, forced or not: the last
        // attempt kept in the cache is what counts (the app's own refreshes; `status --live` does not write the cache).
        if let reader, reader.minimumReadInterval > 0, let last = usage.checkedAt {
            let age = now.timeIntervalSince(last)
            if age >= 0, age < reader.minimumReadInterval { return usage }
        }
        usage.checkedAt = now

        guard let reader else {
            return failed(usage, status: .unavailable, detail: "no reader for \(account.provider.rawValue)",
                          now: now, backoff: false)
        }

        switch await reader.read(account: account, now: now) {
        case .limits(let limits, let shape):
            return read(usage, limits: limits, shape: shape, note: nil, now: now)
        case .annotated(let limits, let shape, let note):
            return read(usage, limits: limits, shape: shape, note: note, now: now)
        case .expired:
            return failed(usage, status: .expired, detail: nil, now: now, backoff: false)
        case .notReadable(let reason):
            var result = failed(usage, status: .notReadable, detail: nil, now: now, backoff: false)
            result.reason = reason
            return result
        case .failure(let status, let detail, let wait):
            var result = failed(usage, status: status, detail: detail, now: now, backoff: Self.backsOff(status))
            if let wait {
                let candidate = now.addingTimeInterval(wait)
                if candidate > (result.retryAfter ?? now) { result.retryAfter = candidate }
            }
            return result
        }
    }

    private func read(_ usage: AccountUsage, limits: [UsageLimit], shape: String, note: AccountNote?,
                      now: Date) -> AccountUsage {
        var u = usage
        u.limits = ProviderText.sanitize(limits, now: now)
        u.status = .ok
        u.fetchedAt = now
        u.failureCount = 0
        u.retryAfter = nil
        u.detail = nil
        u.reason = nil
        u.responseShape = shape.isEmpty ? nil : shape
        u.note = note
        return u
    }

    private func failed(_ usage: AccountUsage, status: AccountStatus, detail: String?, now: Date,
                        backoff: Bool) -> AccountUsage {
        var u = usage
        u.status = status
        u.detail = detail
        u.reason = nil
        u.note = nil
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
