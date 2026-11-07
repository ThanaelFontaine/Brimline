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
        self.assertIn(".github/workflows/checks.yml: line 3: runner not hosted by GitHub", out.stdout)
        self.assertNotIn("release.yml", out.stdout)
        self.assertIn("2 problem(s)", out.stdout)

    def test_a_runner_label_must_be_one_hosted_by_github(self):
        text = "jobs:\n  a:\n    runs-on: [macOS, ARM64]\n  b:\n    runs-on: macOS\n  c:\n    runs-on: macos-latest\n  d:\n    runs-on: ubuntu-24.04 # comment\n"
        self.assertEqual(check_text.find_unhosted_runners(".github/workflows/checks.yml", text), [3, 5])
        self.assertEqual(check_text.find_unhosted_runners("docs/ci.md", text), [])

    def test_an_action_must_be_pinned_by_a_full_commit_sha(self):
        sha = "3d3c42e5aac5ba805825da76410c181273ba90b1"
        text = (f"steps:\n  - uses: actions/checkout@v7\n  - uses: actions/checkout@{sha} # v7.0.1\n"
                f"  - uses: ./.github/actions/local\n  - uses: actions/setup-node@{sha[:12]}\n")
        self.assertEqual(check_text.find_unpinned_actions(".github/workflows/checks.yml", text), [2, 5])
        self.assertEqual(check_text.find_unpinned_actions("docs/ci.md", text), [])

    def test_runner_forms_that_cannot_be_checked_are_refused(self):
        refused = {
            "made-up label": "    runs-on: macos-mini\n",
            "expression": "    runs-on: ${{ matrix.os }}\n",
            "block of two items": "    runs-on:\n      - macos-latest\n      - ARM64\n",
            "runner group": "    runs-on:\n      group: home\n",
            "space before the colon": "    runs-on : macos-latest\n",
            "quoted key": '    "runs-on": macOS\n',
            "quoted key, list": '    "runs-on": [macOS, ARM64]\n',
            "flow style": '  a: {"runs-on": "macOS", steps: [{run: x}]}\n',
            "JSON": '{"jobs": {"a": {"runs-on": "macOS", "steps": []}}}\n',
            "escaped key": '    "runs\\u002don": macOS\n',
            "explicit key": "    ? runs-on\n    : macOS\n",
        }
        for name, body in refused.items():
            with self.subTest(name):
                self.assertNotEqual(check_text.find_unhosted_runners(".github/workflows/x.yml", "jobs:\n  a:\n" + body), [], name)
        accepted = "jobs:\n  a:\n    runs-on: [macos-latest]\n  b:\n    runs-on:\n      - 'ubuntu-latest'\n"
        self.assertEqual(check_text.find_unhosted_runners(".github/workflows/x.yml", accepted), [])

    def test_self_hosted_in_a_comment_after_a_valid_label(self):
        text = "jobs:\n  a:\n    runs-on: macos-latest # not self-hosted\n"
        self.assertEqual(check_text.find_unhosted_runners(".github/workflows/x.yml", text), [])
        self.assertEqual(check_text.find_self_hosted(".github/workflows/x.yml", text), [3])

    def test_self_hosted_written_with_an_escape_is_found(self):
        text = 'jobs:\n  a:\n    env:\n      X: "self-host\\x65d"\n'
        self.assertEqual(check_text.find_self_hosted(".github/workflows/x.yml", text), [4])

    def test_action_forms_that_cannot_be_checked_are_refused(self):
        sha = "3d3c42e5aac5ba805825da76410c181273ba90b1"
        refused = {
            "branch": "      - uses: actions/checkout@main\n",
            "upper case SHA": f"      - uses: actions/checkout@{sha.upper()}\n",
            "docker image with a tag": "      - uses: docker://alpine:3.20\n",
            "docker image with a digest": "      - uses: docker://alpine@sha256:" + "a" * 64 + "\n",
            "reusable workflow of another repository": f"    uses: other/repo/.github/workflows/x.yml@{sha}\n",
            "flow style list": "    steps: [{uses: actions/checkout@v4}]\n",
            "flow style item": "      - {uses: actions/checkout@v4}\n",
            "quoted key": '      - "uses": actions/checkout@v4\n',
        }
        for name, body in refused.items():
            with self.subTest(name):
                self.assertNotEqual(check_text.find_unpinned_actions(".github/workflows/x.yml", "jobs:\n  a:\n" + body), [], name)

    def test_container_and_service_images_must_be_pinned_by_a_digest(self):
        digest = "@sha256:" + "a" * 64
        text = ("jobs:\n  a:\n    container: node:22\n    services:\n      db:\n        image: postgres:17\n"
                f"  b:\n    container: node:22{digest}\n    services:\n      db:\n        image: postgres:17{digest}\n"
                "    steps:\n      - run: echo \"disk image: built\"\n")
        self.assertEqual(check_text.find_unpinned_images(".github/workflows/x.yml", text), [3, 6])
        self.assertEqual(check_text.find_unpinned_images("docs/ci.md", text), [])

    def test_a_workflow_with_an_unpinned_action_fails_the_check(self):
        out = run_in_repo({
            ".github/workflows/checks.yml": "jobs:\n  a:\n    runs-on: macos-latest\n    steps:\n      - uses: actions/checkout@v7\n",
        })
        self.assertEqual(out.returncode, 1)
        self.assertIn(".github/workflows/checks.yml: line 5: action not pinned by a full commit SHA", out.stdout)
        self.assertIn("1 problem(s)", out.stdout)

    def test_the_workflows_of_this_repository_run_on_github_runners(self):
        folder = Path(check_text.__file__).resolve().parent.parent / ".github" / "workflows"
        files = sorted(folder.glob("*.yml"))
        self.assertTrue(files)
        for file in files:
            text = file.read_text(encoding="utf-8")
            self.assertEqual(check_text.find_self_hosted(f".github/workflows/{file.name}", text), [], file.name)
            self.assertEqual(check_text.find_unhosted_runners(f".github/workflows/{file.name}", text), [], file.name)
            self.assertEqual(check_text.find_unpinned_actions(f".github/workflows/{file.name}", text), [], file.name)
            self.assertEqual(check_text.find_unpinned_images(f".github/workflows/{file.name}", text), [], file.name)
            self.assertIn("runs-on: macos-latest", text, file.name)


if __name__ == "__main__":
    unittest.main()
