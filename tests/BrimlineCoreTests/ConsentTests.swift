import Foundation
import Testing
@testable import BrimlineCore

/// A reader that counts every call and reads nothing: the proof that a provider that is off, or an
/// account marked "Do not read", is never even approached.
final class CountingReader: ProviderReader, @unchecked Sendable {
    let provider: Provider
    private let lock = NSLock()
    private var discovered = 0
    private var reads = 0

    init(_ provider: Provider) { self.provider = provider }

    var discoverCalls: Int { lock.withLock { discovered } }
    var readCalls: Int { lock.withLock { reads } }

    var allowedURLs: [URL] { [] }

    func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        lock.withLock { discovered += 1 }
        return []
    }

    func read(account: Account, now: Date) async -> ProviderReading {
        lock.withLock { reads += 1 }
        return .limits([UsageLimit(kind: .session, percent: 10, resetsAt: nil)], shape: "")
    }
}

@Suite("Consent: providers off by default, \"Do not read\"")
struct ConsentTests {
    let now = date("2026-10-27T10:00:00Z")

    @Test("Claude is on by default and every other provider is off")
    func defaults() {
        let settings = BrimlineSettings()
        #expect(settings.enabledProviders == ["claude"])
        #expect(settings.isEnabled(.claude))
        for provider in Provider.allCases where provider != .claude {
            #expect(!settings.isEnabled(provider))
        }
        #expect(settings.unreadAccounts.isEmpty)
    }

    @Test("A settings file written before the providers keeps Claude on and nothing else")
    func settingsMigration() throws {
        let old = #"{"schemaVersion":1,"labels":{"a":"Work"},"hiddenAccounts":["b"],"refreshMinutes":10,"showPercentInMenuBar":true}"#
        let settings = try JSONDecoder().decode(BrimlineSettings.self, from: Data(old.utf8))
        #expect(settings.enabledProviders == ["claude"])
        #expect(settings.unreadAccounts.isEmpty)
        #expect(settings.labels == ["a": "Work"])
        #expect(settings.refreshMinutes == 10)
    }

    @Test("The choices survive a save and a load")
    func roundTrip() throws {
        let home = try TemporaryHome()
        let store = SettingsStore(file: BrimlinePaths(home: home.url).settingsFile)
        var settings = BrimlineSettings()
        settings.enabledProviders = ["chatgpt"]
        settings.unreadAccounts = ["chatgpt:/x"]
        try store.save(settings)
        #expect(store.load() == settings)
        #expect(!store.load().isEnabled(.claude))
    }

    @Test("A provider that is off is not looked for at all")
    func offIsNotDiscovered() {
        let claude = CountingReader(.claude)
        let chatgpt = CountingReader(.chatgpt)
        _ = Providers.discover(readers: [claude, chatgpt], settings: BrimlineSettings())
        #expect(claude.discoverCalls == 1)
        #expect(chatgpt.discoverCalls == 0)

        var on = BrimlineSettings()
        on.enabledProviders.append("chatgpt")
        _ = Providers.discover(readers: [claude, chatgpt], settings: on)
        #expect(chatgpt.discoverCalls == 1)
    }

    @Test("A Claude folder is not even listed when Claude is off")
    func claudeOff() throws {
        let home = try TemporaryHome()
        try home.write(".claude.json", claudeJSON(email: "you@example.com"))
        var settings = BrimlineSettings()
        #expect(Providers.discover(home: home.url, settings: settings).count == 1)
        settings.enabledProviders = []
        #expect(Providers.discover(home: home.url, settings: settings).isEmpty)
    }

    @Test("An account of a provider that is off gets no file, no security call and no request")
    func offIsNeverRead() async {
        let a = Account(provider: .chatgpt, source: "/opt/chatgpt", email: nil, organization: nil, seatTier: nil,
                        keychainService: nil)
        let counting = CountingReader(.chatgpt)
        let credentials = FakeCredentials([:])
        let http = FakeHTTP([:])
        let claude = ClaudeReader(credentials: credentials, http: http)
        let service = UsageService(readers: [claude, counting])

        let usage = await service.refresh(account: a, settings: BrimlineSettings(), previous: nil, now: now, force: true)
        #expect(counting.readCalls == 0)
        #expect(credentials.reads.isEmpty)
        #expect(http.requests.isEmpty)
        #expect(usage.status == .pending)
        #expect(usage.checkedAt == nil)
    }

    @Test("An account marked \"Do not read\" is never read, even when forced, and keeps its last numbers")
    func unreadIsNeverRead() async {
        let a = account("a@example.com", dir: "/opt/a")
        let credentials = FakeCredentials([a.keychainService!: .success(ClaudeCredential(accessToken: "tok-a", expiresAt: nil))])
        let http = FakeHTTP(["tok-a": (200, Data("{}".utf8), [:])])
        let service = UsageService(readers: [ClaudeReader(credentials: credentials, http: http)])

        let known = AccountUsage(account: a, status: .ok, limits: [UsageLimit(kind: .weekly, percent: 42, resetsAt: nil)],
                                 fetchedAt: now.addingTimeInterval(-600), checkedAt: now.addingTimeInterval(-600))
        var settings = BrimlineSettings()
        settings.unreadAccounts = [a.id]

        let usage = await service.refresh(account: a, settings: settings, previous: known, now: now, force: true)
        #expect(credentials.reads.isEmpty)
        #expect(http.requests.isEmpty)
        #expect(usage.limits == known.limits)
        #expect(usage.fetchedAt == known.fetchedAt)
        #expect(usage.checkedAt == known.checkedAt)
        #expect(usage.age(at: now) == 600)

        let snapshot = await service.refresh(accounts: [a], settings: settings, previous: UsageSnapshot(generatedAt: now, accounts: [known]), now: now, force: true)
        #expect(snapshot.accounts.first?.limits == known.limits)
        #expect(credentials.reads.isEmpty)
    }

    @Test("Turning \"Do not read\" off reads the account again")
    func unreadOff() async {
        let a = account("a@example.com", dir: "/opt/a")
        let counting = CountingReader(.claude)
        let service = UsageService(readers: [counting])
        var settings = BrimlineSettings()
        settings.unreadAccounts = [a.id]
        _ = await service.refresh(account: a, settings: settings, previous: nil, now: now)
        #expect(counting.readCalls == 0)
        settings.unreadAccounts = []
        let usage = await service.refresh(account: a, settings: settings, previous: nil, now: now)
        #expect(counting.readCalls == 1)
        #expect(usage.status == .ok)
    }

    @Test("A reading that is not readable by design has its own status, its reason and no retry delay")
    func notReadable() async {
        struct Stub: ProviderReader {
            var provider: Provider { .claude }
            var allowedURLs: [URL] { [] }
            func discover(home: URL, settings: BrimlineSettings) -> [Account] { [] }
            func read(account: Account, now: Date) async -> ProviderReading { .notReadable(reason: .consumerPlan) }
        }
        let a = account("a@example.com")
        let usage = await UsageService(readers: [Stub()]).refresh(account: a, settings: allOn, previous: nil, now: now)
        #expect(usage.status == .notReadable)
        #expect(usage.reason == .consumerPlan)
        #expect(usage.retryAfter == nil)
        #expect(usage.failureCount == 0)
    }

    @Test("The glyph follows the most loaded account among the providers that are on")
    func glyphIgnoresOffProviders() {
        let claude = AccountUsage(account: account("a@example.com"), status: .ok,
                                  limits: [UsageLimit(kind: .session, percent: 30, resetsAt: nil)], fetchedAt: now)
        let other = Account(provider: .chatgpt, source: "/opt/c", email: nil, organization: nil, seatTier: nil, keychainService: nil)
        let heavy = AccountUsage(account: other, status: .ok,
                                 limits: [UsageLimit(kind: .period, percent: 90, resetsAt: nil)], fetchedAt: now)
        #expect(Ranking.mostLoaded([claude, heavy], now: now)?.percent == 90)
        #expect(Ranking.mostLoaded([claude, heavy], providers: [.claude], now: now)?.percent == 30)
        #expect(Ranking.mostLoaded([claude, heavy], providers: [.chatgpt], now: now)?.percent == 90)
        #expect(Ranking.mostLoaded([claude, heavy], providers: [], now: now) == nil)
    }
}
