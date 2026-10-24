"""Repository text checks: no em or en dash, no personal data in tracked text files.

The maintainer's own patterns live in the untracked .check-text.local (one regex per line,
"#" comments). Without that file only the generic patterns run, as in CI.
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


def local_patterns(root):
    local = root / ".check-text.local"
    if not local.exists():
        return []
    lines = [l.strip() for l in local.read_text(encoding="utf-8").split("\n")]
    return [re.compile(l) for l in lines if l and not l.startswith("#")]


def main():
    root = Path(__file__).resolve().parent.parent
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True).stdout.split()
    patterns = GENERIC_PATTERNS + local_patterns(root)
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
