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


SHA = "3d3c42e5aac5ba805825da76410c181273ba90b1"
DIGEST = "sha256:" + "a" * 64
WF = ".github/workflows/x.yml"
HEAD = "on: push\njobs:\n  a:\n"
JOB = "    runs-on: macos-latest\n    steps:\n      - run: id\n"


def text_problems(text):
    return check_text.find_workflow_text_problems(WF, text)


def structure_problems(text):
    return check_text.find_workflow_structure_problems(WF, text)


CONFORMING = (
    "on: [push]\n"
    "jobs:\n"
    "  a:\n"
    "    runs-on: ubuntu-latest\n"
    "    services:\n"
    "      postgres:\n"
    f"        image: postgres:17@{DIGEST}\n"
    "        options: >-\n"
    "          --health-cmd \"pg_isready\" # not a comment inside a block\n"
    "    steps:\n"
    f"      - uses: actions/checkout@{SHA} # v7.0.1\n"
    "      - uses: ./.github/actions/local\n"
    "      - run: |\n"
    "          echo \"ok\" && ls *.yml \\\n"
    "            | wc -l\n"
    "          echo '[ { ? & * !'\n"
    "      - name: Last\n"
    "        if: ${{ !cancelled() && github.event_name == 'push' }}\n"
    "        run: echo last\n"
    "  b:\n"
    "    runs-on: [macos-latest]\n"
    "    container: {image: node:22@" + DIGEST + "}\n"
    "    steps:\n"
    "      - run: id\n"
    "  c:\n"
    "    runs-on:\n"
    "      - 'windows-latest'\n"
    "    container:\n"
    f"      image: node:22@{DIGEST}\n"
    "    steps:\n"
    "      - run: id\n"
    "  d:\n"
    "    uses: ./.github/workflows/local.yml\n"
    "  e:\n"
    "    runs-on: \"ubuntu-24.04\"\n"
    f"    container: node:22@{DIGEST}\n"
    "    steps:\n"
    "      - run: id\n"
)

# Bypasses found in review: valid YAML that PyYAML reads as aiming at macOS, self-hosted or an
# action on a tag. Each one is a whole workflow, and each check must refuse it on its own.
BYPASSES = {
    "1 escaped quote then #, flow mapping":
        'on: push\njobs:\n  a: {"name": "x\\" #", "runs-on": "macOS", "steps": [{"run": "id"}]}\n',
    "1 escaped quote then #, self-hosted":
        HEAD + '    runs-on: macos-latest\n    env: {"N": "x\\" #", "L": "self-hosted"}\n'
        "    steps:\n      - run: id\n",
    "1 escaped quote then #, uses":
        HEAD + '    runs-on: macos-latest\n    steps:\n'
        '      - {"name": "a\\" #", "uses": "actions/checkout@v4"}\n',
    "2 string on two lines, second line starting with #":
        'on: push\njobs:\n  a: {name: "x\n# ", runs-on: macOS, steps: [{run: id}]}\n',
    "2 string on two lines in a flow sequence":
        HEAD + '    runs-on: macos-latest\n    steps: [\n      {run: "x\n# ", uses: actions/checkout@v4}\n    ]\n',
    "3 flow mapping opened on a line, closed later":
        "on: push\njobs:\n  a: {\n    runs-on: macOS,\n    steps: [{run: id}]}\n",
    "4 explicit key after a dash":
        HEAD + "    runs-on: macos-latest\n    steps:\n      - ? uses\n        : actions/checkout@v4\n",
    "4 explicit image key":
        HEAD + JOB + "    container:\n      ? image\n      : node:22\n",
    "4 explicit key in a flow mapping":
        'on: push\njobs:\n  a: { ? "runs-\\\n    on" : macOS, steps: [{run: id}] }\n',
    "5 key split by a backslash":
        HEAD + '    runs-on: macos-latest\n    steps:\n      - ? "us\\\n          es"\n        : actions/checkout@v4\n',
    "6 anchor then alias as a key":
        HEAD + '    x: &k "runs-\\\n      on"\n    *k : macOS\n    steps:\n      - run: id\n',
    "6 anchor in env then alias as a key":
        HEAD + "    env:\n      K: &r runs-on\n    *r : [macOS, ARM64]\n    steps:\n      - run: id\n",
    "6 alias as the key of a step":
        HEAD + "    runs-on: macos-latest\n    steps:\n      - name: &u uses\n        run: id\n"
        "      - *u : actions/checkout@v4\n",
    "7 container: then a value on the next line":
        HEAD + JOB + "    container:\n      node:22\n",
    "8 upper case key":
        HEAD + "    RUNS-ON: macOS\n    steps:\n      - run: id\n",
    "8 mixed case key":
        HEAD + "    Runs-On: macOS\n    steps:\n      - run: id\n",
}


class WorkflowCheckTest(unittest.TestCase):
    def test_only_the_workflows_are_checked(self):
        text = "jobs:\n  a:\n    runs-on: [Self-Hosted, macOS]\n"
        self.assertEqual(check_text.find_workflow_text_problems("docs/ci.md", text), [])
        self.assertEqual(check_text.find_workflow_structure_problems("docs/ci.md", text), [])

    def test_a_conforming_workflow_passes_both_checks(self):
        self.assertEqual(text_problems(CONFORMING), [])
        self.assertEqual(structure_problems(CONFORMING), [])

    def test_the_bypasses_are_valid_yaml(self):
        import yaml
        for name, text in BYPASSES.items():
            with self.subTest(name):
                self.assertIsInstance(yaml.safe_load(text), dict, name)

    def test_the_text_check_alone_refuses_every_bypass(self):
        for name, text in BYPASSES.items():
            with self.subTest(name):
                self.assertNotEqual(text_problems(text), [], name)

    def test_the_structure_check_alone_refuses_every_bypass(self):
        for name, text in BYPASSES.items():
            with self.subTest(name):
                self.assertNotEqual(structure_problems(text), [], name)

    def test_an_explicit_key_gets_its_own_message(self):
        problems = text_problems(HEAD + "    runs-on: macos-latest\n    steps:\n      - ? uses\n")
        self.assertTrue(problems)
        self.assertTrue(all(check_text.NOT_CHECKABLE in p for p in problems), problems)

    def test_a_runner_label_must_be_one_hosted_by_github(self):
        text = "jobs:\n  a:\n    runs-on: [macOS, ARM64]\n  b:\n    runs-on: macOS\n  c:\n    runs-on: macos-latest\n  d:\n    runs-on: ubuntu-24.04\n"
        self.assertEqual(text_problems(text), ["line 3: runner not hosted by GitHub", "line 5: runner not hosted by GitHub"])
        self.assertEqual(structure_problems(text), ["jobs.a.runs-on: runner not hosted by GitHub", "jobs.b.runs-on: runner not hosted by GitHub"])

    def test_an_action_must_be_pinned_by_a_full_commit_sha(self):
        text = (f"steps:\n  - uses: actions/checkout@v7\n  - uses: actions/checkout@{SHA} # v7.0.1\n"
                f"  - uses: ./.github/actions/local\n  - uses: actions/setup-node@{SHA[:12]}\n")
        self.assertEqual(text_problems(text), ["line 2: action not pinned by a full commit SHA",
                                               "line 5: action not pinned by a full commit SHA"])

    def test_text_forms_that_cannot_be_checked_are_refused(self):
        refused = {
            "self-hosted": "    runs-on: [self-hosted, macOS]\n",
            "self-hosted in a comment after a valid label": "    runs-on: macos-latest # not self-hosted\n",
            "keyword in a comment": "    # runs-on: macOS\n",
            "self-hosted with an escape": '    env:\n      X: "self-host\\x65d"\n',
            "made-up label": "    runs-on: macos-mini\n",
            "expression": "    runs-on: ${{ matrix.os }}\n",
            "unclosed expression": "    name: ${{ x\n",
            "block of two items": "    runs-on:\n      - macos-latest\n      - ARM64\n",
            "runner group": "    runs-on:\n      group: home\n",
            "space before the colon": "    runs-on : macos-latest\n",
            "quoted key": '    "runs-on": macOS\n',
            "quoted key, list": '    "runs-on": [macOS, ARM64]\n',
            "flow style": '  a: {"runs-on": "macOS", steps: [{run: x}]}\n',
            "JSON": '{"jobs": {"a": {"runs-on": "macOS", "steps": []}}}\n',
            "escaped key": '    "runs\\u002don": macOS\n',
            "explicit key": "    ? runs-on\n    : macOS\n",
            "YAML tag on a key": "    !!str runs-on: macOS\n",
            "YAML tag on a value": "    name: !x value\n",
            "document marker": "--- {jobs: {}}\n",
            "branch": "      - uses: actions/checkout@main\n",
            "upper case SHA": f"      - uses: actions/checkout@{SHA.upper()}\n",
            "docker image with a tag": "      - uses: docker://alpine:3.20\n",
            "docker image with a digest": f"      - uses: docker://alpine@{DIGEST}\n",
            "reusable workflow of another repository": f"    uses: other/repo/.github/workflows/x.yml@{SHA}\n",
            "flow style list": "    steps: [{uses: actions/checkout@v4}]\n",
            "flow style item": "      - {uses: actions/checkout@v4}\n",
            "quoted uses key": '      - "uses": actions/checkout@v4\n',
            "container with no digest": "    container: node:22\n",
            "container mapping with no digest": "    container: {image: node:22}\n",
            "service image with no digest": "      db:\n        image: postgres:17\n",
            "quoted image key": '        "image": postgres:17\n',
            "keyword inside a quoted value": '      - run: echo "disk image: built"\n',
        }
        for name, body in refused.items():
            with self.subTest(name):
                self.assertNotEqual(text_problems("jobs:\n  a:\n" + body), [], name)

    def test_structures_that_break_the_rules_are_refused(self):
        refused = {
            "macOS label": HEAD + "    runs-on: macOS\n",
            "runner group": HEAD + "    runs-on:\n      group: home\n",
            "no runs-on": HEAD + "    steps:\n      - run: id\n",
            "action on a tag": HEAD + "    runs-on: macos-latest\n    steps:\n      - uses: actions/checkout@v4\n",
            "docker image with a digest": HEAD + f"    runs-on: macos-latest\n    steps:\n      - uses: docker://alpine@{DIGEST}\n",
            "reusable workflow of another repository": HEAD + f"    uses: other/repo/.github/workflows/x.yml@{SHA}\n",
            "service with no digest": HEAD + JOB + "    services:\n      db:\n        image: postgres:17\n",
            "service as a string": HEAD + JOB + "    services:\n      db: postgres:17\n",
            "container mapping with no digest": HEAD + JOB + "    container:\n      image: node:22\n",
            "self-hosted in a string": HEAD + JOB + "    env:\n      X: self-hosted\n",
            "duplicate key": HEAD + "    runs-on: macOS\n    runs-on: macos-latest\n    steps:\n      - run: id\n",
            "merge key": HEAD + "    <<: {runs-on: macOS}\n    steps:\n      - run: id\n",
            "step that is not a mapping": HEAD + "    runs-on: macos-latest\n    steps:\n      - id\n",
            "job that is not a mapping": "on: push\njobs:\n  a: [x]\n",
            "no jobs": "on: push\n",
            "unreadable YAML": "on: push\njobs:\n  a: {\n",
            "two documents": "on: push\n---\njobs: {}\n",
        }
        for name, text in refused.items():
            with self.subTest(name):
                self.assertNotEqual(structure_problems(text), [], name)

    def test_the_structure_check_fails_closed_without_pyyaml(self):
        saved = check_text.yaml
        check_text.yaml = None
        try:
            problems = structure_problems(CONFORMING)
        finally:
            check_text.yaml = saved
        self.assertEqual(len(problems), 1)
        self.assertIn("PyYAML missing", problems[0])

    def test_a_workflow_with_a_self_hosted_runner_fails_the_check(self):
        out = run_in_repo({
            ".github/workflows/checks.yml": "on: push\njobs:\n  a:\n    runs-on: [self-hosted, macOS]\n",
            ".github/workflows/release.yml": "on: push\njobs:\n  a:\n    runs-on: macos-latest\n    steps:\n      - run: id\n",
        })
        self.assertEqual(out.returncode, 1)
        self.assertIn(".github/workflows/checks.yml: line 4: self-hosted runner", out.stdout)
        self.assertIn(".github/workflows/checks.yml: line 4: runner not hosted by GitHub", out.stdout)
        self.assertIn(".github/workflows/checks.yml: (file): self-hosted runner", out.stdout)
        self.assertIn(".github/workflows/checks.yml: jobs.a.runs-on: runner not hosted by GitHub", out.stdout)
        self.assertNotIn("release.yml", out.stdout)
        self.assertIn("4 problem(s)", out.stdout)

    def test_a_workflow_with_an_unpinned_action_fails_the_check(self):
        out = run_in_repo({
            ".github/workflows/checks.yml": "on: push\njobs:\n  a:\n    runs-on: macos-latest\n    steps:\n      - uses: actions/checkout@v7\n",
        })
        self.assertEqual(out.returncode, 1)
        self.assertIn(".github/workflows/checks.yml: line 6: action not pinned by a full commit SHA", out.stdout)
        self.assertIn(".github/workflows/checks.yml: jobs.a.steps[0].uses: action not pinned by a full commit SHA", out.stdout)
        self.assertIn("2 problem(s)", out.stdout)

    def test_the_workflows_of_this_repository_run_on_github_runners(self):
        folder = Path(check_text.__file__).resolve().parent.parent / ".github" / "workflows"
        files = sorted(folder.glob("*.yml"))
        self.assertTrue(files)
        for file in files:
            text = file.read_text(encoding="utf-8")
            name = f".github/workflows/{file.name}"
            self.assertEqual(check_text.find_workflow_text_problems(name, text), [], file.name)
            self.assertEqual(check_text.find_workflow_structure_problems(name, text), [], file.name)
            self.assertIn("runs-on: macos-latest", text, file.name)


if __name__ == "__main__":
    unittest.main()
