"""Checks on the design tokens (design/tokens.json): contrast, both themes, flat template glyph.

Contrast is computed here from the hex values (WCAG 2.2 relative luminance), never read from
the "contrast" figures of the file: those are only compared to the computed ones.
Run: python3 -m unittest discover -s tests
"""
import json
import math
import re
import unittest
from pathlib import Path

DESIGN = Path(__file__).resolve().parent.parent / "design"
TOKENS = json.loads((DESIGN / "tokens.json").read_text(encoding="utf-8"))
THEMES = ("light", "dark")
TEXT_ROLES = ("text", "text2", "accent", "gaugeOk", "gaugeWarn", "gaugeCrit")
GROUNDS = ("bg", "surface")
HEX = re.compile(r"#[0-9A-Fa-f]{6}\b")
PROVIDERS = ("providerClaude", "providerChatgpt", "providerGemini", "providerGrok", "providerCursor")
PLANCHES = ("planche.html", "planche-fournisseurs.html", "planche-comptes.html")
PALETTE = [slot["token"] for slot in TOKENS["accountPalette"]["slots"]]
# Grounds of the menu bar simulated in the planches (macOS draws them, they are not tokens).
MENUBAR = {"light": "#DADDE0", "dark": "#2F3338"}
# Tinted wallpapers of the accounts' planche, and the two custom colors of its settings mock-up.
SIMULATED = {"#DADDE0", "#2F3338", "#E8D3BE", "#C9DCE6", "#26324A", "#3B2A45", "#6A4FD3", "#D5DCE2"}


def luminance(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def lab(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    r, g, b = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116
    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))


def ciede2000(lab1, lab2):
    """CIEDE2000 colour difference (Sharma, Wu, Dalal 2005)."""
    (l1, a1, b1), (l2, a2, b2) = lab1, lab2
    c_bar = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    g = 0.5 * (1 - math.sqrt(c_bar ** 7 / (c_bar ** 7 + 25 ** 7)))
    a1p, a2p = (1 + g) * a1, (1 + g) * a2
    c1p, c2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360 if c1p else 0
    h2p = math.degrees(math.atan2(b2, a2p)) % 360 if c2p else 0
    dh = 0
    if c1p * c2p:
        dh = h2p - h1p
        dh = dh - 360 if dh > 180 else dh + 360 if dh < -180 else dh
    d_l, d_c = l2 - l1, c2p - c1p
    d_h = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dh / 2))
    l_bar, cp_bar = (l1 + l2) / 2, (c1p + c2p) / 2
    h_bar = h1p + h2p
    if c1p * c2p:
        h_bar = h_bar / 2 if abs(h1p - h2p) <= 180 else (h_bar + 360) / 2 if h_bar < 360 else (h_bar - 360) / 2
    t = (1 - 0.17 * math.cos(math.radians(h_bar - 30)) + 0.24 * math.cos(math.radians(2 * h_bar))
         + 0.32 * math.cos(math.radians(3 * h_bar + 6)) - 0.20 * math.cos(math.radians(4 * h_bar - 63)))
    d_theta = 30 * math.exp(-((h_bar - 275) / 25) ** 2)
    r_c = 2 * math.sqrt(cp_bar ** 7 / (cp_bar ** 7 + 25 ** 7))
    s_l = 1 + 0.015 * (l_bar - 50) ** 2 / math.sqrt(20 + (l_bar - 50) ** 2)
    s_c, s_h = 1 + 0.045 * cp_bar, 1 + 0.015 * cp_bar * t
    r_t = -math.sin(math.radians(2 * d_theta)) * r_c
    return math.sqrt((d_l / s_l) ** 2 + (d_c / s_c) ** 2 + (d_h / s_h) ** 2 + r_t * (d_c / s_c) * (d_h / s_h))


def delta_e(a, b):
    return ciede2000(lab(a), lab(b))


def value(theme, role):
    return TOKENS["color"][theme][role]["value"]


class TokensTest(unittest.TestCase):
    def test_both_themes_have_the_same_roles(self):
        self.assertEqual(set(TOKENS["color"]["light"]), set(TOKENS["color"]["dark"]))
        for theme in THEMES:
            for role in TEXT_ROLES + GROUNDS + ("border", "track", "gaugeMuted"):
                self.assertIn(role, TOKENS["color"][theme], f"{theme}.{role}")

    def test_every_color_is_a_hex_value(self):
        for theme in THEMES:
            for role, token in TOKENS["color"][theme].items():
                self.assertRegex(token["value"], r"^#[0-9A-F]{6}$", f"{theme}.{role}")

    def test_text_contrast_at_least_4_5_on_bg_and_surface(self):
        for theme in THEMES:
            for role in TEXT_ROLES:
                for ground in GROUNDS:
                    ratio = contrast(value(theme, role), value(theme, ground))
                    self.assertGreaterEqual(ratio, 4.5, f"{theme}: {role} on {ground} = {ratio:.2f}")

    def test_gauge_colors_at_least_3_on_track(self):
        for theme in THEMES:
            for role in ("gaugeOk", "gaugeWarn", "gaugeCrit"):
                ratio = contrast(value(theme, role), value(theme, "track"))
                self.assertGreaterEqual(ratio, 3.0, f"{theme}: {role} on track = {ratio:.2f}")

    def test_declared_contrast_matches_computed(self):
        for theme in THEMES:
            for role, token in TOKENS["color"][theme].items():
                for ground, declared in token.get("contrast", {}).items():
                    ratio = contrast(token["value"], value(theme, ground))
                    self.assertAlmostEqual(ratio, declared, delta=0.011, msg=f"{theme}.{role} on {ground}")

    def test_provider_dots_at_least_4_5_on_bg_and_surface(self):
        for theme in THEMES:
            for role in PROVIDERS:
                for ground in GROUNDS:
                    ratio = contrast(value(theme, role), value(theme, ground))
                    self.assertGreaterEqual(ratio, 4.5, f"{theme}: {role} on {ground} = {ratio:.2f}")

    def test_provider_dots_are_not_gauge_colors(self):
        # a dot must never read as a gauge state: no provider shares a gauge or accent color
        for theme in THEMES:
            dots = [value(theme, r) for r in PROVIDERS]
            self.assertEqual(len(set(dots)), len(dots), theme)
            gauges = {value(theme, r) for r in ("accent", "gaugeOk", "gaugeWarn", "gaugeCrit", "gaugeMuted")}
            self.assertFalse(set(dots) & gauges, theme)

    def test_thresholds_are_ordered(self):
        self.assertLess(TOKENS["threshold"]["warn"], TOKENS["threshold"]["crit"])
        self.assertLessEqual(TOKENS["threshold"]["crit"], 1)

    def test_planche_and_css_use_only_token_colors(self):
        allowed = {v["value"].upper() for t in THEMES for v in TOKENS["color"][t].values()}
        for name in PLANCHES + ("tokens.css",):
            used = {h.upper() for h in HEX.findall((DESIGN / name).read_text(encoding="utf-8"))}
            # surfaces simulated in the planches are not tokens (macOS draws them), see SIMULATED
            extra = used - allowed - SIMULATED
            self.assertFalse(extra, f"{name}: colors outside tokens.json: {sorted(extra)}")

    def test_planche_is_self_contained(self):
        for name in PLANCHES:
            text = (DESIGN / name).read_text(encoding="utf-8")
            self.assertNotRegex(text, r"(?i)(src|href)=[\"']https?:", name)
            self.assertNotRegex(text, r"(?i)@import|url\(\s*[\"']?https?:", name)
            self.assertNotRegex(text, "[\u2013\u2014]", f"{name}: no en or em dash")
        # these planches draw everything themselves: no image at all, so no third-party logo
        for name in ("planche-fournisseurs.html", "planche-comptes.html"):
            text = (DESIGN / name).read_text(encoding="utf-8")
            self.assertNotRegex(text, r"(?i)<img|<image|\.(svg|png|jpe?g|webp)[\"')]", name)
        text = (DESIGN / "planche.html").read_text(encoding="utf-8")
        for level in ("0 %", "25 %", "50 %", "72 %", "80 %", "95 %", "100 %", "expiré"):
            self.assertIn(level, text)


class AccountPaletteTest(unittest.TestCase):
    """The ten account colors (QUOTA-72): readable in the gauge, distinct, never a gauge state."""

    def test_ciede2000_matches_sharma_reference_values(self):
        # Sharma, Wu, Dalal (2005), test data pairs 1, 7, 17 and 25.
        pairs = [((50, 2.6772, -79.7751), (50, 0, -82.7485), 2.0425),
                 ((50, 0, 0), (50, -1, 2), 2.3669),
                 ((50, 2.5, 0), (73, 25, -18), 27.1492),
                 ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644)]
        for lab1, lab2, expected in pairs:
            self.assertAlmostEqual(ciede2000(lab1, lab2), expected, places=4)

    def test_palette_has_ten_distinct_slots_with_both_themes(self):
        self.assertEqual(len(PALETTE), 10)
        self.assertEqual(len(set(PALETTE)), 10)
        self.assertEqual(PALETTE[:5], list(PROVIDERS))
        for slot in TOKENS["accountPalette"]["slots"]:
            self.assertTrue(slot["fr"] and slot["en"], slot["token"])
            for theme in THEMES:
                self.assertIn(slot["token"], TOKENS["color"][theme])
        palette = TOKENS["accountPalette"]
        self.assertEqual(sorted(palette["freeOrder"]), list(range(5, 10)))
        self.assertEqual({PALETTE[i] for i in palette["providerSlot"].values()}, set(PROVIDERS))

    def test_palette_at_least_3_on_track_grounds_and_menu_bar(self):
        floor = TOKENS["accountPalette"]["minContrast"]
        for theme in THEMES:
            grounds = [value(theme, g) for g in ("track", "bg", "surface")] + [MENUBAR[theme]]
            for role in PALETTE:
                for ground in grounds:
                    ratio = contrast(value(theme, role), ground)
                    self.assertGreaterEqual(ratio, floor, f"{theme}: {role} on {ground} = {ratio:.2f}")

    def test_palette_colors_are_far_apart(self):
        floor = TOKENS["accountPalette"]["minDeltaE"]
        for theme in THEMES:
            for i, a in enumerate(PALETTE):
                for b in PALETTE[i + 1:]:
                    diff = delta_e(value(theme, a), value(theme, b))
                    self.assertGreaterEqual(diff, floor, f"{theme}: {a} / {b} = {diff:.1f}")

    def test_palette_never_reads_as_accent_or_gauge_state(self):
        floor = TOKENS["accountPalette"]["closeWarningDeltaE"]
        for theme in THEMES:
            for role in PALETTE:
                for ref in ("accent", "gaugeOk", "gaugeWarn", "gaugeCrit", "gaugeMuted"):
                    diff = delta_e(value(theme, role), value(theme, ref))
                    self.assertGreaterEqual(diff, floor, f"{theme}: {role} / {ref} = {diff:.1f}")

    def test_css_exposes_the_account_colors(self):
        css = (DESIGN / "tokens.css").read_text(encoding="utf-8").upper()
        for role in PALETTE[5:]:
            for theme in THEMES:
                self.assertIn(value(theme, role).upper(), css, f"{theme}.{role}")

    def test_menubar_item_stays_within_80_pt(self):
        g = TOKENS["menubarGauge"]
        runs = [min(g["runMax"], g["runFewAccounts"] + g["runPerExtraAccount"] * max(0, n - g["fewAccounts"])) for n in range(1, 13)]
        self.assertEqual(runs[3], g["runFewAccounts"])
        self.assertEqual(runs[9], g["runMax"])
        # run + tank wall and insets + gap + room for the alert mark (planche: run + 10)
        self.assertLessEqual(max(runs) + 10, g["maxItemWidth"])
        self.assertLessEqual(g["liquidHeight"] + 2 * g["liquidInset"], g["tankHeight"] - 2)
        self.assertLessEqual(g["lineHeight"], g["imageHeight"])

    def test_planche_shows_every_required_case(self):
        text = (DESIGN / "planche-comptes.html").read_text(encoding="utf-8")
        for needle in ("one:", "three:", "ten:", "thanael:", "nofig:", "stale:", "alert:", "full:", "empty:",
                       "'cells'", "'B'", "'C'", "selL", "selD", "wallL", "wallD", "fr-dark", "en-light"):
            self.assertIn(needle, text)


class IconsTest(unittest.TestCase):
    def test_menubar_template_has_no_color(self):
        svg = (DESIGN / "icons" / "menubar-template.svg").read_text(encoding="utf-8")
        self.assertNotRegex(svg, r"#[0-9A-Fa-f]{3,8}\b")
        self.assertNotRegex(svg, r"(?i)\b(rgb|hsl)a?\(")
        self.assertNotRegex(svg, r"(?i)(fill|stroke|stop-color)=\"(?!currentColor|none)")
        self.assertIn('fill="currentColor"', svg)

    def test_glyph_files_share_the_ras_geometry(self):
        # Design "A · Ras": a limit line above the rim, an open tank, a liquid column.
        limit = '<rect x="2" y="2" width="14" height="1.5" rx="0.75"/>'
        tank = "M4 5H5.5V13.5A1 1 0 0 0 6.5 14.5H11.5A1 1 0 0 0 12.5 13.5V5H14V13.5A2.5 2.5 0 0 1 11.5 16H6.5A2.5 2.5 0 0 1 4 13.5Z"
        for name in (Path("icons") / "menubar-template.svg", Path("glyph-level.svg")):
            svg = (DESIGN / name).read_text(encoding="utf-8")
            self.assertIn(limit, svg, name)
            self.assertIn(tank, svg, name)
            self.assertIn('x="7"', svg, name)
        self.assertIn("var(--level", (DESIGN / "glyph-level.svg").read_text(encoding="utf-8"))

    def test_small_icon_has_no_gradient_detail(self):
        # 16 and 32 px: no halo, reflection or glow, thicker strokes (app-icon-small.svg).
        small = (DESIGN / "icons" / "app-icon-small.svg").read_text(encoding="utf-8")
        self.assertNotIn("-halo)", small)
        self.assertNotIn("filter=\"url(#as-glow)\"", small)

    def test_menubar_template_pdf_exists(self):
        pdf = (DESIGN / "icons" / "menubar-template.pdf").read_bytes()
        self.assertTrue(pdf.startswith(b"%PDF-"))

    def test_app_icon_svg_uses_token_icon_colors(self):
        svg = (DESIGN / "icons" / "app-icon.svg").read_text(encoding="utf-8")
        icon = {v.upper() for v in TOKENS["color"]["icon"].values()}
        for color in ("graphiteTop", "graphiteBottom", "liquidTop", "liquidBottom"):
            self.assertIn(TOKENS["color"]["icon"][color].upper(), svg.upper(), color)
        self.assertTrue(icon)

    def test_icns_is_valid(self):
        icns = (DESIGN / "icons" / "AppIcon.icns").read_bytes()
        self.assertEqual(icns[:4], b"icns")
        self.assertEqual(int.from_bytes(icns[4:8], "big"), len(icns))


if __name__ == "__main__":
    unittest.main()
