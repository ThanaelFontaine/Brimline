import Foundation
import Testing
@testable import BrimlineCore

@Suite("Gemini: a sentence only")
struct GeminiTests {
    let now = date("2026-10-27T10:00:00Z")
    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("gemini")
        return settings
    }

    static let english = "Google does not publish Gemini limits in a form Brimline can read. They are in the Gemini app (Settings, Usage limits) and in Gemini CLI (/stats model)."
    static let french = "Google ne publie pas les limites de Gemini sous une forme que Brimline peut lire. Elles sont dans l'app Gemini (Réglages, Limites d'utilisation) et dans Gemini CLI (/stats model)."

    @Test("Gemini is in the registry, after Claude, and calls nothing")
    func registry() {
        #expect(Providers.all.map(\.provider) == [.claude, .gemini])
        #expect(GeminiReader().allowedURLs.isEmpty)
        #expect(Providers.isSupported(.gemini))
    }

    @Test("Gemini is off by default: the folder is not even looked for")
    func offByDefault() throws {
        let home = try TemporaryHome()
        try home.mkdir(".gemini")
        #expect(!BrimlineSettings().isEnabled(.gemini))
        #expect(Providers.discover(home: home.url, settings: BrimlineSettings()).isEmpty)
        let found = Providers.discover(home: home.url, settings: on)
        #expect(found.map(\.provider) == [.gemini])
    }

    @Test("One card when ~/.gemini is a folder, none otherwise, and the card holds no identity")
    func discovery() throws {
        let home = try TemporaryHome()
        #expect(GeminiReader().discover(home: home.url, settings: on).isEmpty)

        try home.write(".gemini", "a file, not a folder")
        #expect(GeminiReader().discover(home: home.url, settings: on).isEmpty)
        try FileManager.default.removeItem(at: home.url.appendingPathComponent(".gemini"))

        try home.mkdir(".gemini")
        let accounts = GeminiReader().discover(home: home.url, settings: on)
        #expect(accounts.count == 1)
        let card = try #require(accounts.first)
        #expect(card.provider == .gemini)
        #expect(card.source == home.path(".gemini"))
        #expect(card.id == "gemini:\(home.path(".gemini"))")
        #expect(card.email == nil && card.organization == nil && card.seatTier == nil && card.keychainService == nil)
    }

    @Test("Only ~/.gemini is considered: no other folder, no folder added by hand")
    func exactPlace() throws {
        let home = try TemporaryHome()
        try home.mkdir(".gemini-work")
        try home.mkdir(".config/gemini")
        try home.mkdir("Library/Application Support/Gemini")
        var settings = on
        settings.extraFolders = [home.path(".gemini-work")]
        #expect(GeminiReader().discover(home: home.url, settings: settings).isEmpty)
    }

    @Test("Nothing inside ~/.gemini is opened: unreadable files and a bait token stay untouched")
    func nothingOpened() throws {
        let home = try TemporaryHome()
        let secret = "ya29.GEMINI-BAIT-TOKEN-0123456789"
        try home.write(".gemini/oauth_creds.json", #"{"access_token":"\#(secret)","refresh_token":"1//BAIT"}"#)
        let creds = home.url.appendingPathComponent(".gemini/oauth_creds.json")
        // A file that cannot be opened would make any read fail loudly.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: creds.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: creds.path) }
        let before = try FileManager.default.attributesOfItem(atPath: creds.path)

        let accounts = GeminiReader().discover(home: home.url, settings: on)
        #expect(accounts.count == 1)
        let after = try FileManager.default.attributesOfItem(atPath: creds.path)
        #expect((after[.modificationDate] as? Date) == (before[.modificationDate] as? Date))
        #expect(!String(describing: accounts).contains(secret))
    }

    @Test("A reading is always not readable, for the consumer plan, with no request")
    func reading() async throws {
        let account = Account(provider: .gemini, source: "/opt/box/you/.gemini", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        guard case .notReadable(.consumerPlan) = await GeminiReader().read(account: account, now: now) else {
            Issue.record("expected not readable")
            return
        }
        let http = FakeHTTP([:])
        let credentials = FakeCredentials([:])
        let service = UsageService(readers: [ClaudeReader(credentials: credentials, http: http), GeminiReader()])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        #expect(usage.status == .notReadable)
        #expect(usage.reason == .consumerPlan)
        #expect(usage.limits.isEmpty)
        #expect(usage.retryAfter == nil && usage.failureCount == 0)
        #expect(http.requests.isEmpty)
        #expect(credentials.reads.isEmpty)
    }

    @Test("Turned off, or marked \"Do not read\", Gemini is not read at all")
    func consent() async {
        let account = Account(provider: .gemini, source: "/opt/box/you/.gemini", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let off = await UsageService(readers: [GeminiReader()]).refresh(account: account, settings: BrimlineSettings(),
                                                                         previous: nil, now: now, force: true)
        #expect(off.status == .pending)
        #expect(off.checkedAt == nil)
        var unread = on
        unread.unreadAccounts = [account.id]
        let skipped = await UsageService(readers: [GeminiReader()]).refresh(account: account, settings: unread,
                                                                             previous: nil, now: now, force: true)
        #expect(skipped.status == .pending)
        #expect(skipped.checkedAt == nil)
    }

    @Test("The sentence is exact, in English and French, in the strings, the agent report and the MCP answer")
    func sentence() async throws {
        #expect(Strings(.en).geminiNotReadableMessage == Self.english)
        #expect(Strings(.fr).geminiNotReadableMessage == Self.french)

        let account = Account(provider: .gemini, source: "/opt/box/you/.gemini", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .notReadable, reason: .consumerPlan)
        #expect(Strings(.en).message(for: usage) == Self.english)
        #expect(Strings(.fr).message(for: usage) == Self.french)
        // Every other state, and every other provider, keeps its own message.
        let other = AccountUsage(account: account, status: .notReadable, reason: .apiKey)
        #expect(Strings(.en).message(for: other) == Strings(.en).notReadableMessage)
        let claude = AccountUsage(account: Account(provider: .claude, source: "/x", email: nil, organization: nil,
                                                   seatTier: nil, keychainService: "s"),
                                  status: .notReadable, reason: .consumerPlan)
        #expect(Strings(.en).message(for: claude) == Strings(.en).notReadableMessage)
        #expect(Strings(.en).message(for: AccountUsage(account: account, status: .ok)) == nil)

        let snapshot = UsageSnapshot(generatedAt: now, accounts: [usage])
        let report = AgentUsageReport(snapshot: snapshot, settings: on, source: "cache", now: now,
                                      home: URL(fileURLWithPath: "/opt/box/you"))
        #expect(report.accounts[0].message == Self.english)
        #expect(report.accounts[0].reason == "consumer_plan")
        #expect(report.accounts[0].source == "~/.gemini")
        #expect(report.accounts[0].limits.isEmpty)

        let server = MCPServer(version: "0.0.0", load: { (snapshot, on) }, now: { now }, home: URL(fileURLWithPath: "/opt/box/you"))
        let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_usage","arguments":{"provider":"gemini"}}}"#))
        #expect(line.contains("consumer_plan"))
        #expect(line.contains("Gemini CLI"))
    }

    @Test("A Gemini account is never offered as the best account")
    func neverRanked() {
        let account = Account(provider: .gemini, source: "/opt/box/you/.gemini", email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let usage = AccountUsage(account: account, status: .notReadable, reason: .consumerPlan)
        #expect(Ranking.rank([usage], window: .any, model: nil, now: now).isEmpty)
    }

    @Test("No long dash in the sentence")
    func noLongDash() {
        for text in [Self.english, Self.french] {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
        }
    }
}
