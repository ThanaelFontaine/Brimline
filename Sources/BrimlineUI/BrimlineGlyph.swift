// BrimlineGlyph.swift
// The menu bar glyph of Brimline: the level sight glass.
// A monochrome template image (black and transparency), 18 x 18 pt; macOS tints it.
// The level (0 to 1) is the share used of the closest limit:
// the liquid rises toward the top flange, which stands for the limit.
//
// Geometry (in points, origin at the bottom left, 18 x 18 frame):
//   flanges     x 3 to 15; 2x: 1.5 pt thick (y 1 to 2.5 and 15.5 to 17); 1x: 1 pt (y 1 to 2 and 16 to 17)
//   walls       on each side of a cavity x 6 to 12; 1.5 pt at 2x, 1 pt at 1x
//   liquid      x 7 to 11, 1 pt above the bottom flange, rises to 1 pt under the top flange
// Everything sits on the pixel grid at 1x and 2x to stay sharp.

import AppKit
import BrimlineCore

public enum BrimlineGlyph {

    /// Size of the glyph in points.
    public static let size = NSSize(width: 18, height: 18)

    /// Opacity of the glyph when the numbers are expired or unavailable.
    public static let dimmedAlpha: CGFloat = 0.45

    /// Returns an 18 x 18 pt template image for a level from 0 to 1.
    /// - Parameters:
    ///   - level: share used, from 0 (empty) to 1 (limit reached). `nil`: unknown level, empty tube.
    ///   - dimmed: true when the numbers are expired or unavailable (dimmed glyph).
    public static func image(level: Double?, dimmed: Bool = false) -> NSImage {
        let lvl = level.map { min(max($0, 0), 1) }
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Real scale of the surface (1x or 2x), to align on pixels.
            let scale = max(1, ctx.userSpaceToDeviceSpaceTransform.a)
            draw(level: lvl, in: ctx, origin: rect.origin, scale: scale,
                 color: NSColor.black.withAlphaComponent(dimmed ? dimmedAlpha : 1).cgColor)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel(level: lvl)
        return image
    }

    /// Default VoiceOver label, in the language of the interface.
    public static func accessibilityLabel(level: Double?) -> String {
        guard let level else { return "Brimline" }
        return Strings().menuBarAccessibility(level * 100)
    }

    /// Draws the glyph in a CoreGraphics context (unflipped, 18 x 18 units).
    /// `scale`: pixels per point of the surface, to align the edges.
    public static func draw(level: Double?, in ctx: CGContext, origin: CGPoint = .zero,
                            scale: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.setFillColor(color)

        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

        // Sizes: whole pixels at 1x, half points at 2x and over.
        let hiDPI = scale >= 2
        let flange: CGFloat = hiDPI ? 1.5 : 1        // flange thickness
        let wall: CGFloat = hiDPI ? 1.5 : 1          // wall thickness
        let bottomY: CGFloat = 1                     // bottom of the bottom flange
        let topY: CGFloat = 17                       // top of the top flange
        let tubeMinY = bottomY + flange, tubeMaxY = topY - flange
        let liquidMinY = tubeMinY + 1, liquidMaxY = tubeMaxY - 1
        let travel = liquidMaxY - liquidMinY         // 11 pt at 2x, 12 pt at 1x

        // Flanges (top and bottom): the top flange stands for the limit.
        let flangeRadius: CGFloat = hiDPI ? 0.5 : 0
        for y in [bottomY, tubeMaxY] {
            let r = CGRect(x: 3, y: y, width: 12, height: flange)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: flangeRadius, cornerHeight: flangeRadius, transform: nil))
        }
        ctx.fillPath()

        // Walls of the glass tube, around a cavity from x 6 to 12.
        ctx.fill(CGRect(x: 6 - wall, y: tubeMinY, width: wall, height: tubeMaxY - tubeMinY))
        ctx.fill(CGRect(x: 12, y: tubeMinY, width: wall, height: tubeMaxY - tubeMinY))

        // Liquid: at least 1 pt as soon as the level is above 0 (1% shows);
        // the full travel is kept for 100%, so that 99% is never mistaken for the limit.
        if let level, level > 0 {
            var h = snap(CGFloat(level) * travel)
            h = max(h, 1)
            if level < 1 { h = min(h, travel - 1 / scale) }
            h = min(h, travel)
            ctx.fill(CGRect(x: 7, y: liquidMinY, width: 4, height: h))
        }
        ctx.restoreGState()
    }
}
