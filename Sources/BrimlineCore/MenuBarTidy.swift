import Foundation

/// An app that puts its own icon in the menu bar and has its own setting to take it out (QUOTA-73).
///
/// Brimline cannot hide another app's icon: macOS has no public way for an app to touch another app's menu bar
/// item, and the non-public ways need Accessibility or Screen Recording and are broken on macOS 27. So the
/// "Tidy up the menu bar" tab only says where each app keeps its setting and opens the app. It reads nothing
/// of these apps but where they are installed, and asks for no permission.
public enum MenuBarApp: String, CaseIterable, Sendable {
    // The order is the one of the providers.
    case claude, chatgpt, cursor

    /// The bundle identifier macOS knows the app by (read from the installed apps, 27/10/2026).
    public var bundleIdentifier: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .chatgpt: "com.openai.codex"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        }
    }

    /// The name of the row (not the name of the bundle, which can differ: the ChatGPT app is Codex's).
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .cursor: "Cursor"
        }
    }
}

/// One of those apps, found on this Mac.
public struct InstalledMenuBarApp: Sendable, Equatable, Identifiable {
    public var app: MenuBarApp
    public var url: URL
    public var id: String { app.rawValue }

    public init(app: MenuBarApp, url: URL) {
        self.app = app
        self.url = url
    }
}

public enum MenuBarTidy {
    /// The apps of `MenuBarApp` that are installed, in the order of the providers. `locate` answers where an app
    /// is, from its bundle identifier (`NSWorkspace.urlForApplication(withBundleIdentifier:)` in the app).
    public static func installed(locate: (String) -> URL?) -> [InstalledMenuBarApp] {
        MenuBarApp.allCases.compactMap { app in
            locate(app.bundleIdentifier).map { InstalledMenuBarApp(app: app, url: $0) }
        }
    }

    /// The page of System Settings that lists the apps allowed in the menu bar. Apple does not document this
    /// address; the settings extension it names exists on macOS 26 and 27 (Cursor opens the same one).
    public static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    /// The page of System Settings that lists the apps with the Accessibility permission (on macOS 27 in English,
    /// "Device Control and Data Access"). Apple does not document this address; it opens that page on macOS 27.0.1.
    public static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// The System Settings app itself, for when the address above is not taken.
    public static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    public enum SettingsOutcome: Sendable, Equatable {
        /// The address was taken: System Settings was asked for the Menu Bar page.
        case menuBarPage
        /// The address was refused, System Settings opened on its own: the tab says which page to choose.
        case homePage
        /// Neither worked.
        case failed
    }

    /// Opens System Settings on the Menu Bar page; when macOS refuses the address, opens System Settings itself.
    /// `openURL` and `openApp` answer whether macOS took the request.
    public static func openSystemSettings(openURL: (URL) -> Bool, openApp: (String) -> Bool) -> SettingsOutcome {
        if openURL(systemSettingsURL) { return .menuBarPage }
        return openApp(systemSettingsBundleIdentifier) ? .homePage : .failed
    }
}
