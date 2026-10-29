import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import check_text  # noqa: E402


def run_in_repo(files):
    """Runs the checker in a throwaway git repository holding the given {name: text} files."""
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "scripts").mkdir()
        (root / "scripts" / "check_text.py").write_text(Path(check_text.__file__).read_text(encoding="utf-8"), encoding="utf-8")
        for name, text in files.items():
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_text(text, encoding="utf-8")
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        return subprocess.run([sys.executable, "scripts/check_text.py"], cwd=root, capture_output=True, text=True,
                              env={**os.environ, "HOME": d})


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

    def test_finds_the_old_name_in_any_case(self):
        text = "ok\nthe Sightglass app\nfine\nSIGHTGLASS_LANG and sightglass"
        self.assertEqual(check_text.find_old_name("README.md", text), [2, 4])

    def test_a_formerly_line_may_name_the_old_product(self):
        text = "*Formerly Sightglass. Renamed.*\n*Anciennement Sightglass.*\nSightglass alone"
        self.assertEqual(check_text.find_old_name("README.md", text), [3])

    def test_history_and_migration_files_may_name_the_old_product(self):
        for name in ("CHANGELOG.md", "scripts/install.sh", "Sources/BrimlineCore/LegacyMigration.swift"):
            self.assertEqual(check_text.find_old_name(name, "Sightglass"), [], name)
        self.assertEqual(check_text.find_old_name("docs/install.md", "Sightglass"), [1])

    def test_new_name_is_fine(self):
        self.assertEqual(check_text.find_old_name("README.md", "Brimline, sight glass"), [])

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
            out = subprocess.run([sys.executable, "scripts/check_text.py"], cwd=root, capture_output=True, text=True,
                                 env={**os.environ, "HOME": d})
        self.assertEqual(out.returncode, 1)
        self.assertIn("notes 1.md: line 1", out.stdout)
        self.assertIn("été.md: line 1", out.stdout)
        self.assertIn("4 tracked files, 3 problem(s)", out.stdout)

    def test_old_name_is_refused_in_a_text_and_in_a_file_name(self):
        out = run_in_repo({
            "README.md": "# Brimline\n*Formerly Sightglass.*\n",
            "docs/why.md": "Why Sightglass\n",
            "docs/sightglass.md": "fine\n",
            "CHANGELOG.md": "Sightglass is now Brimline.\n",
        })
        self.assertEqual(out.returncode, 1)
        self.assertIn("docs/why.md: line 1: old product name", out.stdout)
        self.assertIn("docs/sightglass.md: old product name in the file name", out.stdout)
        self.assertNotIn("README.md", out.stdout)
        self.assertNotIn("CHANGELOG.md", out.stdout)
        self.assertIn("2 problem(s)", out.stdout)

    def test_self_hosted_runner_is_refused_in_the_workflows_only(self):
        text = "jobs:\n  a:\n    runs-on: [Self-Hosted, macOS]\n"
        self.assertEqual(check_text.find_self_hosted(".github/workflows/checks.yml", text), [3])
        self.assertEqual(check_text.find_self_hosted(".github/workflows/checks.yml", "runs-on: macos-latest\n"), [])
        self.assertEqual(check_text.find_self_hosted("docs/ci.md", text), [])

    def test_a_workflow_with_a_self_hosted_runner_fails_the_check(self):
        out = run_in_repo({
            ".github/workflows/checks.yml": "jobs:\n  a:\n    runs-on: [self-hosted, macOS]\n",
            ".github/workflows/release.yml": "jobs:\n  a:\n    runs-on: macos-latest\n",
        })
        self.assertEqual(out.returncode, 1)
        self.assertIn(".github/workflows/checks.yml: line 3: self-hosted runner", out.stdout)
        self.assertNotIn("release.yml", out.stdout)
        self.assertIn("1 problem(s)", out.stdout)

    def test_the_workflows_of_this_repository_run_on_github_runners(self):
        folder = Path(check_text.__file__).resolve().parent.parent / ".github" / "workflows"
        files = sorted(folder.glob("*.yml"))
        self.assertTrue(files)
        for file in files:
            text = file.read_text(encoding="utf-8")
            self.assertEqual(check_text.find_self_hosted(f".github/workflows/{file.name}", text), [], file.name)
            self.assertIn("runs-on: macos-latest", text, file.name)


if __name__ == "__main__":
    unittest.main()
