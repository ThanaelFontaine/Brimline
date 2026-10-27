import AppKit
import Testing
@testable import BrimlineUI

/// The menu bar glyph (design "A · Ras"): a limit line above the rim of an open tank, a liquid column inside.
/// Pixels are read from a 2x bitmap, so one design point is two pixels; row 0 is the top of the glyph.
@Suite("Menu bar glyph")
struct BrimlineGlyphTests {
    struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        func alpha(x: Double, y: Double) -> UInt8 { pixels[Int(y * 2) * width + Int(x * 2)] }
        /// Share of the pixels of a rectangle (in points) that carry ink.
        func ink(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
            var on = 0, total = 0
            var py = y.lowerBound
            while py < y.upperBound {
                var px = x.lowerBound
                while px < x.upperBound { total += 1; if alpha(x: px, y: py) > 127 { on += 1 }; px += 0.5 }
                py += 0.5
            }
            return Double(on) / Double(total)
        }
        var total: Int { pixels.filter { $0 > 127 }.count }
    }

    func render(_ level: Double?) -> Bitmap {
        let w = 36
        var data = [UInt8](repeating: 0, count: w * w)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: w, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            ctx.scaleBy(x: 2, y: 2)
            BrimlineGlyph.draw(level: level, in: ctx, scale: 2, color: NSColor.black.cgColor)
        }
        return Bitmap(pixels: data, width: w)
    }

    // The liquid column: x 7 to 11, from y 13 (base) up to y 5 (the rim).
    let column: ClosedRange<Double> = 7.5...10.5

    @Test("the limit line and the tank are always there, even with no level")
    func structureIsAlwaysDrawn() {
        for level in [nil, 0, 0.5, 1] as [Double?] {
            let b = render(level)
            #expect(b.ink(x: 3...15, y: 2.25...3.25) > 0.99, "limit line at \(String(describing: level))")
            #expect(b.ink(x: 4.25...5.25, y: 6...13) > 0.99, "left wall at \(String(describing: level))")
            #expect(b.ink(x: 12.75...13.75, y: 6...13) > 0.99, "right wall at \(String(describing: level))")
            #expect(b.ink(x: 7...11, y: 14.75...15.75) > 0.99, "floor at \(String(describing: level))")
        }
    }

    @Test("the line stays clear of the tank: nothing between the line and the rim")
    func lineIsFreeOfTheRim() {
        #expect(render(1).ink(x: 4...14, y: 3.75...4.75) == 0)
    }

    @Test("an empty tank, or an unknown level, has no liquid")
    func emptyTankHasNoLiquid() {
        for level in [nil, 0] as [Double?] {
            #expect(render(level).ink(x: column, y: 5...14) == 0)
        }
    }

    @Test("the liquid rises with the level, 0, 25, 72, 95 and 100 %")
    func liquidRises() {
        let inks = [0, 0.25, 0.72, 0.95, 1].map { render($0).total }
        #expect(inks == inks.sorted())
        #expect(Set(inks).count == inks.count)
    }

    @Test("1 % already shows a line of liquid")
    func onePercentShows() {
        #expect(render(0.01).ink(x: column, y: 12...13) > 0.99)
    }

    @Test("99 % never reaches the rim: only 100 % fills the whole travel")
    func fullTravelIsReservedFor100() {
        #expect(render(0.99).ink(x: column, y: 5...5.5) == 0)
        #expect(render(1).ink(x: column, y: 5.25...13) > 0.99)
    }

    @Test("the image is an 18 x 18 pt template, and a level outside 0...1 is clamped")
    func imageIsATemplate() {
        let image = BrimlineGlyph.image(level: 1.4)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(BrimlineGlyph.dimmedAlpha == 0.45)
    }
}
