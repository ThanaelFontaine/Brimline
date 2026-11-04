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

    var usageLaunches: [Launch] { lock.withLock { launches } }

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

/// A fake check of Google's signature: answers in turn (the last answer repeats), records every question.
/// No certificate of Google's is needed, and the real `~/.local/bin/agy` is never looked at: a question about it
/// is a failure of the test.
final class FakeChecker: AntigravityCodeChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [AntigravitySignatureCheck]
    private(set) var checked: [URL] = []
    /// Called during each check (a test can replace the file there, as an update of `agy` would).
    var duringCheck: (@Sendable (Int) -> Void)?
    var otherIdentifier = false

    init(_ answers: AntigravitySignatureCheck...) {
        self.answers = answers.isEmpty ? [.accepted] : answers
    }

    var checks: Int { lock.withLock { checked.count } }

    func checkStatic(at url: URL) -> AntigravitySignatureCheck {
        let realAgy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(AntigravityBinary.relativePath).path
        if url.path == realAgy { Issue.record("a test asked about the real \(realAgy)") }
        let (index, answer) = lock.withLock { () -> (Int, AntigravitySignatureCheck) in
            checked.append(url)
            let index = checked.count - 1
            return (index, answers[min(index, answers.count - 1)])
        }
        duringCheck?(index)
        return answer
    }

    func isOtherIdentifier(at url: URL) -> Bool { otherIdentifier }
}

/// Gemini read through Antigravity, on the shape of the real text of `/usage` (Antigravity CLI 1.4.8, 27/10/2026,
/// 1.4.9, 28/10/2026, 1.4.10, 29/10/2026, and 1.4.11, 04/11/2026: the same text).
@Suite("Gemini: read through Antigravity, trusted by Google's signature")
struct AntigravityTests {
    let now = date("2026-10-27T10:00:00Z")
    static let usage = ["--print", "/usage", "--sandbox"]

    var on: BrimlineSettings {
        var settings = BrimlineSettings()
        settings.enabledProviders.append("gemini")
        return settings
    }

    /// Homes of the tests, kept until the end of the run (a test that drops its home would delete the folder).
    private static let keptHomes = Kept()

    /// A home with a fake `agy` (a few bytes, mode 0700) and a check that accepts it.
    func installed(mode: Int = 0o700) throws -> (home: TemporaryHome, checker: FakeChecker, account: Account) {
        let home = try TemporaryHome()
        Self.keptHomes.keep(home)
        try home.mkdir(".gemini")
        try home.write(".local/bin/agy", "not a real agy")
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: home.url.appendingPathComponent(".local/bin/agy").path)
        let account = Account(provider: .gemini, source: home.path(".gemini"), email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        return (home, FakeChecker(.accepted), account)
    }

    func ok(_ text: String = "", stderr: String = "", code: Int32 = 0) -> Result<AntigravityRun, AntigravityRunFailure> {
        .success(AntigravityRun(exitCode: code, stdout: Data(text.utf8), stderr: Data(stderr.utf8)))
    }

    /// Answers `--print /usage --sandbox` only: any other launch (`--version` included) fails and is recorded.
    func runner(usage: Result<AntigravityRun, AntigravityRunFailure>, delayMilliseconds: UInt64 = 0) -> FakeAntigravity {
        FakeAntigravity([Self.usage: usage], delayMilliseconds: delayMilliseconds)
    }

    /// A reader with no pause before the new try.
    func reader(_ fake: FakeAntigravity, _ checker: FakeChecker, owner: uid_t = getuid()) -> GeminiReader {
        GeminiReader(runner: fake, checker: checker, binaryOwner: owner, retryDelay: 0)
    }

    func text(_ name: String) throws -> String { String(decoding: try fixture(name, extension: "txt"), as: UTF8.self) }

    @Test("Without agy at its path, the card says the sentence and nothing is launched")
    func noAgy() async throws {
        let home = try TemporaryHome()
        Self.keptHomes.keep(home)
        try home.mkdir(".gemini")
        let account = Account(provider: .gemini, source: home.path(".gemini"), email: nil, organization: nil,
                              seatTier: nil, keychainService: nil)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let checker = FakeChecker(.accepted)
        let reader = GeminiReader(runner: fake, checker: checker)
        guard case .notReadable(.consumerPlan) = await reader.read(account: account, now: now) else {
            Issue.record("expected the sentence")
            return
        }
        #expect(fake.launches.isEmpty && checker.checks == 0)
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

    // MARK: a build signed by Google

    @Test("A build signed by Google: one launch, --print /usage --sandbox and nothing else (no --version); each line is a limit, the percentage remaining becomes the share used")
    func reads() async throws {
        let (home, checker, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        guard case .limits(let limits, _) = await reader(fake, checker).read(account: account, now: now) else {
            Issue.record("expected limits")
            return
        }
        let agy = AntigravityBinary.url(home: home.url).path
        #expect(fake.launches == [
            .init(binary: agy, arguments: ["--print", "/usage", "--sandbox"], home: home.path("")),
        ])
        #expect(checker.checked == [AntigravityBinary.url(home: home.url)])
        #expect(limits.map(\.model) == ["Gemini Models", "Gemini Models", "Claude and GPT models", "Claude and GPT models", "Gemini 4 Argon"])
        #expect(limits.map(\.windowSeconds) == [604_800, 18_000, 604_800, 18_000, 604_800])
        // The text says what remains (64 %, 90 %, 100 %, 100 %, 75 %): the card shows what is used.
        #expect(limits.map(\.percent) == [36, 10, 0, 0, 25])
        #expect(limits.map(\.kind) == Array(repeating: .model, count: 5))
        #expect(limits[0].resetsAt == date("2026-11-03T18:10:18Z"))
        #expect(limits[1].resetsAt == date("2026-10-27T23:10:18Z"))
        #expect(limits.allSatisfy { $0.label == nil })
    }

    @Test("The service keeps them, ok and with no note, and the card names each window and group")
    func namesInTheCard() async throws {
        let (_, checker, account) = try installed()
        let service = UsageService(readers: [reader(runner(usage: ok(try text("antigravity-usage-normal"))), checker)])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        #expect(usage.status == .ok && usage.note == nil)
        #expect(usage.limits.count == 5)
        let en = Strings(.en), fr = Strings(.fr)
        #expect(usage.limits.map { en.limitName($0, provider: .gemini) } == [
            "Week · Gemini Models", "5 h · Gemini Models", "Week · Claude and GPT models", "5 h · Claude and GPT models",
            "Week · Gemini 4 Argon",
        ])
        #expect(fr.limitName(usage.limits[0], provider: .gemini) == "Semaine · Gemini Models")
    }

    @Test("A model's own limit (Gemini 4 Argon Weekly Limit) is the limit of that model: an agent can ask for it by name")
    func ownLimitOfAModel() async throws {
        let (_, checker, account) = try installed()
        let service = UsageService(readers: [reader(runner(usage: ok(try text("antigravity-usage-normal"))), checker)])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        let best = try #require(Ranking.rank([usage], window: .any, model: "gemini 4 argon", now: now).first)
        #expect(best.headroom == 75)
        #expect(best.bindingLimit?.model == "Gemini 4 Argon")
    }

    // MARK: the guards of the launch

    @Test("A build of Google's that no list has ever seen: read, no entry to add (the point of the check by signature)")
    func anyBuildOfGoogleIsRead() async throws {
        let (home, checker, account) = try installed()
        let path = AntigravityBinary.url(home: home.url)
        for build in ["agy 1.4.11", "agy 1.4.12", "agy 2.0.0"] {
            try Data(build.utf8).write(to: path)
            let fake = runner(usage: ok(try text("antigravity-usage-normal")))
            guard case .limits(let limits, _) = await reader(fake, checker).read(account: account, now: now) else {
                Issue.record("expected limits for \(build)")
                return
            }
            #expect(limits.map(\.percent) == [36, 10, 0, 0, 25])
            #expect(fake.launches.map(\.arguments) == [Self.usage])
        }
    }

    @Test("A program that does not carry Google's signature (unsigned, other team, other identifier, unreadable) is not launched: unavailable, never format_changed")
    func signatureRefused() async throws {
        let cases: [(AntigravitySignatureCheck, Bool, String)] = [
            (.unsigned, false, "agy signature not recognized"),
            (.requirementFailed, false, "agy signature not recognized"),
            (.requirementFailed, true, "agy signature: other identifier"),
            (.unreadable, false, "agy signature unreadable"),
        ]
        for (answer, otherIdentifier, detail) in cases {
            let (_, _, account) = try installed()
            let checker = FakeChecker(answer)
            checker.otherIdentifier = otherIdentifier
            let fake = runner(usage: ok(try text("antigravity-usage-normal")))
            let reading = await reader(fake, checker).read(account: account, now: now)
            guard case .refused(.signatureNotRecognized, detail) = reading else {
                Issue.record("expected the refusal \(detail) for \(answer), got \(reading)")
                continue
            }
            #expect(fake.launches.isEmpty)
            #expect(checker.checks == 1)
        }
    }

    @Test("The refusal reaches the app, brimline status and the JSON for agents: unavailable, reason signature_not_recognized, the sentence in both languages, a growing delay")
    func refusalInEveryOutput() async throws {
        let (_, _, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let service = UsageService(readers: [reader(fake, FakeChecker(.requirementFailed))])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        #expect(usage.status == .unavailable)
        #expect(usage.reason == .signatureNotRecognized)
        #expect(usage.detail == "agy signature not recognized")
        #expect(usage.failureCount == 1 && usage.retryAfter != nil)
        #expect(fake.launches.isEmpty)

        #expect(Strings(.en).message(for: usage) == "Brimline does not recognize Google's signature on agy (~/.local/bin/agy), so it does not launch it.")
        #expect(Strings(.fr).message(for: usage) == "Brimline ne reconnaît pas la signature de Google sur agy (~/.local/bin/agy) : il ne le lance pas.")

        // The JSON for agents and `brimline status --json`.
        let entry = AgentAccount(usage, settings: on, now: now, home: URL(fileURLWithPath: "/nonexistent"))
        #expect(entry.status == "unavailable" && entry.reason == "signature_not_recognized")

        // A later good read clears the reason.
        let (_, _, good) = try installed()
        let again = await UsageService(readers: [reader(runner(usage: ok(try text("antigravity-usage-normal"))), FakeChecker(.accepted))])
            .refresh(account: good, settings: on, previous: usage, now: now.addingTimeInterval(3_600), force: true)
        #expect(again.status == .ok && again.reason == nil && again.detail == nil)
    }

    @Test("agy replaced while it is checked (an update in place): one new try after a pause, in the same read, then it is launched once")
    func updateDuringCheckThenAccepted() async throws {
        let (_, _, account) = try installed()
        let checker = FakeChecker(.changedDuringCheck, .accepted)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        guard case .limits(let limits, _) = await reader(fake, checker).read(account: account, now: now) else {
            Issue.record("expected limits")
            return
        }
        #expect(limits.count == 5)
        #expect(checker.checks == 2)
        #expect(fake.launches.count == 1)
    }

    @Test("Changed during the check twice: refused, and nothing is launched. Only one new try, never more")
    func updateDuringCheckTwice() async throws {
        let (_, _, account) = try installed()
        let checker = FakeChecker(.changedDuringCheck)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let reading = await reader(fake, checker).read(account: account, now: now)
        guard case .refused(.signatureNotRecognized, _) = reading else {
            Issue.record("expected the refusal, got \(reading)")
            return
        }
        #expect(checker.checks == 2)
        #expect(fake.launches.isEmpty)
    }

    @Test("A file replaced after the file checks and before the end of the signature check (new size or date): checked again, then launched once")
    func fileReplacedDuringCheck() async throws {
        let (home, _, account) = try installed()
        let path = AntigravityBinary.url(home: home.url)
        let checker = FakeChecker(.accepted)
        checker.duringCheck = { index in
            // Only the first check is interrupted: the update lands during it.
            if index == 0 { try? Data("an updated agy, a longer file".utf8).write(to: path) }
        }
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        guard case .limits = await reader(fake, checker).read(account: account, now: now) else {
            Issue.record("expected limits")
            return
        }
        #expect(checker.checks == 2)
        #expect(fake.launches.count == 1)
    }

    @Test("The registry's Gemini reader checks Google's signature, with the exact requirement")
    func registryReaderChecksGoogle() throws {
        let reader = try #require(Providers.all.compactMap { $0 as? GeminiReader }.first)
        let checker = try #require(reader.checker as? SecurityFrameworkCodeChecker)
        #expect(checker.requirement == SecurityFrameworkCodeChecker.google)
        #expect(reader.allowedURLs.isEmpty)
        #expect(reader.minimumReadInterval == 15 * 60)
        #expect(GeminiReader.updateRetryDelay == 2)
    }

    @Test("No test builds the reader on the real home folder: each one gives its own (the CI may run on a Mac that has a real agy)")
    func neverTheRealHome() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("Antigravity") && $0.hasSuffix("Tests.swift") && $0 != "AntigravitySignatureTests.swift" }
        #expect(files.count >= 3)
        for file in files {
            let source = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            // The only mention is the guard of `FakeChecker`, which refuses the real path.
            let mentions = source.components(separatedBy: "homeDirectoryFor" + "CurrentUser").count - 1
            #expect(mentions == (file == "AntigravityTests.swift" ? 1 : 0), "\(file)")
            #expect(!source.contains("NSHome" + "Directory()") || file == "AntigravityTests.swift", "\(file)")
        }
    }

    @Test("A link, a file of someone else, a file others can write, a file that cannot run: refused, nothing launched")
    func refusedBinaries() async throws {
        // A link (even one that points at a good file).
        let (home, checker, account) = try installed()
        let target = home.url.appendingPathComponent("real-agy")
        let path = AntigravityBinary.url(home: home.url)
        try FileManager.default.moveItem(at: path, to: target)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        guard case .failure(.unavailable, "agy refused", _) = await reader(fake, checker).read(account: account, now: now) else {
            Issue.record("a link must be refused")
            return
        }
        #expect(fake.launches.isEmpty)

        // Owner: the file belongs to another user id than the one expected.
        let (_, checker2, account2) = try installed()
        let other = runner(usage: ok(try text("antigravity-usage-normal")))
        let wrongOwner = reader(other, checker2, owner: getuid() &+ 1)
        guard case .failure(.unavailable, "agy refused", _) = await wrongOwner.read(account: account2, now: now) else {
            Issue.record("a file of someone else must be refused")
            return
        }
        #expect(other.launches.isEmpty)

        // Writable by the group, or not executable.
        for mode in [0o770, 0o602, 0o600] {
            let (_, checker3, account3) = try installed(mode: mode)
            let fake3 = runner(usage: ok(try text("antigravity-usage-normal")))
            guard case .failure(.unavailable, "agy refused", _) = await reader(fake3, checker3).read(account: account3, now: now) else {
                Issue.record("mode \(String(mode, radix: 8)) must be refused")
                return
            }
            #expect(fake3.launches.isEmpty)
        }
    }

    // MARK: what comes back

    @Test("A report that is not the expected one is format_changed, never a number")
    func unexpectedReports() async throws {
        let line = "Gemini Models\tFive Hour Limit Remaining\t42%\t2026-10-27T15:00:00Z"
        let cases = [
            try text("antigravity-usage-hostile"),
            try text("antigravity-usage-model-line"),
            try text("antigravity-usage-three-columns"),
            try text("antigravity-usage-out-of-bounds"),
            try text("antigravity-usage-empty"),
            "",
            "   \n\n",
            "I am sorry, I cannot run /usage.\n" + line + "\n",
            "Model quotas\n" + line + "\n",
            "Gemini 3.1 Pro: 42% used\n",
            line + "\n" + line + "\n",
            line + " \u{1B}[31m\n",
            (0..<60).map { "Model \($0)\tFive Hour Limit Remaining\t1%\t2026-10-27T15:00:00Z" }.joined(separator: "\n"),
        ]
        let (_, checker, account) = try installed()
        for report in cases {
            let reader = reader(runner(usage: ok(report)), checker)
            guard case .failure(.formatChanged, _, _) = await reader.read(account: account, now: now) else {
                Issue.record("expected format_changed for: \(report.prefix(60))")
                continue
            }
        }
        // Not UTF-8 at all.
        let binary = AntigravityRun(exitCode: 0, stdout: Data([0x4D, 0xFF, 0xFE, 0x0A]), stderr: Data())
        guard case .failure(.formatChanged, _, _) = await reader(runner(usage: .success(binary)), checker)
            .read(account: account, now: now) else {
            Issue.record("expected format_changed for bytes")
            return
        }
    }

    @Test("An output that is too long, a launch that fails, a delay that runs out: nothing is read")
    func runnerFailures() async throws {
        let (_, checker, account) = try installed()
        let tooLong = reader(runner(usage: .failure(.outputTooLong)), checker)
        guard case .failure(.formatChanged, _, _) = await tooLong.read(account: account, now: now) else {
            Issue.record("expected format_changed")
            return
        }
        let slow = reader(runner(usage: .failure(.timedOut)), checker)
        guard case .failure(.unavailable, _, _) = await slow.read(account: account, now: now) else {
            Issue.record("expected unavailable")
            return
        }
        let broken = reader(runner(usage: .failure(.couldNotLaunch)), checker)
        guard case .failure(.unavailable, _, _) = await broken.read(account: account, now: now) else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test("A non-zero exit, or \"authentication required\": the sign-in expired, said in words")
    func expired() async throws {
        let (_, checker, account) = try installed()
        for answer in [ok("", stderr: "error: authentication required", code: 1),
                       ok(try text("antigravity-usage-normal"), stderr: "Authentication required"),
                       ok("", code: 3)] {
            let reader = reader(runner(usage: answer), checker)
            guard case .expired = await reader.read(account: account, now: now) else {
                Issue.record("expected expired")
                return
            }
        }
        let usage = AccountUsage(account: account, status: .expired)
        #expect(Strings(.en).message(for: usage) == "Open Antigravity to refresh the sign-in.")
        #expect(Strings(.fr).message(for: usage) == "Ouvrez Antigravity pour rafraîchir la connexion.")
        let changed = AccountUsage(account: account, status: .formatChanged)
        #expect(Strings(.en).message(for: changed) == "Google changed the /usage report: update Brimline.")
        #expect(Strings(.fr).message(for: changed) == "Google a changé le rapport /usage : mettez Brimline à jour.")
    }

    // MARK: how often, and when it is off

    @Test("Never two launches in 15 minutes, forced or not; a new read after")
    func every15Minutes() async throws {
        let (_, checker, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let service = UsageService(readers: [reader(fake, checker)])

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
        let (_, checker, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")), delayMilliseconds: 300)
        let reader = reader(fake, checker)
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
        let (_, checker, account) = try installed()
        let fake = runner(usage: ok(try text("antigravity-usage-normal")))
        let service = UsageService(readers: [reader(fake, checker)])
        let off = await service.refresh(account: account, settings: BrimlineSettings(), previous: nil, now: now, force: true)
        #expect(off.status == .pending && off.checkedAt == nil)
        var unread = on
        unread.unreadAccounts = [account.id]
        let skipped = await service.refresh(account: account, settings: unread, previous: nil, now: now, force: true)
        #expect(skipped.status == .pending && skipped.checkedAt == nil)
        #expect(fake.launches.isEmpty)
        #expect(Providers.discover(readers: [reader(fake, checker)], home: URL(fileURLWithPath: "/nonexistent"),
                                   settings: BrimlineSettings()).isEmpty)
    }

    @Test("Nothing of the report but the group names, the windows, the percentages and the reset times is kept")
    func nothingElseKept() async throws {
        let (_, checker, account) = try installed()
        let service = UsageService(readers: [reader(runner(usage: ok(try text("antigravity-usage-normal"))), checker)])
        let usage = await service.refresh(account: account, settings: on, previous: nil, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(usage), as: UTF8.self)
        #expect(!json.contains("Limit Remaining") && !json.contains("Weekly Limit"))
        #expect(usage.responseShape == nil)
        #expect(usage.limits.count == 5)
    }

    @Test("No long dash in the new sentences")
    func noLongDash() {
        for language in [Language.en, .fr] {
            let s = Strings(language)
            for text in [s.geminiExpiredMessage, s.geminiFormatChangedMessage, s.geminiSignatureNotRecognizedMessage,
                         s.resetNotPublishedMessage] {
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
