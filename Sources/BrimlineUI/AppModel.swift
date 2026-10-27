import AppKit
import Foundation
import Observation
import BrimlineCore

/// The state of the app: accounts, last numbers, settings. Every change of settings is saved.
@MainActor
@Observable
public final class AppModel {
    public private(set) var settings: BrimlineSettings
    public private(set) var accounts: [Account] = []
    public private(set) var snapshot: UsageSnapshot?
    public private(set) var isRefreshing = false
    public private(set) var launchAtLogin: Bool
    /// Moves with a timer so ages and "resets in" texts stay true while the panel is open.
    public private(set) var now: Date
    /// The selected tab of the settings window.
    public var settingsTab: SettingsTab = .accounts
    /// The text last copied from the Agents tab, to show "Copied" on its button for a moment.
    public private(set) var lastCopied: String?

    public let strings: Strings
    public let time: TimeFormatter
    @ObservationIgnored public var openSettingsAction: (() -> Void)?
    /// The icon shown in the About tab (the app's own icon, or the one given to the images).
    @ObservationIgnored public var appIcon: NSImage?

    @ObservationIgnored private let service: UsageService?
    @ObservationIgnored private let cache: UsageCache?
    @ObservationIgnored private let settingsStore: SettingsStore?
    @ObservationIgnored private let paths: BrimlinePaths
    @ObservationIgnored private let home: URL
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private let fixedNow: Date?

    /// The live model of the app.
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let paths = BrimlinePaths(home: home)
        self.paths = paths
        self.home = home
        service = UsageService()
        cache = UsageCache(file: paths.cacheFile)
        settingsStore = SettingsStore(file: paths.settingsFile)
        settings = SettingsStore(file: paths.settingsFile).load()
        snapshot = UsageCache(file: paths.cacheFile).load()
        launchAtLogin = LaunchAgent.isInstalled(paths: paths)
        strings = Strings()
        time = TimeFormatter()
        now = Date()
        fixedNow = nil
    }

    /// A model with fixed data, for the images of the documentation. It reads and writes nothing.
    public init(preview snapshot: UsageSnapshot?, settings: BrimlineSettings, now: Date,
                language: Language, timeZone: TimeZone, home: URL, launchAtLogin: Bool = false) {
        paths = BrimlinePaths(home: home)
        self.home = home
        service = nil
        cache = nil
        settingsStore = nil
        self.settings = settings
        self.snapshot = snapshot
        self.accounts = snapshot?.accounts.map(\.account) ?? []
        self.launchAtLogin = launchAtLogin
        strings = Strings(language)
        time = TimeFormatter(language: language, timeZone: timeZone)
        self.now = now
        fixedNow = now
    }

    // MARK: Lifecycle

    public func start() {
        guard service != nil, loop == nil else { return }
        rescan()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(force: false)
                let minutes = self?.settings.refreshMinutes ?? 5
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.now = Date()
            }
        }
    }

    /// Reads every account now. `force` ignores the growing delay after failures (the button).
    public func refresh(force: Bool) async {
        guard let service, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let accounts = self.accounts
        let previous = snapshot
        let result = await service.refresh(accounts: accounts, previous: previous, now: Date(), force: force)
        snapshot = result
        now = Date()
        try? cache?.save(result)
    }

    public func refreshNow() {
        Task { await refresh(force: true) }
    }

    /// Looks for the accounts again (new ~/.claude-* folder, folder added by hand).
    public func rescan() {
        accounts = AccountDiscovery(home: home, extraFolders: settings.extraFolders).discover()
        if var snap = snapshot {
            let ids = Set(accounts.map(\.id))
            snap.accounts.removeAll { !ids.contains($0.account.id) }
            for account in accounts where snap.usage(for: account.id) == nil {
                snap.accounts.append(AccountUsage(account: account))
            }
            snap.accounts.sort { a, b in
                (accounts.firstIndex { $0.id == a.account.id } ?? 0) < (accounts.firstIndex { $0.id == b.account.id } ?? 0)
            }
            snapshot = snap
        } else {
            snapshot = UsageSnapshot(generatedAt: Date(), accounts: accounts.map { AccountUsage(account: $0) })
        }
    }

    public func rescanAndRefresh() {
        rescan()
        Task { await refresh(force: true) }
    }

    // MARK: Derived state

    /// Every known account, in discovery order, with its last numbers.
    public var allUsages: [AccountUsage] { snapshot?.accounts ?? [] }

    public var visibleUsages: [AccountUsage] { allUsages.filter { !settings.isHidden($0.account.id) } }

    /// Level of the menu bar glyph: the visible limit closest to its ceiling.
    public var menuBarLevel: (percent: Double?, dimmed: Bool) {
        let visible = visibleUsages
        guard let top = Ranking.mostLoaded(visible, now: now) else { return (nil, false) }
        return (top.percent, top.usage.status != .ok)
    }

    public var lastUpdate: Date? { allUsages.compactMap(\.fetchedAt).max() }

    /// Numbers older than two refresh intervals are shown with their age.
    public var staleAfter: TimeInterval { TimeInterval(settings.refreshMinutes * 60 * 2 + 60) }

    public func title(for account: Account) -> String {
        settings.label(for: account.id) ?? account.email ?? account.folderName
    }

    public func subtitle(for account: Account) -> String? {
        if settings.label(for: account.id) != nil, let email = account.email { return email }
        let parts = [account.organization, account.seatTier?.capitalized].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Settings

    private func update(_ change: (inout BrimlineSettings) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        settings = s
        try? settingsStore?.save(s)
    }

    public func setHidden(_ hidden: Bool, accountID: String) {
        update { s in
            s.hiddenAccounts.removeAll { $0 == accountID }
            if hidden { s.hiddenAccounts.append(accountID) }
        }
    }

    /// Stored as typed (spaces included, so typing is not disturbed); trimmed when read.
    public func setLabel(_ label: String, accountID: String) {
        update { s in
            s.labels[accountID] = label.isEmpty ? nil : label
        }
    }

    public func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastCopied = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if self?.lastCopied == text { self?.lastCopied = nil }
        }
    }

    public func setRefreshMinutes(_ minutes: Int) {
        guard BrimlineSettings.refreshChoices.contains(minutes) else { return }
        update { $0.refreshMinutes = minutes }
        if service != nil {
            loop?.cancel()
            loop = nil
            clock?.cancel()
            clock = nil
            start()
        }
    }

    public func setShowPercent(_ show: Bool) {
        update { $0.showPercentInMenuBar = show }
    }

    public func addFolder(_ url: URL) {
        let path = KeychainServiceName.normalize(url.path)
        update { s in
            if !s.extraFolders.contains(path) { s.extraFolders.append(path) }
        }
        rescanAndRefresh()
    }

    public func removeFolder(_ path: String) {
        update { s in s.extraFolders.removeAll { $0 == path } }
        rescan()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        guard service != nil else { launchAtLogin = enabled; return }
        do {
            if enabled {
                try LaunchAgent.install(appPath: Bundle.main.bundlePath, paths: paths)
            } else {
                try LaunchAgent.remove(paths: paths)
            }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = LaunchAgent.isInstalled(paths: paths)
    }

    // MARK: Paths shown in the Agents tab

    /// Absolute path of the command: the ~/.local/bin link when install.sh made it, else the
    /// copy inside the app. Absolute, because MCP configuration files do not expand "~".
    public var commandPath: String {
        let link = home.appendingPathComponent(".local/bin/brimline").path
        // The images show the link install.sh creates, in the fictitious home folder.
        guard service != nil else { return link }
        if FileManager.default.fileExists(atPath: link) { return link }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/brimline").path
    }

    public var mcpAddCommand: String { "claude mcp add brimline -- \(shellQuoted(commandPath)) mcp" }

    public var mcpJSON: String {
        let escaped = commandPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "mcpServers": {
            "brimline": {
              "command": "\(escaped)",
              "args": ["mcp"]
            }
          }
        }
        """
    }

    private func shellQuoted(_ s: String) -> String {
        let safe = s.allSatisfy { $0.isLetter || $0.isNumber || "/._-+~".contains($0) }
        return safe ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public var cachePathForDisplay: String { "~/Library/Application Support/Brimline/usage.json" }

    public var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "0.0.0"
    }

    public func openSettings() { openSettingsAction?() }

    /// A folder as people write it: "~/.claude-work" for a folder of the home.
    public func displayPath(_ path: String) -> String {
        let h = KeychainServiceName.normalize(home.path)
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + path.dropFirst(h.count) }
        return path
    }
}
