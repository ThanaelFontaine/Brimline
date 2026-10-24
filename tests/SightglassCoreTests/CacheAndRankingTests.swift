import Foundation
import Testing
@testable import SightglassCore

@Suite("Cache, settings, ranking")
struct CacheAndRankingTests {
    @Test("The cache never holds a token: full read with a fake sign-in, then the file is searched")
    func cacheHasNoToken() async throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "you@example.com"))
        let accounts = AccountDiscovery(home: home.url).discover()
        let access = "sk-ant-oat01-FAKE-ACCESS-0123456789"
        let refresh = "sk-ant-ort01-FAKE-REFRESH-0123456789"
        let keychainValue = #"{"claudeAiOauth":{"accessToken":"\#(access)","refreshToken":"\#(refresh)","expiresAt":4102444800000}}"#
        let credential = try #require(ClaudeCredential.decode(Data(keychainValue.utf8)))
        let service = UsageService(
            credentials: FakeCredentials([accounts[0].keychainService: .success(credential)]),
            http: FakeHTTP([access: (200, try fixture("usage-contact-np"), [:])])
        )
        let snapshot = await service.refresh(accounts: accounts, previous: nil)
        #expect(snapshot.accounts[0].status == .ok)

        let cache = UsageCache(file: SightglassPaths(home: home.url).cacheFile)
        try cache.save(snapshot)
        let text = try String(contentsOf: cache.file, encoding: .utf8)
        for forbidden in [access, refresh, "sk-ant", "accessToken", "refreshToken", "Bearer", "FAKE"] {
            #expect(!text.contains(forbidden), "cache contains \(forbidden)")
        }
        // The agents' JSON is built from the same data: no token there either.
        let report = AgentUsageReport(snapshot: snapshot, settings: SightglassSettings(), source: "live", now: Date()).jsonString()
        #expect(!report.contains("sk-ant") && !report.contains("FAKE"))

        // Readable back, user only.
        let loaded = try #require(cache.load())
        #expect(loaded.accounts[0].limits == snapshot.accounts[0].limits)
        let perms = try FileManager.default.attributesOfItem(atPath: cache.file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test("A cache of another schema version is ignored")
    func cacheVersion() throws {
        let home = try TemporaryHome()
        let cache = UsageCache(file: SightglassPaths(home: home.url).cacheFile)
        try home.write("Library/Application Support/Sightglass/usage.json", #"{"schemaVersion":99,"generatedAt":"2026-10-25T00:00:00Z","accounts":[]}"#)
        #expect(cache.load() == nil)
    }

    @Test("Settings: defaults, unknown interval replaced, labels and hidden accounts")
    func settings() throws {
        let home = try TemporaryHome()
        let store = SettingsStore(file: SightglassPaths(home: home.url).settingsFile)
        #expect(store.load() == SightglassSettings())
        try home.write("Library/Application Support/Sightglass/settings.json", #"{"refreshMinutes":7,"labels":{"claude:/opt/a":"  Work  "}}"#)
        let loaded = store.load()
        #expect(loaded.refreshMinutes == 5)
        #expect(loaded.label(for: "claude:/opt/a") == "Work")
        var s = loaded
        s.hiddenAccounts = ["claude:/opt/b"]
        s.refreshMinutes = 10
        try store.save(s)
        #expect(store.load() == s)
        #expect(store.load().isHidden("claude:/opt/b"))
    }

    @Test("The LaunchAgent opens the app at login")
    func launchAgent() throws {
        let home = try TemporaryHome()
        let paths = SightglassPaths(home: home.url)
        try LaunchAgent.install(appPath: "/Applications/Sightglass.app", paths: paths)
        #expect(LaunchAgent.isInstalled(paths: paths))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: paths.launchAgentFile), format: nil) as? [String: Any]
        #expect(plist?["Label"] as? String == "eu.thanaelfontaine.sightglass")
        #expect(plist?["ProgramArguments"] as? [String] == ["/usr/bin/open", "-g", "-a", "/Applications/Sightglass.app"])
        #expect(plist?["RunAtLoad"] as? Bool == true)
        try LaunchAgent.remove(paths: paths)
        #expect(!LaunchAgent.isInstalled(paths: paths))
    }

    static let now = date("2026-10-25T01:00:00Z")

    static func usage(_ email: String, _ limits: [UsageLimit], status: AccountStatus = .ok) -> AccountUsage {
        AccountUsage(account: account(email, dir: "/opt/\(email)"), status: status, limits: limits, fetchedAt: now.addingTimeInterval(-60))
    }

    static let soon = date("2026-10-25T03:00:00Z")
    static let monday = date("2026-10-27T12:00:00Z")

    static var accounts: [AccountUsage] {
        [
            usage("you@example.com", [
                UsageLimit(kind: .session, percent: 34, resetsAt: soon),
                UsageLimit(kind: .weekly, percent: 70, resetsAt: monday),
                UsageLimit(kind: .weeklyModel, model: "Fable", percent: 0, resetsAt: monday),
            ]),
            usage("team@example.org", [
                UsageLimit(kind: .session, percent: 90, resetsAt: soon),
                UsageLimit(kind: .weeklyModel, model: "Fable", percent: 95, resetsAt: monday),
            ]),
            usage("idle@example.net", [
                UsageLimit(kind: .session, percent: 100, resetsAt: date("2026-10-25T00:30:00Z")), // already reset
                UsageLimit(kind: .weekly, percent: 20, resetsAt: monday),
            ]),
            usage("refused@example.com", [UsageLimit(kind: .session, percent: 0, resetsAt: soon)], status: .reconnect),
        ]
    }

    @Test("The most loaded account sets the menu bar glyph")
    func mostLoaded() throws {
        let top = try #require(Ranking.mostLoaded(Self.accounts, now: Self.now))
        #expect(top.usage.account.email == "team@example.org")
        #expect(top.percent == 95)
        #expect(Ranking.mostLoaded([], now: Self.now) == nil)
    }

    @Test("best_account: every limit, session only, week only, with a model")
    func best() {
        let any = Ranking.rank(Self.accounts, window: .any, model: nil, now: Self.now)
        #expect(any.map(\.usage.account.email) == ["idle@example.net", "you@example.com", "team@example.org"])
        #expect(any.map(\.headroom) == [80, 30, 10])
        #expect(any[0].bindingLimit?.kind == .weekly)

        let session = Ranking.rank(Self.accounts, window: .session, model: nil, now: Self.now)
        #expect(session.first?.usage.account.email == "idle@example.net") // its 100 % has reset
        #expect(session.first?.headroom == 100)

        let fableWeek = Ranking.rank(Self.accounts, window: .week, model: "fable", now: Self.now)
        #expect(fableWeek.map(\.usage.account.email) == ["idle@example.net", "you@example.com", "team@example.org"])
        #expect(fableWeek.last?.headroom == 5)
        // The team seat has no global week: only its Fable week counts.
        #expect(fableWeek.last?.bindingLimit?.model == "Fable")
    }
}
