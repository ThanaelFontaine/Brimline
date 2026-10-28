import AppKit
import BrimlineCore

/// What the Menu Bar tab asks of macOS: where an app is, its icon, and opening an app or an address.
/// The live one uses `NSWorkspace`; the images and the tests give their own, so nothing real is opened.
public struct MenuBarEnvironment {
    public var locate: @MainActor (String) -> URL?
    /// The icon macOS shows for the app at that URL (never copied anywhere).
    public var icon: @MainActor (URL) -> NSImage?
    /// Opens the app at that URL; false when macOS could not.
    public var openApp: @MainActor (URL) async -> Bool
    public var openURL: @MainActor (URL) -> Bool
    /// Opens an app from its bundle identifier; false when it is not found or could not open.
    public var openBundle: @MainActor (String) -> Bool

    public init(locate: @escaping @MainActor (String) -> URL?,
                icon: @escaping @MainActor (URL) -> NSImage?,
                openApp: @escaping @MainActor (URL) async -> Bool,
                openURL: @escaping @MainActor (URL) -> Bool,
                openBundle: @escaping @MainActor (String) -> Bool) {
        self.locate = locate
        self.icon = icon
        self.openApp = openApp
        self.openURL = openURL
        self.openBundle = openBundle
    }

    @MainActor
    public static var live: MenuBarEnvironment {
        MenuBarEnvironment(
            locate: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            icon: { NSWorkspace.shared.icon(forFile: $0.path) },
            openApp: { url in
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    return true
                } catch {
                    return false
                }
            },
            openURL: { NSWorkspace.shared.open($0) },
            openBundle: { id in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
                return NSWorkspace.shared.open(url)
            })
    }
}
