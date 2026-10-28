import Foundation
import Testing
@testable import BrimlineCore

/// Hiding the icons placed left of Brimline's bar (QUOTA-73): the length of the bar, when hiding is refused, and when
/// it may leave some icons shown.
/// The numbers come from the measures of 28/10/2026 on macOS 27.0.1 (a 1920 pt screen, no notch).
@Suite("Menu bar hiding: length and checks")
struct MenuBarHidingTests {
    func placement(bar: Double, screen: Double = 1920, brimline: [Double] = [1500]) -> MenuBarHiding.Placement {
        MenuBarHiding.Placement(barLeft: bar, screenWidth: screen, brimlineLefts: brimline)
    }

    @Test("a bar at 838 pt on a 1920 pt screen hides with a length of 921 pt (48 %)")
    func measuredCase() {
        let decision = MenuBarHiding.decide(placement: placement(bar: 838), screenWidths: [1920], macOSMajor: 27)
        #expect(decision == .hide(length: 921, partial: false))
        // Inside the range that pushed in the measures (380 to 940 pt), under the 960 pt where macOS takes the bar out.
        #expect((380...940).contains(921.0))
    }

    @Test("a bar far right still hides, and says that some icons may stay shown")
    func farRightIsPartial() {
        // 921 + 50 = 971: the last place where every icon is surely pushed out.
        #expect(MenuBarHiding.decide(placement: placement(bar: 971), screenWidths: [1920], macOSMajor: 27) == .hide(length: 921, partial: false))
        #expect(MenuBarHiding.decide(placement: placement(bar: 972), screenWidths: [1920], macOSMajor: 27) == .hide(length: 921, partial: true))
        // The bar measured on 28/10/2026 at 1512 pt: 900, 921, 930 and 940 pt pushed it, 950 pt got it taken out.
        #expect(MenuBarHiding.decide(placement: placement(bar: 1512, brimline: [1660]), screenWidths: [1920], macOSMajor: 27)
                == .hide(length: 921, partial: true))
    }

    @Test("with several screens, the narrowest one counts, for the length and for the place")
    func narrowestScreenCounts() {
        #expect(MenuBarHiding.hidingLength(screenWidths: [1920, 1280, 2560], macOSMajor: 27) == 614)
        // 838 pt on the 1920 pt screen is 1082 pt from its right edge, so 198 pt on the 1280 pt one: every icon is pushed.
        #expect(MenuBarHiding.decide(placement: placement(bar: 838), screenWidths: [1920, 1280], macOSMajor: 27) == .hide(length: 614))
        // 1400 pt on the 1920 pt screen is 760 pt on the 1280 pt one: more than 614 + 50, partial.
        #expect(MenuBarHiding.decide(placement: placement(bar: 1400), screenWidths: [1920, 1280], macOSMajor: 27)
                == .hide(length: 614, partial: true))
    }

    @Test("macOS 26 and before keep the formula of Hidden Bar")
    func olderMacOS() {
        #expect(MenuBarHiding.hidingLength(screenWidths: [1920], macOSMajor: 26) == 3840)
        #expect(MenuBarHiding.hidingLength(screenWidths: [200], macOSMajor: 15) == 500)
        #expect(MenuBarHiding.hidingLength(screenWidths: [1440, 6016], macOSMajor: 14) == 10_000)
        // Such a length is never too short for the place of the bar.
        #expect(MenuBarHiding.decide(placement: placement(bar: 1700, brimline: [1800]), screenWidths: [1920], macOSMajor: 26)
                == .hide(length: 3840))
    }

    @Test("macOS 27 and later never use the length that macOS takes the bar out with")
    func modernLengthStaysUnderHalf() {
        for width in [1024.0, 1280, 1440, 1512, 1728, 1920, 2560, 3008, 5120] {
            let length = MenuBarHiding.hidingLength(screenWidths: [width], macOSMajor: 27)!
            #expect(length < width / 2, "\(width)")
            #expect(length == (width * 0.48).rounded(.down))
        }
        #expect(MenuBarHiding.hidingLength(screenWidths: [1920], macOSMajor: 28) == 921)
    }

    @Test("Brimline left of its bar is never hidden: refused")
    func brimlineLeftOfBar() {
        #expect(MenuBarHiding.decide(placement: placement(bar: 838, brimline: [800]), screenWidths: [1920], macOSMajor: 27)
                == .refuse(.brimlineLeftOfBar))
        #expect(MenuBarHiding.decide(placement: placement(bar: 838, brimline: [1500, 838]), screenWidths: [1920], macOSMajor: 27)
                == .refuse(.brimlineLeftOfBar))
    }

    @Test("a place that cannot be read is refused rather than guessed")
    func placeUnknown() {
        #expect(MenuBarHiding.decide(placement: nil, screenWidths: [1920], macOSMajor: 27) == .refuse(.placeUnknown))
        #expect(MenuBarHiding.decide(placement: placement(bar: 838, brimline: []), screenWidths: [1920], macOSMajor: 27)
                == .refuse(.placeUnknown))
        #expect(MenuBarHiding.decide(placement: placement(bar: 838), screenWidths: [], macOSMajor: 27) == .refuse(.placeUnknown))
        #expect(MenuBarHiding.decide(placement: placement(bar: -10), screenWidths: [1920], macOSMajor: 27) == .refuse(.placeUnknown))
        #expect(MenuBarHiding.decide(placement: placement(bar: 2000), screenWidths: [1920], macOSMajor: 27) == .refuse(.placeUnknown))
        #expect(MenuBarHiding.hidingLength(screenWidths: [0], macOSMajor: 27) == nil)
    }

    @Test("the name the bar's place is saved under never changes")
    func autosaveNameIsStable() {
        #expect(MenuBarHiding.autosaveName == "brimline-separator")
    }

    @Test("the setting is off by default, in a new file and in a file written before it")
    func settingOffByDefault() throws {
        #expect(BrimlineSettings().menuBarHiding.enabled == false)
        let old = try JSONCoding.decoder().decode(BrimlineSettings.self, from: Data(#"{"schemaVersion":1,"refreshMinutes":10}"#.utf8))
        #expect(old.menuBarHiding.enabled == false)
        #expect(old.refreshMinutes == 10)
        let broken = try JSONCoding.decoder().decode(BrimlineSettings.self, from: Data(#"{"menuBarHiding":"yes","refreshMinutes":10}"#.utf8))
        #expect(broken.menuBarHiding.enabled == false)
        #expect(broken.refreshMinutes == 10)
    }

    @Test("the setting is saved as menuBarHiding.enabled and read back")
    func settingRoundTrip() throws {
        var settings = BrimlineSettings()
        settings.menuBarHiding.enabled = true
        let data = try JSONCoding.encoder().encode(settings)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((object?["menuBarHiding"] as? [String: Any])?["enabled"] as? Bool == true)
        #expect(try JSONCoding.decoder().decode(BrimlineSettings.self, from: data).menuBarHiding.enabled == true)
    }

    @Test("every text of hiding exists in English and in French, with no dash")
    func texts() {
        for language in Language.allCases {
            let s = Strings(language)
            let all = [s.menuBarHidingTitle, s.menuBarHidingToggle, s.menuBarHidingHowTo, s.menuBarHidingHide,
                       s.menuBarHidingShow, s.menuBarHidingNote, s.menuBarHidingGuide, s.menuBarHidingBarName,
                       s.menuBarHidingBarHelp, s.menuBarHidingBarHelpHidden, s.menuBarHidingDiagramHidden, s.menuBarHidingDiagramShown,
                       s.menuBarHidingDiagramGesture, s.menuBarHidingDiagramSpoken, s.menuBarHidingPartial,
                       s.menuBarHidingHowToAllowList, s.menuBarHidingNoteAllowList]
                + [MenuBarHiding.Refusal.placeUnknown, .brimlineLeftOfBar, .accessibilityNeeded, .notInApplications,
                   .refusedByMacOS].map(s.menuBarHidingRefusal)
            for text in all {
                #expect(!text.isEmpty)
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)")
            }
        }
        #expect(Strings(.fr).menuBarHidingToggle == "Cacher les icônes placées à gauche du trait")
        #expect(Strings(.en).menuBarHidingToggle == "Hide the icons placed left of the bar")
        #expect(Strings(.en).menuBarHidingPartial.hasPrefix("The icons closest to the bar may stay visible"))
        #expect(!Strings(.en).menuBarHidingRefusal(.brimlineLeftOfBar).contains("too far right"))
        #expect(Links.menuBarDoc(.fr).lastPathComponent == "menu-bar.fr.md")
        #expect(Links.menuBarDoc(.en).lastPathComponent == "menu-bar.md")
    }

    @Test("macOS 27: the apps right of the bar and Brimline stay; the others go from the leftmost to the nearest")
    func nativePlan() {
        let icon = { (id: String, fromRight: Double) in MenuBarHiding.MenuBarIcon(bundleIdentifier: id, middleFromRight: fromRight) }
        // The bar's middle at 465 pt from the right edge. Claude has four icons left of it, the clock is right of it.
        let plan = MenuBarHiding.nativePlan(icons: [
            icon("com.anthropic.claudefordesktop", 738), icon("com.anthropic.claudefordesktop", 618),
            icon("com.raycast.macos", 753), icon("com.corsair.ControlCenter", 846),
            icon("com.cron.electron", 688), icon("com.apple.campo", 454), icon("com.kyome.Neo.RunCat", 343),
            icon("eu.thanaelfontaine.brimline", 261), icon("eu.thanaelfontaine.brimline", 478),
        ], barMiddleFromRight: 465, own: "eu.thanaelfontaine.brimline")
        #expect(plan.shown == ["eu.thanaelfontaine.brimline", "com.apple.campo", "com.kyome.Neo.RunCat"])
        #expect(plan.hiddenLeftToRight == ["com.corsair.ControlCenter", "com.raycast.macos",
                                           "com.anthropic.claudefordesktop", "com.cron.electron"])
        #expect(plan.allowed(hiding: 0) == plan.shown + plan.hiddenLeftToRight)
        #expect(plan.allowed(hiding: 1).last == "com.cron.electron" && !plan.allowed(hiding: 1).contains("com.corsair.ControlCenter"))
        #expect(plan.allowed(hiding: 9) == plan.shown)
    }

    @Test("macOS 27: an app with an icon on each side of the bar stays, every icon with it")
    func nativePlanBothSides() {
        let plan = MenuBarHiding.nativePlan(icons: [
            MenuBarHiding.MenuBarIcon(bundleIdentifier: "com.apple.MenuBarAgent", middleFromRight: 700),
            MenuBarHiding.MenuBarIcon(bundleIdentifier: "com.apple.MenuBarAgent", middleFromRight: 200),
        ], barMiddleFromRight: 465, own: "eu.thanaelfontaine.brimline")
        #expect(plan.shown == ["eu.thanaelfontaine.brimline", "com.apple.MenuBarAgent"])
        #expect(plan.hiddenLeftToRight.isEmpty)
    }

    @Test("macOS 27: Brimline hides only from the Applications folder, and with the Accessibility permission")
    func nativeRefusal() {
        #expect(MenuBarHiding.nativeRefusal(appPath: "/Volumes/Disk/Applications/Brimline.app", accessibilityTrusted: true) == .notInApplications)
        #expect(MenuBarHiding.nativeRefusal(appPath: "/Applications/Brimline.app", accessibilityTrusted: false) == .accessibilityNeeded)
        #expect(MenuBarHiding.nativeRefusal(appPath: "/Applications/Brimline.app", accessibilityTrusted: true) == nil)
        // After an update, the permission may be missing: the apps found the last time still let it hide.
        #expect(MenuBarHiding.nativeRefusal(appPath: "/Applications/Brimline.app", accessibilityTrusted: false,
                                            knowsShownApps: true) == nil)
    }
}
