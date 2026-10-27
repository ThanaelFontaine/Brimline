import CryptoKit
import Foundation
import Testing
@testable import BrimlineCore

/// A fake `agy` launcher: answers by arguments, records every launch. No real `agy` is ever started.
final class FakeAntigravity: AntigravityRunning, @unchecked Sendable {
    struct Launch: Equatable {
        var binary: String
        var arguments: [String]
        var home: String
    }

    private let lock = NSLock()
    private var answers: [[String]: Result<AntigravityRun, AntigravityRunFailure>]
    private let delay: UInt64
    private(set) var launches: [Launch] = []

    init(_ answers: [[String]: Result<AntigravityRun, AntigravityRunFailure>], delayMilliseconds: UInt64 = 0) {
        self.answers = answers
        self.delay = delayMilliseconds
    }

    var usageLaunches: [Launch] { lock.withLock { launches.filter { $0.arguments != ["--version"] } } }

    func run(binary: URL, arguments: [String], home: URL) async throws(AntigravityRunFailure) -> AntigravityRun {
        let answer = lock.withLock {
            launches.append(Launch(binary: binary.path, arguments: arguments, home: home.path))
            return answers[arguments]
        }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay * 1_000_000) }
        guard let answer else { throw .couldNotLaunch }
        return try answer.get()
    }
}

/// Gemini read through Antigravity, on data written from Google's documentation (provisional).
@Suite("Gemini: read through Antigravity (provisional test data)")
struct AntigravityTests {
    let now = date("2026-10-27T10:00:00Z")
    static let version = "agy 9.9.9"
    static let usage = ["--print", "/usage", "--sandbox"]

    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("gemini")
        return settings
    }

    /// Homes of the tests, kept until the end of the run (a test that drops its home would delete the folder).
    private static let keptHomes = Kept()

    /// A home with a fake `agy` (a few bytes, mode 0700) and the trust list that lists it.
    func installed(mode: Int = 0o700) throws -> (home: TemporaryHome, trust: AntigravityTrust, account: Account) {
        let home = try TemporaryHome()
        Self.keptHomes.keep(home)
        try home.mkdir(".gemini")
        try home.write(".local/bin/agy", "not a real agy")
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: home.url.appendingPathComponent(".local/bin/agy").path)
        let digest = SHA256.hash(data: Data("not a real agy".utf8)).map { String(format: "%02x", $0) }.joined()
        let trust = AntigravityTrust(entries: [.init(sha256: digest, versionOutput: Self.version)])
        let account = Account(provider: .gemini, source: home.path(".gemini"), email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        return (home, trust, account)
    }

    func ok(_ text: String = "", stderr: String = "", code: Int32 = 0) -> Result<AntigravityRun, AntigravityRunFailure> {
        .success(AntigravityRun(exitCode: code, stdout: Data(text.utf8), stderr: Data(stderr.utf8)))
    }

    func runner(usage: Result<AntigravityRun, AntigravityRunFailure>,
                version: Result<AntigravityRun, AntigravityRunFailure>? = nil,
                delayMilliseconds: UInt64 = 0) -> FakeAntigravity {
        FakeAntigravity([["--version"]: version ?? ok(Self.version + "\n"), Self.usage: usage],
                        delayMilliseconds: delayMilliseconds)
    }

    func text(_ name: String) throws -> String { String(decoding: try fixture(name, extension: "txt"), as: UTF8.self) }

    // MARK: the default: nothing verified, nothing launched

    @Test("The list of verified builds is empty: format_changed and not one launch, even with agy there")
    func emptyTrustLaunchesNothing() async throws {
        let (home, _, account) = try installed()
        #expect(AntigravityTrust.verified.isEmpty)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let reader = GeminiReader(runner: fake, trust: .verified)
        guard case .failure(.formatChanged, _, _) = await reader.read(account: account, now: now) else {
            Issue.record("expected format_changed")
            return
        }
        #expect(fake.launches.isEmpty)
        _ = home
    }

    @Test("The registry's Gemini reader has the empty list: a real Brimline launches nothing yet")
    func registryReaderIsEmpty() throws {
        let reader = try #require(Providers.all.compactMap { $0 as? GeminiReader }.first)
        #expect(reader.trust.isEmpty)
        #expect(reader.allowedURLs.isEmpty)
        #expect(reader.minimumReadInterval == 15 * 60)
    }

    @Test("Without agy at its path, the card says the sentence and nothing is launched")
    func noAgy() async throws {
        let home = try TemporaryHome()
        Self.keptHomes.keep(home)
        try home.mkdir(".gemini")
        let account = Account(provider: .gemini, source: home.path(".gemini"), email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let reader = GeminiReader(runner: fake, trust: .init(entries: [.init(sha256: "00", versionOutput: Self.version)]))
        guard case .notReadable(.consumerPlan) = await reader.read(account: account, now: now) else {
            Issue.record("expected the sentence")
            return
        }
        #expect(fake.launches.isEmpty)
    }

    // MARK: discovery

    @Test("agy alone makes a card, without ~/.gemini, and only at its exact path")
    func discovery() throws {
        let home = try TemporaryHome()
        let reader = GeminiReader()
        #expect(reader.discover(home: home.url, settings: on).isEmpty)
        try home.write("bin/agy", "elsewhere")
        try home.write(".config/agy", "elsewhere")
        #expect(reader.discover(home: home.url, settings: on).isEmpty)
        try home.write(".local/bin/agy", "here")
        let card = try #require(reader.discover(home: home.url, settings: on).first)
        #expect(card.source == home.path(".gemini"))
        #expect(card.email == nil && card.keychainService == nil)
    }

    @Test("PATH is never searched: an agy found only there is ignored")
    func pathNotSearched() throws {
        let home = try TemporaryHome()
        try home.write("somewhere/agy", "on the PATH")
        setenv("PATH", home.path("somewhere") + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin"), 1)
        defer { setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1) }
        #expect(GeminiReader().discover(home: home.url, settings: on).isEmpty)
    }

    // MARK: a verified build

    @Test("A verified build: --version, then --print /usage --sandbox, and the models come out as limits")
    func reads() async throws {
        let (home, trust, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let reader = GeminiReader(runner: fake, trust: trust)
        guard case .limits(let limits, _) = await reader.read(account: account, now: now) else {
            Issue.record("expected limits")
            return
        }
        let agy = AntigravityBinary.url(home: home.url).path
        #expect(fake.launches == [
            .init(binary: agy, arguments: ["--version"], home: home.path("")),
            .init(binary: agy, arguments: ["--print", "/usage", "--sandbox"], home: home.path("")),
        ])
        #expect(limits.map(\.model) == ["Gemini 3.1 Pro", "Gemini 3.5 Flash"])
        #expect(limits.map(\.percent) == [42, 7])
        #expect(limits.map(\.kind) == [.model, .model])
        #expect(limits[0].resetsAt == now.addingTimeInterval(3 * 3600 + 12 * 60))
        #expect(limits[1].resetsAt == now.addingTimeInterval(86_400 + 2 * 3600))
        #expect(limits.allSatisfy { $0.label == $0.model && $0.windowSeconds == nil })
    }

    @Test("\"remaining\" and \"left\" become the share used; no reset time gives the note, never an invented time")
    func remainingAndNoReset() async throws {
        let (_, trust, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-remaining")))
        let reader = GeminiReader(runner: fake, trust: trust)
        guard case .annotated(let limits, _, .resetNotPublished) = await reader.read(account: account, now: now) else {
            Issue.record("expected limits with the note")
            return
        }
        #expect(limits.map(\.percent) == [42, 7])
        #expect(limits[0].resetsAt != nil)
        #expect(limits[1].resetsAt == nil)

        let service = UsageService(readers: [reader])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        #expect(usage.status == .ok)
        #expect(usage.note == .resetNotPublished)
        #expect(Strings(.en).message(for: usage) == "Reset time not published by Google")
        #expect(Strings(.fr).message(for: usage) == "Remise à zéro non publiée par Google")
        #expect(Strings(.en).limitName(limits[0], provider: .gemini) == "Gemini 3.1 Pro")
    }

    // MARK: the guards of the launch

    @Test("Another build (its SHA-256 is not listed): format_changed, and nothing is launched")
    func otherBuild() async throws {
        let (home, trust, account) = try installed()
        try home.write(".local/bin/agy", "an updated agy")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.url.appendingPathComponent(".local/bin/agy").path)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        guard case .failure(.formatChanged, _, _) = await GeminiReader(runner: fake, trust: trust).read(account: account, now: now) else {
            Issue.record("expected format_changed")
            return
        }
        #expect(fake.launches.isEmpty)
    }

    @Test("A version that is not the one verified: format_changed after --version, /usage is never launched")
    func otherVersion() async throws {
        let (_, trust, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")), version: ok("agy 10.0.0\n"))
        guard case .failure(.formatChanged, _, _) = await GeminiReader(runner: fake, trust: trust).read(account: account, now: now) else {
            Issue.record("expected format_changed")
            return
        }
        #expect(fake.launches.map(\.arguments) == [["--version"]])
        #expect(fake.usageLaunches.isEmpty)

        let failing = runner(usage: ok(try text("antigravity-usage-normal")), version: ok(Self.version, code: 1))
        guard case .failure(.formatChanged, _, _) = await GeminiReader(runner: failing, trust: trust).read(account: account, now: now) else {
            Issue.record("expected format_changed")
            return
        }
        #expect(failing.usageLaunches.isEmpty)
    }

    @Test("A link, a file of someone else, a file others can write, a file that cannot run: refused, nothing launched")
    func refusedBinaries() async throws {
        // A link (even one that points at a good file).
        let (home, trust, account) = try installed()
        let target = home.url.appendingPathComponent("real-agy")
        let path = AntigravityBinary.url(home: home.url)
        try FileManager.default.moveItem(at: path, to: target)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        guard case .failure(.unavailable, "agy refused", _) = await GeminiReader(runner: fake, trust: trust).read(account: account, now: now) else {
            Issue.record("a link must be refused")
            return
        }
        #expect(fake.launches.isEmpty)

        // Owner: the file belongs to another user id than the one expected.
        let (_, trust2, account2) = try installed()
        let other = runner(usage: ok(try text("antigravity-usage-normal")))
        let wrongOwner = GeminiReader(runner: other, trust: trust2, binaryOwner: getuid() &+ 1)
        guard case .failure(.unavailable, "agy refused", _) = await wrongOwner.read(account: account2, now: now) else {
            Issue.record("a file of someone else must be refused")
            return
        }
        #expect(other.launches.isEmpty)

        // Writable by the group, or not executable.
        for mode in [0o770, 0o602, 0o600] {
            let (_, trust3, account3) = try installed(mode: mode)
            let fake3 = runner(usage: ok(try text("antigravity-usage-normal")))
            guard case .failure(.unavailable, "agy refused", _) = await GeminiReader(runner: fake3, trust: trust3).read(account: account3, now: now) else {
                Issue.record("mode \(String(mode, radix: 8)) must be refused")
                return
            }
            #expect(fake3.launches.isEmpty)
        }
    }

    // MARK: what comes back

    @Test("A report that is not the expected one is format_changed, never a number")
    func unexpectedReports() async throws {
        let cases = [
            try text("antigravity-usage-hostile"),
            "",
            "   \n\n",
            "Model quotas\n",
            "I am sorry, I cannot run /usage.\nGemini 3.1 Pro: 42% used\n",
            "Model quotas\nGemini 3.1 Pro: 142% used\n",
            "Model quotas\nGemini 3.1 Pro: 42% used\nGemini 3.1 Pro: 43% used\n",
            "Model quotas\nGemini 3.1 Pro: 42% used \u{1B}[31m\n",
            "Model quotas\nGemini 3.1 Pro: 42% used (resets tomorrow)\n",
            "Model quotas\n" + (0..<60).map { "Model \($0): 1% used" }.joined(separator: "\n"),
        ]
        let (_, trust, account) = try installed()
        for report in cases {
            let reader = GeminiReader(runner: runner(usage: ok(report)), trust: trust)
            guard case .failure(.formatChanged, _, _) = await reader.read(account: account, now: now) else {
                Issue.record("expected format_changed for: \(report.prefix(60))")
                continue
            }
        }
        // Not UTF-8 at all.
        let binary = AntigravityRun(exitCode: 0, stdout: Data([0x4D, 0xFF, 0xFE, 0x0A]), stderr: Data())
        guard case .failure(.formatChanged, _, _) = await GeminiReader(runner: runner(usage: .success(binary)), trust: trust)
            .read(account: account, now: now) else {
            Issue.record("expected format_changed for bytes")
            return
        }
    }

    @Test("An output that is too long, a launch that fails, a delay that runs out: nothing is read")
    func runnerFailures() async throws {
        let (_, trust, account) = try installed()
        let tooLong = GeminiReader(runner: runner(usage: .failure(.outputTooLong)), trust: trust)
        guard case .failure(.formatChanged, _, _) = await tooLong.read(account: account, now: now) else {
            Issue.record("expected format_changed")
            return
        }
        let slow = GeminiReader(runner: runner(usage: .failure(.timedOut)), trust: trust)
        guard case .failure(.unavailable, _, _) = await slow.read(account: account, now: now) else {
            Issue.record("expected unavailable")
            return
        }
        let broken = GeminiReader(runner: runner(usage: .failure(.couldNotLaunch)), trust: trust)
        guard case .failure(.unavailable, _, _) = await broken.read(account: account, now: now) else {
            Issue.record("expected unavailable")
            return
        }
        let versionTimeout = runner(usage: ok(try text("antigravity-usage-normal")), version: .failure(.timedOut))
        guard case .failure(.unavailable, _, _) = await GeminiReader(runner: versionTimeout, trust: trust).read(account: account, now: now) else {
            Issue.record("expected unavailable")
            return
        }
        #expect(versionTimeout.usageLaunches.isEmpty)
    }

    @Test("A non-zero exit, or \"authentication required\": the sign-in expired, said in words")
    func expired() async throws {
        let (_, trust, account) = try installed()
        for answer in [ok("", stderr: "error: authentication required", code: 1),
                       ok(try text("antigravity-usage-normal"), stderr: "Authentication required"),
                       ok("Model quotas\n", code: 3)] {
            let reader = GeminiReader(runner: runner(usage: answer), trust: trust)
            guard case .expired = await reader.read(account: account, now: now) else {
                Issue.record("expected expired")
                return
            }
        }
        let usage = AccountUsage(account: account, status: .expired)
        #expect(Strings(.en).message(for: usage) == "Open Antigravity to refresh the sign-in.")
        #expect(Strings(.fr).message(for: usage) == "Ouvrez Antigravity pour rafraîchir la connexion.")
        let changed = AccountUsage(account: account, status: .formatChanged)
        #expect(Strings(.en).message(for: changed) == "Antigravity was updated: update Brimline.")
        #expect(Strings(.fr).message(for: changed) == "Antigravity a été mis à jour : mettez Brimline à jour.")
    }

    // MARK: how often, and when it is off

    @Test("Never two launches in 15 minutes, forced or not; a new read after")
    func every15Minutes() async throws {
        let (_, trust, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let service = UsageService(readers: [GeminiReader(runner: fake, trust: trust)])

        let first = await service.refresh(account: account, settings: on, previous: nil, now: now)
        #expect(first.status == .ok)
        #expect(fake.usageLaunches.count == 1)

        let soon = await service.refresh(account: account, settings: on, previous: first,
                                         now: now.addingTimeInterval(14 * 60), force: true)
        #expect(fake.usageLaunches.count == 1)
        #expect(soon.checkedAt == first.checkedAt && soon.limits == first.limits)

        let later = await service.refresh(account: account, settings: on, previous: first,
                                          now: now.addingTimeInterval(15 * 60), force: true)
        #expect(fake.usageLaunches.count == 2)
        #expect(later.checkedAt == now.addingTimeInterval(15 * 60))
    }

    @Test("Another reader is not slowed down: only a provider with an interval waits")
    func otherReadersUnaffected() {
        #expect(ClaudeReader(credentials: FakeCredentials([:]), http: FakeHTTP([:])).minimumReadInterval == 0)
        #expect(ChatGPTReader(http: FakeHTTP([:])).minimumReadInterval == 0)
        #expect(GrokReader(http: FakeHTTP([:])).minimumReadInterval == 0)
    }

    @Test("Two reads at once launch one agy only: the other waits for its next turn")
    func oneAtATime() async throws {
        let (_, trust, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")), delayMilliseconds: 300)
        let reader = GeminiReader(runner: fake, trust: trust)
        async let a = reader.read(account: account, now: now)
        async let b = reader.read(account: account, now: now)
        let results = await [a, b]
        var limits = 0, busy = 0
        for result in results {
            switch result {
            case .limits: limits += 1
            case .failure(.unavailable, "already running", _): busy += 1
            default: Issue.record("unexpected \(result)")
            }
        }
        #expect(limits == 1 && busy == 1)
        #expect(fake.usageLaunches.count == 1)
    }

    @Test("Turned off, or marked \"Do not read\": zero launches, the program is not even looked for")
    func consent() async throws {
        let (_, trust, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let service = UsageService(readers: [GeminiReader(runner: fake, trust: trust)])
        let off = await service.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now, force: true)
        #expect(off.status == .pending && off.checkedAt == nil)
        var unread = on
        unread.unreadAccounts = [account.id]
        let skipped = await service.refresh(account: account, settings: unread, previous: nil, now: now, force: true)
        #expect(skipped.status == .pending && skipped.checkedAt == nil)
        #expect(fake.launches.isEmpty)
        #expect(Providers.discover(readers: [GeminiReader(runner: fake, trust: trust)], home: URL(fileURLWithPath: "/nonexistent"),
                                   settings: BrimlineSettings()).isEmpty)
    }

    @Test("Nothing of the report but the model names, the percentages and the reset times is kept")
    func nothingElseKept() async throws {
        let (_, trust, account) = try installed()
        let service = UsageService(readers: [GeminiReader(runner: runner(usage: ok(try text("antigravity-usage-normal"))), trust: trust)])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(usage), as: UTF8.self)
        #expect(!json.contains("Model quotas"))
        #expect(usage.responseShape == nil)
        #expect(usage.limits.count == 2)
    }

    @Test("No long dash in the new sentences")
    func noLongDash() {
        for language in [Language.en, .fr] {
            let s = Strings(language)
            for text in [s.geminiExpiredMessage, s.geminiFormatChangedMessage, s.resetNotPublishedMessage] {
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
            }
        }
    }
}

private final class Kept: @unchecked Sendable {
    private let lock = NSLock()
    private var homes: [TemporaryHome] = []
    func keep(_ home: TemporaryHome) { lock.withLock { homes.append(home) } }
}
