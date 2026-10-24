import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import check_text  # noqa: E402


class CheckTextTest(unittest.TestCase):
    def test_finds_em_and_en_dashes(self):
        text = "ok\nbad " + chr(0x2014) + "\nfine\nbad " + chr(0x2013)
        self.assertEqual(check_text.find_dashes(text), [2, 4])

    def test_plain_hyphen_is_fine(self):
        self.assertEqual(check_text.find_dashes("a - b, c-d"), [])

    def test_finds_personal_paths(self):
        hits = check_text.find_personal_data("README.md", "see /Users/someone/x", check_text.GENERIC_PATTERNS)
        self.assertEqual(len(hits), 1)

    def test_checker_may_quote_its_patterns(self):
        self.assertEqual(check_text.find_personal_data("scripts/check_text.py", "/Users/x", check_text.GENERIC_PATTERNS), [])


if __name__ == "__main__":
    unittest.main()
