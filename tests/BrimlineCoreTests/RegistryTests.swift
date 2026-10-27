import Foundation
import Testing
@testable import BrimlineCore

@Suite("Provider registry")
struct RegistryTests {
    @Test("Claude and Gemini (a sentence only) are the providers with a reader")
    func readers() {
        #expect(Providers.all.map(\.provider) == [.claude, .gemini])
        #expect(Providers.make(credentials: FakeCredentials([:]), http: FakeHTTP([:])).map(\.provider) == [.claude, .gemini])
    }

    @Test("Discovery through the registry gives the accounts of the Claude reader")
    func discoveryThroughRegistry() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "you@example.com"))
        try home.write("elsewhere/custom/.claude.json", claudeJSON(email: "custom@example.com"))
        var settings = BrimlineSettings()
        settings.extraFolders = [home.path("elsewhere/custom")]

        let found = Providers.discover(home: home.url, settings: settings)
        let direct = AccountDiscovery(home: home.url, extraFolders: settings.extraFolders).discover()
        #expect(found == direct)
        #expect(found.map(\.email) == ["you@example.com", "custom@example.com"])
        #expect(found.allSatisfy { $0.provider == .claude })
    }

    @Test("The Claude reader reports each outcome of a reading")
    func claudeReadings() async throws {
        let now = date("2026-10-27T01:00:00Z")
        let later = now.addingTimeInterval(3600)
        let ok = account("ok@example.com", dir: "/opt/ok")
        let expired = account("expired@example.com", dir: "/opt/expired")
        let refused = account("refused@example.com", dir: "/opt/refused")
        let limited = account("limited@example.com", dir: "/opt/limited")
        let missing = account("missing@example.com", dir: "/opt/missing")
        let credentials = FakeCredentials([
            ok.keychainService!: .success(ClaudeCredential(accessToken: "tok-ok", expiresAt: later)),
            expired.keychainService!: .success(ClaudeCredential(accessToken: "tok-expired", expiresAt: now)),
            refused.keychainService!: .success(ClaudeCredential(accessToken: "tok-refused", expiresAt: later)),
            limited.keychainService!: .success(ClaudeCredential(accessToken: "tok-limited", expiresAt: later)),
        ])
        let http = FakeHTTP([
            "tok-ok": (200, try fixture("usage-contact-np"), [:]),
            "tok-refused": (401, Data(), [:]),
            "tok-limited": (429, Data(), ["Retry-After": "99999"]),
        ])
        let reader = ClaudeReader(credentials: credentials, http: http)

        guard case .limits(let limits, _) = await reader.read(account: ok, now: now) else {
            Issue.record("expected limits")
            return
        }
        #expect(limits.count == 3)
        guard case .expired = await reader.read(account: expired, now: now) else {
            Issue.record("expected expired")
            return
        }
        guard case .failure(.reconnect, "HTTP 401", nil) = await reader.read(account: refused, now: now) else {
            Issue.record("expected reconnect")
            return
        }
        // The provider's wait is capped at one hour.
        guard case .failure(.unavailable, "HTTP 429", 3600?) = await reader.read(account: limited, now: now) else {
            Issue.record("expected a capped wait")
            return
        }
        guard case .failure(.signedOut, "no Keychain item", nil) = await reader.read(account: missing, now: now) else {
            Issue.record("expected signed out")
            return
        }
        #expect(!http.requests.contains { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok-expired" })
    }

    @Test("An account whose provider has no reader is left alone, with no retry delay")
    func noReader() async {
        let a = account("a@example.com")
        let usage = await UsageService(readers: []).refresh(account: a, settings: allOn, previous: nil, now: date("2026-10-27T01:00:00Z"))
        #expect(usage.status == .unavailable)
        #expect(usage.retryAfter == nil)
        #expect(usage.failureCount == 0)
    }
}
