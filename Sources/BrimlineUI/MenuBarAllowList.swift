import AppKit
import ApplicationServices
import BrimlineCore
import ObjectiveC

/// macOS 27's own way to keep only some apps' icons in the menu bar: the allow-list of its assessment mode, in the
/// private framework MenuBarClientCore. Hidden Bar 1.11.1 (18 September 2026) hides with it on macOS 27, and so does
/// Brimline when it is there (see `MenuBarHiding.nativePlan`).
///
/// - Every icon of an app that is not on the list disappears in place; the system items (clock, Wi-Fi, Control
///   Center) always stay. macOS adds no « of its own.
/// - It lasts until `invalidate`, or until Brimline's process ends: macOS then shows every icon again by itself.
/// - Apple does not document it: it is looked up when Brimline runs, so a macOS that changes or removes it only makes
///   `isAvailable` false, and Brimline falls back to the length of its bar.
@MainActor
enum MenuBarAllowList {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationClassName = "MBAssessmentModeConfiguration"
    private static let assertionClassName = "MBAssessmentModeAssertion"
    private static let configurationInit = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")
    /// Every system item is kept (the same range as Hidden Bar).
    private static let systemItems = (0..<64).map { NSNumber(value: $0) }

    private typealias InitFunction = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> AnyObject?
    private typealias ActivateFunction = @convention(c) (AnyObject, Selector, AnyObject,
                                                         @escaping @convention(block) (NSError?) -> Void) -> Void

    /// Whether this macOS has the allow-list, with the calls Brimline makes.
    static let isAvailable: Bool = {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
              dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil,
              let configuration = NSClassFromString(configurationClassName),
              let assertion = NSClassFromString(assertionClassName) else { return false }
        return class_respondsToSelector(configuration, configurationInit)
            && class_respondsToSelector(assertion, activateSelector)
            && class_respondsToSelector(assertion, invalidateSelector)
    }()

    /// Keeps the icons of the apps given, and of the system; hides every other app's. Nil when macOS refused.
    static func activate(allowing bundles: [String]) async -> NSObject? {
        guard isAvailable,
              let configurationClass = NSClassFromString(configurationClassName) as? NSObject.Type,
              let assertionClass = NSClassFromString(assertionClassName) as? NSObject.Type,
              let raw = configurationClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
        let initialize = unsafeBitCast(class_getMethodImplementation(configurationClass, configurationInit),
                                       to: InitFunction.self)
        // Both lists must be arrays: the framework reads them by index.
        guard let configuration = initialize(raw, configurationInit, systemItems as NSArray, bundles as NSArray) else {
            return nil
        }
        let assertion = assertionClass.init()
        let activate = unsafeBitCast(class_getMethodImplementation(assertionClass, activateSelector),
                                     to: ActivateFunction.self)
        let accepted: Bool = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            activate(assertion, activateSelector, configuration) { error in once.resume(returning: error == nil) }
        }
        return accepted ? assertion : nil
    }

    /// Resumes the wait once, should macOS call the completion handler more than once.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

        func resume(returning value: Bool) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    /// Ends one allow-list: the icons it hid come back, unless a newer one hides them.
    static func invalidate(_ assertion: NSObject) {
        if assertion.responds(to: invalidateSelector) { assertion.perform(invalidateSelector) }
    }

    /// The other running apps that may have icons in the menu bar, and the screens, read on the main thread.
    static func snapshot() -> (apps: [(pid: pid_t, bundle: String)], screens: [CGRect]) {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid: pid_t, bundle: String)? in
            guard app.processIdentifier != own, let bundle = app.bundleIdentifier else { return nil }
            return (app.processIdentifier, bundle)
        }
        return (apps, NSScreen.screens.map(\.frame))
    }

    /// The icons of those apps in the menu bar, read through Accessibility, away from the main thread (each app
    /// answers within 0.2 s, or is left out). Needs the Accessibility permission.
    nonisolated static func icons(of apps: [(pid: pid_t, bundle: String)], screens: [CGRect]) -> [MenuBarHiding.MenuBarIcon] {
        var icons: [MenuBarHiding.MenuBarIcon] = []
        for (pid, bundle) in apps {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
                  let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let children = children as? [AXUIElement] else { continue }
            for child in children {
                guard let frame = frame(of: child),
                      let screen = screens.first(where: { $0.minX <= frame.midX && frame.midX < $0.maxX }) else { continue }
                icons.append(MenuBarHiding.MenuBarIcon(bundleIdentifier: bundle,
                                                       middleFromRight: Double(screen.maxX - frame.midX)))
            }
        }
        return icons
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent), extent.width > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
