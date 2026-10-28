import AppKit
import BrimlineCore
import SwiftUI

/// What the menu bar shows: the gauge element (one colored part per account), and the percentage of the most loaded
/// account when the setting asks for it. VoiceOver reads it as one element. Its tooltip is set on the status bar
/// button by `MenuBarTooltip`: `.help` here would be lost.
public struct MenuBarLabel: View {
    var model: AppModel
    /// Read so that the image is drawn again when the appearance changes.
    @Environment(\.colorScheme) private var colorScheme

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let gauge = model.menuBarGauge
        let names: (String) -> String = { model.gaugeName(forAccountID: $0) }
        let sentence = model.strings.menuBarAccessibility(gauge, names: names)
        let image = MenuBarGaugeImage.image(gauge, colors: model.menuBarColors(for: gauge), accessibilityDescription: sentence)
        HStack(spacing: 4) {
            Image(nsImage: image)
                .id(colorScheme)
            if model.settings.showPercentInMenuBar, let percent = gauge.mostLoaded?.percent {
                Text(model.strings.percentText(percent))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }
}

/// The settings window. An accessory app (no Dock icon) is not active when its menu bar panel
/// is used, so a window opened then would stay behind the frontmost app: the app is activated
/// first, then the window is brought to the front.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?
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
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                               queue: .main) { _ in
            MainActor.assumeIsolated { ColorPanel.shared.close() }
        }
        return window
    }
}
