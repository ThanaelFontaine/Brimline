import subprocess
import sys
import tempfile
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

    def test_finds_personal_mail_domains(self):
        text = "a@" + "gmail.com\nb@" + "icloud.com\nc@" + "outlook.fr\nyou@example.com"
        hits = check_text.find_personal_data("README.md", text, check_text.GENERIC_PATTERNS)
        self.assertEqual([h.split(":")[0] for h in hits], ["line 1", "line 2", "line 3"])

    def test_checker_may_quote_its_patterns(self):
        self.assertEqual(check_text.find_personal_data("scripts/check_text.py", "/Users/x", check_text.GENERIC_PATTERNS), [])

    def test_local_patterns_merge_files_and_skip_comments(self):
        with tempfile.TemporaryDirectory() as d:
            repo, user = Path(d) / "repo-patterns", Path(d) / "user-patterns"
            repo.write_text("# comment\n\nrepo-secret\n", encoding="utf-8")
            user.write_text("user-secret\n", encoding="utf-8")
            patterns = check_text.local_patterns([repo, user, Path(d) / "missing"])
        self.assertEqual([p.pattern for p in patterns], ["repo-secret", "user-secret"])

    def test_no_local_file_means_no_local_patterns(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(check_text.local_patterns([Path(d) / "missing"]), [])

    def test_names_with_spaces_and_accents_are_checked(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "scripts").mkdir()
            (root / "scripts" / "check_text.py").write_text(Path(check_text.__file__).read_text(encoding="utf-8"), encoding="utf-8")
            for name in ("plain.md", "notes 1.md", "été.md"):
                (root / name).write_text("bad " + chr(0x2014) + "\n", encoding="utf-8")
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
            out = subprocess.run([sys.executable, "scripts/check_text.py"], cwd=root, capture_output=True, text=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn("notes 1.md: line 1", out.stdout)
        self.assertIn("été.md: line 1", out.stdout)
        self.assertIn("4 tracked files, 3 problem(s)", out.stdout)


if __name__ == "__main__":
    unittest.main()
