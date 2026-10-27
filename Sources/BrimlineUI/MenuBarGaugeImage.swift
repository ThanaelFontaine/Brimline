// MenuBarGaugeImage.swift
// Proof of rendering (QUOTA-70, lot L4): a non-template image with colors, in the label of the MenuBarExtra.
import AppKit

public enum MenuBarGaugeImage {
    /// Three colored parts and a label-colored outline, 18 pt high; not a template image.
    public static func proof() -> NSImage {
        let size = NSSize(width: 60, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.455, 0.271, 0.839), (0.110, 0.408, 0.788), (0.690, 0.227, 0.525)]
            for (i, c) in colors.enumerated() {
                ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
                ctx.fill(CGRect(x: 2 + CGFloat(i) * 14, y: 6, width: 14, height: 6))
            }
            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.stroke(CGRect(x: 1.5, y: 3.5, width: 43, height: 11))
            return true
        }
        image.isTemplate = false
        return image
    }
}
