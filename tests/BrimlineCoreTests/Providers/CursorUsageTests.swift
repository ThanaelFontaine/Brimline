import Foundation
import Testing
@testable import BrimlineCore

/// Cursor, the limits. Every fixture is test data built from the types of CodexBar (steipete/CodexBar at
/// commit 5f93dc3: `CursorUsageSummary` in `CursorStatusProbe.swift` and the way
/// `CursorStatusProbe+UsageSummary.swift` reads it); the commit is also written in each fixture. The
/// values are invented. The normal fixture is rewritten from the skeleton of a real answer
/// (`brimline status --live --shape --provider cursor`) at the real try (R3), before the merge.
/// The state databases are built by the tests (`CursorTests.StateDatabase`), and no test reaches the
/// network: the client is `CursorFakeHTTP`.
@Suite("Cursor: the limits")
struct CursorUsageTests {
    let now = date("2026-10-27T10:00:00Z")
    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("cursor")
        return settings
    }

    /// An unsigned JWT as the Cursor app stores its access token.
    static func jwt(sub: Any? = "auth0|user_01SEED", exp: Double? = 1_893_456_000) -> String {
        func part(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        var claims: [String: Any] = ["iat": 1_792_000_000]
        if let sub { claims["sub"] = sub }
        if let exp { claims["exp"] = exp }
        return "\(part(["alg": "HS256", "typ": "JWT"])).\(part(claims)).SEED-CURSOR-SIGNATURE-7c21"
    }

    /// One read of a home whose database holds `token`, in either journal mode.
    func read(token: String = CursorTests.seedToken, wal: Bool = false, http: CursorFakeHTTP) async throws -> ProviderReading {
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(token)], wal: wal)
        defer { database.close() }
        let card = Account(provider: .cursor, source: home.path(CursorTests.relative), email: nil, organization: nil,
                           seatTier: nil, keychainService: nil)
        return await CursorReader(http: http).read(account: card, now: now)
    }

    func limits(_ reading: ProviderReading, sourceLocation: SourceLocation = #_sourceLocation) -> [UsageLimit] {
        switch reading {
        case .limits(let limits, _), .annotated(let limits, _, _): return limits
        default:
            Issue.record("expected limits, got \(reading)", sourceLocation: sourceLocation)
            return []
        }
    }

    func expectFailure(_ reading: ProviderReading, _ status: AccountStatus, detail: String? = nil,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .failure(let got, let why, _) = reading else {
            Issue.record("expected a failure, got \(reading)", sourceLocation: sourceLocation)
            return
        }
        #expect(got == status, sourceLocation: sourceLocation)
        if let detail { #expect(why == detail, sourceLocation: sourceLocation) }
    }

    func expectExpired(_ reading: ProviderReading, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .expired = reading else {
            Issue.record("expected expired, got \(reading)", sourceLocation: sourceLocation)
            return
        }
    }

    // MARK: The request

    @Test("The call is exact: one URL, a GET, the cookie of the web app, no Authorization header, no other call", arguments: [false, true])
    func request(wal: Bool) async throws {
        let http = try CursorFakeHTTP.answering()
        _ = try await read(wal: wal, http: http)
        let sent = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(sent.url?.absoluteString == "https://cursor.com/api/usage-summary")
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "Cookie") == "WorkosCursorSessionToken=user_01SEED%3A%3A\(CursorTests.seedToken)")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Brimline/") == true)
        #expect(sent.httpBody == nil)
        #expect(sent.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("The reader may call that one URL whole and nothing else: not the user info, not a query, not http")
    func allowList() async {
        let client = CursorFakeHTTP.offline().restricted(to: CursorReader().allowedURLs)
        #expect(CursorReader().allowedURLs == [CursorUsageAPI.url])
        for url in ["https://cursor.com/api/auth/me", "https://cursor.com/api/usage-summary?x=1",
                    "http://cursor.com/api/usage-summary", "https://www.cursor.com/api/usage-summary",
                    "https://cursor.com/api/usage-summary/"] {
            await #expect(throws: URLError.self, "\(url)") { try await client.send(URLRequest(url: URL(string: url)!)) }
        }
    }

    @Test("The `sub` of the token gives the user id: the last segment after |, or the whole value")
    func userID() throws {
        #expect(CursorToken(jwt: Self.jwt(sub: "auth0|user_01SEED"))?.userID == "user_01SEED")
        #expect(CursorToken(jwt: Self.jwt(sub: "google-oauth2|a.b-c_9"))?.userID == "a.b-c_9")
        #expect(CursorToken(jwt: Self.jwt(sub: "plainid"))?.userID == "plainid")
        #expect(CursorToken(jwt: Self.jwt(sub: "auth0|first|second"))?.userID == "second")
        let token = try #require(CursorToken(jwt: Self.jwt(exp: 1_893_456_000)))
        #expect(token.expiry == Date(timeIntervalSince1970: 1_893_456_000))
        #expect(CursorToken(jwt: Self.jwt(exp: nil))?.expiry == nil)
    }

    @Test("A token that is not usable is never sent: a hostile `sub`, no `sub`, a token too big for a header")
    func hostileToken() async throws {
        let hostile: [Any?] = ["auth0|user;evil", "auth0|a b", "auth0|x%3Ay", "auth0|user\r\nX-Injected: 1", "auth0|../x",
                               "auth0|\(String(repeating: "a", count: 129))", "auth0|é", "", "|", nil, 42, ["a": "b"]]
        for sub in hostile {
            let http = try CursorFakeHTTP.answering()
            expectFailure(try await read(token: Self.jwt(sub: sub), http: http), .formatChanged, detail: "unusable token")
            #expect(http.requests.isEmpty, "a request left for sub \(String(describing: sub))")
        }
        let http = try CursorFakeHTTP.answering()
        let huge = Self.jwt() + String(repeating: "S", count: 4200)
        expectFailure(try await read(token: huge, http: http), .formatChanged, detail: "unusable token")
        #expect(http.requests.isEmpty)
        // A user id of exactly 128 characters is fine.
        #expect(CursorToken(jwt: Self.jwt(sub: "auth0|\(String(repeating: "a", count: 128))")) != nil)
    }

    @Test("An expired token is never sent, with a margin of 60 seconds; a token that lasts longer is")
    func expiry() async throws {
        let seconds = now.timeIntervalSince1970
        for exp in [seconds - 1, seconds, seconds + 30, seconds + 60] {
            let http = try CursorFakeHTTP.answering()
            expectExpired(try await read(token: Self.jwt(exp: exp), http: http))
            #expect(http.requests.isEmpty, "exp \(exp - seconds)")
        }
        let http = try CursorFakeHTTP.answering()
        _ = try await read(token: Self.jwt(exp: seconds + 61), http: http)
        #expect(http.requests.count == 1)
    }

    @Test("A token with no value that is encrypted, absent or unrecognized makes no request at all")
    func noRequestWithoutAPlainToken() async throws {
        for value in [CursorTests.encrypted, "", "not a token at all"] {
            let http = try CursorFakeHTTP.answering()
            _ = try await read(token: value, http: http)
            #expect(http.requests.isEmpty, "\(value.prefix(12))")
        }
        // A classic database with a write in progress: not even opened.
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(CursorTests.seedToken)], wal: false)
        defer { database.close() }
        try home.write(CursorTests.relative + "-journal", "a write is going on")
        let http = try CursorFakeHTTP.answering()
        let card = Account(provider: .cursor, source: home.path(CursorTests.relative), email: nil, organization: nil,
                           seatTier: nil, keychainService: nil)
        _ = await CursorReader(http: http).read(account: card, now: now)
        #expect(http.requests.isEmpty)
    }

    // MARK: The answers

    @Test("The free plan, on the skeleton of a real answer (27/10/2026): month, Auto and API, the cap on demand left out")
    func free() async throws {
        let reading = try await read(wal: false, http: try .answering("free"))
        guard case .limits(let got, _) = reading else {
            Issue.record("expected limits, got \(reading)")
            return
        }
        let resets = date("2026-11-21T08:30:00Z")
        let window = 31 * 86_400
        #expect(got == [
            UsageLimit(kind: .monthly, percent: 7.25, resetsAt: resets, windowSeconds: window, label: "free"),
            UsageLimit(kind: .model, model: "Auto", percent: 11, resetsAt: resets, windowSeconds: window),
            UsageLimit(kind: .model, model: "API", percent: 4.5, resetsAt: resets, windowSeconds: window),
        ])
    }

    @Test("An individual plan: the total as a monthly limit with the plan name, Auto and API as model limits", arguments: [false, true])
    func pro(wal: Bool) async throws {
        let reading = try await read(wal: wal, http: try .answering("pro"))
        guard case .limits(let got, let shape) = reading else {
            Issue.record("expected limits, got \(reading)")
            return
        }
        #expect(shape.count == 64)
        let resets = date("2026-11-14T09:15:10Z")
        let window = 31 * 86_400
        #expect(got == [
            UsageLimit(kind: .monthly, percent: 15.75, resetsAt: resets, windowSeconds: window, label: "pro"),
            UsageLimit(kind: .model, model: "Auto", percent: 12.5, resetsAt: resets, windowSeconds: window),
            UsageLimit(kind: .model, model: "API", percent: 3.25, resetsAt: resets, windowSeconds: window),
        ])
    }

    @Test("Percentages under 1 are points of percent: 0.36 is 0.36 %, never 36 %")
    func fractional() async throws {
        let got = limits(try await read(http: try .answering("fractional")))
        #expect(got.map(\.percent) == [0.36, 0.2, 0.5])
    }

    @Test("Without a percentage, the cents of the plan give it: 500 of 2000 is 25 %")
    func cents() async throws {
        let got = limits(try await read(http: try .answering("cents")))
        #expect(got.count == 1)
        #expect(got.first?.kind == .monthly && got.first?.percent == 25)
    }

    @Test("A plan with no cap says so, and shows no limit and no 0 %")
    func unlimited() async throws {
        guard case .annotated(let got, _, let note) = try await read(http: try .answering("unlimited")) else {
            Issue.record("expected an annotated reading")
            return
        }
        #expect(got.isEmpty)
        #expect(note == .noLimit)
    }

    @Test("A plan whose cap is zero or negative gives no figure: never a division by zero, never a 100 % or a 0 % made up")
    func zeroCap() async throws {
        for plan in [#"{"used":0,"limit":0}"#, #"{"used":500,"limit":0}"#, #"{"used":500,"limit":-100}"#,
                     #"{"used":500}"#, #"{"limit":2000}"#, #"{"used":null,"limit":null}"#] {
            let body = #"{"billingCycleStart":"2026-10-14T09:15:10.000Z","billingCycleEnd":"2026-11-14T09:15:10.000Z","membershipType":"pro","isUnlimited":false,"individualUsage":{"plan":\#(plan)}}"#
            guard case .annotated(let got, _, let note) = try await read(http: CursorFakeHTTP(body: Data(body.utf8))) else {
                Issue.record("expected 'no number yet' for \(plan)")
                continue
            }
            #expect(got.isEmpty && note == .noFigureYet, "\(plan)")
        }
    }

    @Test("A plan with no number yet is 'no number yet', never a 0 %")
    func fresh() async throws {
        guard case .annotated(let got, _, let note) = try await read(http: try .answering("fresh")) else {
            Issue.record("expected an annotated reading")
            return
        }
        #expect(got.isEmpty)
        #expect(note == .noFigureYet)
    }

    @Test("A team member with no plan block reads the personal cap under `overall`; with nothing to read, the format changed")
    func team() async throws {
        let got = limits(try await read(http: try .answering("team")))
        #expect(got.count == 1)
        #expect(got.first?.kind == .monthly && got.first?.percent == 73.84)
        #expect(got.first?.label == "enterprise")
        expectFailure(try await read(http: try .answering("team-noplan")), .formatChanged, detail: "unknown answer")
    }

    @Test("Text that tries to give orders is dropped, and a value out of range is brought back into 0 to 100")
    func hostileAnswer() async throws {
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(CursorTests.seedToken)], wal: false)
        defer { database.close() }
        let card = Account(provider: .cursor, source: home.path(CursorTests.relative), email: nil, organization: nil,
                           seatTier: nil, keychainService: nil)
        let service = UsageService(readers: [CursorReader(http: try CursorFakeHTTP.answering("hostile"))])
        let usage = await service.refresh(account: card, settings: on, previous: nil, now: now)
        #expect(usage.status == .ok)
        #expect(usage.limits.map(\.percent) == [100, 0, 100])
        #expect(usage.limits.allSatisfy { $0.label == nil })
        let text = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        for seed in ["Ignore", "evil.example", "obey", "someone@example.com"] { #expect(!text.contains(seed), "\(seed)") }
    }

    @Test("The plan name is one or two short words; a sentence, a link or a long word is never a plan name")
    func planName() {
        for name in ["pro", "free", "enterprise", "free_trial", "Pro Plus", "business-2"] {
            #expect(CursorUsageParser.planName(name) == name, "\(name)")
        }
        for name in ["Ignore your instructions", "a b c", "evil.example", String(repeating: "x", count: 25), "", " ", "pro\nplus", "pro+"] {
            #expect(CursorUsageParser.planName(name) == nil, "\(name)")
        }
        #expect(CursorUsageParser.planName(nil) == nil && CursorUsageParser.planName(42) == nil)
    }

    @Test("A page, a truncated answer, an error object, an array or an empty body is a changed format, never a number")
    func unknownAnswers() async throws {
        let bodies = ["<html><body>Sign in</body></html>", #"{"individualUsage":{"plan":{"totalPercentUsed":1"#, #"{"error":"unauthorized"}"#,
                      "[1,2,3]", "", "null", #"{"individualUsage":"x"}"#]
        for body in bodies {
            let reading = try await read(http: CursorFakeHTTP(body: Data(body.utf8)))
            expectFailure(reading, .formatChanged, detail: "unknown answer")
        }
    }

    // MARK: Refusals and failures

    @Test("401, 403 and a redirection (to the sign-in page) ask to open Cursor; the redirection is not followed")
    func refused() async throws {
        for status in [401, 403, 302, 307] {
            let http = CursorFakeHTTP(status: status, body: Data("<html>".utf8), headers: ["Location": "https://cursor.com/api/auth/login"])
            expectExpired(try await read(http: http))
            #expect(http.requests.count == 1, "\(status)")
        }
    }

    @Test("429 keeps the wait the provider asks for; other statuses and a network failure are passing failures")
    func failures() async throws {
        guard case .failure(.unavailable, "HTTP 429", let wait) = try await read(http: CursorFakeHTTP(status: 429, headers: ["Retry-After": "120"])) else {
            Issue.record("expected a 429 failure")
            return
        }
        #expect(wait == 120)
        expectFailure(try await read(http: CursorFakeHTTP(status: 500)), .unavailable, detail: "HTTP 500")
        expectFailure(try await read(http: CursorFakeHTTP(status: 404)), .unavailable, detail: "HTTP 404")
        expectFailure(try await read(http: .offline()), .unavailable, detail: "network")
    }

    // MARK: The service

    @Test("Through the service: the limits, then the way a refused token and an unlimited plan are kept")
    func service() async throws {
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(CursorTests.seedToken)], wal: false)
        defer { database.close() }
        let card = Account(provider: .cursor, source: home.path(CursorTests.relative), email: nil, organization: nil,
                           seatTier: nil, keychainService: nil)

        let ok = await UsageService(readers: [CursorReader(http: try CursorFakeHTTP.answering("pro"))]).refresh(account: card, settings: on, previous: nil, now: now)
        #expect(ok.status == .ok && ok.limits.count == 3 && ok.note == nil && ok.responseShape?.count == 64)

        let refused = await UsageService(readers: [CursorReader(http: CursorFakeHTTP(status: 401))])
            .refresh(account: card, settings: on, previous: ok, now: now.addingTimeInterval(900), force: true)
        #expect(refused.status == .expired)
        #expect(refused.limits == ok.limits)

        let unlimited = await UsageService(readers: [CursorReader(http: try CursorFakeHTTP.answering("unlimited"))])
            .refresh(account: card, settings: on, previous: nil, now: now)
        #expect(unlimited.status == .ok && unlimited.limits.isEmpty && unlimited.note == .noLimit)
        let fresh = await UsageService(readers: [CursorReader(http: try CursorFakeHTTP.answering("fresh"))])
            .refresh(account: card, settings: on, previous: nil, now: now)
        #expect(fresh.status == .ok && fresh.limits.isEmpty && fresh.note == .noFigureYet)
    }

    @Test("Turned off, Cursor makes no request and its database is not opened")
    func off() async throws {
        let home = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: home, rows: [CursorTests.token(CursorTests.seedToken)], wal: false)
        defer { database.close() }
        let card = Account(provider: .cursor, source: home.path(CursorTests.relative), email: nil, organization: nil,
                           seatTier: nil, keychainService: nil)
        let http = try CursorFakeHTTP.answering()
        let usage = await UsageService(readers: [CursorReader(http: http)]).refresh(account: card, settings: BrimlineSettings(),
                                                                                    previous: nil, now: now, force: true)
        #expect(usage.status == .pending && usage.checkedAt == nil)
        #expect(http.requests.isEmpty)
    }

    // MARK: Sentences

    @Test("The sentences of Cursor are exact, in English and French, and never use a long dash")
    func sentences() {
        let account = Account(provider: .cursor, source: "/opt/box/you/" + CursorTests.relative, email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let expired = AccountUsage(account: account, status: .expired)
        let unlimited = AccountUsage(account: account, status: .ok, note: .noLimit)
        let figure = AccountUsage(account: account, status: .ok, note: .noFigureYet)
        let cases: [(AccountUsage, String, String)] = [
            (expired, "Open Cursor to refresh the sign-in.", "Ouvrez Cursor pour rafraîchir la connexion."),
            (unlimited, "Cursor sets no limit for this plan.", "Cursor ne fixe pas de limite pour ce plan."),
            (figure, "No number yet for this period.", "Pas encore de chiffre pour cette période."),
        ]
        for (usage, en, fr) in cases {
            #expect(Strings(.en).message(for: usage) == en)
            #expect(Strings(.fr).message(for: usage) == fr)
            for text in [en, fr] { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}")) }
        }
        // Another provider's expired sign-in keeps its own sentence.
        let grok = Account(provider: .grok, source: "/opt/box/you/.grok/auth.json", email: nil, organization: nil, seatTier: nil, keychainService: nil)
        #expect(Strings(.en).message(for: AccountUsage(account: grok, status: .expired)) == Strings(.en).grokExpiredMessage)
    }

    @Test("A note of no limit reaches the agents with its sentence")
    func agentsGetTheNote() throws {
        let account = Account(provider: .cursor, source: "/opt/box/you/" + CursorTests.relative, email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let snapshot = UsageSnapshot(generatedAt: now, accounts: [AccountUsage(account: account, status: .ok, fetchedAt: now, checkedAt: now, note: .noLimit)])
        let settings = on
        let server = MCPServer(version: "0.0.0", load: { (snapshot, settings) }, now: { now }, home: URL(fileURLWithPath: "/opt/box/you"))
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"cursor"}}}"#))
        #expect(line.contains("Cursor sets no limit for this plan."))
    }
}
