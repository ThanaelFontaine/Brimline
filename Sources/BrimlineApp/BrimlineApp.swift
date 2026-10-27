import AppKit
import BrimlineCore
import BrimlineUI
import SwiftUI

@main
struct BrimlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var settingsWindow = SettingsWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.appIcon = NSApp.applicationIconImage
        model.openSettingsAction = { [weak self] in self?.settingsWindow.show() }
        model.start()
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it runs shows the settings:
    /// without a Dock icon, it is the only other way in besides the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }
}
