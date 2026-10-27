import AppKit
import BrimlineCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Sendable {
    case accounts, general, agents, about
}

/// The settings window: Accounts, General, Agents, About.
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
                    Link(destination: Links.accountsDoc(s.language)) {
                        Label(s.howToLink, systemImage: "questionmark.circle")
                    }
                    .foregroundStyle(SGTheme.accent)
                }
            }

            // One block per provider (Claude, ChatGPT, Gemini, Grok, Cursor): its dot, its name, its switch, what it
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

/// A provider's heading in the Accounts tab: dot, name, switch, and one line that says what Brimline reads.
struct ProviderHeader: View {
    var provider: Provider
    @Bindable var model: AppModel

    var body: some View {
        let s = model.strings
        let supported = Providers.isSupported(provider)
        let on = model.settings.isEnabled(provider)
        VStack(alignment: .leading, spacing: SGTheme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SGTheme.Space.s) {
                SGProviderDot(provider)
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
                    Text(model.displayPath(account.source))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(account.source)
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
