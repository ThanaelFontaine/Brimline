import Foundation
import Testing
@testable import BrimlineCore

/// A client that notes every request and answers `{}` from the URL asked.
final class NotingHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var noted: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { noted } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { noted.append(request) }
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

/// A reader that forgets to restrict its client and calls an URL it never declared.
struct ForgetfulReader: ProviderReader {
    var http: any HTTPClient
    var provider: Provider { .grok }
    var allowedURLs: [URL] { [URL(string: "https://declared.test/usage")!] }
    func discover(home: URL, settings: BrimlineSettings) -> [Account] { [] }
    func read(account: Account, now: Date) async -> ProviderReading {
        _ = try? await http.send(URLRequest(url: URL(string: "https://undeclared.test/steal")!))
        _ = try? await http.send(URLRequest(url: URL(string: "https://declared.test/usage")!))
        return .failure(status: .unavailable, detail: nil, retryAfter: nil)
    }
}

@Suite("The socle holds the consent and the closed list of URLs, not each reader (QUOTA-44)")
struct SocleTests {
    let now = date("2026-10-27T10:00:00Z")

    // MARK: B2, the closed list of URLs

    @Test("A reader that forgets to restrict its client cannot call an URL it did not declare")
    func registryEnvelope() async {
        let base = NotingHTTP()
        let reader = Providers.limited { ForgetfulReader(http: $0) }(base)
        _ = await reader.read(account: Account(provider: .grok, source: "/x", email: nil, organization: nil, seatTier: nil,
                                               keychainService: nil), now: now)
        #expect(base.requests.compactMap(\.url?.absoluteString) == ["https://declared.test/usage"])
    }

    /// Every reader of the registry, made by `Providers.make` with a client that notes the requests, reads one
    /// account: each request that reaches the client is in its `allowedURLs` (Gemini has none and makes none). A
    /// provider added to the registry without a line here fails the test.
    @Test("Every reader of the registry only sends requests listed in its allowedURLs")
    func everyReaderStaysOnItsList() async throws {
        let base = NotingHTTP()
        let a = account("a@example.com")
        let credentials = FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok", expiresAt: nil))])
        let readers = Providers.make(credentials: credentials, http: base)

        let chatgptHome = try TemporaryHome()
        try chatgptHome.write(".codex/auth.json", String(decoding: try fixture("codex-auth-chatgpt"), as: UTF8.self))
        let grokHome = try TemporaryHome()
        try grokHome.write(".grok/auth.json", String(decoding: try fixture("grok-auth-oauth"), as: UTF8.self))
        let cursorHome = try TemporaryHome()
        let database = try CursorTests.StateDatabase(in: cursorHome, rows: [CursorTests.token(CursorTests.seedToken)])
        defer { database.close() }
        let geminiHome = try TemporaryHome()
        try geminiHome.mkdir(".gemini")

        let accounts: [Provider: Account] = [
            .claude: a,
            .chatgpt: Account(provider: .chatgpt, source: chatgptHome.path(".codex"), email: nil, organization: nil,
                              seatTier: nil, keychainService: nil),
            .grok: Account(provider: .grok, source: grokHome.path(".grok/auth.json"), email: nil, organization: nil,
                           seatTier: nil, keychainService: nil),
            .cursor: Account(provider: .cursor, source: cursorHome.path(CursorTests.relative), email: nil, organization: nil,
                             seatTier: nil, keychainService: nil),
            .gemini: Account(provider: .gemini, source: geminiHome.path(".gemini"), email: nil, organization: nil,
                             seatTier: nil, keychainService: nil),
        ]
        for reader in readers {
            let account = try #require(accounts[reader.provider], "no case for \(reader.provider)")
            let before = base.requests.count
            _ = await reader.read(account: account, now: now)
            let made = base.requests[before...].compactMap(\.url?.absoluteString)
            #expect(made.allSatisfy { sent in reader.allowedURLs.contains { $0.absoluteString == sent } }, "\(reader.provider)")
            #expect(made.isEmpty == reader.allowedURLs.isEmpty, "\(reader.provider) made \(made.count) request(s)")
        }
    }

    // MARK: B1, "Do not read" opens no file at discovery

    func cache(_ home: TemporaryHome, _ accounts: [Account]) throws {
        let snapshot = UsageSnapshot(generatedAt: now, accounts: accounts.map { AccountUsage(account: $0) })
        try UsageCache(file: BrimlinePaths(home: home.url).cacheFile).save(snapshot)
    }

    /// A counter of the settings files opened by the Claude discovery.
    final class Opened: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String] = []
        var count: Int { lock.withLock { files.count } }
        func note(_ file: String) { lock.withLock { files.append(file) } }
    }

    @Test("A Claude folder marked \"Do not read\" opens no file during discovery; the others open one each")
    func claudeUnreadOpensNothing() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "default@example.com"))
        try home.write(".claude-work/.claude.json", claudeJSON(email: "work@example.com"))
        try home.write(".claude-side/.claude.json", claudeJSON(email: "side@example.com"))
        let opened = Opened()
        let discovery = AccountDiscovery(home: home.url) { file in
            opened.note(file)
            return AccountDiscovery.readIdentity(configFile: file)
        }

        let all = discovery.discover()
        #expect(all.count == 3)
        #expect(opened.count == 3)

        let before = opened.count
        let unread = Set(all.map(\.id))
        let found = discovery.discover(unreadAccounts: unread)
        #expect(found.map(\.id) == all.map(\.id))   // the paths are still found
        #expect(opened.count == before)             // and no file was opened for them
        #expect(found.allSatisfy { $0.email == nil })   // nothing is known of an address the cache never saw

        // One of three marked: only the two others are opened.
        let one = discovery.discover(unreadAccounts: [all[0].id])
        #expect(one.count == 3)
        #expect(opened.count == before + 2)
    }

    @Test("A Claude account marked \"Do not read\" keeps its last known identity, even when its file changed or cannot be opened")
    func claudeUnreadKeepsLastIdentity() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "old@example.com", organization: "Old Org", seat: "team"))
        let known = Account(source: home.path(".claude"), email: "old@example.com", organization: "Old Org", seatTier: "team",
                            keychainService: KeychainServiceName.forConfigDir(home.path(".claude"), isDefault: true))
        try cache(home, [known])
        // The file now says something else, and cannot be opened at all.
        try home.write(".claude.json", claudeJSON(email: "new@example.com", organization: "New Org"))
        let file = home.url.appendingPathComponent(".claude.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }

        var settings = BrimlineSettings()
        settings.unreadAccounts = [known.id]
        let found = Providers.discover(home: home.url, settings: settings)
        #expect(found.count == 1)
        #expect(found[0].id == known.id)
        #expect(found[0].email == "old@example.com")
        #expect(found[0].organization == "Old Org")
        #expect(found[0].seatTier == "team")
        #expect(found[0].keychainService == known.keychainService)
    }

    @Test("An account marked \"Do not read\" and unknown to the cache is listed without identity")
    func claudeUnreadUnknown() throws {
        let home = try TemporaryHome()
        try home.write(".claude-work/.claude.json", claudeJSON(email: "work@example.com"))
        var settings = BrimlineSettings()
        settings.unreadAccounts = ["claude:" + home.path(".claude-work")]
        let found = Providers.discover(home: home.url, settings: settings)
        #expect(found.count == 1)
        #expect(found[0].email == nil)
    }

    @Test("Turning \"Do not read\" off reads the identity again")
    func claudeUnreadOff() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "new@example.com"))
        let stale = Account(source: home.path(".claude"), email: "old@example.com", organization: nil, seatTier: nil,
                            keychainService: nil)
        try cache(home, [stale])
        var settings = BrimlineSettings()
        settings.unreadAccounts = [stale.id]
        #expect(Providers.discover(home: home.url, settings: settings).first?.email == "old@example.com")
        settings.unreadAccounts = []
        #expect(Providers.discover(home: home.url, settings: settings).first?.email == "new@example.com")
    }

    /// Discovery of every reader of the registry, with every account marked "Do not read" and every file of
    /// every provider unreadable: the accounts are still found, from their paths, and nothing leaks into them.
    @Test("Every reader of the registry still finds its accounts when none of their files can be opened")
    func everyReaderDiscoversWithoutOpening() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "me@example.com"))
        try home.write(".codex/auth.json", "SEED-BAIT-CODEX")
        try home.write(".grok/auth.json", "SEED-BAIT-GROK")
        try home.write(CursorTests.relative, "SEED-BAIT-CURSOR")
        try home.mkdir(".gemini")
        var files: [URL] = []
        for relative in [".claude.json", ".codex/auth.json", ".grok/auth.json", CursorTests.relative] {
            let file = home.url.appendingPathComponent(relative)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
            files.append(file)
        }
        defer { for file in files { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) } }

        let providers = Providers.all
        let first = Providers.discover(readers: providers, home: home.url, settings: allOn)
        var settings = allOn
        settings.unreadAccounts = first.map(\.id)
        let again = Providers.discover(readers: providers, home: home.url, settings: settings)
        #expect(Set(first.map(\.provider)) == Set([.claude, .chatgpt, .grok, .cursor, .gemini]))
        #expect(again.map(\.id) == first.map(\.id))
        #expect(!String(describing: again).contains("SEED-BAIT"))
    }
}
