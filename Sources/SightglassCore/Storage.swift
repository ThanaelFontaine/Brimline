import Foundation

/// Where Sightglass keeps its files: `~/Library/Application Support/Sightglass/`.
public struct SightglassPaths: Sendable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Sightglass", isDirectory: true)
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
    /// to 0700 and the temporary file is created in 0600 before any byte is written.
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(temporary.path, url.path) != 0 {
            let code = errno
            try? fm.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}

/// The usage cache: numbers only. Its type has no field able to hold a token.
public struct UsageCache: Sendable {
    public var file: URL

    public init(file: URL = SightglassPaths().cacheFile) {
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
public struct SightglassSettings: Codable, Sendable, Equatable {
    public static let refreshChoices = [2, 5, 10, 15]

    public var schemaVersion: Int = 1
    public var extraFolders: [String] = []
    public var hiddenAccounts: [String] = []
    public var labels: [String: String] = [:]
    public var refreshMinutes: Int = 5
    public var showPercentInMenuBar: Bool = false

    public init() {}

    public func isHidden(_ accountID: String) -> Bool { hiddenAccounts.contains(accountID) }

    public func label(for accountID: String) -> String? {
        guard let l = labels[accountID]?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else { return nil }
        return l
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SightglassSettings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        extraFolders = try c.decodeIfPresent([String].self, forKey: .extraFolders) ?? defaults.extraFolders
        hiddenAccounts = try c.decodeIfPresent([String].self, forKey: .hiddenAccounts) ?? defaults.hiddenAccounts
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? defaults.labels
        let minutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? defaults.refreshMinutes
        refreshMinutes = Self.refreshChoices.contains(minutes) ? minutes : defaults.refreshMinutes
        showPercentInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showPercentInMenuBar) ?? defaults.showPercentInMenuBar
    }
}

public struct SettingsStore: Sendable {
    public var file: URL

    public init(file: URL = SightglassPaths().settingsFile) {
        self.file = file
    }

    public func load() -> SightglassSettings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONCoding.decoder().decode(SightglassSettings.self, from: data) else {
            return SightglassSettings()
        }
        return settings
    }

    public func save(_ settings: SightglassSettings) throws {
        try JSONCoding.write(try JSONCoding.encoder().encode(settings), to: file)
    }
}

/// Opening at login: a LaunchAgent written and removed by the app.
public enum LaunchAgent {
    public static let label = "eu.thanaelfontaine.sightglass"

    public static func plist(appPath: String) -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", appPath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    public static func isInstalled(paths: SightglassPaths = SightglassPaths()) -> Bool {
        FileManager.default.fileExists(atPath: paths.launchAgentFile.path)
    }

    public static func install(appPath: String, paths: SightglassPaths = SightglassPaths()) throws {
        let url = paths.launchAgentFile
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist(appPath: appPath).write(to: url, options: [.atomic])
    }

    public static func remove(paths: SightglassPaths = SightglassPaths()) throws {
        let url = paths.launchAgentFile
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
