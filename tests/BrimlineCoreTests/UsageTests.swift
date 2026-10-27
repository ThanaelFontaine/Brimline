import Foundation
import Testing
@testable import BrimlineCore

@Suite("Credentials, usage answers and the reading service")
struct UsageTests {
    @Test("Only the access token and its expiry are decoded from the Keychain value")
    func credentialDecode() throws {
        let value = #"{"claudeAiOauth":{"accessToken":"fake-access","refreshToken":"fake-refresh","expiresAt":1761360000000,"scopes":["user:inference"],"subscriptionType":"max"},"other":1}"#
        let credential = try #require(ClaudeCredential.decode(Data(value.utf8)))
        #expect(credential.accessToken == "fake-access")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_761_360_000))
        #expect(!String(describing: Mirror(reflecting: credential).children.map(\.label)).contains("refresh"))
        #expect(ClaudeCredential.decode(Data(#"{"claudeAiOauth":{}}"#.utf8)) == nil)
        #expect(ClaudeCredential.decode(Data("not json".utf8)) == nil)
    }

    @Test("The request carries the documented headers and a 15 second timeout")
    func request() throws {
        let r = ClaudeUsageAPI.request(accessToken: "fake")
        #expect(r.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer fake")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        let agent = try #require(r.value(forHTTPHeaderField: "User-Agent"))
        #expect(agent.hasPrefix("Brimline/"))
        #expect(agent.hasSuffix("(+https://github.com/ThanaelFontaine/Brimline)"))
        #expect(!agent.lowercased().contains("claude"))
        #expect(r.timeoutInterval == 15)
    }

    @Test("A Keychain tool that never ends is stopped at the timeout")
    func credentialTimeout() throws {
        let home = try TemporaryHome()
        try home.write("slow-security", "#!/bin/sh\nexec /bin/sleep 30\n")
        let tool = home.url.appendingPathComponent("slow-security").path
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool)
        let reader = SecurityToolCredentialReader(timeout: 0.5, toolPath: tool)
        let start = Date()
        #expect(throws: CredentialError.toolFailed(-2)) { try reader.readCredential(service: "Claude Code-credentials") }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test("Fixtures hold no address and no token")
    func fixturesAreClean() throws {
        for name in ["usage-team-seat", "usage-contact-np"] {
            let text = String(decoding: try fixture(name), as: UTF8.self)
            for forbidden in ["@", "accessToken", "refreshToken", "sk-ant", "Bearer", "email"] {
                #expect(!text.contains(forbidden), "\(name) contains \(forbidden)")
            }
        }
    }

    @Test("Team seat: session and Fable week, no weekly limit across all models")
    func teamSeat() throws {
        let limits = try UsageParser.parse(try fixture("usage-team-seat"))
        #expect(limits == [
            UsageLimit(kind: .session, percent: 48, resetsAt: date("2026-10-25T03:00:00Z")),
            UsageLimit(kind: .weeklyModel, model: "Fable", percent: 0, resetsAt: date("2026-10-27T02:00:00Z")),
        ])
        let usage = AccountUsage(account: account("team@example.org"), status: .ok, limits: limits, fetchedAt: Date())
        #expect(usage.hasNoGlobalWeeklyLimit)
    }

    @Test("Account with a weekly limit: session, week and Fable week")
    func weeklyAccount() throws {
        let limits = try UsageParser.parse(try fixture("usage-contact-np"))
        #expect(limits.map(\.kind) == [.session, .weekly, .weeklyModel])
        #expect(limits.map(\.percent) == [2, 49, 0])
        #expect(limits[1].resetsAt == date("2026-10-27T12:00:00Z"))
        #expect(limits[2].model == "Fable")
    }

    @Test("Without the limits list, five_hour and seven_day are used")
    func fallback() throws {
        let body = #"{"five_hour":{"utilization":12.5,"resets_at":"2026-10-25T03:00:00+00:00"},"seven_day":{"utilization":40,"resets_at":"2026-10-27T12:00:00+00:00"}}"#
        let limits = try UsageParser.parse(Data(body.utf8))
        #expect(limits.map(\.kind) == [.session, .weekly])
        #expect(limits[0].percent == 12.5)
        #expect(throws: UsageParser.ParseError.noKnownLimit) { try UsageParser.parse(Data(#"{"spend":{}}"#.utf8)) }
        // A boolean is not a percentage.
        #expect(throws: UsageParser.ParseError.noKnownLimit) {
            try UsageParser.parse(Data(#"{"limits":[{"kind":"session","percent":true}]}"#.utf8))
        }
        #expect(throws: UsageParser.ParseError.notJSON) { try UsageParser.parse(Data("<html>".utf8)) }
    }

    @Test("Reset times are rounded to the nearest second: 02:59:59.98 is 03:00")
    func roundedReset() throws {
        let body = #"{"limits":[{"kind":"session","percent":5,"resets_at":"2026-10-25T02:59:59.982+00:00"}]}"#
        let limits = try UsageParser.parse(Data(body.utf8))
        #expect(limits.first?.resetsAt == date("2026-10-25T03:00:00Z"))
    }

    @Test("Absent values are null in the agents' JSON, never missing")
    func nullsInAgentJSON() throws {
        let usage = AccountUsage(account: account("a@example.com"), status: .ok,
                                 limits: [UsageLimit(kind: .session, percent: 0, resetsAt: nil)], fetchedAt: Date())
        let json = AgentUsageReport(snapshot: UsageSnapshot(generatedAt: Date(), accounts: [usage]),
                                    settings: BrimlineSettings(), source: "cache", now: Date()).jsonString()
        #expect(json.contains(#""resets_at" : null"#))
        #expect(json.contains(#""organization" : null"#))
    }

    @Test("A window whose reset time has passed counts as 0 %")
    func effectivePercent() {
        let l = UsageLimit(kind: .session, percent: 80, resetsAt: date("2026-10-25T03:00:00Z"))
        #expect(l.effectivePercent(at: date("2026-10-25T02:00:00Z")) == 80)
        #expect(l.effectivePercent(at: date("2026-10-25T03:00:01Z")) == 0)
    }

    @Test("Reads each account: OK, refused, expired, missing, unavailable")
    func service() async throws {
        let now = date("2026-10-25T01:00:00Z")
        let later = now.addingTimeInterval(3600)
        let a = account("a@example.com", dir: "/opt/a")
        let b = account("b@example.com", dir: "/opt/b")
        let c = account("c@example.com", dir: "/opt/c")
        let d = account("d@example.com", dir: "/opt/d")
        let e = account("e@example.com", dir: "/opt/e")
        let credentials = FakeCredentials([
            a.keychainService: .success(ClaudeCredential(accessToken: "tok-a", expiresAt: later)),
            b.keychainService: .success(ClaudeCredential(accessToken: "tok-b", expiresAt: later)),
            c.keychainService: .success(ClaudeCredential(accessToken: "tok-c", expiresAt: now.addingTimeInterval(-1))),
            e.keychainService: .success(ClaudeCredential(accessToken: "tok-e", expiresAt: nil)),
        ])
        let http = FakeHTTP([
            "tok-a": (200, try fixture("usage-contact-np"), [:]),
            "tok-b": (401, Data(), [:]),
            "tok-e": (503, Data(), [:]),
        ])
        let service = UsageService(credentials: credentials, http: http)

        // Previous numbers for the expired and the unavailable accounts.
        let oldLimits = [UsageLimit(kind: .session, percent: 30, resetsAt: later)]
        let fetched = now.addingTimeInterval(-600)
        let previous = UsageSnapshot(generatedAt: fetched, accounts: [
            AccountUsage(account: c, status: .ok, limits: oldLimits, fetchedAt: fetched),
            AccountUsage(account: e, status: .ok, limits: oldLimits, fetchedAt: fetched),
        ])

        let snapshot = await service.refresh(accounts: [a, b, c, d, e], previous: previous, now: now)
        #expect(snapshot.accounts.map(\.status) == [.ok, .reconnect, .expired, .signedOut, .unavailable])
        #expect(snapshot.accounts[0].limits.count == 3)
        #expect(snapshot.accounts[0].fetchedAt == now)
        // Expired: last known values kept with their date, and no request sent.
        #expect(snapshot.accounts[2].limits == oldLimits)
        #expect(snapshot.accounts[2].fetchedAt == fetched)
        #expect(!http.requests.contains { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok-c" })
        // Unavailable: values kept, growing delay set.
        #expect(snapshot.accounts[4].limits == oldLimits)
        #expect(snapshot.accounts[4].failureCount == 1)
        #expect(snapshot.accounts[4].retryAfter == now.addingTimeInterval(120))
        #expect(snapshot.accounts[4].detail == "HTTP 503")
    }

    @Test("After a failure, no new request before the delay, unless forced; the delay grows")
    func backoff() async throws {
        let now = date("2026-10-25T01:00:00Z")
        let a = account("a@example.com")
        let credentials = FakeCredentials([a.keychainService: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))])
        let http = FakeHTTP(["tok": (429, Data(), ["Retry-After": "600"])])
        let service = UsageService(credentials: credentials, http: http)

        let first = await service.refresh(account: a, previous: nil, now: now)
        #expect(first.status == .unavailable)
        #expect(first.retryAfter == now.addingTimeInterval(600)) // Retry-After wins over 2 min
        let skipped = await service.refresh(account: a, previous: first, now: now.addingTimeInterval(60))
        #expect(http.requests.count == 1)
        #expect(skipped.failureCount == 1)
        let forced = await service.refresh(account: a, previous: first, now: now.addingTimeInterval(60), force: true)
        #expect(http.requests.count == 2)
        #expect(forced.failureCount == 2)

        #expect(UsageService.retryDelay(afterFailures: 1) == 120)
        #expect(UsageService.retryDelay(afterFailures: 2) == 240)
        #expect(UsageService.retryDelay(afterFailures: 5) == 1920)
        #expect(UsageService.retryDelay(afterFailures: 9) == 3600)
    }

    @Test("A network failure or an unknown answer makes the account unavailable")
    func unknownAnswer() async throws {
        let a = account("a@example.com", dir: "/opt/a")
        let b = account("b@example.com", dir: "/opt/b")
        let credentials = FakeCredentials([
            a.keychainService: .success(ClaudeCredential(accessToken: "tok-a", expiresAt: nil)),
            b.keychainService: .success(ClaudeCredential(accessToken: "tok-b", expiresAt: nil)),
        ])
        let http = FakeHTTP(["tok-a": (200, Data(#"{"new_shape":true}"#.utf8), [:])])
        let snapshot = await UsageService(credentials: credentials, http: http).refresh(accounts: [a, b], previous: nil)
        #expect(snapshot.accounts.map(\.status) == [.unavailable, .unavailable])
        #expect(snapshot.accounts.map(\.detail) == ["unknown answer", "network"])
    }
}
