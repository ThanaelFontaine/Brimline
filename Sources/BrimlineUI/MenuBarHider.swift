import AppKit
import BrimlineCore

/// What the model asks of Brimline's bar in the menu bar (QUOTA-73). The app gives `MenuBarHider`; the tests and
/// the images give their own, so nothing real is put in the menu bar.
@MainActor
public protocol MenuBarSeparating: AnyObject {
    /// Puts the bar in the menu bar, icons shown, or takes it out (the icons are shown first).
    func setPresent(_ present: Bool)
    /// Reads where the bar is, then hides the icons left of it. On a refusal, the icons stay shown.
    func hide() -> MenuBarHiding.Decision
    /// Gives the bar its normal length: every icon is shown.
    func show()
    /// Told when the bar decided again by itself (the screens changed while the icons were hidden).
    var onRecheck: ((MenuBarHiding.Decision) -> Void)? { get set }
    /// Told when the person clicks the bar: it hides or shows the icons, without opening the Brimline window.
    var onClick: (() -> Void)? { get set }
}

/// Brimline's bar: one more `NSStatusItem` of Brimline's own, a thin vertical bar, that hides the icons placed left
/// of it by growing (see `MenuBarHiding`). No permission, no private API, no file of macOS or of another app is
/// written: Brimline only changes the length of its own item.
///
/// - It exists only while the setting is on: when it is off, there is no bar in the menu bar.
/// - It always starts at its normal length (icons shown), so a quit never leaves anything hidden (after a crash too, by design, not tried): the
///   icons come back when Brimline's process ends, and the next launch starts with them shown.
/// - Its place is only read while the icons are shown (the frames AppKit gives while they are hidden are wrong).
/// - When the screens change while the icons are hidden, it shows them, reads its place again, and hides them again
///   only if the check passes.
@MainActor
public final class MenuBarHider: NSObject, MenuBarSeparating {
    public var onRecheck: ((MenuBarHiding.Decision) -> Void)?
    public var onClick: (() -> Void)?
    public private(set) var isHiding = false

    private let strings: Strings
    private var item: NSStatusItem?
    private var screenObserver: (any NSObjectProtocol)?
    private var recheck: Task<Void, Never>?
    private var lastDecision: MenuBarHiding.Decision?

    public init(strings: Strings) {
        self.strings = strings
        super.init()
    }

    public func setPresent(_ present: Bool) {
        if present {
            guard item == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = MenuBarHiding.autosaveName
            // Not taken out by a Command-drag out of the menu bar, and never quits Brimline.
            item.behavior = []
            if let button = item.button {
                button.image = Self.barImage
                button.toolTip = strings.menuBarHidingBarHelp
                button.setAccessibilityLabel(strings.menuBarHidingBarName)
                button.target = self
                button.action = #selector(clicked)
            }
            self.item = item
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
        } else {
            guard let item else { return }
            show()
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    public func hide() -> MenuBarHiding.Decision {
        guard let item else { return .refuse(.placeUnknown) }
        if isHiding { return lastDecision ?? .hide(length: Double(item.length)) }
        let decision = MenuBarHiding.decide(
            placement: placement(of: item),
            screenWidths: NSScreen.screens.map { Double($0.frame.width) },
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        if case .hide(let length, _) = decision {
            item.length = CGFloat(length)
            // The thin bar stays where the person put it, at the right end of the long item, not in its middle.
            item.button?.image = Self.hidingImage(length: CGFloat(length))
            item.button?.toolTip = strings.menuBarHidingBarHelpHidden
            item.button?.setAccessibilityLabel(strings.menuBarHidingShow)
            isHiding = true
            lastDecision = decision
        }
        return decision
    }

    public func show() {
        recheck?.cancel()
        recheck = nil
        item?.length = NSStatusItem.variableLength
        item?.button?.image = Self.barImage
        item?.button?.toolTip = strings.menuBarHidingBarHelp
        item?.button?.setAccessibilityLabel(strings.menuBarHidingBarName)
        isHiding = false
        lastDecision = nil
    }

    /// A screen came, went or changed size: the length that hides depends on the screens, and the place read before
    /// may no longer hold. The icons are shown, the bar settles, then the check runs again.
    private func screensChanged() {
        guard isHiding else { return }
        show()
        recheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled, self.item != nil else { return }
            self.onRecheck?(self.hide())
        }
    }

    /// Where the bar and Brimline's own icon are, in points, on the bar's screen. Nil when it cannot be read.
    private func placement(of item: NSStatusItem) -> MenuBarHiding.Placement? {
        guard item.isVisible, let window = item.button?.window, let screen = window.screen ?? NSScreen.main,
              window.frame.width > 0 else { return nil }
        let lefts = Self.brimlineStatusWindows(excluding: window).map { own -> Double in
            // The menu bar is drawn from the right edge of each screen: the same distance from it, on the bar's screen.
            let ownScreen = own.screen ?? screen
            return Double(screen.frame.width - (ownScreen.frame.maxX - own.frame.minX))
        }
        return MenuBarHiding.Placement(barLeft: Double(window.frame.minX - screen.frame.minX),
                                       screenWidth: Double(screen.frame.width),
                                       brimlineLefts: lefts)
    }

    /// Brimline's own icons in the menu bar, the bar left aside: the windows of this app that hold a status bar button
    /// (`NSStatusBarButton`, a public AppKit class). The Brimline window itself holds none.
    public static func brimlineStatusWindows(excluding bar: NSWindow?) -> [NSWindow] {
        NSApp.windows.filter { $0 !== bar && $0.frame.width > 0 && holdsStatusButton($0.contentView, depth: 0) }
    }

    private static func holdsStatusButton(_ view: NSView?, depth: Int) -> Bool {
        guard let view, depth < 6 else { return false }
        if view is NSStatusBarButton { return true }
        return view.subviews.contains { holdsStatusButton($0, depth: depth + 1) }
    }

    @objc private func clicked() {
        onClick?()
    }

    /// A thin vertical bar, drawn in the color of the menu bar (template image).
    static let barImage: NSImage = barImage(width: 8)

    /// While the icons are hidden: an arrow « at the right end of an image as long as the hiding item, so that it sits
    /// where the bar was, next to the icons still shown (AppKit centers the image in the item, with the same margin on
    /// each side as for the short one). A click on it shows the hidden icons.
    static func hidingImage(length: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: max(12, length), height: 16), flipped: false) { rect in
            let arrows = NSBezierPath()
            for dx in [0.0, 4.5] {
                let tip = rect.maxX - 9.5 + dx
                arrows.move(to: NSPoint(x: tip + 3.5, y: rect.midY + 4))
                arrows.line(to: NSPoint(x: tip, y: rect.midY))
                arrows.line(to: NSPoint(x: tip + 3.5, y: rect.midY - 4))
            }
            arrows.lineWidth = 1.5
            arrows.lineCapStyle = .round
            arrows.lineJoinStyle = .round
            NSColor.black.setStroke()
            arrows.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func barImage(width: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { rect in
            let bar = NSBezierPath(roundedRect: NSRect(x: rect.maxX - 4.75, y: 1.5, width: 1.5, height: rect.height - 3),
                                   xRadius: 0.75, yRadius: 0.75)
            NSColor.black.setFill()
            bar.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
