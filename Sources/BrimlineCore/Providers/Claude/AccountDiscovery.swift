import Foundation

/// Finds the Claude Code accounts of the Mac by reading their configuration folders.
///
/// Rules: `~/.claude` (its settings file is `~/.claude.json`), then every `~/.claude-*` folder
/// that contains a `.claude.json`, then the folders added by hand, then the Claude Code reports
/// (`brimline report claude`) of addresses no folder has. Nothing secret is read here, and of the
/// reports only the names are listed.
public struct AccountDiscovery: Sendable {
    public var home: URL
    public var extraFolders: [String]
    /// The folder of the Claude Code reports; nil reads none.
    public var reportsDirectory: URL?
    /// How the identity of a folder is read from its settings file: the only file this discovery opens (tests count
    /// the calls).
    var identityOf: @Sendable (String) -> Identity? = AccountDiscovery.readIdentity(configFile:)

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, extraFolders: [String] = [],
                reportsDirectory: URL? = nil) {
        self.home = home
        self.extraFolders = extraFolders
        self.reportsDirectory = reportsDirectory
    }

    init(home: URL, extraFolders: [String] = [], reportsDirectory: URL? = nil,
         identityOf: @escaping @Sendable (String) -> Identity?) {
        self.init(home: home, extraFolders: extraFolders, reportsDirectory: reportsDirectory)
        self.identityOf = identityOf
    }

    /// "Do not read" closes the report of an address: the addresses in `closedReports` (marks kept by address) and
    /// the address of every folder whose id is in `unreadAccounts`. A closed report is never linked to a folder, and
    /// is listed as an account of its own only when no folder has the address (that account is marked too).
    ///
    /// A folder whose id is in `unreadAccounts` is found by the existence of its path only (`stat`): its settings
    /// file is not opened, and its address, organization and plan are those of `lastKnown` (the accounts of the
    /// cache, by id), nothing when the cache never knew it.
    public func discover(closedReports: Set<String> = [], unreadAccounts: Set<String> = [],
                         lastKnown: [String: Account] = [:]) -> [Account] {
        let folders = discoverFolders(unreadAccounts: unreadAccounts, lastKnown: lastKnown)
        guard let reportsDirectory else { return folders }
        var closed = closedReports
        for folder in folders where unreadAccounts.contains(folder.id) {
            if let email = folder.claudeReportEmail { closed.insert(email) }
        }
        return Self.merge(folders: folders, reports: ClaudeReportStore(directory: reportsDirectory).list(), closed: closed)
    }

    /// Links each report to the folders signed in with its address (case does not matter), and adds one account
    /// for each report no folder has, after the folders, by address. Such an account has no Keychain item: its
    /// numbers come from its report only. A closed address is linked to no folder.
    public static func merge(folders: [Account], reports: [(email: String, file: URL)],
                             closed: Set<String> = []) -> [Account] {
        var accounts = folders
        var withFolder = Set<String>()
        for report in reports {
            for index in accounts.indices where accounts[index].claudeReportEmail == report.email {
                if !closed.contains(report.email) { accounts[index].claudeReport = report.file.path }
                withFolder.insert(report.email)
            }
        }
        for report in reports.sorted(by: { $0.email < $1.email }) where !withFolder.contains(report.email) {
            accounts.append(.claudeReportOnly(email: report.email, file: report.file.path))
        }
        return accounts
    }

    func discoverFolders(unreadAccounts: Set<String> = [], lastKnown: [String: Account] = [:]) -> [Account] {
        var accounts: [Account] = []
        var seen = Set<String>()
        let fm = FileManager.default
        let defaultDir = KeychainServiceName.normalize(home.appendingPathComponent(".claude").path)

        func add(_ dir: String, configFile: String?, byHand: Bool) {
            let dir = KeychainServiceName.normalize(dir)
            guard !seen.contains(dir) else { return }
            seen.insert(dir)
            let identity: Identity?
            if unreadAccounts.contains(Account.id(source: dir)) {
                // "Do not read": the file is not opened, the identity is the last one known.
                identity = lastKnown[Account.id(source: dir)].map {
                    Identity(email: $0.email, organization: $0.organization, seatTier: $0.seatTier)
                }
            } else {
                identity = configFile.flatMap(identityOf)
            }
            let isDefault = dir == defaultDir
            accounts.append(Account(
                source: dir,
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
        // The file belongs to another program: what it says about the account is filtered before Brimline
        // keeps it (an agent and a terminal read it later, see `ProviderText.identity`).
        return Identity(email: ProviderText.address(account.emailAddress),
                        organization: ProviderText.identity(account.organizationName),
                        seatTier: ProviderText.identity(account.seatTier))
    }
}
