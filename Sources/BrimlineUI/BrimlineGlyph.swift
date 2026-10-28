// BrimlineGlyph.swift
// The menu bar glyph of Brimline: a tank with a free line above its rim (design "A · Ras").
// A monochrome template image (black and transparency), 18 x 18 pt; macOS tints it.
// The level (0 to 1) is the share used of the closest limit:
// the liquid rises toward the rim of the tank, and the line above the rim stands for the limit.
//
// Geometry (in points, origin at the top left, 18 x 18 frame; same numbers as design/icons/menubar-template.svg):
//   line        x 2 to 16, y 2, thickness t (1.5 pt at 2x, 2 pt at 1x), round ends
//   tank        open U, x 4 to 14, rim at y 5, bottom at y 16, outer corner radius 2.5, walls and floor of thickness t
//   liquid      x 7 to 11, from y 13 up to y 5 at most (8 pt of travel)
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
    ///   - level: share used, from 0 (empty) to 1 (limit reached). `nil`: unknown level, empty tank.
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
        // Work in the top-left, y-down coordinates of the design files.
        ctx.translateBy(x: origin.x, y: origin.y + size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(color)

        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

        // Stroke thickness: 1.5 pt at 2x and over; 2 whole pixels at 1x, so that a screen without Retina gets the
        // same bold stroke instead of a thin 1 pixel one.
        let hiDPI = scale >= 2
        let t: CGFloat = hiDPI ? 1.5 : 2
        let outerRadius: CGFloat = 2.5
        let innerRadius = outerRadius - t

        // The line above the rim: the limit.
        let lineRect = CGRect(x: 2, y: 2, width: 14, height: t)
        ctx.addPath(CGPath(roundedRect: lineRect, cornerWidth: t / 2, cornerHeight: t / 2, transform: nil))
        ctx.fillPath()

        // The open tank: a U with walls and floor of thickness t.
        let left: CGFloat = 4, right: CGFloat = 14, rim: CGFloat = 5, bottom: CGFloat = 16
        let tank = CGMutablePath()
        tank.move(to: CGPoint(x: left, y: rim))
        tank.addLine(to: CGPoint(x: left + t, y: rim))
        tank.addArc(tangent1End: CGPoint(x: left + t, y: bottom - t), tangent2End: CGPoint(x: right - t, y: bottom - t), radius: innerRadius)
        tank.addArc(tangent1End: CGPoint(x: right - t, y: bottom - t), tangent2End: CGPoint(x: right - t, y: rim), radius: innerRadius)
        tank.addLine(to: CGPoint(x: right - t, y: rim))
        tank.addLine(to: CGPoint(x: right, y: rim))
        tank.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: left, y: bottom), radius: outerRadius)
        tank.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: rim), radius: outerRadius)
        tank.closeSubpath()
        ctx.addPath(tank)
        ctx.fillPath()

        // Liquid: at least 1 pt as soon as the level is above 0 (1% shows);
        // the full travel is kept for 100%, so that 99% is never mistaken for the limit.
        if let level, level > 0 {
            let base: CGFloat = 13
            let travel = base - rim                    // 8 pt
            var h = snap(CGFloat(level) * travel)
            h = max(h, 1)
            if level < 1 { h = min(h, travel - 1 / scale) }
            h = min(h, travel)
            let r = CGRect(x: 7, y: base - h, width: 4, height: h)
            let radius: CGFloat = hiDPI ? 0.5 : 0
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}
