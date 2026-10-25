import Foundation

/// The only part of a Claude Code sign-in that Sightglass uses: the access token and its expiry.
///
/// The Keychain item also holds a refresh token. It is never decoded into a field, never used,
/// and Sightglass never renews anything. The value lives in memory for one request only.
public struct ClaudeCredential: Sendable {
    public var accessToken: String
    public var expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    /// Decodes the Keychain value. Only `accessToken` and `expiresAt` (milliseconds) are read.
    public static func decode(_ data: Data) -> ClaudeCredential? {
        struct Item: Decodable {
            struct OAuth: Decodable {
                var accessToken: String?
                var expiresAt: Double?
            }
            var claudeAiOauth: OAuth?
        }
        guard let item = try? JSONDecoder().decode(Item.self, from: data),
              let oauth = item.claudeAiOauth,
              let token = oauth.accessToken, !token.isEmpty else { return nil }
        let expiry = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCredential(accessToken: token, expiresAt: expiry)
    }
}

public enum CredentialError: Error, Equatable, Sendable {
    /// No item with this service name.
    case notFound
    /// The item exists but its value is not a Claude Code sign-in.
    case unreadable
    /// The `security` tool failed: its exit code, -1 when it could not start, -2 when it did not
    /// finish within the timeout (it is then stopped).
    case toolFailed(Int32)
}

/// Reads the sign-in of one account. A protocol, so tests can supply fake credentials.
public protocol CredentialReading: Sendable {
    func readCredential(service: String) throws(CredentialError) -> ClaudeCredential
}

/// Reads a Keychain item with `/usr/bin/security find-generic-password -s <service> -w`.
///
/// Why the `security` tool and not the Security framework: Claude Code creates and reads these
/// items itself through `security`, so the tool is already on the items' access list. Reading
/// through it grants nothing new and shows no prompt. The framework would ask once per item,
/// and again after every ad hoc build of the app.
///
/// The service name is always exact: the reader never lists or searches the Keychain. The
/// value goes from the tool's output pipe straight to the decoder, never to a log or a file.
public struct SecurityToolCredentialReader: CredentialReading {
    public static let defaultToolPath = "/usr/bin/security"
    public var toolPath: String
    public var timeout: TimeInterval

    /// `toolPath` is only changed by tests, to stand in a slow or failing tool.
    public init(timeout: TimeInterval = 60, toolPath: String = Self.defaultToolPath) {
        self.timeout = timeout
        self.toolPath = toolPath
    }

    public func readCredential(service: String) throws(CredentialError) -> ClaudeCredential {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw .toolFailed(-1) }

        // The output is read on another thread, so a large value never blocks on a full pipe and
        // the wait below is bounded by the timeout even when the tool never ends.
        let collected = CollectedOutput()
        let handle = output.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            collected.finish(with: handle.readDataToEndOfFile())
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw .toolFailed(-2)
        }
        guard let data = collected.wait(timeout: 5) else { throw .toolFailed(-2) }
        switch process.terminationStatus {
        case 0:
            guard let credential = ClaudeCredential.decode(data) else { throw .unreadable }
            return credential
        case 44:
            // The exit code `security` returns when no item has this service name.
            throw .notFound
        default:
            throw .toolFailed(process.terminationStatus)
        }
    }
}

/// The tool's output, handed from the reading thread to the caller.
private final class CollectedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var data: Data?

    func finish(with data: Data) {
        lock.withLock { self.data = data }
        done.signal()
    }

    func wait(timeout: TimeInterval) -> Data? {
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return lock.withLock { data }
    }
}
