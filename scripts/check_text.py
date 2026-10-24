"""Repository text checks: no em or en dash, no personal data in tracked text files.

The maintainer's own patterns (one regex per line, "#" comments) live outside the tracked
files: in .check-text.local at the repository root, and in ~/.config/check-text/patterns for
every repository of the machine (a self-hosted runner reads it too). Without them only the
generic patterns run.
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
        if path.suffix.lower() in BINARY_EXTENSIONS or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        problems += [f"{name}: line {n}: em or en dash" for n in find_dashes(text)]
        problems += [f"{name}: {hit}" for hit in find_personal_data(name, text, patterns)]
    for p in problems:
        print(p)
    print(f"check_text: {len(files)} tracked files, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
