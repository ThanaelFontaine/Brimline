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
}

/// Brimline's bar: one more `NSStatusItem` of Brimline's own, a thin vertical bar, that hides the icons placed left
/// of it by growing (see `MenuBarHiding`). No permission, no private API, no file of macOS or of another app is
/// written: Brimline only changes the length of its own item.
///
/// - It exists only while the setting is on: when it is off, there is no bar in the menu bar.
/// - It always starts at its normal length (icons shown), so a crash or a quit never leaves anything hidden: the
///   icons come back when Brimline's process ends, and the next launch starts with them shown.
/// - Its place is only read while the icons are shown (the frames AppKit gives while they are hidden are wrong).
/// - When the screens change while the icons are hidden, it shows them, reads its place again, and hides them again
///   only if the check passes.
@MainActor
public final class MenuBarHider: MenuBarSeparating {
    public var onRecheck: ((MenuBarHiding.Decision) -> Void)?
    public private(set) var isHiding = false

    private let strings: Strings
    private var item: NSStatusItem?
    private var screenObserver: (any NSObjectProtocol)?
    private var recheck: Task<Void, Never>?

    public init(strings: Strings) {
        self.strings = strings
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
        if isHiding { return .hide(length: Double(item.length)) }
        let decision = MenuBarHiding.decide(
            placement: placement(of: item),
            screenWidths: NSScreen.screens.map { Double($0.frame.width) },
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        if case .hide(let length) = decision {
            item.length = CGFloat(length)
            isHiding = true
        }
        return decision
    }

    public func show() {
        recheck?.cancel()
        recheck = nil
        item?.length = NSStatusItem.variableLength
        isHiding = false
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

    /// A thin vertical bar, drawn in the color of the menu bar (template image).
    static let barImage: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            let bar = NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: 1.5, width: 1.5, height: rect.height - 3),
                                   xRadius: 0.75, yRadius: 0.75)
            NSColor.black.setFill()
            bar.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
