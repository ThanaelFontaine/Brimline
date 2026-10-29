import Foundation
import Testing
import BrimlineCore
@testable import BrimlineUI

/// Hiding the icons left of Brimline's bar (QUOTA-73), seen from the app model: off by default with no bar, a
/// refusal leaves everything shown, turning it off or reopening the app shows every icon again.
@MainActor
@Suite("Menu bar hiding in the app model")
struct MenuBarHidingModelTests {
    /// A bar that records what it is asked and answers what the test says. Nothing real is put in the menu bar.
    @MainActor
    final class FakeBar: MenuBarSeparating {
        var answer: MenuBarHiding.Decision = .hide(length: 864)
        var present: [Bool] = []
        var hides = 0
        var shows = 0
        var hidden = false
        var onRecheck: ((MenuBarHiding.Decision) -> Void)?
        var onClick: (() -> Void)?
        var usesAllowList = false
        var knownShownApps: [String] = []
        var onShownApps: (([String]) -> Void)?
        var hidesWithoutAccessibility = false

        func setPresent(_ present: Bool) {
            self.present.append(present)
        }
        func hide() -> MenuBarHiding.Decision {
            hides += 1
            if case .hide = answer { hidden = true }
            return answer
        }
        func show() {
            shows += 1
            hidden = false
        }
    }

    func model(enabled: Bool = false) -> AppModel {
        var settings = BrimlineSettings()
        settings.menuBarHiding.enabled = enabled
        return AppModel(preview: nil, settings: settings, now: Date(timeIntervalSince1970: 0),
                        language: .en, timeZone: TimeZone(identifier: "UTC")!,
                        home: URL(fileURLWithPath: "/tmp/someone", isDirectory: true))
    }

    @Test("off by default: the bar is never put in the menu bar, and nothing is hidden")
    func offByDefault() {
        let m = model()
        let bar = FakeBar()
        m.attachSeparator(bar)
        #expect(bar.present == [false])
        m.hideMenuBarIcons()
        #expect(bar.hides == 0)
        #expect(!m.menuBarIconsHidden)
    }

    @Test("on: the bar appears with every icon shown, and is asked to hide only by the button")
    func onShowsTheBar() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        #expect(bar.present == [true])
        #expect(!m.menuBarIconsHidden && bar.hides == 0)
        m.toggleMenuBarIcons()
        #expect(m.menuBarIconsHidden && bar.hidden)
        m.toggleMenuBarIcons()
        #expect(!m.menuBarIconsHidden && !bar.hidden)
    }

    @Test("a refusal leaves the icons shown, with the reason, and the next success clears it")
    func refusal() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        bar.answer = .refuse(.brimlineLeftOfBar)
        m.hideMenuBarIcons()
        #expect(!m.menuBarIconsHidden)
        #expect(m.menuBarHidingRefusal == .brimlineLeftOfBar)
        bar.answer = .hide(length: 864)
        m.hideMenuBarIcons()
        #expect(m.menuBarIconsHidden)
        #expect(m.menuBarHidingRefusal == nil)
    }

    @Test("a bar far right hides, with the note that some icons may stay shown, gone once shown again")
    func partial() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        bar.answer = .hide(length: 921, partial: true)
        m.hideMenuBarIcons()
        #expect(m.menuBarIconsHidden && m.menuBarHidingPartial)
        #expect(m.menuBarHidingRefusal == nil)
        m.showMenuBarIcons()
        #expect(!m.menuBarIconsHidden && !m.menuBarHidingPartial)
    }

    @Test("turning the setting off shows every icon, then takes the bar away")
    func turningOffShowsEverything() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        m.hideMenuBarIcons()
        #expect(bar.hidden)
        m.setMenuBarHiding(false)
        #expect(!bar.hidden && bar.shows >= 1)
        #expect(bar.present == [true, false])
        #expect(!m.menuBarIconsHidden && m.menuBarHidingRefusal == nil)
        #expect(!m.settings.menuBarHiding.enabled)
    }

    @Test("a click on the bar hides the icons, a click on the arrow it becomes shows them again")
    func clickToggles() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        m.showMenuBarIcons()
        bar.onClick?()
        #expect(bar.hidden && m.menuBarIconsHidden)
        bar.onClick?()
        #expect(!bar.hidden && !m.menuBarIconsHidden)
    }

    @Test("a refusal after a click on the bar opens Settings on Menu Bar, where it is written")
    func clickRefusedOpensSettings() {
        let m = model(enabled: true)
        let bar = FakeBar()
        bar.answer = .refuse(.brimlineLeftOfBar)
        var opened = 0
        m.openSettingsAction = { opened += 1 }
        m.attachSeparator(bar)
        m.showMenuBarIcons()
        bar.onClick?()
        #expect(!m.menuBarIconsHidden && m.menuBarHidingRefusal == .brimlineLeftOfBar)
        #expect(opened == 1 && m.settingsTab == .menuBar)
    }

    @Test("a hide without the Accessibility permission is said, and showing the icons clears it")
    func withoutAccessibility() {
        let m = model(enabled: true)
        let bar = FakeBar()
        bar.hidesWithoutAccessibility = true
        m.attachSeparator(bar)
        m.hideMenuBarIcons()
        #expect(m.menuBarIconsHidden && m.menuBarHidingWithoutAccessibility)
        m.showMenuBarIcons()
        #expect(!m.menuBarHidingWithoutAccessibility)
        // With the permission back, nothing is said.
        bar.hidesWithoutAccessibility = false
        m.hideMenuBarIcons()
        #expect(m.menuBarIconsHidden && !m.menuBarHidingWithoutAccessibility)
        // A refusal is not a hide: nothing about the permission either.
        m.showMenuBarIcons()
        bar.hidesWithoutAccessibility = true
        bar.answer = .refuse(.refusedByMacOS)
        m.hideMenuBarIcons()
        #expect(!m.menuBarHidingWithoutAccessibility)
    }

    @Test("a click that hides without the permission opens Settings on Menu Bar once per launch")
    func clickWithoutAccessibilityOpensSettingsOnce() {
        let m = model(enabled: true)
        let bar = FakeBar()
        bar.hidesWithoutAccessibility = true
        var opened = 0
        m.openSettingsAction = { opened += 1 }
        m.attachSeparator(bar)
        bar.onClick?()
        #expect(m.menuBarIconsHidden && opened == 1 && m.settingsTab == .menuBar)
        bar.onClick?()
        bar.onClick?()
        #expect(m.menuBarIconsHidden && opened == 1)
    }

    @Test("the button opens the Accessibility list of System Settings, or System Settings when macOS refuses it")
    func openAccessibilityList() {
        let m = model(enabled: true)
        var urls: [URL] = []
        var bundles: [String] = []
        var accept = true
        m.menuBar = MenuBarEnvironment(locate: { _ in nil }, icon: { _ in nil }, openApp: { _ in false },
                                       openURL: { urls.append($0); return accept },
                                       openBundle: { bundles.append($0); return true })
        m.openAccessibilitySettings()
        #expect(urls == [MenuBarTidy.accessibilitySettingsURL] && bundles.isEmpty)
        accept = false
        m.openAccessibilitySettings()
        #expect(bundles == [MenuBarTidy.systemSettingsBundleIdentifier])
    }

    @Test("showing the icons (quit, reopening the app) always gives the bar its normal length")
    func showAlwaysShows() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        m.hideMenuBarIcons()
        m.showMenuBarIcons()
        #expect(!bar.hidden && !m.menuBarIconsHidden)
        // Even when the model already thinks they are shown.
        m.showMenuBarIcons()
        #expect(bar.shows == 2)
    }

    @Test("when the screens change and the check refuses, the model says the icons are shown again, and why")
    func recheckRefused() {
        let m = model(enabled: true)
        let bar = FakeBar()
        m.attachSeparator(bar)
        m.hideMenuBarIcons()
        bar.onRecheck?(.refuse(.brimlineLeftOfBar))
        #expect(!m.menuBarIconsHidden)
        #expect(m.menuBarHidingRefusal == .brimlineLeftOfBar)
    }

    @Test("without a bar yet, the button hides nothing and says why")
    func noBarYet() {
        let m = model(enabled: true)
        m.hideMenuBarIcons()
        #expect(!m.menuBarIconsHidden)
        #expect(m.menuBarHidingRefusal == .placeUnknown)
    }

    @Test("the setting is saved, and the next launch starts with every icon shown")
    func savedAndStartsShown() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("brimline-hiding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let first = AppModel(home: home)
        #expect(!first.settings.menuBarHiding.enabled)
        let bar = FakeBar()
        first.attachSeparator(bar)
        first.setMenuBarHiding(true)
        first.hideMenuBarIcons()
        #expect(first.menuBarIconsHidden)
        let relaunched = AppModel(home: home)
        #expect(relaunched.settings.menuBarHiding.enabled)
        #expect(!relaunched.menuBarIconsHidden)
        let newBar = FakeBar()
        relaunched.attachSeparator(newBar)
        #expect(newBar.present == [true] && newBar.hides == 0)
    }

    @Test("the drawing of the bar is a template image, so it takes the color of the menu bar")
    func barImageIsTemplate() {
        #expect(MenuBarHider.barImage.isTemplate)
        #expect(MenuBarHider.barImage.size.height <= 22)
    }
}
