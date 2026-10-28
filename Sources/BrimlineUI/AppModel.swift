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
    /// The accounts whose "Learn more" is open in the panel (the rest of a "not readable" sentence).
    public private(set) var expandedNotes: Set<String> = []
    /// The apps of the Menu Bar tab that are installed (read again each time the tab opens).
    public private(set) var menuBarApps: [InstalledMenuBarApp] = []
    /// The app that did not open at the last try, for the note under its row.
    public private(set) var menuBarAppFailed: MenuBarApp?
    /// How the last "Open System Settings" ended, for the note under its button.
    public private(set) var menuBarSystemOutcome: MenuBarTidy.SettingsOutcome?
    /// The icons placed left of Brimline's bar are hidden now (QUOTA-73). Always false at launch.
    public private(set) var menuBarIconsHidden = false
    /// Why the last try did not hide them, for the note in the window and in the Menu Bar tab.
    public private(set) var menuBarHidingRefusal: MenuBarHiding.Refusal?

    public let strings: Strings
    public let time: TimeFormatter
    @ObservationIgnored public var openSettingsAction: (() -> Void)?
    /// The icon shown in the About tab (the app's own icon, or the one given to the images).
    @ObservationIgnored public var appIcon: NSImage?
    /// How the Menu Bar tab finds and opens apps (macOS in the app; fixed in the images and the tests).
    @ObservationIgnored public var menuBar = MenuBarEnvironment.live
    @ObservationIgnored public private(set) var menuBarIcons: [String: NSImage] = [:]
    /// Brimline's bar in the menu bar, given by the app once its own icon is there (see `attachSeparator`).
    @ObservationIgnored public private(set) var separator: (any MenuBarSeparating)?

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
        LegacyMigration.run(paths: paths)
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
        // As the app does at its first scan, so the images show the dots an account really gets (nothing is written).
        self.settings.assignDefaultColors(to: accounts)
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
        reloadSettings()
        let accounts = self.accounts
        let previous = snapshot
        let result = await service.refresh(accounts: accounts, settings: settings, previous: previous, now: Date(), force: force)
        snapshot = result
        now = Date()
        try? cache?.save(result)
    }

    /// Takes the settings file again: `brimline providers enable|disable` writes it while the app runs,
    /// and a provider turned off must stop being read at the next attempt, not at the next launch.
    private func reloadSettings() {
        guard let settingsStore else { return }
        let onDisk = settingsStore.load()
        guard onDisk != settings else { return }
        let hidingChanged = onDisk.menuBarHiding != settings.menuBarHiding
        settings = onDisk
        if hidingChanged { applyMenuBarHidingSetting() }
        rescan()
    }

    public func refreshNow() {
        Task { await refresh(force: true) }
    }

    /// Looks for the accounts again (new ~/.claude-* folder, folder added by hand).
    public func rescan() {
        accounts = Providers.discover(home: home, settings: settings)
        // Every account gets a color the first time it is seen, and keeps it (QUOTA-72); saved only when one was given.
        update { $0.assignDefaultColors(to: accounts) }
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

    /// The accounts of each provider that is on, in the panel's order (see `PanelLayout`).
    public var groups: [ProviderGroup] { PanelLayout.groups(visibleUsages, enabled: enabledProviders) }

    /// What the menu bar glyph shows: the visible limit closest to its ceiling among the providers that are on,
    /// up-to-date accounts first (see `PanelLayout.glyph`).
    public var menuBarLevel: (percent: Double?, dimmed: Bool, provider: Provider?, account: String?) {
        let unread = Set(settings.unreadAccounts)
        guard let top = PanelLayout.glyph(visibleUsages, providers: enabledProviders, unread: unread, now: now) else {
            return (nil, false, nil, nil)
        }
        return (top.percent, top.dimmed, top.usage.account.provider, title(for: top.usage.account))
    }

    /// What the menu bar element shows: one part per counted account (see `MenuBarGauge`).
    public var menuBarGauge: GaugeModel {
        MenuBarGauge.model(allUsages, settings: settings, providers: enabledProviders, now: now)
    }

    /// The name of an account in the gauge's sentences (VoiceOver, tooltip): its title, else its id.
    public func gaugeName(forAccountID id: String) -> String {
        allUsages.first { $0.account.id == id }.map { title(for: $0.account) } ?? id
    }

    /// The providers that are on.
    public var enabledProviders: Set<Provider> { Set(Provider.allCases.filter(settings.isEnabled)) }

    /// When Brimline last looked at the accounts: a provider that gives a sentence only has no numbers, but it was checked.
    public var lastUpdate: Date? { allUsages.flatMap { [$0.fetchedAt, $0.checkedAt] }.compactMap { $0 }.max() }

    /// Numbers older than two refresh intervals are shown with their age.
    public var staleAfter: TimeInterval { TimeInterval(settings.refreshMinutes * 60 * 2 + 60) }

    /// The name of an account without its label: the address for Claude, the provider and its plan for the others
    /// ("ChatGPT Plus"); a provider's address is never shown (the readers do not keep it).
    public func identity(for account: Account) -> String {
        AccountNames.identity(for: account)
    }

    public func title(for account: Account) -> String {
        AccountNames.title(for: account, settings: settings)
    }

    public func subtitle(for account: Account) -> String? {
        let siblings = allUsages.filter { $0.account.provider == account.provider }.count
        return AccountNames.subtitle(for: account, settings: settings, siblings: siblings, home: home)
    }

    /// Opens or closes the rest of an account's "not readable" sentence.
    public func toggleNote(accountID: String) {
        if expandedNotes.contains(accountID) { expandedNotes.remove(accountID) } else { expandedNotes.insert(accountID) }
    }

    /// The one-time hint that other providers exist.
    public var showsProviderHint: Bool {
        PanelLayout.showsProviderHint(enabled: enabledProviders, dismissed: settings.providerHintDismissed)
    }

    public func dismissProviderHint() {
        update { $0.providerHintDismissed = true }
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

    /// Turns a provider on or off. On: its accounts are looked for and read from now on. Off: nothing of it
    /// is opened or requested again, and its accounts leave the panel.
    public func setProvider(_ provider: Provider, enabled: Bool) {
        update { s in
            s.enabledProviders.removeAll { $0 == provider.rawValue }
            if enabled { s.enabledProviders.append(provider.rawValue) }
        }
        if enabled { rescanAndRefresh() } else { rescan() }
    }

    /// "Do not read": the account stays listed with its last numbers and is never read.
    public func setUnread(_ unread: Bool, accountID: String) {
        update { s in
            s.unreadAccounts.removeAll { $0 == accountID }
            if unread { s.unreadAccounts.append(accountID) }
        }
    }

    // MARK: Colors of the accounts

    /// The color of an account: the one kept in the settings, else the one the rule gives it now (an account seen
    /// for the first time, before the next scan has kept it).
    public func color(for account: Account) -> AccountColor {
        settings.accountColors[account.id]
            ?? AccountPalette.defaultColor(for: account, among: accounts, assigned: settings.accountColors)
    }

    /// The color of each part of the gauge of the menu bar: the same as the dot of its account in the panel.
    public func menuBarColors(for gauge: GaugeModel) -> [String: AccountColor] {
        var colors: [String: AccountColor] = [:]
        for segment in gauge.segments {
            if let account = accounts.first(where: { $0.id == segment.accountID }) {
                colors[segment.accountID] = color(for: account)
            }
        }
        return colors
    }

    /// Is this account's color the one "Back to default" would give? Then there is nothing to go back to.
    public func hasDefaultColor(_ account: Account) -> Bool {
        var s = settings
        s.resetColor(for: account, accounts: accounts)
        return s.accountColors[account.id] == color(for: account)
    }

    /// The user chose a color (a slot of the palette, or a free one from the system picker).
    public func setColor(_ color: AccountColor, for account: Account) {
        update { $0.accountColors[account.id] = color }
    }

    /// "Back to default": the color the rule gives this account now, kept like any other.
    public func resetColor(for account: Account) {
        update { $0.resetColor(for: account, accounts: accounts) }
    }

    /// The colors of the accounts the gauge shows, in the panel's order: visible, and of a provider that is on.
    var visibleColors: [(id: String, color: AccountColor)] {
        groups.flatMap(\.usages).filter { enabledProviders.contains($0.account.provider) }
            .map { ($0.account.id, color(for: $0.account)) }
    }

    /// What the settings say under the color of an account: too close to another one, too pale for the track.
    public func colorWarnings(for account: Account) -> [ColorWarning] {
        AccountPalette.warnings(for: account.id, color: color(for: account), visible: visibleColors)
    }

    /// The sentence of a warning, the other account of a close pair named as in the panel.
    public func text(for warning: ColorWarning) -> String {
        strings.colorWarning(warning) { id in
            accounts.first { $0.id == id }.map { title(for: $0) } ?? id
        }
    }

    /// Stored as typed (spaces included, so typing is not disturbed); trimmed when read.
    public func setLabel(_ label: String, accountID: String) {
        update { s in
            s.labels[accountID] = label.isEmpty ? nil : label
        }
    }

    // MARK: Menu Bar tab

    /// Looks again for the apps of the Menu Bar tab (they can be installed or removed while Brimline runs).
    public func refreshMenuBarApps() {
        let found = MenuBarTidy.installed(locate: { menuBar.locate($0) })
        menuBarIcons = Dictionary(uniqueKeysWithValues: found.compactMap { entry in
            menuBar.icon(entry.url).map { (entry.id, $0) }
        })
        menuBarApps = found
        menuBarAppFailed = nil
        menuBarSystemOutcome = nil
    }

    /// Opens the app, so the person can reach its setting (no link goes straight to it). A failure is a note under its row.
    public func openMenuBarApp(_ app: MenuBarApp) {
        guard let entry = menuBarApps.first(where: { $0.app == app }) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let opened = await menuBar.openApp(entry.url)
            menuBarAppFailed = opened ? nil : app
        }
    }

    /// Opens System Settings on the Menu Bar page, or on its home page when macOS refuses the address.
    public func openSystemMenuBarSettings() {
        menuBarSystemOutcome = MenuBarTidy.openSystemSettings(
            openURL: { menuBar.openURL($0) }, openApp: { menuBar.openBundle($0) })
    }

    // MARK: Hiding the icons left of Brimline's bar

    /// Takes Brimline's bar and puts it in the menu bar when the setting is on (it is not there otherwise).
    public func attachSeparator(_ separator: any MenuBarSeparating) {
        self.separator = separator
        separator.onRecheck = { [weak self] decision in self?.applyHiding(decision) }
        separator.setPresent(settings.menuBarHiding.enabled)
    }

    /// On: the bar appears, every icon still shown. Off: every icon is shown and the bar goes away.
    public func setMenuBarHiding(_ enabled: Bool) {
        update { $0.menuBarHiding.enabled = enabled }
        applyMenuBarHidingSetting()
    }

    private func applyMenuBarHidingSetting() {
        let on = settings.menuBarHiding.enabled
        if !on {
            menuBarIconsHidden = false
            menuBarHidingRefusal = nil
        }
        separator?.setPresent(on)
    }

    /// Hides the icons left of the bar, after the bar has checked its place; a refusal leaves them shown, with a note.
    public func hideMenuBarIcons() {
        guard settings.menuBarHiding.enabled else { return }
        guard let separator else { return applyHiding(.refuse(.placeUnknown)) }
        applyHiding(separator.hide())
    }

    /// Shows every icon again.
    public func showMenuBarIcons() {
        separator?.show()
        menuBarIconsHidden = false
        menuBarHidingRefusal = nil
    }

    public func toggleMenuBarIcons() {
        if menuBarIconsHidden { showMenuBarIcons() } else { hideMenuBarIcons() }
    }

    private func applyHiding(_ decision: MenuBarHiding.Decision) {
        switch decision {
        case .hide:
            menuBarIconsHidden = true
            menuBarHidingRefusal = nil
        case .refuse(let refusal):
            menuBarIconsHidden = false
            menuBarHidingRefusal = refusal
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

    /// A Codex folder (the one `CODEX_HOME` points to): only its `auth.json` is ever read.
    public func addCodexFolder(_ url: URL) {
        let path = KeychainServiceName.normalize(url.path)
        update { s in
            if !s.extraCodexFolders.contains(path) { s.extraCodexFolders.append(path) }
        }
        rescanAndRefresh()
    }

    /// Takes away a folder added by hand, whichever provider it belongs to.
    public func removeAddedFolder(of account: Account) {
        switch account.provider {
        case .chatgpt:
            update { s in s.extraCodexFolders.removeAll { $0 == account.source } }
            rescan()
        default:
            removeFolder(account.source)
        }
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

    /// `--scope user` makes the server available in every project; without it Claude Code adds it to
    /// the current project only (https://code.claude.com/docs/en/mcp).
    public var mcpAddCommand: String { "claude mcp add --scope user brimline -- \(shellQuoted(commandPath)) mcp" }

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
    public func displayPath(_ path: String) -> String { AccountNames.displayPath(path, home: home) }
}
