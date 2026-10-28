import AppKit
import Foundation
import Testing
import BrimlineCore
@testable import BrimlineUI

/// The tooltip of the menu bar element is set on its status bar button, since `.help` on the label of a
/// `MenuBarExtra` is lost (real try on macOS 27.0.1, 28/10/2026), and it follows the gauge.
@MainActor
@Suite("Tooltip of the menu bar element")
struct MenuBarTooltipTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func model() -> (AppModel, Account, Account) {
        let a = Account(provider: .claude, source: "/tmp/tooltip/a", email: "a@example.com", organization: nil, seatTier: nil, keychainService: nil)
        let b = Account(provider: .claude, source: "/tmp/tooltip/b", email: "b@example.com", organization: nil, seatTier: nil, keychainService: nil)
        func usage(_ account: Account, _ percent: Double) -> AccountUsage {
            AccountUsage(account: account, status: .ok,
                         limits: [UsageLimit(kind: .session, percent: percent, resetsAt: now.addingTimeInterval(3600))],
                         fetchedAt: now, checkedAt: now)
        }
        let model = AppModel(preview: UsageSnapshot(generatedAt: now, accounts: [usage(a, 20), usage(b, 94)]),
                             settings: BrimlineSettings(), now: now, language: .en,
                             timeZone: TimeZone(identifier: "Europe/Paris")!, home: URL(fileURLWithPath: "/tmp/tooltip"),
                             launchAtLogin: false)
        return (model, a, b)
    }

    /// A window laid out like a status item's: the button two views down.
    private func statusWindow() -> (NSWindow, NSStatusBarButton) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 66, height: 30), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        let holder = NSView(frame: NSRect(x: 0, y: 4, width: 66, height: 22))
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 66, height: 22))
        holder.addSubview(button)
        window.contentView?.addSubview(holder)
        return (window, button)
    }

    @Test("The status bar button is found in the views of its window, and a window without one gives none")
    func findsTheButton() {
        let (window, button) = statusWindow()
        #expect(MenuBarTooltip.statusButton(in: window) === button)
        let empty = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
                             backing: .buffered, defer: true)
        empty.contentView?.addSubview(NSButton(frame: .zero))
        #expect(MenuBarTooltip.statusButton(in: empty) == nil)
    }

    @Test("The button gets the average and the alerts, then the new text when the gauge changes")
    func followsTheGauge() async {
        let (model, a, b) = model()
        let (_, button) = statusWindow()
        let tooltip = MenuBarTooltip(model: model)
        tooltip.attach(button)
        let name = model.gaugeName(forAccountID: b.id)
        #expect(button.toolTip == "Average 57% across 2 accounts · \(name) at 94%")
        #expect(button.toolTip == model.menuBarTooltipText)
        model.setHidden(true, accountID: a.id)
        for _ in 0..<50 where button.toolTip != model.menuBarTooltipText { await Task.yield() }
        #expect(button.toolTip == "Average 94% across 1 account · \(name) at 94%")
        // And again: the tracking is taken anew after each change.
        model.setHidden(true, accountID: b.id)
        for _ in 0..<50 where button.toolTip != model.menuBarTooltipText { await Task.yield() }
        #expect(button.toolTip == "Brimline")
    }
}
