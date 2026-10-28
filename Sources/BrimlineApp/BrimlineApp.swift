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
    private lazy var hider = MenuBarHider(strings: model.strings)
    private lazy var tooltip = MenuBarTooltip(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.appIcon = NSApp.applicationIconImage
        model.openSettingsAction = { [weak self] in self?.settingsWindow.show() }
        model.start()
        // Brimline's bar (QUOTA-73) comes after Brimline's own icon: macOS puts a new item left of the others, so the
        // first time, the bar lands left of Brimline, which then stays right of it and is never hidden (the bar also
        // refuses to hide when Brimline's icon is found left of it).
        Task { @MainActor [weak self] in
            var tries = 0
            while MenuBarHider.brimlineStatusWindows(excluding: nil).isEmpty, tries < 30 {
                tries += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self else { return }
            // The tooltip goes on the button of Brimline's element, found before the bar exists.
            if let window = MenuBarHider.brimlineStatusWindows(excluding: nil).first,
               let button = MenuBarTooltip.statusButton(in: window) {
                self.tooltip.attach(button)
            }
            self.model.attachSeparator(self.hider)
        }
    }

    /// Quitting always shows every icon (they would come back anyway when the process ends).
    func applicationWillTerminate(_ notification: Notification) {
        model.showMenuBarIcons()
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it runs shows the settings:
    /// without a Dock icon, it is the only other way in besides the menu bar.
    /// It also shows the hidden icons: a way back that never depends on the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showMenuBarIcons()
        settingsWindow.show()
        return false
    }
}
