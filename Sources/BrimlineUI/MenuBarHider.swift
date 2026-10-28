import AppKit
import ApplicationServices
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
    /// Whether it hides with macOS 27's allow-list (true) or with the length of the bar (false).
    var usesAllowList: Bool { get }
    /// macOS 27: the apps found right of the bar the last time (saved by the model), used when the Accessibility
    /// permission is missing, and the place to tell a new list.
    var knownShownApps: [String] { get set }
    var onShownApps: (([String]) -> Void)? { get set }
}

/// Brimline's bar: one more `NSStatusItem` of Brimline's own, a thin vertical bar, that hides the icons placed left
/// of it. No file of macOS or of another app is written.
///
/// - On macOS 27 and later, when macOS has its allow-list (`MenuBarAllowList`): the bar keeps its size, Brimline
///   reads which apps have icons left of it (Accessibility permission), and macOS hides those apps' icons in place, one
///   app after the other from the left toward the bar, which becomes an arrow «. A click on the arrow brings them back,
///   from the nearest. Brimline must run from the Applications folder.
/// - Otherwise: the bar grows and pushes the icons out of the visible part of the menu bar (see `MenuBarHiding`);
///   no permission is asked.
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
    /// macOS 27's allow-list instead of the length.
    private let native = MenuBarAllowList.isAvailable
    public var usesAllowList: Bool { native }
    public var knownShownApps: [String] = []
    public var onShownApps: (([String]) -> Void)?
    /// The allow-list in force, and the plan it follows, while the icons are hidden that way.
    private var assertion: NSObject?
    private var plan: MenuBarHiding.NativePlan?
    /// The icons going one after the other, or coming back.
    private var wave: Task<Void, Never>?
    private var morph: Task<Void, Never>?
    private var askedAccessibility = false

    /// The pause between two apps, so that their icons go one after the other toward the bar.
    private static let waveStep: Duration = .milliseconds(70)

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
                button.image = native ? Self.nativeImage(arrow: 0) : Self.barImage
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
        if native { return hideNatively(item) }
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
        if native { return showNatively() }
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
        // The allow-list does not depend on the screens.
        guard isHiding, !native else { return }
        show()
        recheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled, self.item != nil else { return }
            self.onRecheck?(self.hide())
        }
    }

    // MARK: macOS 27: the allow-list

    private func hideNatively(_ item: NSStatusItem) -> MenuBarHiding.Decision {
        let trusted = AXIsProcessTrusted()
        if let refusal = MenuBarHiding.nativeRefusal(appPath: Bundle.main.bundlePath, accessibilityTrusted: trusted,
                                                     knowsShownApps: !knownShownApps.isEmpty) {
            if refusal == .accessibilityNeeded { askAccessibility() }
            return .refuse(refusal)
        }
        guard let window = item.button?.window, let screen = window.screen ?? NSScreen.main, window.frame.width > 0 else {
            return .refuse(.placeUnknown)
        }
        let barMiddleFromRight = Double(screen.frame.maxX - window.frame.midX)
        let decision = MenuBarHiding.Decision.hide(length: 0)
        isHiding = true
        lastDecision = decision
        item.button?.toolTip = strings.menuBarHidingBarHelpHidden
        item.button?.setAccessibilityLabel(strings.menuBarHidingShow)
        animateArrow(to: 1)
        let (apps, screens) = MenuBarAllowList.snapshot()
        let own = Bundle.main.bundleIdentifier ?? "eu.thanaelfontaine.brimline"
        let known = knownShownApps
        wave?.cancel()
        wave = Task { @MainActor [weak self] in
            let plan: MenuBarHiding.NativePlan
            if trusted {
                let icons = await Task.detached(priority: .userInitiated) {
                    MenuBarAllowList.icons(of: apps, screens: screens)
                }.value
                plan = MenuBarHiding.nativePlan(icons: icons, barMiddleFromRight: barMiddleFromRight, own: own)
            } else {
                // No permission (after an update): the apps found the last time stay, every other one goes at once.
                plan = MenuBarHiding.NativePlan(shown: [own] + known.filter { $0 != own }, hiddenLeftToRight: [])
            }
            guard let self, !Task.isCancelled else { return }
            self.plan = plan
            if trusted, Array(plan.shown.dropFirst()) != self.knownShownApps {
                self.knownShownApps = Array(plan.shown.dropFirst())
                self.onShownApps?(self.knownShownApps)
            }
            // One allow-list per step, each with one app fewer, from the leftmost: the new one is in force before the
            // previous one ends, so nothing comes back in between.
            for count in 1...max(1, plan.hiddenLeftToRight.count) {
                guard let next = await MenuBarAllowList.activate(allowing: plan.allowed(hiding: count)) else {
                    return self.refusedByMacOS()
                }
                guard !Task.isCancelled, self.isHiding else { return MenuBarAllowList.invalidate(next) }
                if let previous = self.assertion { MenuBarAllowList.invalidate(previous) }
                self.assertion = next
                if count < plan.hiddenLeftToRight.count { try? await Task.sleep(for: Self.waveStep) }
            }
        }
        return decision
    }

    private func showNatively() {
        wave?.cancel()
        isHiding = false
        lastDecision = nil
        item?.button?.toolTip = strings.menuBarHidingBarHelp
        item?.button?.setAccessibilityLabel(strings.menuBarHidingBarName)
        animateArrow(to: 0)
        guard let first = assertion else { plan = nil; return }
        let plan = self.plan
        wave = Task { @MainActor [weak self] in
            // Back from the app nearest the bar to the leftmost, then the last allow-list ends.
            var current = first
            if let plan {
                for count in stride(from: plan.hiddenLeftToRight.count - 1, through: 1, by: -1) {
                    try? await Task.sleep(for: Self.waveStep)
                    guard !Task.isCancelled, let next = await MenuBarAllowList.activate(allowing: plan.allowed(hiding: count))
                    else { break }
                    MenuBarAllowList.invalidate(current)
                    current = next
                    self?.assertion = next
                }
            }
            MenuBarAllowList.invalidate(current)
            if self?.assertion === current { self?.assertion = nil; self?.plan = nil }
        }
    }

    /// macOS did not take an allow-list: everything is shown again, and the model is told why.
    private func refusedByMacOS() {
        if let assertion { MenuBarAllowList.invalidate(assertion) }
        assertion = nil
        plan = nil
        showNatively()
        onRecheck?(.refuse(.refusedByMacOS))
    }

    /// The system's own window that opens System Settings at Accessibility, once per launch.
    private func askAccessibility() {
        guard !askedAccessibility else { return }
        askedAccessibility = true
        // The value of kAXTrustedCheckOptionPrompt, a global that Swift 6 does not let be read from here.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The bar turns into the arrow « (1) or back (0) in a few frames.
    private func animateArrow(to target: CGFloat) {
        morph?.cancel()
        morph = Task { @MainActor [weak self] in
            for step in 1...5 {
                let progress = CGFloat(step) / 5
                self?.item?.button?.image = Self.nativeImage(arrow: target == 1 ? progress : 1 - progress)
                if step < 5 { try? await Task.sleep(for: .milliseconds(30)) }
                if Task.isCancelled { return }
            }
        }
    }

    /// The bar (0), the arrow « (1), or a step between: the bar shrinks while the two chevrons appear in its place.
    static func nativeImage(arrow progress: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 16), flipped: false) { rect in
            let midX = rect.midX
            if progress < 1 {
                let height = (rect.height - 3) * (1 - progress)
                let bar = NSBezierPath(roundedRect: NSRect(x: midX - 0.75, y: rect.midY - height / 2, width: 1.5, height: height),
                                       xRadius: 0.75, yRadius: 0.75)
                NSColor.black.withAlphaComponent(1 - progress).setFill()
                bar.fill()
            }
            if progress > 0 {
                let arrows = NSBezierPath()
                let half = 4 * progress
                for tip in [midX - 4.25, midX + 0.25] {
                    arrows.move(to: NSPoint(x: tip + 3.5 * progress, y: rect.midY + half))
                    arrows.line(to: NSPoint(x: tip, y: rect.midY))
                    arrows.line(to: NSPoint(x: tip + 3.5 * progress, y: rect.midY - half))
                }
                arrows.lineWidth = 1.5
                arrows.lineCapStyle = .round
                arrows.lineJoinStyle = .round
                NSColor.black.withAlphaComponent(progress).setStroke()
                arrows.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
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
