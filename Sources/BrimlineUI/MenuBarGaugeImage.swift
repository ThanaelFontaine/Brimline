// MenuBarGaugeImage.swift
// The menu bar element of Brimline (QUOTA-70, board D, variant A "Ras couché"): the glyph lies down and its tank
// becomes the gauge. The liquid is made of one part per account, packed to the left in the panel's order, each in
// the color of its account; beyond the liquid, the limit line stands free (an "!" in red from 90 %, never touching the tank).
//
// Geometry (points, origin at the top left, y down; same numbers as design/tokens.json, `menubarGauge`):
//   image    18 pt high, `run + 10` pt wide (50 to 74 pt)
//   tank     y 3 to 15, closed on the left (outer radius 2.5), open on the right, stroke `t`
//   liquid   y 6 to 12, `inset` from the walls; `run` pt long: 40 up to 4 accounts, 4 more per account, 64 at 10 and over
//   limit    y 1 to 17, 2 pt past the tank; the alert mark takes its place, so the width never moves
// `t` is 1.5 pt at 2x and 2 pt at 1x (so a screen without Retina gets the same bold outline, not a 1 pixel one),
// `inset` 1.5 pt at 2x and 1 pt at 1x. Everything sits on the pixel grid.
//
// The image is not a template: Brimline resolves the outline color and the account colors for the real appearance of
// the bar at drawing time, so a dark bar on a Mac in light mode gets the dark values. With no counted account the
// element is the upright template glyph (`BrimlineGlyph`), empty tank.

import AppKit
import BrimlineCore

public enum MenuBarGaugeImage {

    // MARK: Measures

    public static let height: CGFloat = 18
    /// The widest the element may be.
    public static let maxWidth: CGFloat = 80
    /// Accounts up to this number share the shortest run.
    public static let fewAccounts = 4
    public static let runFewAccounts: CGFloat = 40
    public static let runPerExtraAccount: CGFloat = 4
    public static let runMax: CGFloat = 64
    /// What the element takes besides the run: walls, gaps and the limit line (or the alert mark).
    public static let extraWidth: CGFloat = 10

    /// The length of the liquid for `accounts` counted accounts.
    public static func run(accounts: Int) -> CGFloat {
        min(runMax, runFewAccounts + runPerExtraAccount * CGFloat(max(0, accounts - fewAccounts)))
    }

    /// The width of the element for `accounts` counted accounts (the upright glyph when there is none).
    public static func width(accounts: Int) -> CGFloat {
        accounts <= 0 ? BrimlineGlyph.size.width : run(accounts: accounts) + extraWidth
    }

    // MARK: Parts in pixels

    /// The width of each part in whole pixels of a run of `runPixels`. The parts add up to the rounded total
    /// (largest remainder first), a part that is not empty is at least one pixel (taken from the empty space),
    /// and the parts never go over the run.
    public static func partPixels(shares: [Double], total: Double, runPixels: Int) -> [Int] {
        let exact = shares.map { $0 * Double(runPixels) }
        var pixels = exact.map { Int($0.rounded(.down)) }
        let target = min(runPixels, Int((total * Double(runPixels)).rounded()))
        var rest = target - pixels.reduce(0, +)
        let order = exact.indices.sorted { a, b in
            let ra = exact[a] - exact[a].rounded(.down), rb = exact[b] - exact[b].rounded(.down)
            return ra != rb ? ra > rb : a < b
        }
        for i in order where rest > 0 && shares[i] > 0 {
            pixels[i] += 1
            rest -= 1
        }
        for i in pixels.indices where shares[i] > 0 && pixels[i] == 0 { pixels[i] = 1 }
        var over = pixels.reduce(0, +) - runPixels
        while over > 0, let widest = pixels.indices.max(by: { pixels[$0] != pixels[$1] ? pixels[$0] < pixels[$1] : $0 > $1 }) {
            pixels[widest] -= 1
            over -= 1
        }
        return pixels
    }

    // MARK: Colors

    /// The color of an account's part: the one chosen in the settings, else the color of its provider.
    public static func color(of segment: GaugeSegment, in colors: [String: AccountColor]) -> AccountColor {
        colors[segment.accountID] ?? .palette(AccountPalette.providerSlot[segment.provider] ?? 0)
    }

    // MARK: Image

    /// The element for a gauge. `colors`: the account colors of the settings (by account id).
    /// With no counted account: the upright template glyph, empty tank.
    public static func image(_ gauge: GaugeModel, colors: [String: AccountColor], accessibilityDescription: String? = nil) -> NSImage {
        guard !gauge.segments.isEmpty else {
            let image = BrimlineGlyph.image(level: nil)
            if let accessibilityDescription { image.accessibilityDescription = accessibilityDescription }
            return image
        }
        let size = NSSize(width: width(accounts: gauge.segments.count), height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = max(1, ctx.userSpaceToDeviceSpaceTransform.a)
            let appearance = NSAppearance.currentDrawing()
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            var label = NSColor.labelColor.cgColor
            appearance.performAsCurrentDrawingAppearance { label = NSColor.labelColor.cgColor }  // the bar's text color
            draw(gauge, colors: colors, in: ctx, size: size, scale: scale, dark: dark, label: label)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// Draws the element in a CoreGraphics context (unflipped, `size` in points).
    /// - Parameters:
    ///   - scale: pixels per point of the surface (1 or 2), to align every edge on a pixel.
    ///   - dark: the appearance of the bar, to pick the light or the dark value of each color.
    ///   - label: the color of the text of the bar, for the outline of the tank and the limit line.
    public static func draw(_ gauge: GaugeModel, colors: [String: AccountColor], in ctx: CGContext,
                            size: CGSize, scale: CGFloat, dark: Bool, label: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        let hiDPI = scale >= 2
        let t: CGFloat = hiDPI ? 1.5 : 2
        let inset: CGFloat = hiDPI ? 1.5 : 1
        let run = run(accounts: gauge.segments.count)
        let liquidStart = t + inset
        let tankEnd = liquidStart + run + inset
        let limitX = tankEnd + 2

        // The tank: closed on the left, open on the right.
        ctx.setFillColor(label)
        ctx.addPath(tankPath(end: tankEnd, thickness: t))
        ctx.fillPath()

        // The parts, packed to the left, in whole pixels.
        let runPixels = Int((run * scale).rounded())
        let pixels = partPixels(shares: gauge.segments.map(\.share), total: gauge.total, runPixels: runPixels)
        var x = Int((liquidStart * scale).rounded())
        for (segment, width) in zip(gauge.segments, pixels) where width > 0 {
            let rgb = color(of: segment, in: colors).rgb(dark: dark)
            ctx.setFillColor(cgColor(rgb, alpha: segment.stale ? CGFloat(AccountPalette.staleOpacity) : 1))
            ctx.fill(CGRect(x: CGFloat(x) / scale, y: 6, width: CGFloat(width) / scale, height: 6))
            x += width
        }

        // The limit line, or the alert mark in its place.
        if gauge.alerts.isEmpty {
            ctx.setFillColor(label)
            let w: CGFloat = hiDPI ? 1.5 : 2
            ctx.addPath(CGPath(roundedRect: CGRect(x: limitX, y: 1, width: w, height: 16),
                               cornerWidth: hiDPI ? 0.75 : 0, cornerHeight: hiDPI ? 0.75 : 0, transform: nil))
            ctx.fillPath()
        } else {
            ctx.setFillColor(cgColor(SGTheme.critRGB(dark: dark)))
            if hiDPI {
                ctx.addPath(CGPath(roundedRect: CGRect(x: limitX, y: 1, width: 2.5, height: 10.5),
                                   cornerWidth: 1.25, cornerHeight: 1.25, transform: nil))
                ctx.addEllipse(in: CGRect(x: limitX, y: 14.5, width: 2.5, height: 2.5))
                ctx.fillPath()
            } else {
                ctx.fill(CGRect(x: limitX, y: 1, width: 2, height: 10))
                ctx.fill(CGRect(x: limitX, y: 15, width: 2, height: 2))
            }
        }
        ctx.restoreGState()
    }

    /// The lying tank as one outline: y 3 to 15, outer radius 2.5 on the left, open on the right at `end`.
    static func tankPath(end: CGFloat, thickness t: CGFloat) -> CGPath {
        let top: CGFloat = 3, bottom: CGFloat = 15, r: CGFloat = 2.5, ri = r - t
        let p = CGMutablePath()
        p.move(to: CGPoint(x: end, y: top))
        p.addLine(to: CGPoint(x: r, y: top))
        p.addArc(tangent1End: CGPoint(x: 0, y: top), tangent2End: CGPoint(x: 0, y: top + r), radius: r)
        p.addLine(to: CGPoint(x: 0, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: 0, y: bottom), tangent2End: CGPoint(x: r, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: end, y: bottom))
        p.addLine(to: CGPoint(x: end, y: bottom - t))
        p.addLine(to: CGPoint(x: t + ri, y: bottom - t))
        p.addArc(tangent1End: CGPoint(x: t, y: bottom - t), tangent2End: CGPoint(x: t, y: bottom - t - ri), radius: ri)
        p.addLine(to: CGPoint(x: t, y: top + t + ri))
        p.addArc(tangent1End: CGPoint(x: t, y: top + t), tangent2End: CGPoint(x: t + ri, y: top + t), radius: ri)
        p.addLine(to: CGPoint(x: end, y: top + t))
        p.closeSubpath()
        return p
    }

    private static func cgColor(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
