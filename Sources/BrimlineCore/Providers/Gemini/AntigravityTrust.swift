import Foundation

/// The builds of Antigravity (`agy`) that Brimline has checked, one entry per build.
///
/// A build is trusted only when BOTH its SHA-256 (of the binary, as it is on disk) and the exact
/// text of `agy --version` match an entry. Antigravity updates itself: a build that is not listed
/// is never launched with `/usage`, and Brimline says "Antigravity was updated: update Brimline."
/// (`format_changed`) instead of guessing.
///
/// The text of `/usage` is not documented by Google: an entry is added only after the real try of that
/// build (`AntigravityUsageParser` reads the text of 1.4.8). A list with no entry (or a build that is not
/// on it) makes Gemini answer `format_changed` with no program launched: honest by default.
public struct AntigravityTrust: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        /// Lowercase hex SHA-256 of the `agy` binary.
        public var sha256: String
        /// The text `agy --version` prints, trimmed.
        public var versionOutput: String

        public init(sha256: String, versionOutput: String) {
            self.sha256 = sha256
            self.versionOutput = versionOutput
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The builds verified on a real account.
    /// - 1.4.8: seen on 27/10/2026 on the Mac mini (installer of antigravity.google/cli/install.sh), the binary
    ///   signed by the team `EQHXZ8M8AV`. Brimline does not check the signature: the SHA-256 is what is compared.
    public static let verified = AntigravityTrust(entries: [
        Entry(sha256: "09fcdd8554e03bed9b2ec936e454c7f115d5610610de09ed7d79fa2feae76940", versionOutput: "1.4.8"),
    ])

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(sha256: String) -> Entry? {
        entries.first { $0.sha256 == sha256 }
    }
}
