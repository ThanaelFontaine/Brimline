// SightglassGlyph.swift
// Glyphe de la barre des menus de Sightglass : le voyant de niveau.
// Image gabarit monochrome (noir et transparence) de 18 x 18 pt ; macOS la teinte.
// Le niveau (0 à 1) est la part consommée de la limite la plus proche :
// le liquide monte vers la bride du haut, qui figure la limite.
//
// Géométrie (en points, origine en bas à gauche, cadre 18 x 18) :
//   brides      x 3 à 15 ; 2x : 1,5 pt d'épaisseur (y 1 à 2,5 et 15,5 à 17) ; 1x : 1 pt (y 1 à 2 et 16 à 17)
//   parois      de part et d'autre d'une cavité x 6 à 12 ; 1,5 pt en 2x, 1 pt en 1x
//   liquide     x 7 à 11, 1 pt au-dessus de la bride du bas, monte jusqu'à 1 pt sous la bride du haut
// Tout est aligné sur la grille de pixels en 1x et en 2x pour rester net.

import AppKit

public enum SightglassGlyph {

    /// Taille du glyphe en points.
    public static let size = NSSize(width: 18, height: 18)

    /// Opacité du glyphe quand les données sont expirées ou indisponibles.
    public static let dimmedAlpha: CGFloat = 0.45

    /// Renvoie une image gabarit 18 x 18 pt pour un niveau de 0 à 1.
    /// - Parameters:
    ///   - level: part consommée, de 0 (vide) à 1 (limite atteinte). `nil` : niveau inconnu, tube vide.
    ///   - dimmed: vrai si les données sont expirées ou indisponibles (glyphe atténué).
    public static func image(level: Double?, dimmed: Bool = false) -> NSImage {
        let lvl = level.map { min(max($0, 0), 1) }
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Échelle réelle du support (1x ou 2x) pour aligner sur les pixels.
            let scale = max(1, ctx.userSpaceToDeviceSpaceTransform.a)
            draw(level: lvl, in: ctx, origin: rect.origin, scale: scale,
                 color: NSColor.black.withAlphaComponent(dimmed ? dimmedAlpha : 1).cgColor)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel(level: lvl)
        return image
    }

    /// Libellé VoiceOver par défaut (à localiser dans l'app).
    public static func accessibilityLabel(level: Double?) -> String {
        guard let level else { return "Sightglass" }
        return "Sightglass, \(Int((level * 100).rounded())) %"
    }

    /// Dessine le glyphe dans un contexte CoreGraphics (repère non retourné, 18 x 18 unités).
    /// `scale` : pixels par point du support, pour aligner les bords.
    public static func draw(level: Double?, in ctx: CGContext, origin: CGPoint = .zero,
                            scale: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.setFillColor(color)

        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

        // Mesures : 1x en pixels entiers, 2x et plus au demi-point.
        let hiDPI = scale >= 2
        let flange: CGFloat = hiDPI ? 1.5 : 1        // épaisseur des brides
        let wall: CGFloat = hiDPI ? 1.5 : 1          // épaisseur des parois
        let bottomY: CGFloat = 1                     // bas de la bride du bas
        let topY: CGFloat = 17                       // haut de la bride du haut
        let tubeMinY = bottomY + flange, tubeMaxY = topY - flange
        let liquidMinY = tubeMinY + 1, liquidMaxY = tubeMaxY - 1
        let travel = liquidMaxY - liquidMinY         // 11 pt en 2x, 12 pt en 1x

        // Brides (haut et bas) : la bride du haut figure la limite.
        let flangeRadius: CGFloat = hiDPI ? 0.5 : 0
        for y in [bottomY, tubeMaxY] {
            let r = CGRect(x: 3, y: y, width: 12, height: flange)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: flangeRadius, cornerHeight: flangeRadius, transform: nil))
        }
        ctx.fillPath()

        // Parois du tube de verre, autour d'une cavité de x 6 à 12.
        ctx.fill(CGRect(x: 6 - wall, y: tubeMinY, width: wall, height: tubeMaxY - tubeMinY))
        ctx.fill(CGRect(x: 12, y: tubeMinY, width: wall, height: tubeMaxY - tubeMinY))

        // Liquide : au moins 1 pt dès que le niveau dépasse 0 (1 % se voit) ;
        // la course pleine est réservée à 100 %, pour que 99 % ne se confonde pas avec la limite.
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
