"""Repository text checks: no em or en dash, no personal data, no old product name in tracked text files,
and no self-hosted runner in the workflows.

The old name of the app (see OLD_NAME) may only appear where it is history or migration: the
files of OLD_NAME_FILES, and the lines that say "Formerly <old name>" (or the French
"Anciennement <old name>"). Anywhere else, in a text or in a file name, it is a problem.

The maintainer's own patterns (one regex per line, "#" comments) live outside the tracked
files: in .check-text.local at the repository root, and in ~/.config/check-text/patterns for
every repository of the machine. Without them (on the runners of GitHub, for one) only the generic
patterns run.

The repository is public: its workflows run on the runners hosted by GitHub, never on a machine of
the maintainer, whose code a pull request could run. So the word "self-hosted" may not appear in a
file of .github/workflows (WORKFLOW_DIR).
Usage: python3 scripts/check_text.py   (exit code 1 when something is found)
"""
import re
import subprocess
import sys
from pathlib import Path

EM_DASH = chr(0x2014)
EN_DASH = chr(0x2013)

GENERIC_PATTERNS = [
    re.compile(r"/Users/[A-Za-z]"),
    re.compile(r"/home/[a-z]"),
    re.compile(r"@gmail\.com"),
    re.compile(r"@icloud\.com"),
    re.compile(r"@outlook\."),
]

# Files allowed to quote the generic patterns (the checker and its test).
ALLOWED = {"scripts/check_text.py", "tests/test_check_text.py"}

# The app was called Sightglass until 26 October 2026 (QUOTA-34). Case does not matter.
OLD_NAME = re.compile("sightglass", re.IGNORECASE)
# A line that says where the name comes from is allowed anywhere.
OLD_NAME_LINE = re.compile("(formerly|anciennement) sightglass", re.IGNORECASE)
# Files where the old name is history (changelog, dated documents) or migration (the code that
# moves the old data, its tests, the installer that turns the old install off), and the checker.
OLD_NAME_FILES = {
    "CHANGELOG.md",
    "docs/releases/v0.1.0.md",
    "docs/releases/v0.2.0.md",
    "docs/audits/2026-10-26-securite.md",
    "Sources/BrimlineCore/LegacyMigration.swift",
    "tests/BrimlineCoreTests/LegacyMigrationTests.swift",
    "scripts/install.sh",
    "scripts/check_text.py",
    "tests/test_check_text.py",
}

# The workflows must run on the runners hosted by GitHub (see the top of this file).
WORKFLOW_DIR = ".github/workflows/"
SELF_HOSTED = re.compile("self-hosted", re.IGNORECASE)

BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".ico", ".icns", ".heic",
    ".woff", ".woff2", ".ttf", ".otf", ".eot", ".pdf", ".zip", ".dmg",
}


def find_dashes(text):
    """Line numbers (1 based) containing an em dash or an en dash."""
    return [i + 1 for i, line in enumerate(text.split("\n")) if EM_DASH in line or EN_DASH in line]


def find_personal_data(path, text, patterns):
    """One "line N: reason" entry per line matching a pattern that is not allowed for this file."""
    if path in ALLOWED:
        return []
    hits = []
    for i, line in enumerate(text.split("\n")):
        for pattern in patterns:
            if pattern.search(line):
                hits.append(f"line {i + 1}: personal data pattern {pattern.pattern}")
    return hits


def find_old_name(path, text):
    """Line numbers (1 based) naming the old product, unless the file or the line is allowed to."""
    if path in OLD_NAME_FILES:
        return []
    return [i + 1 for i, line in enumerate(text.split("\n"))
            if OLD_NAME.search(line) and not OLD_NAME_LINE.search(line)]


def find_self_hosted(path, text):
    """Line numbers (1 based) naming a self-hosted runner, in a file of the workflows folder."""
    if not path.startswith(WORKFLOW_DIR):
        return []
    return [i + 1 for i, line in enumerate(text.split("\n")) if SELF_HOSTED.search(line)]


def local_patterns(paths):
    """Patterns read from the files that exist among paths."""
    patterns = []
    for local in paths:
        if not local.is_file():
            continue
        lines = [l.strip() for l in local.read_text(encoding="utf-8").split("\n")]
        patterns += [re.compile(l) for l in lines if l and not l.startswith("#")]
    return patterns


def main():
    root = Path(__file__).resolve().parent.parent
    # -z: names with spaces or accents come back as they are, never quoted or split.
    listing = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True, check=True).stdout
    files = [name for name in listing.split("\0") if name]
    patterns = GENERIC_PATTERNS + local_patterns([root / ".check-text.local", Path.home() / ".config/check-text/patterns"])
    problems = []
    for name in files:
        path = root / name
        if OLD_NAME.search(name) and name not in OLD_NAME_FILES:
            problems.append(f"{name}: old product name in the file name")
        if path.suffix.lower() in BINARY_EXTENSIONS or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        problems += [f"{name}: line {n}: em or en dash" for n in find_dashes(text)]
        problems += [f"{name}: line {n}: old product name" for n in find_old_name(name, text)]
        problems += [f"{name}: line {n}: self-hosted runner" for n in find_self_hosted(name, text)]
        problems += [f"{name}: {hit}" for hit in find_personal_data(name, text, patterns)]
    for p in problems:
        print(p)
    print(f"check_text: {len(files)} tracked files, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
