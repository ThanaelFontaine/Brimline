import AppKit
import BrimlineCore
import Observation

/// The tooltip of Brimline's element in the menu bar ("Average 45% across 5 accounts" and the alerts).
///
/// `.help` on the label of a `MenuBarExtra` is lost: SwiftUI draws the label into the status bar button as an image
/// and gives the button no tooltip and no view of its own (seen in the real menu bar on macOS 27.0.1, 28/10/2026: the
/// button's `toolTip` was nil and it had no subview). So the tooltip is set on the button itself, with AppKit's public
/// `toolTip`, and set again each time the gauge changes.
@MainActor
public final class MenuBarTooltip {
    private let model: AppModel
    private weak var button: NSButton?

    public init(model: AppModel) {
        self.model = model
    }

    /// Takes the status bar button of Brimline's element and gives it its tooltip now and at each change.
    public func attach(_ button: NSButton) {
        self.button = button
        update()
    }

    private func update() {
        guard let button else { return }
        withObservationTracking {
            button.toolTip = model.menuBarTooltipText
        } onChange: { [weak self] in
            // Told before the change is made: the new text is read on the next turn of the main loop.
            Task { @MainActor [weak self] in self?.update() }
        }
    }

    /// The first status bar button (`NSStatusBarButton`, a public AppKit class) in a window's views, if any.
    public static func statusButton(in window: NSWindow) -> NSStatusBarButton? {
        find(window.contentView, depth: 0)
    }

    private static func find(_ view: NSView?, depth: Int) -> NSStatusBarButton? {
        guard let view, depth < 6 else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for child in view.subviews {
            if let button = find(child, depth: depth + 1) { return button }
        }
        return nil
    }
}

extension AppModel {
    /// The text of the tooltip of the menu bar element.
    public var menuBarTooltipText: String {
        strings.menuBarTooltip(menuBarGauge, names: { gaugeName(forAccountID: $0) })
    }
}
