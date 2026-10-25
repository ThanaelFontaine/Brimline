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

/// Finds the Claude Code accounts of the Mac by reading their configuration folders.
///
/// Rules: `~/.claude` (its settings file is `~/.claude.json`), then every `~/.claude-*` folder
/// that contains a `.claude.json`, then the folders added by hand. Nothing secret is read here.
public struct AccountDiscovery: Sendable {
    public var home: URL
    public var extraFolders: [String]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, extraFolders: [String] = []) {
        self.home = home
        self.extraFolders = extraFolders
    }

    public func discover() -> [Account] {
        var accounts: [Account] = []
        var seen = Set<String>()
        let fm = FileManager.default
        let defaultDir = KeychainServiceName.normalize(home.appendingPathComponent(".claude").path)

        func add(_ dir: String, configFile: String?, byHand: Bool) {
            let dir = KeychainServiceName.normalize(dir)
            guard !seen.contains(dir) else { return }
            seen.insert(dir)
            let identity = configFile.flatMap(Self.readIdentity(configFile:))
            let isDefault = dir == defaultDir
            accounts.append(Account(
                configDir: dir,
                email: identity?.email,
                organization: identity?.organization,
                seatTier: identity?.seatTier,
                keychainService: KeychainServiceName.forConfigDir(dir, isDefault: isDefault),
                addedByHand: byHand
            ))
        }

        // 1. The default folder.
        if let file = defaultConfigFile() { add(defaultDir, configFile: file, byHand: false) }

        // 2. Every ~/.claude-* folder with a .claude.json, in a stable order.
        let names = (try? fm.contentsOfDirectory(atPath: home.path)) ?? []
        for name in names.sorted() where name.hasPrefix(".claude-") {
            let dir = home.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let file = dir.appendingPathComponent(".claude.json").path
            if fm.fileExists(atPath: file) { add(dir.path, configFile: file, byHand: false) }
        }

        // 3. Folders added by hand: listed even without a settings file, so the user sees them.
        for folder in extraFolders {
            let dir = KeychainServiceName.normalize(folder)
            if dir == defaultDir {
                add(dir, configFile: defaultConfigFile(), byHand: true)
            } else {
                let file = (dir as NSString).appendingPathComponent(".claude.json")
                add(dir, configFile: fm.fileExists(atPath: file) ? file : nil, byHand: true)
            }
        }
        return accounts
    }

    private func defaultConfigFile() -> String? {
        let fm = FileManager.default
        let candidates = [
            home.appendingPathComponent(".claude.json").path,
            home.appendingPathComponent(".claude/.claude.json").path,
        ]
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    struct Identity: Equatable {
        var email: String?
        var organization: String?
        var seatTier: String?
    }

    /// Reads `oauthAccount` from a Claude Code settings file. Other keys are ignored.
    static func readIdentity(configFile: String) -> Identity? {
        struct File: Decodable {
            struct OAuthAccount: Decodable {
                var emailAddress: String?
                var organizationName: String?
                var seatTier: String?
            }
            var oauthAccount: OAuthAccount?
        }
        guard let data = FileManager.default.contents(atPath: configFile),
              let file = try? JSONDecoder().decode(File.self, from: data),
              let account = file.oauthAccount else { return nil }
        return Identity(email: account.emailAddress.flatMap(nonEmpty),
                        organization: account.organizationName.flatMap(nonEmpty),
                        seatTier: account.seatTier.flatMap(nonEmpty))
    }

    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
