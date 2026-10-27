import Foundation
import Testing
@testable import BrimlineCore

/// ChatGPT through Codex. Every fixture is test data built from the public source of Codex CLI
/// (openai/codex at commit aeb6b22c8bda5f4d4b6ab80ebd3ccdb3f47fb3ab: the `AuthDotJson` and `TokenData`
/// of `codex-rs/login`, the rate limit models of `codex-rs/codex-backend-openapi-models` and the
/// `GET /wham/usage` call of `codex-rs/backend-client`); the commit is also written in each fixture.
/// The values are invented. The normal fixture is rewritten from the skeleton of a real answer
/// (`brimline status --live --shape --provider chatgpt`) at the real try, before the merge.
@Suite("ChatGPT through Codex")
struct ChatGPTTests {
    let now = date("2026-10-27T10:00:00Z")
    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("chatgpt")
        return settings
    }

    static let seedRefresh = "rt.SEED-CODEX-REFRESH-TOKEN-3a9f1c"
    static let seedAccount = "67e55044-10b1-426f-9247-bb680e5fe0c8"

    /// A home with `~/.codex/auth.json` from a fixture; the access token the file holds.
    func signedIn(_ authFixture: String = "codex-auth-chatgpt") throws -> (home: TemporaryHome, token: String) {
        let text = String(decoding: try fixture(authFixture), as: UTF8.self)
        let home = try TemporaryHome()
        try home.write(".codex/auth.json", text)
        return (home, Self.accessToken(in: text))
    }

    static func accessToken(in text: String) -> String {
        let object = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        return ((object["tokens"] as? [String: Any])?["access_token"] as? String) ?? ""
    }

    /// An unsigned JWT with the given `exp`, as Codex stores its access token.
    static func jwt(exp: Double?) -> String {
        func part(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        var claims: [String: Any] = ["iat": 1_792_000_000]
        if let exp { claims["exp"] = exp }
        return "\(part(["alg": "RS256", "typ": "JWT"])).\(part(claims)).fake-signature"
    }

    func authText(token: String, accountId: String? = Self.seedAccount, extra: String = "") -> String {
        let id = accountId.map { #","account_id":"\#($0)""# } ?? ""
        return #"{"auth_mode":"chatgpt","tokens":{"access_token":"\#(token)","refresh_token":"\#(Self.seedRefresh)"\#(id)}\#(extra)}"#
    }

    func account(in home: TemporaryHome, byHand: Bool = false) -> Account {
        Account(provider: .chatgpt, source: home.path(".codex"), email: nil, organization: nil, seatTier: nil,
                keychainService: nil, addedByHand: byHand)
    }

    func answering(_ token: String, _ body: Data, status: Int = 200, headers: [String: String] = [:]) -> FakeHTTP {
        FakeHTTP([token: (status, body, headers)])
    }

    // MARK: Registry and discovery

    @Test("ChatGPT is in the registry, after Claude, and calls one URL")
    func registry() {
        #expect(Providers.all.map(\.provider) == [.claude, .chatgpt, .gemini, .grok, .cursor])
        #expect(ChatGPTReader().allowedURLs == [URL(string: "https://chatgpt.com/backend-api/wham/usage")!])
        #expect(Providers.isSupported(.chatgpt))
    }

    @Test("ChatGPT is off by default: the folder is not even looked for")
    func offByDefault() throws {
        let home = try TemporaryHome()
        try home.mkdir(".codex")
        #expect(!BrimlineSettings().isEnabled(.chatgpt))
        #expect(Providers.discover(home: home.url, settings: BrimlineSettings()).isEmpty)
        #expect(Providers.discover(home: home.url, settings: on).map(\.provider) == [.chatgpt])
    }

    @Test("One card when ~/.codex is a folder, none otherwise, and the card holds no identity")
    func discovery() throws {
        let home = try TemporaryHome()
        #expect(ChatGPTReader().discover(home: home.url, settings: on).isEmpty)

        try home.write(".codex", "a file, not a folder")
        #expect(ChatGPTReader().discover(home: home.url, settings: on).isEmpty)
        try FileManager.default.removeItem(at: home.url.appendingPathComponent(".codex"))

        try home.mkdir(".codex")
        let accounts = ChatGPTReader().discover(home: home.url, settings: on)
        let card = try #require(accounts.first)
        #expect(accounts.count == 1)
        #expect(card.provider == .chatgpt)
        #expect(card.source == home.path(".codex"))
        #expect(card.id == "chatgpt:\(home.path(".codex"))")
        #expect(card.email == nil && card.organization == nil && card.seatTier == nil && card.keychainService == nil)
        #expect(!card.addedByHand)
    }

    @Test("The places are a closed list: ~/.codex and the folders added by hand, never CODEX_HOME nor a scan")
    func exactPlaces() throws {
        let home = try TemporaryHome()
        try home.mkdir(".codex-work")
        try home.mkdir(".config/codex")
        try home.mkdir("Library/Application Support/Codex")
        try home.mkdir("elsewhere/codex-home")
        setenv("CODEX_HOME", home.path("elsewhere/codex-home"), 1)
        defer { unsetenv("CODEX_HOME") }
        #expect(ChatGPTReader().discover(home: home.url, settings: on).isEmpty)

        var settings = on
        settings.extraCodexFolders = [home.path("elsewhere/codex-home"), home.path("missing"), home.path("elsewhere/codex-home")]
        try home.mkdir(".codex")
        let found = ChatGPTReader().discover(home: home.url, settings: settings)
        #expect(found.map(\.source) == [home.path(".codex"), home.path("elsewhere/codex-home")])
        #expect(found.map(\.addedByHand) == [false, true])
        // Claude's folders are not Codex folders.
        settings.extraFolders = [home.path(".codex-work")]
        #expect(ChatGPTReader().discover(home: home.url, settings: settings).count == 2)
    }

    @Test("Discovery opens nothing inside ~/.codex: an unreadable sign-in stays untouched")
    func nothingOpened() throws {
        let (home, token) = try signedIn()
        let file = home.url.appendingPathComponent(".codex/auth.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        let before = try FileManager.default.attributesOfItem(atPath: file.path)
        let accounts = ChatGPTReader().discover(home: home.url, settings: on)
        #expect(accounts.count == 1)
        let after = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((after[.modificationDate] as? Date) == (before[.modificationDate] as? Date))
        #expect(!String(describing: accounts).contains(token))
    }

    // MARK: Reading

    @Test("A Plus answer: the 5 hour session, the week and a model's limits, with the request exact")
    func plus() async throws {
        let (home, token) = try signedIn()
        let http = answering(token, try fixture("chatgpt-usage-plus"))
        let reader = ChatGPTReader(http: http)
        let card = try #require(reader.discover(home: home.url, settings: on).first)
        guard case .limits(let limits, let shape) = await reader.read(account: card, now: now) else {
            Issue.record("expected limits")
            return
        }
        #expect(!shape.isEmpty)
        #expect(limits.map(\.kind) == [.session, .weekly, .model, .model])
        #expect(limits[0] == UsageLimit(kind: .session, percent: 34, resetsAt: now.addingTimeInterval(7200), windowSeconds: 18000))
        #expect(limits[1] == UsageLimit(kind: .weekly, percent: 12, resetsAt: now.addingTimeInterval(259_200), windowSeconds: 604_800))
        // A model's 5 hour window says its length; its week reads "Week · <model>" by itself.
        #expect(limits[2] == UsageLimit(kind: .model, model: "GPT-5.3-Codex-Spark", percent: 5,
                                        resetsAt: now.addingTimeInterval(9000), windowSeconds: 18000,
                                        label: "GPT-5.3-Codex-Spark 5 h"))
        #expect(limits[3] == UsageLimit(kind: .model, model: "GPT-5.3-Codex-Spark", percent: 2,
                                        resetsAt: now.addingTimeInterval(300_000), windowSeconds: 604_800, label: nil))

        // The request: this URL, this method, these headers, nothing else.
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.allHTTPHeaderFields == [
            "Authorization": "Bearer \(token)",
            "ChatGPT-Account-Id": Self.seedAccount,
            "Accept": "application/json",
            "User-Agent": ChatGPTUsageAPI.userAgent,
        ])
        #expect(ChatGPTUsageAPI.userAgent.hasPrefix("Brimline/"))
        #expect(!ChatGPTUsageAPI.userAgent.localizedCaseInsensitiveContains("codex"))
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("A Pro answer has no 5 hour window: the week only")
    func pro() async throws {
        let (home, token) = try signedIn()
        let reader = ChatGPTReader(http: answering(token, try fixture("chatgpt-usage-pro")))
        let card = try #require(reader.discover(home: home.url, settings: on).first)
        guard case .limits(let limits, _) = await reader.read(account: card, now: now) else {
            Issue.record("expected limits")
            return
        }
        #expect(limits == [UsageLimit(kind: .weekly, percent: 41, resetsAt: now.addingTimeInterval(400_000), windowSeconds: 604_800)])
    }

    @Test("A window is named by its length, not by its position; an unknown length is a period")
    func windowsByLength() async throws {
        let (home, token) = try signedIn()
        let body = #"{"plan_type":"free","rate_limit":{"primary_window":{"used_percent":60,"limit_window_seconds":2592000,"reset_after_seconds":1000,"reset_at":1793096200},"secondary_window":{"used_percent":7,"limit_window_seconds":18000,"reset_after_seconds":60,"reset_at":1793095260}}}"#
        let reader = ChatGPTReader(http: answering(token, Data(body.utf8)))
        let card = try #require(reader.discover(home: home.url, settings: on).first)
        guard case .limits(let limits, _) = await reader.read(account: card, now: now) else {
            Issue.record("expected limits")
            return
        }
        #expect(limits.map(\.kind) == [.session, .period])
        #expect(limits[1].windowSeconds == 2_592_000)
        #expect(limits[1].percent == 60)

        let free = try ChatGPTUsageParser.parse(try fixture("chatgpt-usage-free"), now: now)
        #expect(free == [UsageLimit(kind: .period, percent: 60, resetsAt: now.addingTimeInterval(1_000_000), windowSeconds: 2_592_000)])
    }

    @Test("Missing fields: a window with no percentage is left out, the delay stands in for a missing date")
    func missingFields() throws {
        let body = #"{"plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"reset_at":1793096200},"secondary_window":{"used_percent":9,"limit_window_seconds":604800,"reset_after_seconds":3600}},"additional_rate_limits":[{"metered_feature":"x","rate_limit":null},{"limit_name":"Only-Name"}]}"#
        let limits = try ChatGPTUsageParser.parse(Data(body.utf8), now: now)
        #expect(limits == [UsageLimit(kind: .weekly, percent: 9, resetsAt: now.addingTimeInterval(3600), windowSeconds: 604_800)])
        let bare = #"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":9}}}"#
        let noWindow = try ChatGPTUsageParser.parse(Data(bare.utf8), now: now)
        #expect(noWindow == [UsageLimit(kind: .period, percent: 9, resetsAt: nil, windowSeconds: nil)])
    }

    @Test("An answer that is recognized but has no window is a reading with no limit, never a 0 %")
    func noWindow() async throws {
        let (home, token) = try signedIn()
        for body in [#"{"plan_type":"plus","rate_limit":null}"#, #"{"plan_type":"plus"}"#,
                     #"{"plan_type":"plus","rate_limit":{"allowed":true,"limit_reached":false}}"#] {
            let reader = ChatGPTReader(http: answering(token, Data(body.utf8)))
            let card = try #require(reader.discover(home: home.url, settings: on).first)
            guard case .limits(let limits, _) = await reader.read(account: card, now: now) else {
                Issue.record("expected a reading for \(body)")
                return
            }
            #expect(limits.isEmpty)
        }
    }

    // MARK: Answers that are not usable

    @Test("401 asks to sign in again; 429 waits as long as asked, one hour at most; any other code is unavailable")
    func statusCodes() async throws {
        let (home, token) = try signedIn()
        let card = account(in: home)

        guard case .failure(.reconnect, "HTTP 401", nil) = await ChatGPTReader(http: answering(token, Data(), status: 401)).read(account: card, now: now) else {
            Issue.record("expected reconnect")
            return
        }
        guard case .failure(.unavailable, "HTTP 429", 3600?) = await ChatGPTReader(http: answering(token, Data(), status: 429, headers: ["Retry-After": "99999"])).read(account: card, now: now) else {
            Issue.record("expected a capped wait")
            return
        }
        guard case .failure(.unavailable, "HTTP 429", 120?) = await ChatGPTReader(http: answering(token, Data(), status: 429, headers: ["Retry-After": " 120 "])).read(account: card, now: now) else {
            Issue.record("expected the wait asked")
            return
        }
        guard case .failure(.unavailable, "HTTP 429", nil) = await ChatGPTReader(http: answering(token, Data(), status: 429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"])).read(account: card, now: now) else {
            Issue.record("expected no wait")
            return
        }
        for code in [403, 500, 503] {
            guard case .failure(.unavailable, let detail, nil) = await ChatGPTReader(http: answering(token, Data("<html>".utf8), status: code)).read(account: card, now: now) else {
                Issue.record("expected unavailable for \(code)")
                return
            }
            #expect(detail == "HTTP \(code)")
        }
        guard case .failure(.unavailable, "network", nil) = await ChatGPTReader(http: FakeHTTP([:])).read(account: card, now: now) else {
            Issue.record("expected a network failure")
            return
        }
    }

    @Test("An answer Brimline does not know (cut short, a page, another JSON) is format_changed, never a number")
    func formatChanged() async throws {
        let (home, token) = try signedIn()
        let card = account(in: home)
        let full = try fixture("chatgpt-usage-plus")
        let bodies: [Data] = [
            full.prefix(full.count / 2),
            Data("<!DOCTYPE html><html><title>Just a moment...</title></html>".utf8),
            Data(),
            Data("[1,2,3]".utf8),
            Data("{}".utf8),
            Data(#"{"error":{"code":"unauthorized"}}"#.utf8),
            Data(#"{"usage":{"windows":[{"percent":40}]}}"#.utf8),
        ].map { Data($0) }
        for body in bodies {
            let reading = await ChatGPTReader(http: answering(token, body)).read(account: card, now: now)
            guard case .failure(.formatChanged, "unknown answer", nil) = reading else {
                Issue.record("expected format_changed for \(String(decoding: body.prefix(40), as: UTF8.self))")
                return
            }
        }
    }

    @Test("Hostile values are filtered when the service keeps them")
    func hostile() async throws {
        let (home, token) = try signedIn()
        let card = account(in: home)
        let service = UsageService(readers: [ChatGPTReader(http: answering(token, try fixture("chatgpt-usage-hostile")))])
        let usage = await service.refresh(account: card, settings: on, previous: nil, now: now)
        #expect(usage.status == .ok)
        // Percentages are bounded, names with a line break or 200 characters are dropped (the limit with them),
        // an absurd reset time is dropped (the limit stays, with no date).
        #expect(usage.limits.allSatisfy { $0.percent >= 0 && $0.percent <= 100 })
        #expect(usage.limits.first { $0.kind == .session }?.percent == 100)
        #expect(usage.limits.first { $0.kind == .weekly }?.percent == 0)
        let models = usage.limits.filter { $0.kind == .model }
        #expect(models.map(\.model) == ["Far-Future"])
        #expect(models.first?.resetsAt == nil)
        let text = String(describing: usage)
        #expect(!text.contains("Ignore previous") && !text.contains("<script>"))
    }

    // MARK: The sign-in file

    @Test("No auth.json: not readable (Keychain or signed out), and nothing is requested")
    func noAuthFile() async throws {
        let home = try TemporaryHome()
        try home.mkdir(".codex")
        let http = FakeHTTP([:])
        let reading = await ChatGPTReader(http: http).read(account: account(in: home), now: now)
        guard case .notReadable(.keychainOrSignedOut) = reading else {
            Issue.record("expected not readable")
            return
        }
        // A signed out file has no token either.
        try home.write(".codex/auth.json", "{}")
        guard case .notReadable(.keychainOrSignedOut) = await ChatGPTReader(http: http).read(account: account(in: home), now: now) else {
            Issue.record("expected not readable")
            return
        }
        #expect(http.requests.isEmpty)
    }

    @Test("An API key sign-in has no subscription limit: not readable, and the key is never kept nor sent")
    func apiKey() async throws {
        let (home, _) = try signedIn("codex-auth-apikey")
        let http = FakeHTTP([:])
        let service = UsageService(readers: [ChatGPTReader(http: http)])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.status == .notReadable)
        #expect(usage.reason == .apiKey)
        #expect(usage.limits.isEmpty)
        #expect(usage.retryAfter == nil && usage.failureCount == 0)
        #expect(http.requests.isEmpty)
        #expect(!String(describing: usage).contains("SEED-CODEX-API-KEY"))
    }

    @Test("A sign-in file that is cut short is a passing failure, never signed out")
    func truncatedFile() async throws {
        let (home, token) = try signedIn()
        let full = String(decoding: try Data(contentsOf: home.url.appendingPathComponent(".codex/auth.json")), as: UTF8.self)
        try home.write(".codex/auth.json", String(full.prefix(full.count / 2)))
        let http = answering(token, try fixture("chatgpt-usage-plus"))
        let service = UsageService(readers: [ChatGPTReader(http: http)])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.status == .unavailable)
        #expect(usage.detail == "sign-in file unreadable")
        #expect(usage.failureCount == 1 && usage.retryAfter != nil)
        #expect(http.requests.isEmpty)
    }

    @Test("A link, a file that is too large and a folder are refused, with no request")
    func refusedFiles() async throws {
        let (home, token) = try signedIn()
        let http = answering(token, try fixture("chatgpt-usage-plus"))
        let reader = ChatGPTReader(http: http)
        let card = account(in: home)
        let file = home.url.appendingPathComponent(".codex/auth.json")
        let real = home.url.appendingPathComponent("real-auth.json")
        try FileManager.default.moveItem(at: file, to: real)

        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: real)
        guard case .failure(.unavailable, "sign-in file refused", nil) = await reader.read(account: card, now: now) else {
            Issue.record("a link must be refused")
            return
        }
        try FileManager.default.removeItem(at: file)

        try home.write(".codex/auth.json", String(repeating: " ", count: SecretFile.defaultMaxBytes + 1) + "{}")
        guard case .failure(.unavailable, "sign-in file refused", nil) = await reader.read(account: card, now: now) else {
            Issue.record("a large file must be refused")
            return
        }
        try FileManager.default.removeItem(at: file)

        try home.mkdir(".codex/auth.json")
        guard case .failure(.unavailable, "sign-in file refused", nil) = await reader.read(account: card, now: now) else {
            Issue.record("a folder must be refused")
            return
        }
        #expect(http.requests.isEmpty)
    }

    @Test("Only the mode, the access token and the account id are decoded: the refresh token and the id token never are")
    func onlyThreeFields() throws {
        // Fields that would fail any decoder that tried to read them (a number, an object) are skipped.
        let text = #"{"auth_mode":"chatgpt","OPENAI_API_KEY":{"x":1},"tokens":{"id_token":{"not":"a string"},"access_token":"tok","refresh_token":["a","list"],"account_id":"abc-123","login_owner_id":12},"last_refresh":false}"#
        let auth = try JSONDecoder().decode(CodexAuth.self, from: Data(text.utf8))
        #expect(auth.accessToken == "tok" && auth.accountId == "abc-123" && !auth.isAPIKey)
        #expect(Mirror(reflecting: auth).children.compactMap(\.label).sorted() == ["authMode", "tokens"])
        #expect(Mirror(reflecting: auth.tokens!).children.compactMap(\.label).sorted() == ["accessToken", "accountId"])

        for mode in ["apikey", "ApiKey", "api_key"] {
            let key = try JSONDecoder().decode(CodexAuth.self, from: Data(#"{"auth_mode":"\#(mode)"}"#.utf8))
            #expect(key.isAPIKey)
        }
    }

    // MARK: An expired token is never sent

    @Test("An expired token, or one about to expire, is never sent: the reading is expired")
    func expired() async throws {
        let http = FakeHTTP([:])
        let reader = ChatGPTReader(http: http)
        for exp in [now.timeIntervalSince1970 - 1, now.timeIntervalSince1970, now.timeIntervalSince1970 + 30, now.timeIntervalSince1970 + 60] {
            let home = try TemporaryHome()
            try home.write(".codex/auth.json", authText(token: Self.jwt(exp: exp)))
            guard case .expired = await reader.read(account: account(in: home), now: now) else {
                Issue.record("expected expired for exp \(exp - now.timeIntervalSince1970)")
                return
            }
        }
        #expect(http.requests.isEmpty)

        // Past the margin, the token goes. So does a token with no readable expiry (the server decides).
        for token in [Self.jwt(exp: now.timeIntervalSince1970 + 61), Self.jwt(exp: nil), "opaque-token-without-dots", "a.b.c"] {
            let home = try TemporaryHome()
            try home.write(".codex/auth.json", authText(token: token))
            let sent = answering(token, try fixture("chatgpt-usage-pro"))
            guard case .limits = await ChatGPTReader(http: sent).read(account: account(in: home), now: now) else {
                Issue.record("expected a reading for \(token.prefix(12))")
                return
            }
            #expect(sent.requests.count == 1)
        }
    }

    @Test("An expired account asks to open Codex, waits for no delay and keeps its last numbers")
    func expiredThroughService() async throws {
        let home = try TemporaryHome()
        try home.write(".codex/auth.json", authText(token: Self.jwt(exp: now.timeIntervalSince1970 - 5)))
        let card = account(in: home)
        let before = AccountUsage(account: card, status: .ok, limits: [UsageLimit(kind: .weekly, percent: 44, resetsAt: now.addingTimeInterval(3600))],
                                  fetchedAt: now.addingTimeInterval(-600))
        let usage = await UsageService(readers: [ChatGPTReader(http: FakeHTTP([:]))])
            .refresh(account: card, settings: on, previous: before, now: now)
        #expect(usage.status == .expired)
        #expect(usage.failureCount == 0 && usage.retryAfter == nil)
        #expect(usage.limits == before.limits)
        #expect(Strings(.en).message(for: usage) == "Open Codex to refresh the sign-in.")
        #expect(Strings(.fr).message(for: usage) == "Ouvrez Codex pour rafraîchir la connexion.")
    }

    @Test("The token's expiry is read from the payload of the JWT, with or without padding, and nothing else")
    func jwtExpiry() {
        let at = 1_900_000_000.0
        #expect(JWTExpiry.expiry(of: Self.jwt(exp: at)) == Date(timeIntervalSince1970: at))
        #expect(JWTExpiry.expiry(of: Self.jwt(exp: nil)) == nil)
        for bad in ["", "abc", "a.b", "a.b.c.d", "a..c", "a.!!!.c", "a.e30.c", "a.bnVsbA.c"] {
            #expect(JWTExpiry.expiry(of: bad) == nil, "\(bad)")
        }
        // An exp that is not a number, or is not positive, is no expiry.
        let strings = "e30.\(Data(#"{"exp":"soon"}"#.utf8).base64EncodedString()).x"
        #expect(JWTExpiry.expiry(of: strings) == nil)
        #expect(JWTExpiry.expiry(of: Self.jwt(exp: -5)) == nil)
    }

    // MARK: Values that go in a header

    @Test("A token or an account id that cannot go in a header is never sent")
    func headerValues() async throws {
        for (token, id) in [("tok en", Self.seedAccount), ("tok\nen", Self.seedAccount), ("", Self.seedAccount),
                            ("tok-ok", "id with space"), ("tok-ok", "id\r\nX-Evil: 1"), ("tok-ok", String(repeating: "a", count: 65))] {
            let home = try TemporaryHome()
            try home.write(".codex/auth.json", authText(token: token.replacingOccurrences(of: "\n", with: "\\n"),
                                                        accountId: id.replacingOccurrences(of: "\r\n", with: "\\r\\n")))
            let http = FakeHTTP([:])
            let reading = await ChatGPTReader(http: http).read(account: account(in: home), now: now)
            #expect(http.requests.isEmpty, "\(token) / \(id)")
            switch reading {
            case .failure(.reconnect, _, nil), .notReadable(.keychainOrSignedOut): break
            default: Issue.record("unexpected reading for \(token) / \(id)")
            }
        }
    }

    @Test("No account id in the file: the header is left out and the read goes on")
    func noAccountId() async throws {
        let home = try TemporaryHome()
        try home.write(".codex/auth.json", authText(token: "tok-no-id", accountId: nil))
        let http = answering("tok-no-id", try fixture("chatgpt-usage-pro"))
        guard case .limits = await ChatGPTReader(http: http).read(account: account(in: home), now: now) else {
            Issue.record("expected a reading")
            return
        }
        #expect(http.requests.first?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    // MARK: Consent, files and secrets

    @Test("Turned off, or marked \"Do not read\", ChatGPT is not read at all: no file, no request")
    func consent() async throws {
        let (home, token) = try signedIn()
        let card = account(in: home)
        let http = answering(token, try fixture("chatgpt-usage-plus"))
        let service = UsageService(readers: [ChatGPTReader(http: http)])
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
        let (home, token) = try signedIn()
        try home.write(".codex/config.toml", "model = \"x\"\n")
        let snapshotBefore = try Self.listing(of: home.url)
        let http = answering(token, try fixture("chatgpt-usage-plus"))
        let reader = ChatGPTReader(http: http)
        let service = UsageService(readers: [reader])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        for _ in 0..<3 { _ = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true) }
        #expect(try Self.listing(of: home.url) == snapshotBefore)
        #expect(http.requests.count == 3)
    }

    /// Every path under the folder with its size and modification date, and the bytes of each file.
    static func listing(of root: URL) throws -> [String] {
        let fm = FileManager.default
        var rows: [String] = []
        for case let url as URL in fm.enumerator(at: root, includingPropertiesForKeys: nil)! {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let content = (attributes[.type] as? FileAttributeType) == .typeRegular ? try Data(contentsOf: url).base64EncodedString() : ""
            rows.append("\(url.path)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date())|\(content)")
        }
        return rows.sorted()
    }

    @Test("Seeded secrets are found nowhere in the cache, the settings, the JSON and the MCP answers")
    func seeds() async throws {
        let (home, token) = try signedIn()
        let answerSecret = "SEED-ANSWER-SECRET-91dd"
        var body = try #require(JSONSerialization.jsonObject(with: try fixture("chatgpt-usage-plus")) as? [String: Any])
        body["note"] = answerSecret
        let http = answering(token, try JSONSerialization.data(withJSONObject: body))
        let service = UsageService(readers: [ChatGPTReader(http: http)])
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: on)
        let snapshot = await service.refresh(accounts: accounts, settings: on, previous: nil, now: now, force: true)
        #expect(snapshot.accounts.first?.status == .ok)
        #expect(http.requests.count == 1)

        let paths = BrimlinePaths(home: home.url)
        try UsageCache(file: paths.cacheFile).save(snapshot)
        var settings = on
        settings.labels = [accounts[0].id: "Codex work"]
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
            let arguments = tool == "list_accounts" ? "{}" : #"{"provider":"chatgpt"}"#
            outputs.append(try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#)))
        }
        let seeds = [token, Self.seedRefresh, Self.seedAccount, answerSecret, "someone@example.com", "SEED-CODEX-API-KEY"]
        for text in outputs {
            for seed in seeds { #expect(!text.contains(seed), "\(seed) found in an output") }
            #expect(!text.contains("Bearer"))
        }
        let report = AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url)
        #expect(report.accounts.first?.source == "~/.codex")
        #expect(report.accounts.first?.provider == "chatgpt")
        #expect(report.accounts.first?.limits.count == 4)
    }

    @Test("The fingerprint of an answer keeps no value and changes with its keys; the service keeps it")
    func shape() async throws {
        let (home, token) = try signedIn()
        let plus = try fixture("chatgpt-usage-plus")
        let service = UsageService(readers: [ChatGPTReader(http: answering(token, plus))])
        let usage = await service.refresh(account: account(in: home), settings: on, previous: nil, now: now)
        #expect(usage.responseShape == ResponseShape.fingerprint(of: plus))
        #expect(usage.responseShape?.count == 64)

        // Same keys, other values: same fingerprint. A key that changes: another one.
        let text = String(decoding: plus, as: UTF8.self)
        let otherValues = text.replacingOccurrences(of: "\"used_percent\": 34", with: "\"used_percent\": 99")
        #expect(ResponseShape.fingerprint(of: Data(otherValues.utf8)) == usage.responseShape)
        let renamed = text.replacingOccurrences(of: "\"used_percent\"", with: "\"percent_used\"")
        #expect(ResponseShape.fingerprint(of: Data(renamed.utf8)) != usage.responseShape)

        // The skeleton (status --live --shape) names the keys and the types, no value.
        let skeleton = try #require(ResponseShape.skeleton(of: plus))
        #expect(skeleton.contains("\"used_percent\": \"number\""))
        #expect(!skeleton.contains("GPT-5.3-Codex-Spark") && !skeleton.contains("34"))
    }

    // MARK: Sentences

    @Test("The sentences are exact, in English and French, and never use a long dash")
    func sentences() {
        let account = Account(provider: .chatgpt, source: "/opt/box/you/.codex", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        func usage(_ status: AccountStatus, _ reason: NotReadableReason? = nil) -> AccountUsage {
            AccountUsage(account: account, status: status, reason: reason)
        }
        let expected: [(AccountUsage, String, String)] = [
            (usage(.notReadable, .apiKey),
             "Codex is signed in with an API key: there is no subscription limit to show.",
             "Codex est connecté par une clé d'API : il n'a pas de limite d'abonnement à montrer."),
            (usage(.notReadable, .keychainOrSignedOut),
             "Codex keeps its sign-in in the Keychain or is signed out: Brimline only reads ~/.codex/auth.json.",
             "Codex range sa connexion dans le Trousseau ou n'est pas connecté : Brimline ne lit que ~/.codex/auth.json."),
            (usage(.expired), "Open Codex to refresh the sign-in.", "Ouvrez Codex pour rafraîchir la connexion."),
            (usage(.reconnect), "ChatGPT refused Codex's sign-in: open Codex and sign in again.",
             "ChatGPT a refusé la connexion de Codex : ouvrez Codex et reconnectez-vous."),
        ]
        for (item, en, fr) in expected {
            #expect(Strings(.en).message(for: item) == en)
            #expect(Strings(.fr).message(for: item) == fr)
            for text in [en, fr] { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}")) }
        }
        // The other states keep the generic messages, and Claude keeps its own.
        #expect(Strings(.en).message(for: usage(.unavailable)) == Strings(.en).unavailableMessage)
        #expect(Strings(.en).message(for: usage(.formatChanged)) == Strings(.en).formatChangedMessage)
        #expect(Strings(.en).message(for: usage(.ok)) == nil)
        let claude = AccountUsage(account: Account(source: "/x", email: nil, organization: nil, seatTier: nil, keychainService: "s"),
                                  status: .expired)
        #expect(Strings(.en).message(for: claude) == Strings(.en).expiredMessage)
    }

    @Test("The agent report and the MCP answer carry the sentence and the reason of an account that cannot be read")
    func agentsGetTheSentence() throws {
        let account = Account(provider: .chatgpt, source: "/opt/box/you/.codex", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .notReadable, reason: .apiKey)
        let snapshot = UsageSnapshot(generatedAt: now, accounts: [usage])
        let report = AgentUsageReport(snapshot: snapshot, settings: on, source: "cache", now: now,
                                      home: URL(fileURLWithPath: "/opt/box/you"))
        #expect(report.accounts[0].message == Strings(.en).chatgptAPIKeyMessage)
        #expect(report.accounts[0].reason == "api_key")
        #expect(report.accounts[0].source == "~/.codex")
        let settings = on
        let server = MCPServer(version: "0.0.0", load: { (snapshot, settings) }, now: { now }, home: URL(fileURLWithPath: "/opt/box/you"))
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"chatgpt"}}}"#))
        #expect(line.contains("api_key"))
        #expect(line.contains("Codex is signed in with an API key"))
    }

    @Test("Settings written before the Codex folders decode with none, and keep them when written")
    func settingsMigration() throws {
        let old = try JSONCoding.decoder().decode(BrimlineSettings.self, from: Data(#"{"schemaVersion":1,"extraFolders":["/a"]}"#.utf8))
        #expect(old.extraCodexFolders.isEmpty && old.extraFolders == ["/a"])
        var settings = BrimlineSettings()
        settings.extraCodexFolders = ["/opt/codex-home"]
        let back = try JSONCoding.decoder().decode(BrimlineSettings.self, from: try JSONCoding.encoder().encode(settings))
        #expect(back.extraCodexFolders == ["/opt/codex-home"])
    }
}
