import AppKit
import BrimlineCore
import SwiftUI

/// What the menu bar shows: the level glyph, and the percentage when the setting asks for it.
public struct MenuBarLabel: View {
    var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let level = model.menuBarLevel
        let image = BrimlineGlyph.image(level: level.percent.map { $0 / 100 }, dimmed: level.dimmed)
        HStack(spacing: 3) {
            Image(nsImage: image)
            if model.settings.showPercentInMenuBar, let percent = level.percent {
                Text(model.strings.percentText(percent))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.strings.menuBarAccessibility(level.percent))
    }
}

/// The settings window. An accessory app (no Dock icon) is not active when its menu bar panel
/// is used, so a window opened then would stay behind the frontmost app: the app is activated
/// first, then the window is brought to the front.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = model.strings.settingsTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(SettingsView.size)
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        return window
    }
}
