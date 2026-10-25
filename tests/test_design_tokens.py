"""Checks on the design tokens (design/tokens.json): contrast, both themes, flat template glyph.

Contrast is computed here from the hex values (WCAG 2.2 relative luminance), never read from
the "contrast" figures of the file: those are only compared to the computed ones.
Run: python3 -m unittest discover -s tests
"""
import json
import re
import unittest
from pathlib import Path

DESIGN = Path(__file__).resolve().parent.parent / "design"
TOKENS = json.loads((DESIGN / "tokens.json").read_text(encoding="utf-8"))
THEMES = ("light", "dark")
TEXT_ROLES = ("text", "text2", "accent", "gaugeOk", "gaugeWarn", "gaugeCrit")
GROUNDS = ("bg", "surface")
HEX = re.compile(r"#[0-9A-Fa-f]{6}\b")


def luminance(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


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

    def test_thresholds_are_ordered(self):
        self.assertLess(TOKENS["threshold"]["warn"], TOKENS["threshold"]["crit"])
        self.assertLessEqual(TOKENS["threshold"]["crit"], 1)

    def test_planche_and_css_use_only_token_colors(self):
        allowed = {v["value"].upper() for t in THEMES for v in TOKENS["color"][t].values()}
        for name in ("planche.html", "tokens.css"):
            used = {h.upper() for h in HEX.findall((DESIGN / name).read_text(encoding="utf-8"))}
            # grays of the simulated menu bar in the planche are not tokens (macOS draws them)
            extra = used - allowed - {"#DADDE0", "#2F3338"}
            self.assertFalse(extra, f"{name}: colors outside tokens.json: {sorted(extra)}")

    def test_planche_is_self_contained(self):
        text = (DESIGN / "planche.html").read_text(encoding="utf-8")
        self.assertNotRegex(text, r"(?i)(src|href)=[\"']https?:")
        self.assertNotRegex(text, r"(?i)@import|url\(\s*[\"']?https?:")
        for level in ("0 %", "50 %", "80 %", "100 %"):
            self.assertIn(level, text)


class IconsTest(unittest.TestCase):
    def test_menubar_template_has_no_color(self):
        svg = (DESIGN / "icons" / "menubar-template.svg").read_text(encoding="utf-8")
        self.assertNotRegex(svg, r"#[0-9A-Fa-f]{3,8}\b")
        self.assertNotRegex(svg, r"(?i)\b(rgb|hsl)a?\(")
        self.assertNotRegex(svg, r"(?i)(fill|stroke|stop-color)=\"(?!currentColor|none)")
        self.assertIn('fill="currentColor"', svg)

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
