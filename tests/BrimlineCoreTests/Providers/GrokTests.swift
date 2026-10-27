import Foundation
import Testing
@testable import BrimlineCore

/// Grok, through the Grok CLI. Every fixture is test data built from the public source of the Grok CLI
/// (xai-org/grok-build at commit 2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8: the `GrokAuth` and `AuthStore`
/// of `xai-grok-login`, its `auth_scope`, and the `x.ai/billing` call and the `BillingConfig` of
/// `xai-grok-shell/src/extensions/billing.rs`, with its own tests); the commit is also written in each
/// fixture. The values are invented. The normal fixture is rewritten from the skeleton of a real answer
/// (`brimline status --live --shape --provider grok`) at the real try, before the merge.
@Suite("Grok through the Grok CLI")
struct GrokTests {
    let now = date("2026-10-27T10:00:00Z")
    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("grok")
        return settings
    }

    static let seedKey = "xai-SEED-GROK-SESSION-KEY-7d2e91"
    static let seedRefresh = "rt.SEED-GROK-REFRESH-TOKEN-5b8c13"
    static let seedUser = "9f4e2a1c-6b3d-4f58-a0c7-1d2e3f405162"
    static let seedEmail = "someone@example.com"
    static let scope = "https://auth.x.ai::b7a1c2d3-0000-4000-8000-000000000001"

    /// A home with `~/.grok/auth.json` from a fixture.
    func signedIn(_ authFixture: String = "grok-auth-oauth") throws -> TemporaryHome {
        let home = try TemporaryHome()
        try home.write(".grok/auth.json", String(decoding: try fixture(authFixture), as: UTF8.self))
        return home
    }

    /// An `auth.json` with one sign-in of an xAI account.
    func authText(key: String = GrokTests.seedKey, userId: String? = GrokTests.seedUser,
                  expires: String? = "2099-01-01T00:00:00Z", created: String? = nil, scope: String = GrokTests.scope) -> String {
        var fields = [#""key":"\#(key)""#, #""auth_mode":"oidc""#, #""refresh_token":"\#(Self.seedRefresh)""#, #""email":"\#(Self.seedEmail)""#]
        if let userId { fields.append(#""user_id":"\#(userId)""#) }
        if let expires { fields.append(#""expires_at":"\#(expires)""#) }
        if let created { fields.append(#""create_time":"\#(created)""#) }
        return #"{"\#(scope)":{\#(fields.joined(separator: ","))}}"#
    }

    func account(in home: TemporaryHome) -> Account {
        Account(provider: .grok, source: home.path(".grok/auth.json"), email: nil, organization: nil,
                seatTier: nil, keychainService: nil)
    }

    func answering(_ body: Data, token: String = GrokTests.seedKey, status: Int = 200, headers: [String: String] = [:]) -> FakeHTTP {
        FakeHTTP([token: (status, body, headers)])
    }

    func read(_ http: FakeHTTP, in home: TemporaryHome) async -> ProviderReading {
        await GrokReader(http: http).read(account: account(in: home), now: now)
    }

    // MARK: Registry and discovery

    @Test("Grok is in the registry, after Gemini, and calls one URL")
    func registry() {
        #expect(Providers.all.map(\.provider).contains(.grok))
        #expect(Providers.all.map(\.provider).firstIndex(of: .gemini)! < Providers.all.map(\.provider).firstIndex(of: .grok)!)
        #expect(GrokReader().allowedURLs == [URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!])
        #expect(Providers.isSupported(.grok))
    }

    @Test("Grok is off by default: the folder is not even looked for")
    func offByDefault() throws {
        let home = try TemporaryHome()
        try home.mkdir(".grok")
        #expect(!BrimlineSettings().isEnabled(.grok))
        #expect(Providers.discover(home: home.url, settings: BrimlineSettings()).isEmpty)
        #expect(Providers.discover(home: home.url, settings: on).map(\.provider) == [.grok])
    }

    @Test("One card when ~/.grok is a folder, none otherwise, and the card holds no identity")
    func discovery() throws {
        let home = try TemporaryHome()
        #expect(GrokReader().discover(home: home.url, settings: on).isEmpty)

        try home.write(".grok", "a file, not a folder")
        #expect(GrokReader().discover(home: home.url, settings: on).isEmpty)
        try FileManager.default.removeItem(at: home.url.appendingPathComponent(".grok"))

        try home.mkdir(".grok")
        let accounts = GrokReader().discover(home: home.url, settings: on)
        let card = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(card.provider == .grok)
        #expect(card.source == home.path(".grok") + "/auth.json")
        #expect(card.id == "grok:\(home.path(".grok"))/auth.json")
        #expect(card.email == nil && card.organization == nil && card.seatTier == nil && card.keychainService == nil)
        #expect(!card.addedByHand)
    }

    @Test("The place is exact: ~/.grok only, never GROK_HOME, GROK_AUTH_PATH nor a scan")
    func exactPlace() throws {
        let home = try TemporaryHome()
        try home.mkdir(".grok-work")
        try home.mkdir(".config/grok")
        try home.mkdir("elsewhere/grok-home")
        setenv("GROK_HOME", home.path("elsewhere/grok-home"), 1)
        setenv("GROK_AUTH_PATH", home.path("elsewhere/grok-home/auth.json"), 1)
        defer { unsetenv("GROK_HOME"); unsetenv("GROK_AUTH_PATH") }
        var settings = on
        settings.extraFolders = [home.path(".grok-work")]
        settings.extraCodexFolders = [home.path(".grok-work")]
        #expect(GrokReader().discover(home: home.url, settings: settings).isEmpty)
    }

    @Test("Discovery opens nothing inside ~/.grok: an unreadable sign-in stays untouched")
    func nothingOpened() throws {
        let home = try signedIn()
        let file = home.url.appendingPathComponent(".grok/auth.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        let before = try FileManager.default.attributesOfItem(atPath: file.path)
        let accounts = GrokReader().discover(home: home.url, settings: on)
        #expect(accounts.count == 1)
        let after = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((after[.modificationDate] as? Date) == (before[.modificationDate] as? Date))
        #expect(!String(describing: accounts).contains(Self.seedKey))
    }

    // MARK: Reading

    @Test("A weekly answer: one period limit named by its length, the shared pool said, the request exact")
    func weekly() async throws {
        let home = try signedIn()
        let http = answering(try fixture("grok-billing-weekly"))
        guard case .annotated(let limits, let shape, .sharedPool) = await read(http, in: home) else {
            Issue.record("expected limits with the shared pool note")
            return
        }
        #expect(!shape.isEmpty)
        #expect(limits == [UsageLimit(kind: .period, percent: 42.5, resetsAt: date("2026-11-02T00:00:00Z"), windowSeconds: 604_800)])
        #expect(Strings(.en).limitName(limits[0]) == "Week" && Strings(.fr).limitName(limits[0]) == "Semaine")

        // The request: this URL, this method, these headers, nothing else.
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url?.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.allHTTPHeaderFields == [
            "Authorization": "Bearer \(Self.seedKey)",
            "X-XAI-Token-Auth": "xai-grok-cli",
            "x-userid": Self.seedUser,
            "Accept": "application/json",
            "User-Agent": GrokUsageAPI.userAgent,
        ])
        #expect(GrokUsageAPI.userAgent.hasPrefix("Brimline/"))
        #expect(!GrokUsageAPI.userAgent.localizedCaseInsensitiveContains("grok"))
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("A monthly answer with no shared pool is plain limits, and a month is named by its length")
    func monthly() async throws {
        let home = try signedIn()
        guard case .limits(let limits, _) = await read(answering(try fixture("grok-billing-monthly")), in: home) else {
            Issue.record("expected limits")
            return
        }
        #expect(limits == [UsageLimit(kind: .period, percent: 8, resetsAt: date("2026-11-01T00:00:00Z"), windowSeconds: 2_678_400)])
        #expect(Strings(.en).limitName(limits[0]) == "Month" && Strings(.fr).limitName(limits[0]) == "Mois")
        // Another length is a period.
        let odd = UsageLimit(kind: .period, percent: 1, resetsAt: nil, windowSeconds: 86_400 * 10)
        #expect(Strings(.en).limitName(odd) == "Period")
        #expect(Strings(.en).limitName(UsageLimit(kind: .period, percent: 1, resetsAt: nil)) == "Period")
    }

    @Test("No percentage and no allowance (a free account): xAI gives no credit limit, said as seen, never a 0 %")
    func noCreditLimit() async throws {
        let home = try signedIn()
        guard case .annotated(let limits, let shape, .noCreditLimit) = await read(answering(try fixture("grok-billing-free")), in: home) else {
            Issue.record("expected the no credit limit note")
            return
        }
        #expect(limits.isEmpty && !shape.isEmpty)
        for body in [#"{"config":null}"#, #"{"config":{}}"#, #"{"config":{"creditUsagePercent":null}}"#,
                     #"{"config":{"creditUsagePercent":"41"}}"#, #"{"config":{"monthlyLimit":{},"used":{"val":10}}}"#] {
            guard case .annotated(let none, _, .noCreditLimit) = await read(answering(Data(body.utf8)), in: home) else {
                Issue.record("expected the no credit limit note for \(body)")
                return
            }
            #expect(none.isEmpty)
        }
    }

    @Test("An allowance with no use yet is a cap whose number is not there yet: the old sentence stays for it")
    func capWithoutUse() async throws {
        let home = try signedIn()
        for body in [#"{"config":{"monthlyLimit":{"val":2000}}}"#, #"{"config":{"monthlyLimit":{"val":2000},"used":null}}"#] {
            guard case .annotated(let none, _, .noFigureYet) = await read(answering(Data(body.utf8)), in: home) else {
                Issue.record("expected the no number yet note for \(body)")
                return
            }
            #expect(none.isEmpty)
        }
    }

    @Test("The older answer (monthly allowance and use in cents) is read when the percentage is not there")
    func legacy() async throws {
        let home = try signedIn()
        guard case .limits(let limits, _) = await read(answering(try fixture("grok-billing-legacy")), in: home) else {
            Issue.record("expected limits")
            return
        }
        #expect(limits == [UsageLimit(kind: .period, percent: 25, resetsAt: date("2026-11-01T00:00:00Z"), windowSeconds: 2_678_400)])
        // A zero use is `{}` in proto3 JSON: 0 % of a known allowance is a number. A zero allowance is none.
        let zero = try GrokUsageParser.parse(Data(#"{"config":{"monthlyLimit":{"val":2000},"used":{}}}"#.utf8))
        #expect(zero.limits.map(\.percent) == [0])
        let free = try GrokUsageParser.parse(Data(#"{"config":{"monthlyLimit":{},"used":{"val":10}}}"#.utf8))
        #expect(free.limits.isEmpty)
        // The new percentage wins over the old fields.
        let both = try GrokUsageParser.parse(Data(#"{"config":{"creditUsagePercent":70,"monthlyLimit":{"val":100},"used":{"val":10}}}"#.utf8))
        #expect(both.limits.map(\.percent) == [70])
    }

    @Test("The period length is end minus start, a week for a weekly period with no dates, nothing otherwise")
    func periodLength() throws {
        func limit(_ period: String) throws -> UsageLimit {
            try #require(GrokUsageParser.parse(Data(#"{"config":{"creditUsagePercent":5,"currentPeriod":\#(period)}}"#.utf8)).limits.first)
        }
        #expect(try limit(#"{"type":"USAGE_PERIOD_TYPE_WEEKLY"}"#) == UsageLimit(kind: .period, percent: 5, resetsAt: nil, windowSeconds: 604_800))
        #expect(try limit(#"{"type":"USAGE_PERIOD_TYPE_MONTHLY"}"#).windowSeconds == nil)
        #expect(try limit(#"{"start":"2026-10-27T00:00:00.123456789Z","end":"2026-10-28T00:00:00.123456789Z"}"#).windowSeconds == 86_400)
        // An end before its start gives no length (a week for a weekly period).
        #expect(try limit(#"{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-10-28T00:00:00Z","end":"2026-10-27T00:00:00Z"}"#).windowSeconds == 604_800)
        #expect(try limit(#"{"start":"yesterday","end":"tomorrow"}"#) == UsageLimit(kind: .period, percent: 5, resetsAt: nil, windowSeconds: nil))
        let none = try GrokUsageParser.parse(Data(#"{"config":{"creditUsagePercent":5}}"#.utf8))
        #expect(none.limits.count == 1 && none.limits[0].resetsAt == nil)
    }

    @Test("The shared pool is said only for a true boolean")
    func sharedPoolFlag() throws {
        func shared(_ value: String) throws -> Bool {
            try GrokUsageParser.parse(Data(#"{"config":{"creditUsagePercent":5,"isUnifiedBillingUser":\#(value)}}"#.utf8)).sharedPool
        }
        #expect(try shared("true"))
        for other in ["false", "1", #""true""#, "null", "[]"] { #expect(try !shared(other), "\(other)") }
    }

    // MARK: Answers that are not usable

    @Test("401 asks to sign in again; 429 waits as long as asked, one hour at most; any other code is unavailable")
    func statusCodes() async throws {
        let home = try signedIn()
        guard case .failure(.reconnect, "HTTP 401", nil) = await read(answering(Data(), status: 401), in: home) else {
            Issue.record("expected reconnect")
            return
        }
        guard case .failure(.unavailable, "HTTP 429", 3600?) = await read(answering(Data(), status: 429, headers: ["Retry-After": "99999"]), in: home) else {
            Issue.record("expected a capped wait")
            return
        }
        guard case .failure(.unavailable, "HTTP 429", 120?) = await read(answering(Data(), status: 429, headers: ["Retry-After": " 120 "]), in: home) else {
            Issue.record("expected the wait asked")
            return
        }
        guard case .failure(.unavailable, "HTTP 429", nil) = await read(answering(Data(), status: 429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]), in: home) else {
            Issue.record("expected no wait")
            return
        }
        for code in [403, 500, 503] {
            guard case .failure(.unavailable, let detail, nil) = await read(answering(Data("<html>".utf8), status: code), in: home) else {
                Issue.record("expected unavailable for \(code)")
                return
            }
            #expect(detail == "HTTP \(code)")
        }
        guard case .failure(.unavailable, "network", nil) = await read(FakeHTTP([:]), in: home) else {
            Issue.record("expected a network failure")
            return
        }
    }

    @Test("An answer Brimline does not know (cut short, a page, another JSON) is format_changed, never a number")
    func formatChanged() async throws {
        let home = try signedIn()
        let full = try fixture("grok-billing-weekly")
        let bodies: [Data] = [
            full.prefix(full.count / 2),
            Data("<!DOCTYPE html><html><title>Just a moment...</title></html>".utf8),
            Data(),
            Data("[1,2,3]".utf8),
            Data("{}".utf8),
            Data(#"{"error":"unauthenticated"}"#.utf8),
            Data(#"{"config":"nope"}"#.utf8),
            Data(#"{"config":[1]}"#.utf8),
            Data(#"{"usage":{"percent":40}}"#.utf8),
        ].map { Data($0) }
        for body in bodies {
            guard case .failure(.formatChanged, "unknown answer", nil) = await read(answering(body), in: home) else {
                Issue.record("expected format_changed for \(String(decoding: body.prefix(40), as: UTF8.self))")
                return
            }
        }
    }

    @Test("Hostile values are filtered when the service keeps them")
    func hostile() async throws {
        let home = try signedIn()
        let service = UsageService(readers: [GrokReader(http: answering(try fixture("grok-billing-hostile")))])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.status == .ok)
        // The percentage is bounded, the absurd reset time is dropped (the limit stays, with no date), the
        // texts of the answer (period type, tier) end up nowhere, a flag that is not a boolean is no flag.
        #expect(usage.limits.count == 1)
        #expect(usage.limits[0].percent == 100)
        #expect(usage.limits[0].resetsAt == nil)
        #expect(usage.note == nil)
        let text = String(describing: usage)
        #expect(!text.contains("Ignore") && !text.contains("rm -rf") && !text.contains("USAGE_PERIOD"))
    }

    // MARK: The sign-in file

    @Test("No auth.json, or none of an xAI account: not readable (no Grok CLI), and nothing is requested")
    func noSignIn() async throws {
        let home = try TemporaryHome()
        try home.mkdir(".grok")
        let http = FakeHTTP([:])
        guard case .notReadable(.noCLI) = await read(http, in: home) else {
            Issue.record("expected not readable")
            return
        }
        for text in ["{}", #"{"https://auth.x.ai::c":{"key":""}}"#, #"{"https://auth.x.ai.evil.example::c":{"key":"tok"}}"#,
                     #"{"https://auth.x.aix":{"key":"tok"}}"#, #"{"http://auth.x.ai::c":{"key":"tok"}}"#] {
            try home.write(".grok/auth.json", text)
            guard case .notReadable(.noCLI) = await read(http, in: home) else {
                Issue.record("expected not readable for \(text)")
                return
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test("An API key sign-in has no subscription limit: not readable, and the key is never kept nor sent")
    func apiKey() async throws {
        let home = try signedIn("grok-auth-apikey")
        let http = FakeHTTP([:])
        let service = UsageService(readers: [GrokReader(http: http)])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.status == .notReadable)
        #expect(usage.reason == .apiKey)
        #expect(usage.limits.isEmpty)
        #expect(usage.retryAfter == nil && usage.failureCount == 0)
        #expect(http.requests.isEmpty)
        #expect(!String(describing: usage).contains("SEED-GROK-API-KEY"))
    }

    @Test("Another issuer's sign-in is never read nor sent: an enterprise login is not an xAI account")
    func enterprise() async throws {
        let home = try signedIn("grok-auth-enterprise")
        let http = FakeHTTP(["SEED-ENTERPRISE-TOKEN-cc33dd44": (200, try fixture("grok-billing-weekly"), [:])])
        guard case .notReadable(.noCLI) = await read(http, in: home) else {
            Issue.record("expected not readable")
            return
        }
        #expect(http.requests.isEmpty)
        // An xAI account next to an API key and an enterprise login: the xAI account is the one used.
        let mixed = #"{"xai::api_key":{"key":"SEED-API"},"https://acme.okta.com::c":{"key":"SEED-OTHER"},"\#(Self.scope)":{"key":"\#(Self.seedKey)","user_id":"u-1","expires_at":"2099-01-01T00:00:00Z"}}"#
        try home.write(".grok/auth.json", mixed)
        let sent = answering(try fixture("grok-billing-monthly"))
        guard case .limits = await read(sent, in: home) else {
            Issue.record("expected a reading")
            return
        }
        #expect(sent.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.seedKey)")
    }

    @Test("A sign-in file that is cut short is a passing failure, never signed out")
    func truncatedFile() async throws {
        let home = try signedIn()
        let full = String(decoding: try Data(contentsOf: home.url.appendingPathComponent(".grok/auth.json")), as: UTF8.self)
        try home.write(".grok/auth.json", String(full.prefix(full.count / 2)))
        let http = answering(try fixture("grok-billing-weekly"))
        let service = UsageService(readers: [GrokReader(http: http)])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.status == .unavailable)
        #expect(usage.detail == "sign-in file unreadable")
        #expect(usage.failureCount == 1 && usage.retryAfter != nil)
        #expect(http.requests.isEmpty)
        // An empty file, or one that is not an object (a list), is unreadable too, never "no Grok CLI".
        for text in ["", "  \n", "[1,2]"] {
            try home.write(".grok/auth.json", text)
            guard case .failure(.unavailable, "sign-in file unreadable", nil) = await read(http, in: home) else {
                Issue.record("expected a passing failure for \(text)")
                return
            }
        }
    }

    @Test("A link, a file that is too large and a folder are refused, with no request")
    func refusedFiles() async throws {
        let home = try signedIn()
        let http = answering(try fixture("grok-billing-weekly"))
        let file = home.url.appendingPathComponent(".grok/auth.json")
        let real = home.url.appendingPathComponent("real-auth.json")
        try FileManager.default.moveItem(at: file, to: real)

        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: real)
        guard case .failure(.unavailable, "sign-in file refused", nil) = await read(http, in: home) else {
            Issue.record("a link must be refused")
            return
        }
        try FileManager.default.removeItem(at: file)

        try home.write(".grok/auth.json", String(repeating: " ", count: SecretFile.defaultMaxBytes + 1) + "{}")
        guard case .failure(.unavailable, "sign-in file refused", nil) = await read(http, in: home) else {
            Issue.record("a large file must be refused")
            return
        }
        try FileManager.default.removeItem(at: file)

        try home.mkdir(".grok/auth.json")
        guard case .failure(.unavailable, "sign-in file refused", nil) = await read(http, in: home) else {
            Issue.record("a folder must be refused")
            return
        }
        #expect(http.requests.isEmpty)
    }

    @Test("Only the key, the user id and the two dates of an xAI account are decoded: the refresh token, the address and every other scope never are")
    func onlyFourFields() throws {
        // Fields and scopes that would fail any decoder that tried to read them (a number, an object, a list) are skipped.
        let text = #"{"\#(Self.scope)":{"key":"tok","auth_mode":3,"user_id":"u-1","email":{"x":1},"refresh_token":["a"],"expires_at":"2099-01-01T00:00:00Z","create_time":"2026-10-20T08:15:30Z","team_id":false},"xai::api_key":{"key":{"not":"a string"}},"https://acme.okta.com::c":"garbage","_note":12}"#
        let auth = try JSONDecoder().decode(GrokAuth.self, from: Data(text.utf8))
        let session = try #require(auth.session)
        #expect(session.token == "tok" && session.userId == "u-1" && auth.hasAPIKey)
        #expect(Mirror(reflecting: session).children.compactMap(\.label).sorted() == ["createTime", "expiresAt", "key", "userId"])
        #expect(Mirror(reflecting: auth).children.compactMap(\.label).sorted() == ["hasAPIKey", "session"])
        // A sign-in whose own fields have the wrong type is a file Brimline cannot read: passing failure.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(GrokAuth.self, from: Data(#"{"\#(Self.scope)":{"key":5}}"#.utf8))
        }
    }

    @Test("When the CLI keeps several sign-ins of the xAI account, the one that lasts longest is used")
    func severalSessions() async throws {
        let home = try TemporaryHome()
        let text = #"{"https://auth.x.ai::old":{"key":"tok-old","expires_at":"2027-01-01T00:00:00Z"},"https://auth.x.ai::new":{"key":"tok-new","expires_at":"2028-01-01T00:00:00.5Z"},"https://auth.x.ai":{"key":"tok-bare","expires_at":"2026-12-01T00:00:00Z"}}"#
        try home.write(".grok/auth.json", text)
        let http = FakeHTTP(["tok-new": (200, try fixture("grok-billing-monthly"), [:])])
        guard case .limits = await read(http, in: home) else {
            Issue.record("expected a reading with the longest sign-in")
            return
        }
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-new")
        #expect(http.requests.first?.value(forHTTPHeaderField: "x-userid") == nil)
    }

    // MARK: An expired token is never sent

    @Test("An expired token, or one about to expire, is never sent: the reading is expired")
    func expired() async throws {
        let http = FakeHTTP([:])
        for expires in ["2026-10-27T09:59:59Z", "2026-10-27T10:00:00Z", "2026-10-27T10:00:30.123456789Z", "2026-10-27T10:01:00Z"] {
            let home = try TemporaryHome()
            try home.write(".grok/auth.json", authText(expires: expires))
            guard case .expired = await read(http, in: home) else {
                Issue.record("expected expired for \(expires)")
                return
            }
        }
        #expect(http.requests.isEmpty)

        // Past the margin the token goes. So does a token with no expiry at all (the server decides).
        for expires in ["2026-10-27T10:01:01Z", "2026-10-27T10:01:01.999999999Z", nil] {
            let home = try TemporaryHome()
            try home.write(".grok/auth.json", authText(expires: expires))
            let sent = answering(try fixture("grok-billing-monthly"))
            guard case .limits = await read(sent, in: home) else {
                Issue.record("expected a reading for \(expires ?? "no expiry")")
                return
            }
            #expect(sent.requests.count == 1)
        }
    }

    @Test("With no server expiry, a token lives 30 days from the day it was minted (as the CLI counts)")
    func thirtyDays() async throws {
        let http = FakeHTTP([:])
        let home = try TemporaryHome()
        try home.write(".grok/auth.json", authText(expires: nil, created: "2026-09-27T09:00:00.5Z"))
        guard case .expired = await read(http, in: home) else {
            Issue.record("expected expired")
            return
        }
        try home.write(".grok/auth.json", authText(expires: nil, created: "2026-09-28T09:00:00Z"))
        let sent = answering(try fixture("grok-billing-monthly"))
        guard case .limits = await read(sent, in: home) else {
            Issue.record("expected a reading")
            return
        }
        // A date that cannot be read is no expiry: the token goes, the server decides.
        try home.write(".grok/auth.json", authText(expires: nil, created: "long ago"))
        let other = answering(try fixture("grok-billing-monthly"))
        guard case .limits = await read(other, in: home) else {
            Issue.record("expected a reading")
            return
        }
    }

    @Test("An expired account asks to open the Grok CLI, waits for no delay and keeps its last numbers")
    func expiredThroughService() async throws {
        let home = try TemporaryHome()
        try home.write(".grok/auth.json", authText(expires: "2026-10-27T09:59:55Z"))
        let card = account(in: home)
        let before = AccountUsage(account: card, status: .ok, limits: [UsageLimit(kind: .period, percent: 44, resetsAt: now.addingTimeInterval(3600))],
                                  fetchedAt: now.addingTimeInterval(-600))
        let usage = await UsageService(readers: [GrokReader(http: FakeHTTP([:]))])
            .refresh(account: card, settings: on, previous: before, now: now)
        #expect(usage.status == .expired)
        #expect(usage.failureCount == 0 && usage.retryAfter == nil)
        #expect(usage.limits == before.limits)
        #expect(Strings(.en).message(for: usage) == "Open the Grok CLI to refresh the sign-in.")
        #expect(Strings(.fr).message(for: usage) == "Ouvrez le CLI Grok pour rafraîchir la connexion.")
    }

    // MARK: Values that go in a header

    @Test("A token or a user id that cannot go in a header is never sent")
    func headerValues() async throws {
        for (key, user) in [("tok en", Self.seedUser), ("tok\\nen", Self.seedUser), ("tok-ok", "id with space"),
                            ("tok-ok", "id\\r\\nX-Evil: 1"), ("tok-ok", String(repeating: "a", count: 65)), ("tok-ok", "")] {
            let home = try TemporaryHome()
            try home.write(".grok/auth.json", authText(key: key, userId: user))
            let http = FakeHTTP([:])
            let reading = await read(http, in: home)
            #expect(http.requests.isEmpty, "\(key) / \(user)")
            switch reading {
            case .failure(.reconnect, _, nil): break
            default: Issue.record("unexpected reading for \(key) / \(user)")
            }
        }
    }

    @Test("No user id in the file: the header is left out and the read goes on")
    func noUserId() async throws {
        let home = try TemporaryHome()
        try home.write(".grok/auth.json", authText(key: "tok-no-id", userId: nil))
        let http = answering(try fixture("grok-billing-monthly"), token: "tok-no-id")
        guard case .limits = await read(http, in: home) else {
            Issue.record("expected a reading")
            return
        }
        #expect(http.requests.first?.value(forHTTPHeaderField: "x-userid") == nil)
    }

    // MARK: Consent, files and secrets

    @Test("Turned off, or marked \"Do not read\", Grok is not read at all: no file, no request")
    func consent() async throws {
        let home = try signedIn()
        let card = account(in: home)
        let http = answering(try fixture("grok-billing-weekly"))
        let service = UsageService(readers: [GrokReader(http: http)])
        let off = await service.refresh(account: card, settings: BrimlineSettings(), previous: nil, now: now, force: true)
        #expect(off.status == .pending && off.checkedAt == nil)
        var unread = on
        unread.unreadAccounts = [card.id]
        let skipped = await service.refresh(account: card, settings: unread, previous: nil, now: now, force: true)
        #expect(skipped.status == .pending && skipped.checkedAt == nil)
        #expect(http.requests.isEmpty)
    }

    @Test("The home folder is read only: not a byte, a date or a file changes, and nothing is created")
    func homeStaysAsItWas() async throws {
        let home = try signedIn()
        try home.write(".grok/config.toml", "model = \"x\"\n")
        try home.write(".grok/mcp_credentials.json", #"{"SEED-MCP":"never read"}"#)
        let before = try ChatGPTTests.listing(of: home.url)
        let http = answering(try fixture("grok-billing-weekly"))
        let service = UsageService(readers: [GrokReader(http: http)])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        for _ in 0..<3 { _ = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true) }
        #expect(try ChatGPTTests.listing(of: home.url) == before)
        #expect(http.requests.count == 3)
    }

    @Test("Seeded secrets are found nowhere in the cache, the settings, the JSON and the MCP answers")
    func seeds() async throws {
        let home = try signedIn()
        let answerSecret = "SEED-ANSWER-SECRET-91dd"
        var body = try #require(JSONSerialization.jsonObject(with: try fixture("grok-billing-weekly")) as? [String: Any])
        body["note"] = answerSecret
        let http = answering(try JSONSerialization.data(withJSONObject: body))
        let service = UsageService(readers: [GrokReader(http: http)])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        let snapshot = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true)
        #expect(snapshot.accounts.first?.status == .ok)
        #expect(http.requests.count == 1)

        let paths = BrimlinePaths(home: home.url)
        try UsageCache(file: paths.cacheFile).save(snapshot)
        var settings = on
        settings.labels = [accounts[0].id: "Grok work"]
        try SettingsStore(file: paths.settingsFile).save(settings)
        var outputs: [String] = [
            String(decoding: try Data(contentsOf: paths.cacheFile), as: UTF8.self),
            String(decoding: try Data(contentsOf: paths.settingsFile), as: UTF8.self),
            AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url).jsonString(),
            String(describing: snapshot),
        ]
        let finalSettings = settings
        let server = MCPServer(version: "0.0.0", load: { (snapshot, finalSettings) }, now: { now }, home: home.url)
        for tool in ["list_accounts", "get_usage", "best_account"] {
            let arguments = tool == "list_accounts" ? "{}" : #"{"provider":"grok"}"#
            outputs.append(try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#)))
        }
        let seeds = [Self.seedKey, Self.seedRefresh, Self.seedUser, Self.seedEmail, answerSecret, "b7a1c2d3-0000-4000-8000-000000000001", "SuperGrok"]
        for text in outputs {
            for seed in seeds { #expect(!text.contains(seed), "\(seed) found in an output") }
            #expect(!text.contains("Bearer"))
        }
        let report = AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url)
        #expect(report.accounts.first?.source == "~/.grok/auth.json")
        #expect(report.accounts.first?.provider == "grok")
        #expect(report.accounts.first?.limits.count == 1)
        #expect(report.accounts.first?.limits.first?.kind == "period")
        #expect(report.accounts.first?.message == Strings(.en).sharedPoolMessage)
    }

    @Test("The fingerprint of an answer keeps no value and changes with its keys; the service keeps it")
    func shape() async throws {
        let home = try signedIn()
        let weekly = try fixture("grok-billing-weekly")
        let service = UsageService(readers: [GrokReader(http: answering(weekly))])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.responseShape == ResponseShape.fingerprint(of: weekly))
        #expect(usage.responseShape?.count == 64)

        // Same keys, other values: same fingerprint. A key that changes: another one.
        let text = String(decoding: weekly, as: UTF8.self)
        let otherValues = text.replacingOccurrences(of: "\"creditUsagePercent\": 42.5", with: "\"creditUsagePercent\": 99")
        #expect(ResponseShape.fingerprint(of: Data(otherValues.utf8)) == usage.responseShape)
        let renamed = text.replacingOccurrences(of: "\"creditUsagePercent\"", with: "\"creditPercentUsed\"")
        #expect(ResponseShape.fingerprint(of: Data(renamed.utf8)) != usage.responseShape)

        // The skeleton (status --live --shape) names the keys and the types, no value.
        let skeleton = try #require(ResponseShape.skeleton(of: weekly))
        #expect(skeleton.contains("\"creditUsagePercent\": \"number\""))
        #expect(!skeleton.contains("SuperGrok") && !skeleton.contains("42.5") && !skeleton.contains("2026-11-02"))
    }

    // MARK: Notes kept with the numbers

    @Test("The note is kept with the reading, replaced by the next one and dropped when the read fails")
    func noteLifecycle() async throws {
        let home = try signedIn()
        let card = account(in: home)
        let shared = await UsageService(readers: [GrokReader(http: answering(try fixture("grok-billing-weekly")))])
            .refresh(account: card, settings: on, previous: nil, now: now)
        #expect(shared.note == .sharedPool && shared.status == .ok && shared.limits.count == 1)

        let plain = await UsageService(readers: [GrokReader(http: answering(try fixture("grok-billing-monthly")))])
            .refresh(account: card, settings: on, previous: shared, now: now)
        #expect(plain.note == nil)

        let fresh = await UsageService(readers: [GrokReader(http: answering(try fixture("grok-billing-free")))])
            .refresh(account: card, settings: on, previous: shared, now: now)
        #expect(fresh.note == .noCreditLimit && fresh.status == .ok && fresh.limits.isEmpty && fresh.fetchedAt == now)

        let failed = await UsageService(readers: [GrokReader(http: answering(Data(), status: 500))])
            .refresh(account: card, settings: on, previous: shared, now: now.addingTimeInterval(600), force: true)
        #expect(failed.status == .unavailable && failed.note == nil)
        #expect(failed.limits == shared.limits)

        // The cache keeps the note, and an old cache without it still reads.
        let data = try JSONCoding.encoder().encode(UsageSnapshot(generatedAt: now, accounts: [shared]))
        #expect(String(decoding: data, as: UTF8.self).contains("shared_pool"))
        let back = try JSONCoding.decoder().decode(UsageSnapshot.self, from: data)
        #expect(back.accounts[0].note == .sharedPool)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var accounts = try #require(object["accounts"] as? [[String: Any]])
        accounts[0].removeValue(forKey: "note")
        object["accounts"] = accounts
        let old = try JSONCoding.decoder().decode(UsageSnapshot.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.accounts[0].note == nil)
    }

    // MARK: Sentences

    @Test("The sentences are exact, in English and French, and never use a long dash")
    func sentences() {
        let account = Account(provider: .grok, source: "/opt/box/you/.grok/auth.json", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        func usage(_ status: AccountStatus, _ reason: NotReadableReason? = nil, note: AccountNote? = nil) -> AccountUsage {
            AccountUsage(account: account, status: status, reason: reason, note: note)
        }
        let expected: [(AccountUsage, String, String)] = [
            (usage(.notReadable, .noCLI),
             "xAI only publishes Grok limits for the Grok CLI. Without it, they are in your Grok account settings.",
             "xAI ne publie les limites de Grok que pour le CLI Grok. Sans lui, elles sont dans les réglages de votre compte Grok."),
            (usage(.notReadable, .apiKey),
             "The Grok CLI is signed in with an API key: there is no subscription limit to show.",
             "Le CLI Grok est connecté par une clé d'API : il n'a pas de limite d'abonnement à montrer."),
            (usage(.expired), "Open the Grok CLI to refresh the sign-in.", "Ouvrez le CLI Grok pour rafraîchir la connexion."),
            (usage(.reconnect), "xAI refused the Grok CLI's sign-in: run grok login again.",
             "xAI a refusé la connexion du CLI Grok : relancez grok login."),
            (usage(.ok, note: .noFigureYet), "No number yet for this period.", "Pas encore de chiffre pour cette période."),
            (usage(.ok, note: .noCreditLimit), "xAI returns no credit limit for this account.",
             "xAI ne renvoie aucune limite de crédits pour ce compte."),
            (usage(.ok, note: .sharedPool), "This limit is a pool shared by the Grok products.",
             "Cette limite est un pool partagé entre les produits Grok."),
        ]
        for (item, en, fr) in expected {
            #expect(Strings(.en).message(for: item) == en)
            #expect(Strings(.fr).message(for: item) == fr)
            for text in [en, fr] { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}")) }
        }
        // The other states keep the generic messages.
        #expect(Strings(.en).message(for: usage(.unavailable)) == Strings(.en).unavailableMessage)
        #expect(Strings(.en).message(for: usage(.formatChanged)) == Strings(.en).formatChangedMessage)
        #expect(Strings(.en).message(for: usage(.ok)) == nil)
    }

    @Test("The agent report and the MCP answer carry the sentence, the reason and the note of a Grok account")
    func agentsGetTheSentence() throws {
        let home = URL(fileURLWithPath: "/opt/box/you")
        let account = Account(provider: .grok, source: "/opt/box/you/.grok/auth.json", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let unread = AccountUsage(account: account, status: .notReadable, reason: .noCLI)
        let fresh = AccountUsage(account: Account(provider: .grok, source: "/opt/box/you/.grok-b/auth.json", email: nil,
                                                  organization: nil, seatTier: nil, keychainService: nil),
                                 status: .ok, fetchedAt: now, note: .noFigureYet)
        let free = AccountUsage(account: Account(provider: .grok, source: "/opt/box/you/.grok-c/auth.json", email: nil,
                                                 organization: nil, seatTier: nil, keychainService: nil),
                                status: .ok, fetchedAt: now, note: .noCreditLimit)
        let snapshot = UsageSnapshot(generatedAt: now, accounts: [unread, fresh, free])
        let report = AgentUsageReport(snapshot: snapshot, settings: on, source: "cache", now: now, home: home)
        #expect(report.accounts[0].message == Strings(.en).grokNoCLIMessage)
        #expect(report.accounts[0].reason == "no_cli")
        #expect(report.accounts[0].source == "~/.grok/auth.json")
        #expect(report.accounts[1].message == "No number yet for this period.")
        #expect(report.accounts[1].reason == nil)
        #expect(report.accounts[2].message == "xAI returns no credit limit for this account.")
        #expect(Ranking.rank([free], window: .any, model: nil, now: now).isEmpty)
        // An account with no number yet is never ranked: it would read as 100% room.
        let measured = AccountUsage(account: account, status: .ok,
                                    limits: [UsageLimit(kind: .period, percent: 40, resetsAt: now.addingTimeInterval(3600))],
                                    fetchedAt: now)
        #expect(Ranking.rank([fresh], window: .any, model: nil, now: now).isEmpty)
        #expect(Ranking.rank([fresh, measured], window: .any, model: nil, now: now).map(\.headroom) == [60])
        let settings = on
        let server = MCPServer(version: "0.0.0", load: { (snapshot, settings) }, now: { now }, home: home)
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"grok"}}}"#))
        #expect(line.contains("no_cli"))
        #expect(line.contains("xAI only publishes Grok limits"))
        #expect(line.contains("No number yet for this period."))
        #expect(line.contains("xAI returns no credit limit for this account."))
        // The windows of Grok are `any` and `period`: a session is an error, not an empty answer.
        #expect(Provider.grok.windows == [.any, .period])
    }
}
