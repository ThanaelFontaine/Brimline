import Foundation

/// Where Brimline keeps its files: `~/Library/Application Support/Brimline/`.
public struct BrimlinePaths: Sendable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Brimline", isDirectory: true)
    }
    public var cacheFile: URL { supportDirectory.appendingPathComponent("usage.json") }
    public var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    public var launchAgentFile: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(LaunchAgent.label).plist")
    }
}

enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Writes atomically, readable by the user only, with no wider window: the folder is put back
    /// to 0700 and the temporary file is opened with `open(2)` in mode 0600 (`O_EXCL`, so never an
    /// existing file or a link), fixed with `fchmod` against the umask, then filled, synced and renamed.
    /// Any failure removes the temporary file and is thrown. With `replacing: false` the final
    /// step never replaces a file that is already there (`renamex_np` with `RENAME_EXCL`): the
    /// call throws `EEXIST` instead and the existing file is untouched.
    static func write(_ data: Data, to url: URL, replacing: Bool = true) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError(errno) }
        var closed = false
        func fail(_ code: Int32) -> POSIXError {
            if !closed { close(descriptor); closed = true }
            unlink(temporary.path)
            return posixError(code)
        }
        if fchmod(descriptor, 0o600) != 0 { throw fail(errno) }
        var failure: Int32?
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        if let failure { throw fail(failure) }
        if fsync(descriptor) != 0 { throw fail(errno) }
        closed = true
        if close(descriptor) != 0 { throw fail(errno) }
        let renamed = replacing ? rename(temporary.path, url.path)
                                : renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL))
        if renamed != 0 { throw fail(errno) }
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}

/// The usage cache: numbers only. Its type has no field able to hold a token.
public struct UsageCache: Sendable {
    public var file: URL

    public init(file: URL = BrimlinePaths().cacheFile) {
        self.file = file
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONCoding.decoder().decode(UsageSnapshot.self, from: data),
              snapshot.schemaVersion == UsageSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        try JSONCoding.write(try JSONCoding.encoder().encode(snapshot), to: file)
    }
}

/// Preferences shared by the app and the command (folders added by hand, hidden accounts...).
public struct BrimlineSettings: Codable, Sendable, Equatable {
    public static let refreshChoices = [2, 5, 10, 15]

    public var schemaVersion: Int = 1
    public var extraFolders: [String] = []
    /// Codex folders (`CODEX_HOME`) added by hand, besides `~/.codex`. Each is read for its `auth.json` only.
    public var extraCodexFolders: [String] = []
    public var hiddenAccounts: [String] = []
    public var labels: [String: String] = [:]
    public var refreshMinutes: Int = 5
    public var showPercentInMenuBar: Bool = false
    /// The providers Brimline may read (raw values of `Provider`). Claude only by default: a
    /// provider is off until the user turns it on, and nothing of it is touched before.
    public var enabledProviders: [String] = [Provider.claude.rawValue]
    /// The accounts the user marked "Do not read" (account ids). They keep their last numbers.
    public var unreadAccounts: [String] = []

    public init() {}

    public func isHidden(_ accountID: String) -> Bool { hiddenAccounts.contains(accountID) }

    public func isEnabled(_ provider: Provider) -> Bool { enabledProviders.contains(provider.rawValue) }

    public func isUnread(_ accountID: String) -> Bool { unreadAccounts.contains(accountID) }

    /// May Brimline read this account at all: its provider is on and the account is not "Do not read".
    public func mayRead(_ account: Account) -> Bool { isEnabled(account.provider) && !isUnread(account.id) }

    public func label(for accountID: String) -> String? {
        guard let l = labels[accountID]?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else { return nil }
        return l
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrimlineSettings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        extraFolders = try c.decodeIfPresent([String].self, forKey: .extraFolders) ?? defaults.extraFolders
        extraCodexFolders = try c.decodeIfPresent([String].self, forKey: .extraCodexFolders) ?? defaults.extraCodexFolders
        hiddenAccounts = try c.decodeIfPresent([String].self, forKey: .hiddenAccounts) ?? defaults.hiddenAccounts
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? defaults.labels
        let minutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? defaults.refreshMinutes
        refreshMinutes = Self.refreshChoices.contains(minutes) ? minutes : defaults.refreshMinutes
        showPercentInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showPercentInMenuBar) ?? defaults.showPercentInMenuBar
        // A file written before the providers has neither key: Claude stays on, as it was.
        enabledProviders = try c.decodeIfPresent([String].self, forKey: .enabledProviders) ?? defaults.enabledProviders
        unreadAccounts = try c.decodeIfPresent([String].self, forKey: .unreadAccounts) ?? defaults.unreadAccounts
    }
}

public struct SettingsStore: Sendable {
    public var file: URL

    public init(file: URL = BrimlinePaths().settingsFile) {
        self.file = file
    }

    public func load() -> BrimlineSettings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONCoding.decoder().decode(BrimlineSettings.self, from: data) else {
            return BrimlineSettings()
        }
        return settings
    }

    public func save(_ settings: BrimlineSettings) throws {
        try JSONCoding.write(try JSONCoding.encoder().encode(settings), to: file)
    }
}

/// Opening at login: a LaunchAgent written and removed by the app.
public enum LaunchAgent {
    public static let label = "eu.thanaelfontaine.brimline"

    public static func plist(appPath: String) -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", appPath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    public static func isInstalled(paths: BrimlinePaths = BrimlinePaths()) -> Bool {
        FileManager.default.fileExists(atPath: paths.launchAgentFile.path)
    }

    public static func install(appPath: String, paths: BrimlinePaths = BrimlinePaths()) throws {
        let url = paths.launchAgentFile
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist(appPath: appPath).write(to: url, options: [.atomic])
    }

    public static func remove(paths: BrimlinePaths = BrimlinePaths()) throws {
        let url = paths.launchAgentFile
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
