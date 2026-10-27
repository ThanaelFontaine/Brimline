import Foundation
import Testing
@testable import BrimlineCore

/// What the service does with each answer of a reader, and what the Claude reader reports for the
/// edge cases (QA of lot P0a: Claude must behave exactly as before the protocol).
@Suite("Reader answers and the reading service")
struct ReaderServiceTests {
    private let now = date("2026-10-27T01:00:00Z")

    private func claudeService(_ a: Account, credential: Result<ClaudeCredential, CredentialError>,
                               http: FakeHTTP = FakeHTTP([:])) -> UsageService {
        UsageService(credentials: FakeCredentials([a.keychainService: credential]), http: http)
    }

    @Test("A Keychain tool that fails is unavailable and backs off; an unreadable item is signed out with no delay")
    func keychainFailures() async {
        let a = account("a@example.com", dir: "/opt/a")
        let failed = await claudeService(a, credential: .failure(.toolFailed(44))).refresh(account: a, previous: nil, now: now)
        #expect(failed.status == .unavailable)
        #expect(failed.detail == "security exited with 44")
        #expect(failed.failureCount == 1)
        #expect(failed.retryAfter == now.addingTimeInterval(120))

        let unreadable = await claudeService(a, credential: .failure(.unreadable)).refresh(account: a, previous: nil, now: now)
        #expect(unreadable.status == .signedOut)
        #expect(unreadable.detail == "unreadable Keychain item")
        #expect(unreadable.failureCount == 0)
        #expect(unreadable.retryAfter == nil)
    }

    @Test("Retry-After: a longer wait wins, a shorter one never shortens the backoff, junk is ignored")
    func retryAfterEdges() async {
        let a = account("a@example.com")
        let cred = Result<ClaudeCredential, CredentialError>.success(ClaudeCredential(accessToken: "tok", expiresAt: nil))
        let cases: [(String?, TimeInterval)] = [
            ("600", 600), ("30", 120), ("0", 120), ("-5", 120), ("soon", 120), (nil, 120), (" 300 ", 300), ("99999", 3600),
        ]
        for (header, expected) in cases {
            let http = FakeHTTP(["tok": (429, Data(), header.map { ["Retry-After": $0] } ?? [:])])
            let usage = await claudeService(a, credential: cred, http: http).refresh(account: a, previous: nil, now: now)
            #expect(usage.status == .unavailable, "header \(header ?? "none")")
            #expect(usage.failureCount == 1, "header \(header ?? "none")")
            #expect(usage.retryAfter == now.addingTimeInterval(expected), "header \(header ?? "none")")
        }
    }

    @Test("A 429 with a Retry-After is the only status that reads the header")
    func headerOnlyOn429() async {
        let a = account("a@example.com")
        let cred = Result<ClaudeCredential, CredentialError>.success(ClaudeCredential(accessToken: "tok", expiresAt: nil))
        let http = FakeHTTP(["tok": (500, Data(), ["Retry-After": "900"])])
        let usage = await claudeService(a, credential: cred, http: http).refresh(account: a, previous: nil, now: now)
        #expect(usage.detail == "HTTP 500")
        #expect(usage.retryAfter == now.addingTimeInterval(120))
    }

    @Test("A success clears the failures, the delay and the detail; a refusal resets the delay but keeps the numbers")
    func recoveryAndRefusal() async throws {
        let a = account("a@example.com")
        let cred = Result<ClaudeCredential, CredentialError>.success(ClaudeCredential(accessToken: "tok", expiresAt: nil))
        let old = [UsageLimit(kind: .session, percent: 30, resetsAt: now.addingTimeInterval(3600))]
        let failing = AccountUsage(account: a, status: .unavailable, limits: old, fetchedAt: now.addingTimeInterval(-900),
                                   failureCount: 4, retryAfter: now.addingTimeInterval(-1), detail: "HTTP 503")

        let ok = FakeHTTP(["tok": (200, try fixture("usage-contact-np"), [:])])
        let healed = await claudeService(a, credential: cred, http: ok).refresh(account: a, previous: failing, now: now)
        #expect(healed.status == .ok)
        #expect(healed.failureCount == 0)
        #expect(healed.retryAfter == nil)
        #expect(healed.detail == nil)
        #expect(healed.fetchedAt == now)

        let refused = FakeHTTP(["tok": (401, Data(), [:])])
        let after = await claudeService(a, credential: cred, http: refused).refresh(account: a, previous: failing, now: now)
        #expect(after.status == .reconnect)
        #expect(after.failureCount == 0)
        #expect(after.retryAfter == nil)
        #expect(after.limits == old)
        #expect(after.fetchedAt == failing.fetchedAt)
    }

    @Test("The request goes to the exact URL, once per account, with the token of that account")
    func oneRequestPerAccount() async throws {
        let a = account("a@example.com", dir: "/opt/a")
        let b = account("b@example.com", dir: "/opt/b")
        let credentials = FakeCredentials([
            a.keychainService: .success(ClaudeCredential(accessToken: "tok-a", expiresAt: nil)),
            b.keychainService: .success(ClaudeCredential(accessToken: "tok-b", expiresAt: nil)),
        ])
        let http = FakeHTTP(["tok-a": (200, try fixture("usage-contact-np"), [:]), "tok-b": (200, try fixture("usage-contact-np"), [:])])
        _ = await UsageService(credentials: credentials, http: http).refresh(accounts: [a, b], previous: nil, now: now)
        #expect(http.requests.count == 2)
        #expect(http.requests.allSatisfy { $0.url == URL(string: "https://api.anthropic.com/api/oauth/usage") })
        #expect(Set(http.requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }) == ["Bearer tok-a", "Bearer tok-b"])
        #expect(Set(credentials.reads) == [a.keychainService, b.keychainService])
    }

    @Test("Results keep the order of the accounts and each account goes to the reader of its provider")
    func routing() async {
        struct Stub: ProviderReader {
            var provider: Provider
            var answer: ProviderReading
            func discover(home: URL, settings: BrimlineSettings) -> [Account] { [] }
            func read(account: Account, now: Date) async -> ProviderReading { answer }
        }
        let claude = account("c@example.com", dir: "/opt/c")
        var other = account("o@example.com", dir: "/opt/o")
        other.provider = .grok
        let limits = [UsageLimit(kind: .session, percent: 12, resetsAt: now.addingTimeInterval(60))]
        let service = UsageService(readers: [
            Stub(provider: .claude, answer: .limits(limits, shape: "x")),
            Stub(provider: .grok, answer: .failure(status: .reconnect, detail: "stub", retryAfter: nil)),
        ])
        let snapshot = await service.refresh(accounts: [other, claude], previous: nil, now: now)
        #expect(snapshot.accounts.map(\.account.id) == [other.id, claude.id])
        #expect(snapshot.accounts.map(\.status) == [.reconnect, .ok])
        #expect(snapshot.accounts[1].limits == limits)
    }

    @Test("A reader's notReadable answer never retries sooner or later: no failure counted, no delay")
    func notReadableAnswer() async {
        struct Stub: ProviderReader {
            var provider: Provider { .claude }
            func discover(home: URL, settings: BrimlineSettings) -> [Account] { [] }
            func read(account: Account, now: Date) async -> ProviderReading { .notReadable(reason: .consumerPlan) }
        }
        let a = account("a@example.com")
        let usage = await UsageService(readers: [Stub()]).refresh(account: a, previous: nil, now: now)
        #expect(usage.failureCount == 0)
        #expect(usage.retryAfter == nil)
    }

    @Test("The reader of an expired credential never contacts the network, even with no expiry margin")
    func expiredNeverSent() async {
        let a = account("a@example.com")
        let http = FakeHTTP(["tok": (200, Data(), [:])])
        let reader = ClaudeReader(credentials: FakeCredentials([a.keychainService: .success(ClaudeCredential(accessToken: "tok", expiresAt: now))]), http: http)
        guard case .expired = await reader.read(account: a, now: now) else {
            Issue.record("expected expired")
            return
        }
        #expect(http.requests.isEmpty)
    }
}
