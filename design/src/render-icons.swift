// render-icons.swift : produit les images de la DA de Brimline (icône, favicons, og, aperçu, gabarit PDF).
// Compilation : ce fichier sert de main.swift, avec BrimlineGlyph.swift et les sources de BrimlineCore
// dans un seul module (sans la ligne `import BrimlineCore`) : swiftc -O -swift-version 6 -enable-bare-slash-regex
// Usage : ./render <dossier da>

import AppKit
import ImageIO
import UniformTypeIdentifiers

let OUT = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func nsrgb(_ v: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(cgColor: rgb(v, a))! }

/// Crée une image w x h pixels dans un repère retourné (origine en haut à gauche), et l'écrit en PNG.
func png(_ w: Int, _ h: Int, _ path: String, opaque: Bool = false, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    ctx.setShouldSmoothFonts(false)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    let img = ctx.makeImage()!
    let url = URL(fileURLWithPath: OUT + "/" + path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

/// Exécute `body` dans un repère non retourné de hauteur h, dont l'origine est en bas à gauche de `rect`.
func unflipped(_ ctx: CGContext, _ rect: CGRect, _ body: () -> Void) {
    ctx.saveGState(); ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1); body(); ctx.restoreGState()
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// MARK: - Icône (piste A · Ras : une cuve ouverte, et au-dessus de son bord un trait libre, la limite)

/// Dessine l'icône, avec les coordonnées de `icons/app-icon.svg` (grille macOS 1024 : carré arrondi de 824 à 100 du bord,
/// y vers le bas). `square` : le carré arrondi (en coordonnées du contexte non retourné).
/// `detail` : faux pour les très petites tailles (16 et 32 px : pas de reflet, de ménisque ni de halo, traits plus épais),
/// comme `icons/app-icon-small.svg`.
/// `fullBleed` : fond carré plein, sans arrondi ni ombre (apple-touch-icon).
func drawIcon(_ ctx: CGContext, square: CGRect, detail: Bool = true, fullBleed: Bool = false, level: CGFloat = 0.62) {
    let u = square.width / 824
    let shape = fullBleed ? CGPath(rect: square, transform: nil)
        : CGPath(roundedRect: square, cornerWidth: 185.4 * u, cornerHeight: 185.4 * u, transform: nil)

    // Ombre portée de la grille macOS.
    if !fullBleed {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: rgb(0x000000, 0.32))
        ctx.addPath(shape); ctx.setFillColor(rgb(0x14181B)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // À partir d'ici : coordonnées du SVG (y vers le bas, carré arrondi de (100, 100) à (924, 924)).
    ctx.translateBy(x: square.minX, y: square.maxY)
    ctx.scaleBy(x: u, y: -u)
    ctx.translateBy(x: -100, y: -100)
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

    // Fond graphite, puis halo très léger derrière la cuve (grandes tailles seulement).
    linear(ctx, [rgb(0x2C333A), rgb(0x111417)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    if detail {
        let halo = CGGradient(colorsSpace: sRGB, colors: [rgb(0x3BBDC2, 0.18), rgb(0x3BBDC2, 0)] as CFArray, locations: nil)!
        ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
    }

    /// Cuve ouverte : intérieur (x0...x1, du bord `top` au fond `bottom`, coins de rayon `r`).
    func inner(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat, _ bottom: CGFloat, _ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: top)); p.addLine(to: CGPoint(x: x1, y: top))
        p.addLine(to: CGPoint(x: x1, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: x1, y: bottom), tangent2End: CGPoint(x: x1 - r, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: x0 + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: x0, y: bottom), tangent2End: CGPoint(x: x0, y: bottom - r), radius: r)
        p.closeSubpath(); return p
    }
    /// Parois de la cuve : l'anneau entre l'intérieur et l'extérieur, ouvert en haut (des pieds arrondis de rayon `cap`).
    func walls(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat, _ bottom: CGFloat, _ r: CGFloat, _ thick: CGFloat, cap: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let ro = r + thick
        p.move(to: CGPoint(x: x0 - thick, y: top))
        if cap > 0 {
            p.addArc(tangent1End: CGPoint(x: x0 - thick, y: top - cap), tangent2End: CGPoint(x: x0, y: top - cap), radius: cap)
            p.addArc(tangent1End: CGPoint(x: x0, y: top - cap), tangent2End: CGPoint(x: x0, y: top), radius: cap)
        } else { p.addLine(to: CGPoint(x: x0, y: top)) }
        p.addLine(to: CGPoint(x: x0, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: x0, y: bottom), tangent2End: CGPoint(x: x0 + r, y: bottom), radius: r)
        p.addLine(to: CGPoint(x: x1 - r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: x1, y: bottom), tangent2End: CGPoint(x: x1, y: bottom - r), radius: r)
        p.addLine(to: CGPoint(x: x1, y: top))
        if cap > 0 {
            p.addArc(tangent1End: CGPoint(x: x1, y: top - cap), tangent2End: CGPoint(x: x1 + thick, y: top - cap), radius: cap)
            p.addArc(tangent1End: CGPoint(x: x1 + thick, y: top - cap), tangent2End: CGPoint(x: x1 + thick, y: top), radius: cap)
        } else { p.addLine(to: CGPoint(x: x1 + thick, y: top)) }
        p.addLine(to: CGPoint(x: x1 + thick, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: x1 + thick, y: bottom + thick), tangent2End: CGPoint(x: x1 + thick - ro, y: bottom + thick), radius: ro)
        p.addLine(to: CGPoint(x: x0 - thick + ro, y: bottom + thick))
        p.addArc(tangent1End: CGPoint(x: x0 - thick, y: bottom + thick), tangent2End: CGPoint(x: x0 - thick, y: bottom - r), radius: ro)
        p.closeSubpath(); return p
    }

    if detail {
        ctx.translateBy(x: 0, y: -20)
        let glass = inner(380, 644, 388, 736, 68)
        // Verre de la cuve.
        ctx.addPath(glass); ctx.setFillColor(rgb(0xFFFFFF, 0.06)); ctx.fillPath()
        // Liquide (62 % par défaut) et son ménisque.
        let top = 736 - level * 348
        ctx.saveGState(); ctx.addPath(glass); ctx.clip()
        ctx.clip(to: R(380, top, 264, 736 - top))
        linear(ctx, [rgb(0x4FD0D6), rgb(0x0E7C86)], from: CGPoint(x: 512, y: top), to: CGPoint(x: 512, y: 736))
        ctx.setFillColor(rgb(0xA6ECEE, 0.85)); ctx.fill(R(380, top, 264, 10))
        ctx.restoreGState()
        // Reflet.
        ctx.addPath(rounded(R(404, 410, 20, 270), 10)); ctx.setFillColor(rgb(0xFFFFFF, 0.18)); ctx.fillPath()
        // Parois de verre.
        ctx.addPath(walls(380, 644, 388, 736, 68, 28, cap: 14)); ctx.setFillColor(rgb(0xFFFFFF, 0.34)); ctx.fillPath()
        // Le trait, sa lueur d'abord (flou gaussien de 16 : l'ombre d'une copie hors cadre en tient lieu).
        ctx.saveGState()
        let far: CGFloat = 4000
        ctx.setShadow(offset: CGSize(width: far * u, height: 0), blur: 32 * u, color: rgb(0x3BBDC2, 0.45))
        ctx.addPath(rounded(R(282 - far, 300, 460, 44), 22)); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(rounded(R(282, 300, 460, 44), 22)); ctx.clip()
        linear(ctx, [rgb(0xFFFFFF), rgb(0xC9D1D8)], from: CGPoint(x: 512, y: 300), to: CGPoint(x: 512, y: 344))
        ctx.restoreGState()
    } else {
        ctx.translateBy(x: 0, y: -18)
        let glass = inner(388, 636, 400, 724, 54)
        let top = 724 - level * 324
        ctx.saveGState(); ctx.addPath(glass); ctx.clip()
        ctx.setFillColor(rgb(0x3BBDC2)); ctx.fill(R(388, top, 248, 724 - top))
        ctx.restoreGState()
        ctx.addPath(walls(388, 636, 400, 724, 54, 56, cap: 0)); ctx.setFillColor(rgb(0xE6EAED)); ctx.fillPath()
        ctx.addPath(rounded(R(272, 280, 480, 72), 36)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    }
    ctx.restoreGState()

    // Liseré intérieur du carré.
    if !fullBleed {
        ctx.saveGState()
        ctx.translateBy(x: square.minX, y: square.minY)
        let inset = 2 * u
        ctx.addPath(CGPath(roundedRect: square.offsetBy(dx: -square.minX, dy: -square.minY).insetBy(dx: inset, dy: inset),
                           cornerWidth: 183.4 * u, cornerHeight: 183.4 * u, transform: nil))
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(4 * u); ctx.strokePath()
        ctx.restoreGState()
    }
}

func iconPNG(_ px: Int, _ name: String) {
    png(px, px, name) { ctx in
        let s = CGFloat(px)
        unflipped(ctx, CGRect(x: 0, y: 0, width: s, height: s)) {
            drawIcon(ctx, square: CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024),
                     detail: px > 32)
        }
    }
}

// MARK: - Palette et texte

struct Palette {
    let bg, surface, text, text2, border, track, accent, ok, warn, crit: UInt32
    static let light = Palette(bg: 0xF5F6F7, surface: 0xFFFFFF, text: 0x15191D, text2: 0x56606A, border: 0xD3D8DD,
                               track: 0xE7EAED, accent: 0x0B6E7A, ok: 0x127A82, warn: 0x9A5800, crit: 0xC0302B)
    static let dark = Palette(bg: 0x111315, surface: 0x1B1E21, text: 0xECEFF2, text2: 0x9BA5AF, border: 0x30353A,
                              track: 0x2B3035, accent: 0x5CC8D0, ok: 0x3BBDC2, warn: 0xEFA63A, crit: 0xFF6F64)
    func level(_ f: CGFloat) -> UInt32 { f >= 0.9 ? crit : (f >= 0.7 ? warn : ok) }
}

enum Align { case left, right, center }

@discardableResult
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
          color: UInt32, alpha: CGFloat = 1, align: Align = .left, mono: Bool = false, width: CGFloat? = nil) -> CGSize {
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
    para.alignment = align == .left ? .left : (align == .right ? .right : .center)
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: nsrgb(color, alpha), .paragraphStyle: para])
    if let width {
        let r = a.boundingRect(with: NSSize(width: width, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        a.draw(with: NSRect(x: x, y: y, width: width, height: r.height + 4), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return r.size
    }
    let sz = a.size()
    let dx: CGFloat = align == .left ? 0 : (align == .right ? -sz.width : -sz.width / 2)
    a.draw(at: NSPoint(x: x + dx, y: y))
    return sz
}

func roundRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, line: CGFloat = 1) {
    let p = CGPath(roundedRect: r, cornerWidth: min(radius, r.height / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
    if let fill { ctx.addPath(p); ctx.setFillColor(fill); ctx.fillPath() }
    if let stroke { ctx.addPath(p); ctx.setStrokeColor(stroke); ctx.setLineWidth(line); ctx.strokePath() }
}

enum GaugeState { case value(CGFloat), expired(CGFloat), unavailable }

/// Jauge en repère retourné : capsule de hauteur h, repères à 70 et 90 %.
func gauge(_ ctx: CGContext, _ r: CGRect, _ state: GaugeState, _ p: Palette) {
    roundRect(ctx, r, r.height / 2, fill: rgb(p.track))
    ctx.setFillColor(rgb(p.border))
    for t in [0.7, 0.9] as [CGFloat] { ctx.fill(CGRect(x: (r.minX + r.width * t).rounded() - 0.5, y: r.minY, width: 1, height: r.height)) }
    switch state {
    case .value(let f) where f > 0:
        roundRect(ctx, CGRect(x: r.minX, y: r.minY, width: max(r.height, r.width * min(f, 1)), height: r.height), r.height / 2, fill: rgb(p.level(f)))
    case .expired(let f):
        roundRect(ctx, CGRect(x: r.minX, y: r.minY, width: max(r.height, r.width * f), height: r.height), r.height / 2, fill: rgb(p.text2, 0.55))
    default: break
    }
    if case .unavailable = state {
        ctx.saveGState(); ctx.setLineDash(phase: 0, lengths: [2, 2])
        roundRect(ctx, r.insetBy(dx: 0.5, dy: 0.5), r.height / 2, stroke: rgb(p.border), line: 1)
        ctx.restoreGState()
    } else {
        roundRect(ctx, r.insetBy(dx: 0.25, dy: 0.25), r.height / 2, stroke: rgb(p.border), line: 0.5)
    }
}

/// Glyphe en repère retourné : cadre carré de côté 18*k, couleur donnée.
func glyph(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, k: CGFloat, level: Double?, color: CGColor) {
    unflipped(ctx, CGRect(x: x, y: y, width: 18 * k, height: 18 * k)) {
        ctx.scaleBy(x: k, y: k)
        BrimlineGlyph.draw(level: level, in: ctx, scale: max(2, k), color: color)
    }
}

// MARK: - Carte de compte (maquette), repère retourné, en points (k = facteur d'échelle)

func card(_ ctx: CGContext, x: CGFloat, y: CGFloat, k: CGFloat, _ p: Palette) {
    ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.scaleBy(x: k, y: k)
    let W: CGFloat = 340, pad: CGFloat = 16, inner = W - 2 * pad - 8
    typealias Row = (String, GaugeState, String, String)
    let accounts: [(String, String, [Row], String?)] = [
        ("you@example.com", "Example Team · Team", [
            ("Session 5 h", .value(0.34), "34 %", "repart dans 2 h 10 (14:30)"),
            ("Semaine · Fable", .value(0.72), "72 %", "repart dans 3 j (mar. 09:00)"),
            ("Semaine · Opus", .value(0.93), "93 %", "repart dans 3 j (mar. 09:00)"),
        ], "Pas de limite hebdomadaire globale"),
        ("team@example.org", "Example Org · Max", [
            ("Session 5 h", .expired(0.58), "58 %", "valeur d'il y a 3 h · repart à 16:00"),
        ], "Session expirée : ouvrez Claude Code avec ce compte pour la reconnecter."),
    ]
    func noteHeight(_ n: String?) -> CGFloat {
        guard let n else { return 0 }
        let r = NSAttributedString(string: n, attributes: [.font: NSFont.systemFont(ofSize: 11)])
            .boundingRect(with: NSSize(width: inner, height: 500), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(r.height) + 6
    }
    func blockHeight(_ rows: Int, _ note: String?) -> CGFloat { 12 + 18 + 22 + CGFloat(rows) * 48 + noteHeight(note) + 8 }
    let H = 46 + accounts.reduce(0) { $0 + blockHeight($1.2.count, $1.3) + 8 } + 40

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: rgb(0x000000, 0.18))
    roundRect(ctx, CGRect(x: 0, y: 0, width: W, height: H), 12, fill: rgb(p.bg))
    ctx.restoreGState()
    roundRect(ctx, CGRect(x: 0.5, y: 0.5, width: W - 1, height: H - 1), 12, stroke: rgb(p.border), line: 1)
    var cy: CGFloat = 14
    glyph(ctx, pad - 2, cy - 1, k: 1, level: 0.93, color: rgb(p.text))
    text("Brimline", pad + 20, cy, size: 13, weight: .semibold, color: p.text)
    cy += 32

    for (email, org, rows, note) in accounts {
        let h = blockHeight(rows.count, note)
        roundRect(ctx, CGRect(x: 8, y: cy, width: W - 16, height: h), 10, fill: rgb(p.surface), stroke: rgb(p.border), line: 0.5)
        var y = cy + 12
        text(email, pad + 4, y, size: 13, weight: .semibold, color: p.text); y += 18
        text(org, pad + 4, y, size: 11, color: p.text2); y += 22
        for (label, st, pct, reset) in rows {
            text(label, pad + 4, y, size: 12, color: p.text)
            text(pct, W - pad - 4, y, size: 12, weight: .semibold, color: p.text, align: .right, mono: true)
            gauge(ctx, CGRect(x: pad + 4, y: y + 20, width: inner, height: 6), st, p)
            text(reset, pad + 4, y + 30, size: 11, color: p.text2)
            y += 48
        }
        if let note { text(note, pad + 4, y, size: 11, weight: .medium, color: p.text2, width: inner) }
        cy += h + 8
    }

    // Pied : boutons sans cadre, comme les fenêtres de barre des menus du système.
    let fy = H - 30
    ctx.setFillColor(rgb(p.border)); ctx.fill(CGRect(x: 0, y: fy - 10, width: W, height: 0.5))
    text("Actualisé à 12:20", pad, fy, size: 11, color: p.text2)
    var bx = W - pad
    for b in ["Quitter", "Réglages…", "Actualiser"] {
        let w = (b as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        bx -= w
        text(b, bx, fy - 1, size: 12, weight: b == "Actualiser" ? .medium : .regular, color: b == "Actualiser" ? p.accent : p.text)
        bx -= 14
    }
    ctx.restoreGState()
}

// MARK: - Sorties

// 1. Icône : iconset complet (noms attendus par iconutil).
let iconSizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"), (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"), (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in iconSizes { iconPNG(px, "AppIcon.iconset/" + name) }

// 2. Site : favicon PNG 32 et 16, apple-touch-icon 180 (plein cadre, opaque, iOS arrondit lui-même).
iconPNG(32, "favicon-32.png")
iconPNG(16, "favicon-16.png")
png(180, 180, "apple-touch-icon.png", opaque: true) { ctx in
    unflipped(ctx, CGRect(x: 0, y: 0, width: 180, height: 180)) {
        drawIcon(ctx, square: CGRect(x: 0, y: 0, width: 180, height: 180), detail: true, fullBleed: true)
    }
}

// 3. Image de partage 1200 x 630.
png(1200, 630, "og.png", opaque: true) { ctx in
    let p = Palette.dark
    ctx.setFillColor(rgb(p.bg)); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
    let halo = CGGradient(colorsSpace: sRGB, colors: [rgb(0x3BBDC2, 0.10), rgb(0x3BBDC2, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 250, y: 315), startRadius: 0, endCenter: CGPoint(x: 250, y: 315), endRadius: 420, options: [])
    unflipped(ctx, CGRect(x: 70, y: 135, width: 360, height: 360)) {
        drawIcon(ctx, square: CGRect(x: 360 * 100 / 1024, y: 360 * 100 / 1024, width: 360 * 824 / 1024, height: 360 * 824 / 1024))
    }
    let x: CGFloat = 470
    text("Brimline", x, 150, size: 76, weight: .semibold, color: p.text)
    text("See how much of every AI subscription you have left.", x, 252, size: 38, color: p.text2, width: 660)
    // Trois jauges d'exemple.
    let rows: [(String, CGFloat)] = [("5-hour session", 0.34), ("Week, all models", 0.72), ("Week · Fable", 0.93)]
    var y: CGFloat = 400
    for (label, f) in rows {
        text(label, x, y, size: 22, color: p.text)
        text("\(Int((f * 100).rounded()))%", 1130, y, size: 22, weight: .semibold, color: p.text, align: .right, mono: true)
        gauge(ctx, CGRect(x: x, y: y + 34, width: 660, height: 10), .value(f), p)
        y += 64
    }
    text("A calm macOS menu bar gauge · source-available", x, 590, size: 18, color: p.text2)
}

// 4. Aperçu de la DA.
png(1600, 1320, "apercu.png", opaque: true) { ctx in
    let L = Palette.light, D = Palette.dark
    ctx.setFillColor(rgb(0xE9ECEF)); ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1320))
    text("Brimline · direction artistique", 64, 40, size: 28, weight: .semibold, color: L.text)
    text("Icône, glyphe de la barre des menus, carte de compte en clair et en sombre", 64, 80, size: 16, color: L.text2)

    // Icône.
    unflipped(ctx, CGRect(x: 40, y: 120, width: 300, height: 300)) {
        drawIcon(ctx, square: CGRect(x: 300 * 100 / 1024, y: 300 * 100 / 1024, width: 300 * 824 / 1024, height: 300 * 824 / 1024))
    }
    text("AppIcon", 190, 424, size: 13, color: L.text2, align: .center)
    // Petites tailles de l'icône.
    var ix: CGFloat = 90
    for s in [16, 32, 64] as [CGFloat] {
        unflipped(ctx, CGRect(x: ix, y: 520 - s, width: s, height: s)) {
            drawIcon(ctx, square: CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024), detail: s > 32)
        }
        text("\(Int(s)) px", ix + s / 2, 526, size: 11, color: L.text2, align: .center)
        ix += s + 40
    }

    // Glyphe agrandi (x4), clair et sombre.
    let levels: [(Double, String)] = [(0, "0 %"), (0.25, "25 %"), (0.72, "72 %"), (0.95, "95 %")]
    for (row, pal) in [(0, L), (1, D)] {
        let y0: CGFloat = 130 + CGFloat(row) * 150
        roundRect(ctx, CGRect(x: 380, y: y0, width: 560, height: 130), 12, fill: rgb(pal.surface), stroke: rgb(pal.border))
        for (i, (lv, label)) in levels.enumerated() {
            let gx = 410 + CGFloat(i) * 130
            glyph(ctx, gx, y0 + 14, k: 4, level: lv, color: rgb(pal.text))
            text(label, gx + 36, y0 + 100, size: 13, weight: .semibold, color: pal.text, align: .center, mono: true)
        }
    }
    text("Gabarit 18 pt ×4 : le liquide monte vers le bord, le trait au-dessus est la limite", 380, 418, size: 13, color: L.text2)

    // Barres des menus simulées, taille réelle en 2x (18 pt = 36 px).
    for (row, pal) in [(0, L), (1, D)] {
        let y0: CGFloat = 130 + CGFloat(row) * 150
        let bar = CGRect(x: 980, y: y0 + 41, width: 560, height: 48)
        roundRect(ctx, bar, 10, fill: rgb(row == 0 ? 0xF2F2F4 : 0x26292D), stroke: rgb(pal.border))
        var bx: CGFloat = 1000
        for (lv, label) in [(0.25, "25 %"), (0.72, "72 %"), (0.95, "95 %")] as [(Double, String)] {
            glyph(ctx, bx, y0 + 47, k: 2, level: lv, color: rgb(pal.text))
            text(label, bx + 40, y0 + 53, size: 26, weight: .medium, color: pal.text, mono: true)
            bx += 122
        }
        glyph(ctx, bx + 6, y0 + 47, k: 2, level: 0.58, color: rgb(pal.text, BrimlineGlyph.dimmedAlpha))
        text("expiré", bx + 48, y0 + 53, size: 26, color: pal.text, alpha: BrimlineGlyph.dimmedAlpha)
    }
    text("Barre des menus, taille réelle en 2x, pourcentage affiché", 980, 418, size: 13, color: L.text2)

    // Cartes de compte.
    card(ctx, x: 300, y: 580, k: 1.5, L)
    card(ctx, x: 860, y: 580, k: 1.5, D)
}
// 5. Gabarit de la barre des menus en PDF vectoriel (noir et transparence, niveau 60 %), comme icons/menubar-template.svg.
do {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let info = [kCGPDFContextTitle: "Brimline menubar template"] as CFDictionary
    if let consumer = CGDataConsumer(url: URL(fileURLWithPath: OUT + "/menubar-template.pdf") as CFURL),
       let pdf = CGContext(consumer: consumer, mediaBox: &box, info) {
        pdf.beginPDFPage(nil)
        BrimlineGlyph.draw(level: 0.6, in: pdf, scale: 2, color: rgb(0x000000))
        pdf.endPDFPage(); pdf.closePDF()
    }
}
print("ok")
