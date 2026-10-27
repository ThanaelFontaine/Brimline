"""Checks on the planche of the "Tidy up the menu bar" tab (design/planche-barre.html, QUOTA-73, lot L6).

Kept apart from test_design_tokens.py so that both planches can change without touching the same file.
Run: python3 -m unittest discover -s tests
"""
import json
import re
import unittest
from pathlib import Path

DESIGN = Path(__file__).resolve().parent.parent / "design"
TOKENS = json.loads((DESIGN / "tokens.json").read_text(encoding="utf-8"))
PLANCHE = (DESIGN / "planche-barre.html").read_text(encoding="utf-8")
HEX = re.compile(r"#[0-9A-Fa-f]{6}\b")


class PlancheBarreTest(unittest.TestCase):
    def test_uses_only_token_colors(self):
        allowed = {v["value"].upper() for t in ("light", "dark") for v in TOKENS["color"][t].values()}
        # grays of the simulated menu bar (macOS draws them, they are not tokens)
        extra = {h.upper() for h in HEX.findall(PLANCHE)} - allowed - {"#DADDE0", "#2F3338"}
        self.assertFalse(extra, f"colors outside tokens.json: {sorted(extra)}")

    def test_is_self_contained_without_third_party_logo(self):
        self.assertNotRegex(PLANCHE, r"(?i)(src|href)=[\"']https?:")
        self.assertNotRegex(PLANCHE, r"(?i)@import|url\(\s*[\"']?https?:")
        self.assertNotRegex(PLANCHE, r"(?i)<img|<image|\.(svg|png|jpe?g|webp|icns)[\"')]")

    def test_no_en_or_em_dash(self):
        self.assertNotRegex(PLANCHE, "[\u2013\u2014]")

    def test_both_languages_cover_the_three_apps_and_every_state(self):
        for app in ("claude", "chatgpt", "cursor"):
            self.assertEqual(PLANCHE.count(f"{app}: ['"), 2, app)
        for key in ("none: '", "appErr: a =>", "sysErr: '", "sysBtn: '", "stepsNote: '"):
            self.assertEqual(PLANCHE.count(key), 2, key)


if __name__ == "__main__":
    unittest.main()
