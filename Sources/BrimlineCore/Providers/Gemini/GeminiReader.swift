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
/// - only a build listed in `AntigravityTrust` (SHA-256 of the binary and the text of `--version`): any
///   other build says `format_changed` and launches nothing;
/// - fixed arguments, a new empty working folder, a reduced environment, 20 seconds, 64 KiB
///   (`ProcessAntigravityRunner`), one run at a time and one read every 15 minutes at
///   most (`minimumReadInterval`, applied by the service);
/// - the report is read strictly (`AntigravityUsageParser`): anything else is `format_changed`.
///
/// Without `agy` at that path the card says the sentence (`not_readable`), as before. `~/.gemini` is
/// only looked for (one `stat`), nothing inside it is ever opened or listed.
public struct GeminiReader: ProviderReader {
    public var runner: any AntigravityRunning
    public var trust: AntigravityTrust
    /// The user id `agy` must belong to; the user's own (tests change it).
    public var binaryOwner: uid_t
    /// One launch at a time per reader (the app has one: its timer and a manual refresh can overlap).
    private let launching = Launching()

    /// At most one read every 15 minutes: `/usage` asks Google's backend each time.
    public static let readInterval: TimeInterval = 15 * 60

    /// Arguments of the two launches. Fixed: never an option that skips permissions.
    static let versionArguments = ["--version"]
    static let usageArguments = ["--print", "/usage", "--sandbox"]

    public init(runner: any AntigravityRunning = ProcessAntigravityRunner(), trust: AntigravityTrust = .verified,
                binaryOwner: uid_t = getuid()) {
        self.runner = runner
        self.trust = trust
        self.binaryOwner = binaryOwner
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
        // No verified build: nothing is launched, and nothing is hashed.
        guard !trust.isEmpty else { return Self.updated("no verified Antigravity build") }

        let digest: String
        do throws(AntigravityBinary.Failure) {
            digest = try AntigravityBinary.inspect(at: binary, owner: binaryOwner)
        } catch {
            switch error {
            case .notFound: return .notReadable(reason: .consumerPlan)
            case .refused: return .failure(status: .unavailable, detail: "agy refused", retryAfter: nil)
            case .unreadable: return .failure(status: .unavailable, detail: "agy unreadable", retryAfter: nil)
            }
        }
        guard let entry = trust.entry(sha256: digest) else { return Self.updated("Antigravity build not verified") }

        guard launching.acquire() else {
            return .failure(status: .unavailable, detail: "already running", retryAfter: nil)
        }
        defer { launching.release() }

        let version: AntigravityRun
        do { version = try await runner.run(binary: binary, arguments: Self.versionArguments, home: home) }
        catch { return Self.failure(error) }
        guard version.exitCode == 0,
              Self.text(version.stdout) == entry.versionOutput else { return Self.updated("Antigravity version not verified") }

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
            return Self.updated("unknown report")
        }
    }

    private static func updated(_ detail: String) -> ProviderReading {
        .failure(status: .formatChanged, detail: detail, retryAfter: nil)
    }

    private static func failure(_ error: AntigravityRunFailure) -> ProviderReading {
        switch error {
        case .couldNotLaunch: return .failure(status: .unavailable, detail: "agy could not start", retryAfter: nil)
        case .timedOut: return .failure(status: .unavailable, detail: "agy timed out", retryAfter: nil)
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
