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
    /// The `security` tool failed (exit code), timed out, or was denied.
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
    public static let toolPath = "/usr/bin/security"
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    public func readCredential(service: String) throws(CredentialError) -> ClaudeCredential {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.toolPath)
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw .toolFailed(-1) }

        // Read while the tool runs, so a large value never blocks on a full pipe.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw .toolFailed(-2)
        }
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
