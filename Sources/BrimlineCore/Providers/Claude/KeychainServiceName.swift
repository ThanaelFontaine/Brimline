import CryptoKit
import Foundation

/// Name of the Keychain item where Claude Code keeps the sign-in of a configuration folder.
///
/// Claude Code stores the default folder (`~/.claude`) under "Claude Code-credentials". A folder
/// chosen with the `CLAUDE_CONFIG_DIR` variable gets a suffix: the first eight hexadecimal
/// characters of the SHA-256 of the folder's absolute path. This was observed on the Claude Code
/// versions of October 2026; it is not documented and may change.
public enum KeychainServiceName {
    public static let base = "Claude Code-credentials"

    public static func forConfigDir(_ path: String, isDefault: Bool) -> String {
        if isDefault { return base }
        return "\(base)-\(hashPrefix(of: normalize(path)))"
    }

    /// First eight hexadecimal characters of the SHA-256 of `path`.
    public static func hashPrefix(of path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Absolute path, `~` expanded, `.` and `..` resolved, no trailing slash.
    public static func normalize(_ path: String) -> String {
        // URL.standardized resolves "." and "..", without the "/private" rewriting of
        // NSString.standardizingPath, so the path stays the one Claude Code hashed.
        var p = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
