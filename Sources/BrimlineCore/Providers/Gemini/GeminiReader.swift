import Foundation

/// Gemini, through Antigravity (`agy`), Google's replacement of Gemini CLI for individual plans.
///
/// **The rule lifted for Gemini, in so many words:** Brimline launches Google's official command
/// `agy --print /usage`; Google's program may then renew its own sign-in. Brimline neither reads nor
/// writes that sign-in (it is in the Keychain, never touched), asks no Google address itself and
/// never presents itself as Antigravity. No other provider launches a program.
///
/// Everything that guards the launch lives here and in its helpers:
/// - only when Gemini is on (the service checks consent before any reader runs);
/// - only the exact path `~/.local/bin/agy` (`AntigravityBinary`: no `PATH`, no link, a file of the
///   user's, not writable by others);
/// - only a program that carries Google's Developer ID signature (team `EQHXZ8M8AV`, identifier `cli`),
///   checked by Security.framework just before the launch (`SecurityFrameworkCodeChecker`). There is no
///   list of builds: Antigravity updates itself, and a build signed by Google is read like the one before.
///   Any other program is `unavailable` ("signature not recognized") and is never launched. `--version` is
///   not launched: nothing depends on its text;
/// - fixed arguments, a new empty working folder, a reduced environment, 20 seconds, 64 KiB
///   (`ProcessAntigravityRunner`), one run at a time and one read every 15 minutes at
///   most (`minimumReadInterval`, applied by the service);
/// - the report is read strictly (`AntigravityUsageParser`): `format_changed` is the answer to a text
///   Brimline does not recognize, and to nothing else.
///
/// Without `agy` at that path the card says the sentence (`not_readable`), as before. `~/.gemini` is
/// only looked for (one `stat`), nothing inside it is ever opened or listed.
public struct GeminiReader: ProviderReader {
    public var runner: any AntigravityRunning
    /// Checks Google's signature before the launch. Tests give one that needs no certificate.
    public var checker: any AntigravityCodeChecking
    /// The user id `agy` must belong to; the user's own (tests change it).
    public var binaryOwner: uid_t
    /// One launch at a time per reader (the app has one: its timer and a manual refresh can overlap).
    private let launching = Launching()

    /// At most one read every 15 minutes: `/usage` asks Google's backend each time.
    public static let readInterval: TimeInterval = 15 * 60

    /// How long to wait before looking a second time, when `agy` was being replaced during the check.
    public static let updateRetryDelay: TimeInterval = 2

    /// Arguments of the launch. Fixed: never an option that skips permissions.
    static let usageArguments = ["--print", "/usage", "--sandbox"]

    /// Seconds to wait before the one new try (tests give 0).
    public var retryDelay: TimeInterval

    public init(runner: any AntigravityRunning = ProcessAntigravityRunner(),
                checker: any AntigravityCodeChecking = SecurityFrameworkCodeChecker(),
                binaryOwner: uid_t = getuid(), retryDelay: TimeInterval = GeminiReader.updateRetryDelay) {
        self.runner = runner
        self.checker = checker
        self.binaryOwner = binaryOwner
        self.retryDelay = retryDelay
    }

    public var provider: Provider { .gemini }
    /// Brimline asks no address itself: `agy` does.
    public var allowedURLs: [URL] { [] }
    public var minimumReadInterval: TimeInterval { Self.readInterval }

    /// One card when `~/.gemini` is a folder or `agy` is at its path. Both are only looked for.
    public func discover(home: URL, settings: BrimlineSettings) -> [Account] {
        let folder = KeychainServiceName.normalize(home.appendingPathComponent(".gemini").path)
        var isDirectory: ObjCBool = false
        let hasFolder = FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue
        guard hasFolder || AntigravityBinary.isPresent(at: AntigravityBinary.url(home: home)) else { return [] }
        return [Account(provider: .gemini, source: folder, email: nil, organization: nil, seatTier: nil,
                        keychainService: nil)]
    }

    public func read(account: Account, now: Date) async -> ProviderReading {
        // The card's source is `<home>/.gemini`: the home is its parent.
        let home = URL(fileURLWithPath: (account.source as NSString).deletingLastPathComponent)
        let binary = AntigravityBinary.url(home: home)

        guard AntigravityBinary.isPresent(at: binary) else { return .notReadable(reason: .consumerPlan) }

        // The file, then its signature. If `agy` was replaced while this ran (it updates itself in place:
        // a half written file, or another file than the one first checked), look once more after a pause.
        var verdict = await examine(binary)
        if case .retry = verdict {
            if retryDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000)) }
            verdict = await examine(binary)
        }
        switch verdict {
        case .go: break
        case .retry: return Self.refused("agy signature not recognized")
        case .answer(let reading): return reading
        }

        guard launching.acquire() else {
            return .failure(status: .unavailable, detail: "already running", retryAfter: nil)
        }
        defer { launching.release() }

        let usage: AntigravityRun
        do { usage = try await runner.run(binary: binary, arguments: Self.usageArguments, home: home) }
        catch { return Self.failure(error) }

        if usage.exitCode != 0 || Self.text(usage.stderr).localizedCaseInsensitiveContains("authentication required") {
            // Google's program asks for a new sign-in: it renews it itself when it is opened.
            return .expired
        }
        do {
            return .limits(try AntigravityUsageParser.parse(usage.stdout), shape: "")
        } catch {
            return Self.reportChanged("unknown report")
        }
    }

    private enum Examination {
        /// The file is as it must be and Google signed it: launch.
        case go
        /// Looks like an update in progress: once more, then refuse.
        case retry
        /// Done: this is the reading to give.
        case answer(ProviderReading)
    }

    /// The checks on the file, then the signature, with a look at the file after the signature check.
    private func examine(_ binary: URL) async -> Examination {
        let before: AntigravityBinary.Identity
        do throws(AntigravityBinary.Failure) {
            before = try AntigravityBinary.inspect(at: binary, owner: binaryOwner)
        } catch {
            switch error {
            case .notFound: return .answer(.notReadable(reason: .consumerPlan))
            case .refused: return .answer(.failure(status: .unavailable, detail: "agy refused", retryAfter: nil))
            case .unreadable: return .answer(.failure(status: .unavailable, detail: "agy unreadable", retryAfter: nil))
            }
        }
        let signature = checker.checkStatic(at: binary)
        let after = try? AntigravityBinary.inspect(at: binary, owner: binaryOwner)
        if signature == .changedDuringCheck || after != before { return .retry }
        switch signature {
        case .accepted: return .go
        case .unsigned, .requirementFailed:
            let other = signature == .requirementFailed && checker.isOtherIdentifier(at: binary)
            return .answer(Self.refused(other ? "agy signature: other identifier" : "agy signature not recognized"))
        case .unreadable: return .answer(Self.refused("agy signature unreadable"))
        case .changedDuringCheck: return .retry
        }
    }

    /// Brimline does not launch this program: `unavailable`, never `format_changed` (the text was not read).
    private static func refused(_ detail: String) -> ProviderReading {
        .refused(reason: .signatureNotRecognized, detail: detail)
    }

    /// The text of the report is not the one Brimline reads.
    private static func reportChanged(_ detail: String) -> ProviderReading {
        .failure(status: .formatChanged, detail: detail, retryAfter: nil)
    }

    private static func failure(_ error: AntigravityRunFailure) -> ProviderReading {
        switch error {
        case .couldNotLaunch: return .failure(status: .unavailable, detail: "agy could not start", retryAfter: nil)
        case .timedOut: return .failure(status: .unavailable, detail: "agy timed out", retryAfter: nil)
        // More than 64 KiB is a text Brimline refuses to read: the only other way to `format_changed`.
        case .outputTooLong: return .failure(status: .formatChanged, detail: "agy output too long", retryAfter: nil)
        }
    }

    private static func text(_ data: Data) -> String {
        (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class Launching: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    func acquire() -> Bool { lock.withLock { if busy { return false }; busy = true; return true } }
    func release() { lock.withLock { busy = false } }
}
