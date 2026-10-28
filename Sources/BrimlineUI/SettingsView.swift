import AppKit
import BrimlineCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Sendable {
    case accounts, general, menuBar, agents, about
}

/// The settings window: Accounts, General, Menu Bar, Agents, About.
public struct SettingsView: View {
    // No @State here: in the macOS 27 SDK, @State is a macro whose plugin ships with Xcode only,
    // and Brimline builds with the Command Line Tools. Local state lives in the model.
    @Bindable var model: AppModel
    var height: CGFloat

    public static let size = CGSize(width: 620, height: 600)

    /// `height` is only changed by the images, to show a whole tab without scrolling.
    public init(model: AppModel, height: CGFloat = SettingsView.size.height) {
        self.model = model
        self.height = height
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch model.settingsTab {
                case .accounts: AccountsTab(model: model)
                case .general: GeneralTab(model: model)
                case .menuBar: MenuBarTab(model: model)
                case .agents: AgentsTab(model: model)
                case .about: AboutTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: height)
        .tint(SGTheme.accent)
    }

    /// Tabs drawn like the toolbar of a macOS settings window: a symbol above each name.
    private var tabBar: some View {
        let s = model.strings
        let tabs: [(SettingsTab, String, String)] = [
            (.accounts, s.tabAccounts, "person.2"),
            (.general, s.tabGeneral, "gearshape"),
            (.menuBar, s.tabMenuBar, "menubar.rectangle"),
            (.agents, s.tabAgents, "terminal"),
            (.about, s.tabAbout, "info.circle"),
        ]
        return HStack(spacing: SGTheme.Space.xs) {
            ForEach(tabs, id: \.0) { tab, title, symbol in
                let selected = model.settingsTab == tab
                Button {
                    model.settingsTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: symbol)
                            .font(.system(size: 17))
                            .frame(height: 20)
                        Text(title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? SGTheme.accent : Color.secondary)
                    .frame(minWidth: 76)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: SGTheme.Radius.control, style: .continuous)
                            .fill(selected ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, SGTheme.Space.s)
        .frame(maxWidth: .infinity)
    }
}

// MARK: Accounts

struct AccountsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        Form {
            Section {
                VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
                    Text(s.accountsIntro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(s.colorsIntro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: Links.accountsDoc(s.language)) {
                        Label(s.howToLink, systemImage: "questionmark.circle")
                    }
                    .foregroundStyle(SGTheme.accent)
                }
            }

            // One block per provider (Claude, ChatGPT, Gemini, Grok, Cursor): its name, its switch, what it
            // reads, then its accounts (only when it is on: a provider that is off is not looked for).
            ForEach(Provider.allCases, id: \.self) { provider in
                let usages = model.allUsages.filter { $0.account.provider == provider }
                let on = model.settings.isEnabled(provider)
                Section {
                    if on {
                        if usages.isEmpty, provider == .claude {
                            Text(s.noAccountBody).foregroundStyle(.secondary)
                        }
                        ForEach(usages) { usage in
                            AccountSettingsRow(usage: usage, model: model)
                        }
                        if provider == .claude {
                            ClaudeReportsBlock(model: model)
                        }
                    }
                } header: {
                    ProviderHeader(provider: provider, model: model)
                } footer: {
                    if on { footerButtons(for: provider) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func footerButtons(for provider: Provider) -> some View {
        let s = model.strings
        switch provider {
        case .claude:
            HStack {
                Button(s.addFolder) { chooseFolder(message: s.chooseFolderMessage, prompt: s.addFolder) { model.addFolder($0) } }
                Button(s.rescan) { model.rescanAndRefresh() }
                Spacer()
            }
            .padding(.top, SGTheme.Space.xs)
        case .chatgpt:
            HStack {
                Button(s.addCodexFolder) { chooseFolder(message: s.chooseCodexFolderMessage, prompt: s.addCodexFolder) { model.addCodexFolder($0) } }
                Spacer()
            }
            .padding(.top, SGTheme.Space.xs)
        default:
            EmptyView()
        }
    }

    private func chooseFolder(message: String, prompt: String, then add: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = message
        panel.prompt = prompt.replacingOccurrences(of: "…", with: "")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            add(url)
        }
    }
}

/// The Claude Code reports: what they are, the command to add to a status line, where they are kept. An account
/// known by its report is listed with the others above, with its own "Don't read this account" box.
struct ClaudeReportsBlock: View {
    var model: AppModel

    var body: some View {
        let s = model.strings
        VStack(alignment: .leading, spacing: SGTheme.Space.s) {
            Text(s.reportsTitle)
                .font(.system(size: 13, weight: .semibold))
            Text(s.reportsIntro)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let commands = model.statuslineCommands
            if commands.isEmpty {
                Text(s.reportsNoAddress)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(commands, id: \.email) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.email)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    CopyableCode(model: model, text: entry.command, copyLabel: s.copy, copiedLabel: s.copied)
                }
            }
            Text(s.reportsAuto)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CopyableCode(model: model, text: model.statuslineAutoCommand, copyLabel: s.copy, copiedLabel: s.copied)
            HStack(alignment: .firstTextBaseline, spacing: SGTheme.Space.s) {
                Text(s.reportsFolder)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(model.reportsFolderForDisplay)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Text(s.reportsDoNotRead)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, SGTheme.Space.xs)
    }
}

/// A provider's heading in the Accounts tab: name, switch, and one line that says what Brimline reads.
struct ProviderHeader: View {
    var provider: Provider
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        let supported = Providers.isSupported(provider)
        let on = model.settings.isEnabled(provider)
        VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SGTheme.Space.s) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let qualifier = s.qualifier(for: provider) {
                    Text(qualifier)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if supported {
                    Toggle(s.readProvider(provider.displayName), isOn: Binding(
                        get: { on },
                        set: { model.setProvider(provider, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(s.readProvider(provider.displayName))
                } else {
                    Text(s.comingSoon).foregroundStyle(.secondary)
                }
            }
            if supported {
                // What is read, and where it is asked (the same line, off or on, so the promise is plain).
                (Text(s.providerCaption(provider, on: on)) + Text(" ")
                    + Text(.init("[\(s.whatIsRead)](\(Links.providersDoc.absoluteString))")))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .tint(SGTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textCase(nil)
        .padding(.bottom, SGTheme.Space.xs)
    }
}

struct AccountSettingsRow: View {
    var usage: AccountUsage
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        let account = usage.account
        VStack(alignment: .leading, spacing: SGTheme.Space.s) {
            HStack(alignment: .top, spacing: SGTheme.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SGAccountDot(model.color(for: account))
                        .alignedWithText()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.identity(for: account))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(account.email ?? account.source)
                        Text(Self.details(for: usage, unread: model.settings.isUnread(account.id), strings: s))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(account.readsReportOnly ? s.reportSourceLine : model.displayPath(account.source))
                            .font(.system(size: 11, design: account.readsReportOnly ? .default : .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(account.source)
                    }
                }
                Spacer(minLength: SGTheme.Space.s)
                HStack(spacing: SGTheme.Space.s) {
                    Text(s.show)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Toggle(s.show, isOn: Binding(
                        get: { !model.settings.isHidden(account.id) },
                        set: { model.setHidden(!$0, accountID: account.id) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel("\(s.show) \(model.identity(for: account))")
                }
                .fixedSize()
            }
            HStack(spacing: SGTheme.Space.s) {
                TextField(s.customLabel, text: Binding(
                    get: { model.settings.labels[account.id] ?? "" },
                    set: { model.setLabel($0, accountID: account.id) }
                ), prompt: Text(s.customLabel))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                if account.addedByHand {
                    Button(s.removeFolder) { model.removeAddedFolder(of: account) }
                }
            }
            AccountColorRow(account: account, model: model)
            VStack(alignment: .leading, spacing: 2) {
                Toggle(s.doNotRead, isOn: Binding(
                    get: { model.settings.isUnread(account.id) },
                    set: { model.setUnread($0, accountID: account.id) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                Text(s.doNotReadHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, SGTheme.Space.xs)
    }

    /// The line under an account: its provider (never another provider's name), organization and status.
    static func details(for usage: AccountUsage, unread: Bool = false, strings s: Strings) -> String {
        var parts = [usage.account.provider.displayName]
        if let org = usage.account.organization { parts.append(org) }
        if let tier = usage.account.seatTier { parts.append(tier.capitalized) }
        parts.append(unread ? s.readingOffStatus : s.statusName(usage.status))
        return parts.joined(separator: " · ")
    }
}

// MARK: General

struct GeneralTab: View {
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        Form {
            Section {
                Picker(s.refreshEvery, selection: Binding(
                    get: { model.settings.refreshMinutes },
                    set: { model.setRefreshMinutes($0) }
                )) {
                    ForEach(BrimlineSettings.refreshChoices, id: \.self) { n in
                        Text(s.minutes(n)).tag(n)
                    }
                }
                Toggle(s.percentInMenuBar, isOn: Binding(
                    get: { model.settings.showPercentInMenuBar },
                    set: { model.setShowPercent($0) }
                ))
                Text(s.menuBarHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle(s.openAtLogin, isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Text(s.openAtLoginHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Text(s.readOnlyNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Menu Bar

/// "Tidy up the menu bar": where each app keeps the switch of its icon, and a button that opens the app.
/// Brimline cannot hide another app's icon (QUOTA-73), so this tab asks for no permission and reads nothing
/// of these apps but where they are installed.
struct MenuBarTab: View {
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        Form {
            Section {
                VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
                    Text(s.menuBarTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(s.menuBarIntro)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                if model.menuBarApps.isEmpty {
                    Text(s.menuBarNoApps)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.menuBarApps) { entry in
                    MenuBarAppRow(entry: entry, model: model)
                }
            } header: {
                Text(s.menuBarInApps)
            } footer: {
                if !model.menuBarApps.isEmpty {
                    Text(s.menuBarInstalledOnly).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section(s.menuBarForAll) {
                Text(s.menuBarSystemText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(s.menuBarOpenSystem) { model.openSystemMenuBarSettings() }
                switch model.menuBarSystemOutcome {
                case .homePage: MenuBarNote(text: s.menuBarSystemHomePage, symbol: "exclamationmark.triangle")
                case .failed: MenuBarNote(text: s.menuBarSystemFailed, symbol: "exclamationmark.triangle")
                case .menuBarPage, nil: EmptyView()
                }
            }
            Section(s.menuBarByHand) {
                VStack(alignment: .leading, spacing: SGTheme.Space.s) {
                    MenuBarStep(number: 1) {
                        HStack(spacing: SGTheme.Space.xs) {
                            Text(s.menuBarStep1Before)
                            CommandKey()
                            Text(s.menuBarStep1After)
                        }
                    }
                    MenuBarStep(number: 2) { Text(s.menuBarStep2) }
                    MenuBarStep(number: 3) { Text(s.menuBarStep3) }
                }
                MenuBarNote(text: s.menuBarStepsNote, symbol: "info.circle")
            }
            MenuBarHidingSection(model: model)
        }
        .formStyle(.grouped)
        .onAppear { model.refreshMenuBarApps() }
    }
}

/// "Hide without removing" (QUOTA-73): the switch of Brimline's bar, the one gesture to make, and the button.
/// Off by default; on, Brimline adds its bar to the menu bar and hides only what the person put left of it.
public struct MenuBarHidingSection: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let s = model.strings
        let on = model.settings.menuBarHiding.enabled
        Section(s.menuBarHidingTitle) {
            Toggle(s.menuBarHidingToggle, isOn: Binding(
                get: { on },
                set: { model.setMenuBarHiding($0) }
            ))
            VStack(alignment: .leading, spacing: SGTheme.Space.s) {
                Text(s.menuBarHidingHowTo)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                MenuBarHidingDiagram(strings: s)
            }
            if on {
                HStack {
                    Button(model.menuBarIconsHidden ? s.menuBarHidingShow : s.menuBarHidingHide) {
                        model.toggleMenuBarIcons()
                    }
                    Spacer()
                }
                if let refusal = model.menuBarHidingRefusal {
                    MenuBarNote(text: s.menuBarHidingRefusal(refusal), symbol: "exclamationmark.triangle")
                }
            }
            VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
                MenuBarNote(text: s.menuBarHidingNote, symbol: "info.circle")
                Link(destination: Links.menuBarDoc(s.language)) {
                    Label(s.menuBarHidingGuide, systemImage: "questionmark.circle")
                }
                .font(.system(size: 11))
                .foregroundStyle(SGTheme.accent)
            }
        }
    }
}

/// A drawing of the menu bar for the one gesture: the icons put left of Brimline's bar are hidden, the others,
/// Brimline included, stay. Neutral tiles with first letters, never the logo of another app.
public struct MenuBarHidingDiagram: View {
    var strings: Strings

    public init(strings: Strings) {
        self.strings = strings
    }

    private static let tile: CGFloat = 18
    private static let gap: CGFloat = 6
    private static let hiddenNames = ["Cl", "Ch", "Cu", "Ge"]
    private static var hiddenWidth: CGFloat { CGFloat(hiddenNames.count) * tile + CGFloat(hiddenNames.count - 1) * gap }

    public var body: some View {
        VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
            HStack(spacing: 10) {
                HStack(spacing: Self.gap) {
                    ForEach(Self.hiddenNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 8, weight: .semibold))
                            .frame(width: Self.tile, height: Self.tile)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.12)))
                            .opacity(0.55)
                    }
                }
                .frame(width: Self.hiddenWidth)
                Capsule()
                    .fill(SGTheme.accent)
                    .frame(width: 2, height: 16)
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                    Image(systemName: "magnifyingglass")
                    Image(nsImage: BrimlineGlyph.image(level: 0.58))
                    Text("12:20").monospacedDigit()
                }
                .font(.system(size: 11))
            }
            .padding(.horizontal, SGTheme.Space.s)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
            HStack(spacing: 10) {
                Text(strings.menuBarHidingDiagramHidden)
                    .frame(width: Self.hiddenWidth, alignment: .center)
                Color.clear.frame(width: 2, height: 1)
                Text(strings.menuBarHidingDiagramShown)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, SGTheme.Space.s)
            HStack(spacing: SGTheme.Space.xs) {
                Image(systemName: "arrow.left")
                CommandKey()
                Text(strings.menuBarHidingDiagramGesture)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, SGTheme.Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strings.menuBarHidingDiagramSpoken)
    }
}

/// One installed app: its own icon, the name of its switch, where it is, and a button that opens the app.
struct MenuBarAppRow: View {
    var entry: InstalledMenuBarApp
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        let app = entry.app
        VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
            HStack(spacing: SGTheme.Space.m) {
                if let icon = model.menuBarIcons[entry.id] {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(s.menuBarTurnOff(app))
                        .font(.system(size: 12))
                    Text(s.menuBarSettingPath(app))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                // One element for VoiceOver: the app, its switch and where it is. The button stays apart.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(s.menuBarRowSpoken(app))
                Spacer(minLength: SGTheme.Space.s)
                Button(s.menuBarOpenApp(app)) { model.openMenuBarApp(app) }
            }
            if model.menuBarAppFailed == app {
                MenuBarNote(text: s.menuBarAppError(app), symbol: "exclamationmark.triangle")
            }
        }
        .padding(.vertical, SGTheme.Space.xs)
    }
}

/// A line of small secondary text with its symbol (never red: it is not a consumption alert).
struct MenuBarNote: View {
    var text: String
    var symbol: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SGTheme.Space.s) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

/// A numbered step: a round number, then its text.
struct MenuBarStep<Content: View>: View {
    var number: Int
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: SGTheme.Space.m) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(SGTheme.track))
                .accessibilityHidden(true)
            content
        }
    }
}

/// The ⌘ key, as a small keycap.
struct CommandKey: View {
    var body: some View {
        Text("⌘")
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            )
            .accessibilityLabel("Command")
    }
}

// MARK: Agents

struct AgentsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        Form {
            Section {
                Text(s.agentsIntro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: Links.agentsDoc) {
                    Label(s.agentsDoc, systemImage: "book")
                }
                .foregroundStyle(SGTheme.accent)
            }
            Section(s.commandPath) {
                CopyableCode(model: model, text: model.commandPath, copyLabel: s.copy, copiedLabel: s.copied)
                CopyableCode(model: model, text: "brimline status --json", copyLabel: s.copy, copiedLabel: s.copied)
            }
            Section(s.mcpClaudeCode) {
                CopyableCode(model: model, text: model.mcpAddCommand, copyLabel: s.copy, copiedLabel: s.copied)
            }
            Section(s.mcpJSON) {
                CopyableCode(model: model, text: model.mcpJSON, copyLabel: s.copy, copiedLabel: s.copied)
            }
            Section(s.cachePath) {
                CopyableCode(model: model, text: model.cachePathForDisplay, copyLabel: s.copy, copiedLabel: s.copied)
            }
        }
        .formStyle(.grouped)
    }
}

/// A block of monospaced text with a Copy button.
struct CopyableCode: View {
    var model: AppModel
    var text: String
    var copyLabel: String
    var copiedLabel: String
    private var copied: Bool { model.lastCopied == text }

    var body: some View {
        HStack(alignment: .top, spacing: SGTheme.Space.s) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? copiedLabel : copyLabel) {
                model.copy(text)
            }
            .controlSize(.small)
        }
    }
}

// MARK: About

struct AboutTab: View {
    @Bindable var model: AppModel
    var icon: NSImage? { model.appIcon }

    var body: some View {
        let s = model.strings
        VStack(spacing: SGTheme.Space.m) {
            Spacer(minLength: 0)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
            }
            Text("Brimline")
                .font(.system(size: 22, weight: .semibold))
            Text(s.tagline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(versionText)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(s.licenseLine)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: SGTheme.Space.l) {
                Link("GitHub", destination: Links.repository)
                Link(s.documentation, destination: Links.documentationBase)
            }
            .foregroundStyle(SGTheme.accent)
            .padding(.top, SGTheme.Space.xs)
            Spacer(minLength: 0)
            Text("© 2026 Thanaël Fontaine")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(SGTheme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionText: String {
        let v = model.appVersion
        let s = model.strings
        return v == "0.0.0" ? "\(s.version) \(v) (\(s.development))" : "\(s.version) \(v)"
    }
}
