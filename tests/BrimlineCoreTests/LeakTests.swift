import Foundation
import Testing
@testable import BrimlineCore

/// Seeds fake secrets in a sign-in and in an answer, runs the whole chain, then looks for every seed
/// in everything Brimline writes or says: the cache, the settings, the JSON of the command and the
/// answers of the MCP server.
@Suite("No secret goes out")
struct LeakTests {
    static let access = "SEED-ACCESS-TOKEN-4f1c9d"
    static let refresh = "SEED-REFRESH-TOKEN-77ab02"
    static let uuid = "SEED-UUID-0b3e7a54"
    static let answerSecret = "SEED-ANSWER-SECRET-91dd"
    let now = date("2026-10-27T10:00:00Z")

    @Test("Seeded tokens are found nowhere in the cache, the settings, the JSON and the MCP answers")
    func seeds() async throws {
        let home = try TemporaryHome()
        let dir = home.path(".claude")
        try home.write(".claude.json", #"{"oauthAccount":{"emailAddress":"you@example.com","accountUuid":"\#(Self.uuid)","organizationName":"Example"}}"#)
        let keychain = #"{"claudeAiOauth":{"accessToken":"\#(Self.access)","refreshToken":"\#(Self.refresh)","expiresAt":4102444800000}}"#
        let credential = try #require(ClaudeCredential.decode(Data(keychain.utf8)))
        let answer = #"{"five_hour":{"utilization":34,"resets_at":"2026-10-27T12:00:00Z"},"seven_day":{"utilization":10,"resets_at":"2026-10-30T12:00:00Z"},"note":"\#(Self.answerSecret)"}"#
        let http = FakeHTTP([Self.access: (200, Data(answer.utf8), [:])])

        let service = UsageService(credentials: FakeCredentials([KeychainServiceName.forConfigDir(dir, isDefault: true): .success(credential)]), http: http)
        let accounts = Providers.discover(readers: service.readers, home: home.url, settings: BrimlineSettings())
        #expect(accounts.count == 1)
        let snapshot = await service.refresh(accounts: accounts, settings: BrimlineSettings(), previous: nil, now: now, force: true)
        #expect(snapshot.accounts.first?.status == .ok)

        // The only place the token goes: the Authorization header of the listed URL.
        #expect(http.requests.count == 1)
        #expect(http.requests.first?.url == ClaudeUsageAPI.url)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.access)")

        // Everything Brimline writes.
        let paths = BrimlinePaths(home: home.url)
        try UsageCache(file: paths.cacheFile).save(snapshot)
        var settings = BrimlineSettings()
        settings.labels = [accounts[0].id: "Work"]
        try SettingsStore(file: paths.settingsFile).save(settings)
        var outputs: [String] = [
            String(decoding: try Data(contentsOf: paths.cacheFile), as: UTF8.self),
            String(decoding: try Data(contentsOf: paths.settingsFile), as: UTF8.self),
            AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url).jsonString(),
            String(describing: snapshot),
        ]

        // Everything the MCP server says, tool by tool.
        let finalSettings = settings
        let server = MCPServer(version: "0.0.0", load: { (snapshot, finalSettings) }, now: { now }, home: home.url)
        for tool in ["list_accounts", "get_usage", "best_account"] {
            let line = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":{}}}"#))
            outputs.append(line)
        }
        let list = try #require(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        outputs.append(list)

        for text in outputs {
            for seed in [Self.access, Self.refresh, Self.uuid, Self.answerSecret] {
                #expect(!text.contains(seed), "\(seed) found in an output")
            }
            #expect(!text.contains("Bearer"))
        }

        // The paths agents read start with ~/ and carry no user name.
        let report = AgentUsageReport(snapshot: snapshot, settings: settings, source: "live", now: now, home: home.url)
        #expect(report.accounts.first?.source == "~/.claude")
        for entry in report.accounts {
            #expect(entry.source.hasPrefix("~"))
            #expect(!entry.source.contains(home.url.path))
        }
    }

    @Test("The types that are cached have no field able to hold a token")
    func noTokenField() {
        let now = date("2026-10-27T10:00:00Z")
        let usage = AccountUsage(account: account("a@example.com"), status: .ok, limits: [], fetchedAt: now)
        let labels = Mirror(reflecting: usage).children.compactMap(\.label) + Mirror(reflecting: usage.account).children.compactMap(\.label)
        for label in labels {
            #expect(!label.lowercased().contains("token") && !label.lowercased().contains("secret") && !label.lowercased().contains("password"))
        }
    }
}
