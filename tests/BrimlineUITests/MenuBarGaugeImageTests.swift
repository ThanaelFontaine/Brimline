import AppKit
import Foundation
import Testing
@testable import BrimlineCore
@testable import BrimlineUI

/// The menu bar element (QUOTA-70, board D, variant A "Ras couché"): size, parts in pixels, colors, alert mark.
/// Pixels are read from a bitmap drawn at 1x or 2x; row 0 is the top of the element.
@Suite("Menu bar gauge image")
struct MenuBarGaugeImageTests {
    struct Pixel: Equatable {
        var r, g, b, a: UInt8
        func isColor(_ rgb: UInt32, tolerance: Int = 1) -> Bool {
            a == 255
                && abs(Int(r) - Int((rgb >> 16) & 0xFF)) <= tolerance
                && abs(Int(g) - Int((rgb >> 8) & 0xFF)) <= tolerance
                && abs(Int(b) - Int(rgb & 0xFF)) <= tolerance
        }
        var isEmpty: Bool { a == 0 }
    }

    struct Bitmap {
        let data: [UInt8]
        let width: Int
        let height: Int
        func pixel(_ x: Int, _ y: Int) -> Pixel {
            let i = (y * width + x) * 4
            return Pixel(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3])
        }
    }

    static let black: UInt32 = 0x000000

    func render(_ gauge: GaugeModel, colors: [String: AccountColor] = [:], scale: Int = 2, dark: Bool = false) -> Bitmap {
        let size = CGSize(width: MenuBarGaugeImage.width(accounts: gauge.segments.count), height: MenuBarGaugeImage.height)
        let w = Int(size.width) * scale, h = Int(size.height) * scale
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            MenuBarGaugeImage.draw(gauge, colors: colors, in: ctx, size: size, scale: CGFloat(scale), dark: dark,
                                   label: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        }
        return Bitmap(data: data, width: w, height: h)
    }

    /// A gauge of counted accounts with these percentages (account ids "a0", "a1", ...), average as the total.
    func gauge(_ percents: [Double], stale: Set<Int> = [], providers: [Provider]? = nil) -> GaugeModel {
        let n = Double(percents.count)
        let segments = percents.enumerated().map { i, p in
            GaugeSegment(accountID: "a\(i)", provider: providers?[i] ?? .claude, percent: p,
                         share: min(max(p, 0), 100) / 100 / n, stale: stale.contains(i))
        }
        return GaugeModel(segments: segments, total: min(1, segments.reduce(0) { $0 + $1.share }),
                          mostLoaded: segments.max { $0.percent < $1.percent },
                          alerts: segments.filter { $0.percent >= MenuBarGauge.alertThreshold }.sorted { $0.percent > $1.percent },
                          withoutFigure: [])
    }

    func colors(_ n: Int) -> [String: AccountColor] {
        Dictionary(uniqueKeysWithValues: (0..<n).map { ("a\($0)", AccountColor.palette($0)) })
    }

    // MARK: Size

    @Test("The run and the width follow the number of accounts: 50 pt up to 4, 4 pt more each, 74 pt at 10 and over")
    func widths() {
        #expect(MenuBarGaugeImage.width(accounts: 1) == 50)
        #expect(MenuBarGaugeImage.width(accounts: 4) == 50)
        #expect(MenuBarGaugeImage.width(accounts: 5) == 54)
        #expect(MenuBarGaugeImage.width(accounts: 10) == 74)
        #expect(MenuBarGaugeImage.width(accounts: 25) == 74)
        #expect(MenuBarGaugeImage.width(accounts: 0) == 18)
        for n in 0...40 { #expect(MenuBarGaugeImage.width(accounts: n) <= MenuBarGaugeImage.maxWidth) }
    }

    @Test("The image of a gauge has the width of its accounts, 18 pt high, and is not a template")
    func imageSizeAndTemplate() {
        for n in [1, 3, 10] {
            let image = MenuBarGaugeImage.image(gauge(Array(repeating: 20, count: n)), colors: colors(n))
            #expect(image.size == NSSize(width: MenuBarGaugeImage.width(accounts: n), height: 18))
            #expect(!image.isTemplate)
        }
    }

    @Test("With no counted account the element is the upright template glyph")
    func emptyIsTheTemplateGlyph() {
        let image = MenuBarGaugeImage.image(GaugeModel(), colors: [:], accessibilityDescription: "Brimline")
        #expect(image.isTemplate)
        #expect(image.size == BrimlineGlyph.size)
        #expect(image.accessibilityDescription == "Brimline")
    }

    // MARK: Parts in pixels

    @Test("Parts add up to the rounded total, a part that is not empty has one pixel at least, and never over the run")
    func partPixelsRules() {
        // The example of the board: 10 to 15 %, 25 to 35 %, a small part, over 5 accounts.
        let shares = [0.12 / 5, 0.30 / 5, 0.04 / 5, 0.0, 0.002]
        let total = shares.reduce(0, +)
        let px = MenuBarGaugeImage.partPixels(shares: shares, total: total, runPixels: 80)
        #expect(px.reduce(0, +) <= 80)
        #expect(px[3] == 0)
        for (share, width) in zip(shares, px) where share > 0 { #expect(width >= 1) }
        #expect(abs(px.reduce(0, +) - Int((total * 80).rounded())) <= 1)  // a tiny part takes its pixel from the empty space
    }

    @Test("Random gauges: parts never over the run, none empty when its share is not, order kept (fixed seed)")
    func partPixelsProperty() {
        var generator = SeededGenerator(seed: 2710)
        for _ in 0..<500 {
            let n = Int.random(in: 1...12, using: &generator)
            let percents = (0..<n).map { _ in [0, 0.4, 3, 50, 100, 140].randomElement(using: &generator)! + Double.random(in: 0...1, using: &generator) }
            let g = gauge(percents)
            for runPixels in [80, 128] {
                let px = MenuBarGaugeImage.partPixels(shares: g.segments.map(\.share), total: g.total, runPixels: runPixels)
                #expect(px.count == n)
                #expect(px.reduce(0, +) <= runPixels)
                for (segment, width) in zip(g.segments, px) where segment.share > 0 { #expect(width >= 1) }
            }
        }
    }

    @Test("The widths of the parts drawn, counted in the bitmap, add up to the total and stay in the run (2x)")
    func drawnWidths() {
        let g = gauge([30, 60, 15])    // shares 0.10, 0.20, 0.05 of 80 px: 8, 16 and 4 px
        let b = render(g, colors: colors(3))
        let y = 9 * 2
        func ink(_ x: Int) -> Bool { !b.pixel(x, y).isEmpty }
        // The liquid starts at 3 pt (6 px): 8 + 16 + 4 = 28 px, then nothing until the end of the tank.
        for x in 6..<34 { #expect(ink(x), "px \(x)") }
        #expect(!ink(34))
        #expect(b.pixel(6, y).isColor(AccountColor.palette(0).rgb(dark: false)))
        #expect(b.pixel(13, y).isColor(AccountColor.palette(0).rgb(dark: false)))
        #expect(b.pixel(14, y).isColor(AccountColor.palette(1).rgb(dark: false)))
        #expect(b.pixel(29, y).isColor(AccountColor.palette(1).rgb(dark: false)))
        #expect(b.pixel(30, y).isColor(AccountColor.palette(2).rgb(dark: false)))
        #expect(b.pixel(33, y).isColor(AccountColor.palette(2).rgb(dark: false)))
        // Never over the run: the liquid ends 40 pt (80 px) after it starts.
        for x in 86..<92 { #expect(!ink(x)) }
    }

    @Test("A part that is not empty is at least one pixel, at 1x too")
    func minimumPart() {
        for scale in [1, 2] {
            let g = gauge([100, 0.4])      // 0.4 % of 2 accounts: far under one pixel
            let b = render(g, colors: colors(2), scale: scale)
            let y = 9 * scale
            let start = 3 * scale
            let run = 40 * scale
            let first = (0..<run).filter { b.pixel(start + $0, y).isColor(AccountColor.palette(0).rgb(dark: false)) }.count
            let second = (0..<run).filter { b.pixel(start + $0, y).isColor(AccountColor.palette(1).rgb(dark: false)) }.count
            #expect(second == 1, "scale \(scale)")
            #expect(first + second <= run)
        }
    }

    // MARK: Colors

    @Test("The colors follow the appearance of the bar: the dark value on a dark bar")
    func lightAndDark() {
        let g = gauge([50])
        let light = render(g, colors: ["a0": .palette(0)], dark: false)
        let dark = render(g, colors: ["a0": .palette(0)], dark: true)
        #expect(light.pixel(8, 18).isColor(AccountColor.palette(0).rgb(dark: false)))
        #expect(dark.pixel(8, 18).isColor(AccountColor.palette(0).rgb(dark: true)))
        #expect(AccountColor.palette(0).rgb(dark: false) != AccountColor.palette(0).rgb(dark: true))
    }

    @Test("A free color is drawn as chosen; an account with no color takes the color of its provider")
    func customAndFallback() {
        let g = gauge([50, 50], providers: [.claude, .gemini])
        let b = render(g, colors: ["a0": .custom(hex: "12ab34")!])     // a1 has no color
        // 50 % of 2 accounts: 20 px each at 2x, from px 6.
        #expect(b.pixel(8, 18).isColor(0x12AB34))
        #expect(b.pixel(8 + 20, 18).isColor(AccountPalette.entries[AccountPalette.providerSlot[.gemini]!].light))
    }

    @Test("The last known value is dimmed to the stale opacity")
    func staleIsDimmed() {
        let g = gauge([60, 60], stale: [1])
        let b = render(g, colors: colors(2))
        let fresh = b.pixel(8, 18), stale = b.pixel(8 + 24, 18)
        #expect(fresh.a == 255)
        #expect(abs(Int(stale.a) - Int((AccountPalette.staleOpacity * 255).rounded())) <= 2)
    }

    // MARK: Alert

    // The limit line (or the alert mark) starts 2 pt past the end of the tank: 3 + run + 1.5 + 2 pt at 2x.
    func limitX(run: Int) -> Int { Int((6.5 + Double(run)) * 2) + 1 }

    @Test("From 90 %, the limit line becomes a red mark that is not the color alone: a bar and a dot")
    func alertMark() {
        let calm = render(gauge([50, 20]), colors: colors(2))
        let alert = render(gauge([94, 20]), colors: colors(2))
        let x = limitX(run: 40)
        // No alert: a thin line in the color of the bar's text, full height (y 1 to 17).
        #expect(calm.pixel(x, 4).isColor(Self.black))
        #expect(calm.pixel(x, 24).isColor(Self.black))
        // Alert: the red mark, a bar (y 1 to 11.5) and a dot (y 14.5 to 17), a gap between.
        let red = SGTheme.critRGB(dark: false)
        #expect(alert.pixel(x, 4).isColor(red))
        #expect(alert.pixel(x, 15 * 2 + 1).isColor(red))
        #expect(alert.pixel(x, 12 * 2 + 2).isEmpty, "the gap between the bar and the dot")
        #expect(render(gauge([94, 20]), colors: colors(2), dark: true).pixel(x, 4).isColor(SGTheme.critRGB(dark: true)))
    }

    @Test("The alert mark takes the place of the line: the width never moves")
    func alertDoesNotMoveTheWidth() {
        #expect(render(gauge([89.9, 0])).width == render(gauge([90, 0])).width)
        #expect(!render(gauge([89.9, 0])).pixel(limitX(run: 40), 4).isColor(SGTheme.critRGB(dark: false)))
        #expect(render(gauge([90, 0])).pixel(limitX(run: 40), 4).isColor(SGTheme.critRGB(dark: false)))
    }

    @Test("The tank outline is drawn in the color of the bar's text, closed on the left and open on the right")
    func tank() {
        let b = render(gauge([50, 0]), colors: colors(2))
        #expect(b.pixel(1, 18).isColor(Self.black))                      // the left wall (x 0 to 1.5 pt)
        #expect(b.pixel(20, 6 + 1).isColor(Self.black))                  // the top wall (y 3 to 4.5 pt)
        #expect(b.pixel(20, 29).isColor(Self.black))                     // the floor (y 13.5 to 15 pt)
        // Open on the right: past the end of the tank (x 3 + 40 + 1.5 pt = 44.5 pt) there is only the limit line.
        #expect(b.pixel(Int(44.2 * 2), 18).isEmpty)
    }

    @Test("At 1x the edges sit on whole pixels: no half-covered pixel in the liquid or the line")
    func oneXIsSharp() {
        let g = gauge([94, 40, 10])
        let b = render(g, colors: colors(3), scale: 1)
        for x in 0..<b.width {
            for y in [9, 2, 16] {   // across the liquid, above the tank (the line only) and below it
                let a = b.pixel(x, y).a
                #expect(a == 0 || a == 255, "alpha \(a) at \(x),\(y)")
            }
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
