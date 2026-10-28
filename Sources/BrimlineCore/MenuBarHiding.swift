import Foundation

/// Hiding the icons placed left of Brimline's bar (QUOTA-73): the pure part, with no AppKit.
///
/// Brimline never touches another app's icon. When the setting is on, it puts one more item of its own in the menu
/// bar, a thin vertical bar (the "separator"). The person drags, once, with Command held down, the icons to hide to the
/// left of that bar. To hide them, Brimline makes its own bar very long: the bar grows to the left and pushes the icons
/// beside it out of the visible part of the menu bar, where macOS does not draw them. To show them, the bar gets its
/// normal length back. Hidden Bar and Dozer used the same technique before macOS 27.
///
/// On macOS 27 and later, when its menu bar allows it, Brimline uses macOS's own allow-list instead (see `nativePlan`):
/// the icons left of the bar disappear in place, and macOS adds no « of its own. The length technique below stays for
/// older versions of macOS, and for a macOS 27 that no longer offers the allow-list.
///
/// Apple does not document it. Measured on macOS 27.0.1 (a 1920 pt screen, no notch): with the bar at 838 pt, a length
/// between 380 and 940 pt pushes the icons and from 960 pt macOS takes the bar out and hides nothing; with the bar at
/// 1512 pt, 900 to 940 pt push and 950 pt takes it out (10,000, the length of
/// Hidden Bar, no longer works). An icon pushed onto the menus of the app in front is not drawn; one that still fits
/// beside them stays shown. So the length is computed from the screens, and when the bar is so far right that the push
/// may leave some icons shown, the person is told. Not tried on a MacBook with a notch, nor with several screens.
public enum MenuBarHiding {
    /// The name the bar's position is saved under by macOS. Never change it: the place the person dragged the bar to
    /// would be lost. (macOS 27 keeps it in its own file, under the name of the executable and this name; Brimline
    /// never writes that file.)
    public static let autosaveName = "brimline-separator"

    /// The share of the narrowest screen the bar takes when it hides, on macOS 27 and later: under the half of the
    /// screen where macOS takes the bar out (950 pt of 1920 in the measures, 940 still pushed, 921 tried at both places).
    public static let modernShare = 0.48

    /// What stays at the left of the menu bar whatever app is in front (the Apple menu, a short app menu), in points.
    public static let leftMargin = 50.0

    /// The length of the bar that hides, or nil when no screen is known.
    ///
    /// macOS 27 and later: 48 % of the narrowest screen (rounded down). Before: the formula of Hidden Bar,
    /// `max(500, min(2 × widest screen, 10000))`, which those versions accept.
    public static func hidingLength(screenWidths: [Double], macOSMajor: Int) -> Double? {
        let widths = screenWidths.filter { $0 > 0 }
        guard let narrowest = widths.min(), let widest = widths.max() else { return nil }
        if macOSMajor >= 27 { return (narrowest * modernShare).rounded(.down) }
        return max(500, min(2 * widest, 10_000))
    }

    /// Where the bar and Brimline's own icon are, read while the icons are shown (the frames AppKit gives while they
    /// are hidden are wrong).
    public struct Placement: Sendable, Equatable {
        /// The left edge of the bar, from the left edge of its screen, in points.
        public var barLeft: Double
        /// The width of the bar's screen, in points.
        public var screenWidth: Double
        /// The left edge of each of Brimline's own icons (the glyph), on the same screen.
        public var brimlineLefts: [Double]

        public init(barLeft: Double, screenWidth: Double, brimlineLefts: [Double]) {
            self.barLeft = barLeft
            self.screenWidth = screenWidth
            self.brimlineLefts = brimlineLefts
        }
    }

    /// Why the icons were not hidden. Every refusal leaves the icons shown.
    public enum Refusal: String, Sendable, Equatable {
        /// The bar's place or Brimline's icon could not be read: nothing is hidden rather than guessed.
        case placeUnknown
        /// Brimline's own icon is left of the bar: hiding would hide Brimline too, and its panel with the button that
        /// shows the icons again.
        case brimlineLeftOfBar
        /// macOS 27: Brimline needs the Accessibility permission to read which icons are left of its bar.
        case accessibilityNeeded
        /// macOS 27: Brimline runs from somewhere else than the Applications folder, where macOS hides its icons too.
        case notInApplications
        /// macOS 27: macOS did not take the allow-list.
        case refusedByMacOS
    }

    public enum Decision: Sendable, Equatable {
        /// `partial`: the bar is so far right that the longest push macOS accepts may leave the icons nearest the bar
        /// shown (which ones depends on the app in front). The bar still hides what it can.
        case hide(length: Double, partial: Bool = false)
        case refuse(Refusal)
    }

    // MARK: macOS 27: the allow-list

    /// One icon of another app in the menu bar, read through Accessibility: its app, and the distance from the middle
    /// of the icon to the right edge of its screen (the menu bar is laid out from the right edge, so this distance is
    /// the same on every screen).
    public struct MenuBarIcon: Sendable, Equatable {
        public var bundleIdentifier: String
        public var middleFromRight: Double

        public init(bundleIdentifier: String, middleFromRight: Double) {
            self.bundleIdentifier = bundleIdentifier
            self.middleFromRight = middleFromRight
        }
    }

    /// The apps whose icons stay, and the others in the order they disappear.
    public struct NativePlan: Sendable, Equatable {
        /// Kept by the allow-list: Brimline, and every app with at least one icon right of the bar.
        public var shown: [String]
        /// Hidden, from the leftmost to the one nearest the bar, so that they go one after the other toward the arrow.
        public var hiddenLeftToRight: [String]

        public init(shown: [String], hiddenLeftToRight: [String]) {
            self.shown = shown
            self.hiddenLeftToRight = hiddenLeftToRight
        }

        /// The allow-list after the first `count` hidden apps are gone (all of them when `count` is past the end).
        public func allowed(hiding count: Int) -> [String] {
            shown + hiddenLeftToRight.dropFirst(max(0, count))
        }
    }

    /// Which apps keep their icons when the bar hides with macOS's allow-list. The allow-list works per app: an app
    /// with an icon on each side of the bar stays, all its icons with it. Brimline always stays.
    public static func nativePlan(icons: [MenuBarIcon], barMiddleFromRight: Double, own: String) -> NativePlan {
        var nearestRight: [String: Double] = [:]
        for icon in icons where icon.bundleIdentifier != own {
            nearestRight[icon.bundleIdentifier] = min(nearestRight[icon.bundleIdentifier] ?? .infinity, icon.middleFromRight)
        }
        let shown = nearestRight.filter { $0.value <= barMiddleFromRight }.keys.sorted()
        var farthest: [String: Double] = [:]
        for icon in icons where icon.bundleIdentifier != own && !shown.contains(icon.bundleIdentifier) {
            farthest[icon.bundleIdentifier] = max(farthest[icon.bundleIdentifier] ?? 0, icon.middleFromRight)
        }
        let hidden = farthest.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        return NativePlan(shown: [own] + shown, hiddenLeftToRight: hidden)
    }

    /// Whether Brimline may hide with macOS's allow-list, given where it runs from (the path of Brimline.app). Without
    /// the Accessibility permission, it still hides with the apps it found right of the bar the last time, if any.
    public static func nativeRefusal(appPath: String, accessibilityTrusted: Bool, knowsShownApps: Bool = false) -> Refusal? {
        guard appPath.hasPrefix("/Applications/") else { return .notInApplications }
        guard accessibilityTrusted || knowsShownApps else { return .accessibilityNeeded }
        return nil
    }

    /// Whether the icons left of the bar may be hidden, and with which length.
    ///
    /// The menu bar is drawn from the right edge of each screen, so a distance from the right edge is the same on
    /// every screen: the bar's place is carried over to the narrowest screen, the one where the icons have the least
    /// room. There, every icon is surely hidden only when the one just left of the bar is pushed past `leftMargin`:
    /// the hiding is `partial` when `bar's left edge − leftMargin > length`.
    public static func decide(placement: Placement?, screenWidths: [Double], macOSMajor: Int) -> Decision {
        guard let placement, placement.screenWidth > 0,
              placement.barLeft >= 0, placement.barLeft <= placement.screenWidth,
              let length = hidingLength(screenWidths: screenWidths, macOSMajor: macOSMajor),
              let narrowest = screenWidths.filter({ $0 > 0 }).min() else { return .refuse(.placeUnknown) }
        // Brimline must be found, and be right of the bar: it is never hidden, and with it the way back.
        guard !placement.brimlineLefts.isEmpty else { return .refuse(.placeUnknown) }
        guard placement.brimlineLefts.allSatisfy({ $0 > placement.barLeft }) else { return .refuse(.brimlineLeftOfBar) }
        let fromRight = placement.screenWidth - placement.barLeft
        let barLeftOnNarrowest = narrowest - fromRight
        return .hide(length: length, partial: barLeftOnNarrowest - leftMargin > length)
    }
}

/// The setting, saved in `settings.json` as `"menuBarHiding": { "enabled": false, "shownApps": [] }`. Off by default:
/// until it is turned on, Brimline puts nothing more in the menu bar.
public struct MenuBarHidingSettings: Codable, Sendable, Equatable {
    public var enabled: Bool = false
    /// macOS 27: the apps found right of the bar the last time Brimline could read the menu bar (bundle identifiers).
    /// Brimline is signed ad hoc, so macOS ties the Accessibility permission to one build (its grant names the cdhash):
    /// after an update, until the permission is given again, or when nothing could be read, the bar hides with this list.
    public var shownApps: [String] = []

    public init(enabled: Bool = false, shownApps: [String] = []) {
        self.enabled = enabled
        self.shownApps = shownApps
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        shownApps = (try? c.decodeIfPresent([String].self, forKey: .shownApps)) ?? []
    }
}
