import Foundation

/// The builds of Antigravity (`agy`) that Brimline has checked, one entry per build.
///
/// A build is trusted only when BOTH its SHA-256 (of the binary, as it is on disk) and the exact
/// text of `agy --version` match an entry. Antigravity updates itself: a build that is not listed
/// is never launched with `/usage`, and Brimline says "Antigravity was updated: update Brimline."
/// (`format_changed`) instead of guessing.
///
/// **The list is empty for now.** The text of `/usage` is not documented by Google, so the first
/// entry is added only at the real try (R4 of QUOTA-35), together with the real first line of the
/// report (`AntigravityUsageParser.expectedFirstLine`). Until then Gemini answers `format_changed`
/// and no program is launched: honest by default.
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

    /// The builds verified on a real account. Empty until R4.
    public static let verified = AntigravityTrust(entries: [])

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(sha256: String) -> Entry? {
        entries.first { $0.sha256 == sha256 }
    }
}
