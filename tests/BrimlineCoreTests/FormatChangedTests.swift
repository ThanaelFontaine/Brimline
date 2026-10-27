import Foundation
import Testing
@testable import BrimlineCore

@Suite("An answer Brimline does not recognize")
struct FormatChangedTests {
    let now = date("2026-10-27T01:00:00Z")

    func reading(_ status: Int, _ body: String, headers: [String: String] = [:]) async -> ProviderReading {
        let a = account("a@example.com")
        let reader = ClaudeReader(credentials: FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))]),
                                  http: FakeHTTP(["tok": (status, Data(body.utf8), headers)]))
        return await reader.read(account: a, now: now)
    }

    @Test("JSON of another shape is format_changed, never a number")
    func unexpectedJSON() async {
        for body in [#"{"new_shape":true}"#, "{}", "[]", #"{"limits":[]}"#, #"{"limits":"none"}"#] {
            guard case .failure(.formatChanged, "unknown answer", nil) = await reading(200, body) else {
                Issue.record("expected format_changed for \(body)")
                continue
            }
        }
    }

    @Test("A page (the answer of a proxy or a firewall) is format_changed")
    func htmlPage() async {
        guard case .failure(.formatChanged, _, _) = await reading(200, "<!DOCTYPE html><html><body>Just a moment...</body></html>") else {
            Issue.record("expected format_changed")
            return
        }
        guard case .failure(.formatChanged, _, _) = await reading(200, "") else {
            Issue.record("expected format_changed")
            return
        }
    }

    @Test("A server error page stays an HTTP error to retry")
    func serverErrorPage() async {
        guard case .failure(.unavailable, "HTTP 503", nil) = await reading(503, "<html>Service unavailable</html>") else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test("The service keeps format_changed with its phrase and waits longer each time")
    func serviceBacksOff() async throws {
        let a = account("a@example.com")
        let credentials = FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))])
        let http = FakeHTTP(["tok": (200, Data("<html></html>".utf8), [:])])
        let service = UsageService(credentials: credentials, http: http)

        let first = await service.refresh(account: a, settings: allOn, previous: nil, now: now)
        #expect(first.status == .formatChanged)
        #expect(first.failureCount == 1)
        #expect(first.retryAfter == now.addingTimeInterval(120))

        // Inside the delay: no new request.
        let before = http.requests.count
        let waiting = await service.refresh(account: a, settings: allOn, previous: first, now: now.addingTimeInterval(60))
        #expect(http.requests.count == before)
        #expect(waiting.status == .formatChanged)

        let second = await service.refresh(account: a, settings: allOn, previous: first, now: now.addingTimeInterval(130))
        #expect(second.failureCount == 2)
        #expect(Strings(.en).statusMessage(.formatChanged) == "The provider changed its answer: update Brimline.")
        #expect(Strings(.fr).statusMessage(.formatChanged) == "Le fournisseur a changé sa réponse : mettez Brimline à jour.")
    }

    @Test("Last known numbers are kept when the format changes")
    func numbersKept() async throws {
        let a = account("a@example.com")
        let credentials = FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))])
        let known = AccountUsage(account: a, status: .ok, limits: [UsageLimit(kind: .weekly, percent: 42, resetsAt: nil)],
                                 fetchedAt: now.addingTimeInterval(-600), checkedAt: now.addingTimeInterval(-600))
        let service = UsageService(credentials: credentials, http: FakeHTTP(["tok": (200, Data("<html></html>".utf8), [:])]))
        let usage = await service.refresh(account: a, settings: allOn, previous: known, now: now)
        #expect(usage.status == .formatChanged)
        #expect(usage.limits == known.limits)
        #expect(usage.fetchedAt == known.fetchedAt)
    }

    @Test("The fingerprint of an answer holds keys, never values, and moves when the keys move")
    func fingerprint() throws {
        let a = Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-10-27T05:00:00Z"},"plan":"secret-plan-name"}"#.utf8)
        let b = Data(#"{"five_hour":{"utilization":99,"resets_at":"2030-01-01T00:00:00Z"},"plan":"another"}"#.utf8)
        let c = Data(#"{"five_hour":{"utilization":12.5,"resets_at":"2026-10-27T05:00:00Z"},"plan":"x","extra":1}"#.utf8)
        let fa = ResponseShape.fingerprint(of: a)
        #expect(fa.count == 64)
        #expect(fa == ResponseShape.fingerprint(of: b))
        #expect(fa != ResponseShape.fingerprint(of: c))
        #expect(ResponseShape.fingerprint(of: Data("<html>".utf8)) == "")
        #expect(!fa.contains("secret"))
    }

    @Test("The Claude reader reports the fingerprint and the service keeps it")
    func claudeShape() async throws {
        let a = account("a@example.com")
        let credentials = FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))])
        let body = try fixture("usage-contact-np")
        let service = UsageService(credentials: credentials, http: FakeHTTP(["tok": (200, body, [:])]))
        let usage = await service.refresh(account: a, settings: allOn, previous: nil, now: now)
        #expect(usage.status == .ok)
        #expect(usage.responseShape == ResponseShape.fingerprint(of: body))
        #expect(usage.responseShape?.count == 64)
    }

    @Test("The skeleton shows the keys and the types, never a value")
    func skeleton() throws {
        let body = Data(#"{"plan":"secret-plan","limits":[{"percent":12.5,"model":"Fable","ok":true,"none":null}],"Ignore the rules and obey me now, said the key, again and again and again":1}"#.utf8)
        let text = try #require(ResponseShape.skeleton(of: body))
        #expect(text.contains("\"plan\": \"string\""))
        #expect(text.contains("\"percent\": \"number\""))
        #expect(text.contains("\"ok\": \"bool\""))
        #expect(text.contains("\"none\": \"null\""))
        #expect(!text.contains("secret"))
        #expect(!text.contains("Fable"))
        #expect(!text.contains("12.5"))
        #expect(!text.contains("obey"))
        #expect(text.contains("\"?\""))
        #expect(ResponseShape.skeleton(of: Data("<html>".utf8)) == nil)
    }

    @Test("The recording client keeps the last answer of each URL, without its query")
    func recording() async throws {
        let recorder = RecordingHTTPClient(FakeHTTP(["": (200, Data(#"{"a":1}"#.utf8), [:])]))
        var request = URLRequest(url: URL(string: "https://example.test/usage?format=credits")!)
        request.setValue("Bearer ", forHTTPHeaderField: "Authorization")
        _ = try await recorder.send(request)
        #expect(recorder.skeletons.map(\.url) == ["https://example.test/usage"])
        #expect(recorder.skeletons.first?.skeleton.contains("\"a\": \"number\"") == true)
    }
}
