r"""Repository text checks: no em or en dash, no personal data, no old product name in tracked text files,
no self-hosted runner, no unpinned action and no unpinned image in the workflows.

The old name of the app (see OLD_NAME) may only appear where it is history or migration: the
files of OLD_NAME_FILES, and the lines that say "Formerly <old name>" (or the French
"Anciennement <old name>"). Anywhere else, in a text or in a file name, it is a problem.

The maintainer's own patterns (one regex per line, "#" comments) live outside the tracked
files: in .check-text.local at the repository root, and in ~/.config/check-text/patterns for
every repository of the machine. Without them (on the runners of GitHub, for one) only the generic
patterns run.

The repository is public: its workflows run on the runners hosted by GitHub, never on a machine of
the maintainer, whose code a pull request could run. In a file of .github/workflows (WORKFLOW_DIR):
- the word "self-hosted" may not appear (YAML escapes such as \x65 are decoded first);
- every "runs-on:" names one label from the closed list HOSTED_LABELS (standard runners hosted by
  GitHub), as a plain value or a one item list;
- every "uses:" of an action is pinned by a full commit SHA of 40 lowercase hex characters (a tag
  can be moved); a local action ("./...") is allowed; "docker://" images and reusable workflows of
  another repository are refused;
- every image of "container:" or "services:" is pinned by a "@sha256:" digest;
- a line that holds one of the keys runs-on, uses, image or container in any other form (quoted
  key, flow style "{...}", JSON, escape, explicit "? " key, space before the colon) is refused:
  what cannot be checked line by line fails.
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
# The labels of the standard runners hosted by GitHub: a closed list, copied from the tables of
# the official documentation (docs.github.com, Actions, "GitHub-hosted runners", read on
# 2026-11-08). A made-up label (macos-mini...) is refused; a new GitHub image is added here
# after reading that page.
HOSTED_LABELS = {
    "ubuntu-slim", "ubuntu-latest", "ubuntu-26.04", "ubuntu-24.04", "ubuntu-22.04",
    "ubuntu-26.04-arm", "ubuntu-24.04-arm", "ubuntu-22.04-arm",
    "windows-latest", "windows-2025", "windows-2025-vs2026", "windows-2022",
    "windows-11-arm", "windows-11-vs2026-arm",
    "macos-latest", "macos-26", "macos-15", "macos-26-intel", "macos-15-intel", "xcode-27",
}
# A key of interest, however it is written (quoted, followed by spaces before the colon...).
WORKFLOW_KEY = re.compile(r"(?<![A-Za-z0-9_-])(runs-on|uses|image|container)[\"']?\s*:")
KEY_START = re.compile(r"^\s*(?:-\s+)?[\"']?(image|container)[\"']?\s*:")
RUNS_ON = re.compile(r"^(\s*)(?:-\s+)?runs-on:(?:\s+(.*))?$")
USES = re.compile(r"^\s*(?:-\s+)?uses:\s+(\S+)$")
IMAGE = re.compile(r"^\s*(?:-\s+)?image:\s+(\S+)$")
CONTAINER = re.compile(r"^\s*container:(?:\s+(\S+))?$")
ACTION = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_./-]+)?@([0-9a-f]{40})$")
DIGEST = re.compile(r"@sha256:[0-9a-f]{64}$")
ESCAPE = re.compile(r"\\x([0-9A-Fa-f]{2})|\\u([0-9A-Fa-f]{4})|\\U([0-9A-Fa-f]{8})")

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


def decode_escapes(line):
    """The line with the YAML escapes \\xNN, \\uNNNN and \\UNNNNNNNN decoded."""
    def one(match):
        try:
            return chr(int(match.group(1) or match.group(2) or match.group(3), 16))
        except ValueError:
            return match.group(0)
    return ESCAPE.sub(one, line)


def strip_comment(line):
    """The line without its trailing comment ("#" at the start or after a blank, outside quotes)."""
    quote = None
    for i, c in enumerate(line):
        if quote:
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i].rstrip()
    return line.rstrip()


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def hosted_label(value):
    """True when value is one label of HOSTED_LABELS, plain, quoted or in a one item list."""
    if value.startswith("["):
        match = re.fullmatch(r"\[([^\[\]{},]*)\]", value)
        if not match:
            return False
        value = match.group(1)
    return unquote(value) in HOSTED_LABELS


def workflow_lines(path, text, keys):
    """(line number, line without comment, next lines) for each line holding one of keys."""
    if not path.startswith(WORKFLOW_DIR):
        return
    lines = text.split("\n")
    for i, raw in enumerate(lines):
        line = strip_comment(raw)
        found = set()
        for candidate in (line, decode_escapes(line)):
            for m in WORKFLOW_KEY.finditer(candidate):
                # "image" and "container" also occur in prose ("disk image: ..."): they count
                # as keys at the start of a line, or on a line in flow style.
                if m.group(1) in ("runs-on", "uses") or "{" in candidate or KEY_START.match(candidate):
                    found.add(m.group(1))
        if line.lstrip().startswith("?") and "runs-on" in keys:
            found.add("runs-on")
        if found & set(keys):
            yield i + 1, line, lines[i + 1:]


def unverifiable(line):
    """A form this check cannot read line by line: flow style, escape, explicit key."""
    return "{" in line or "\\" in line or line.lstrip().startswith("?")


def find_self_hosted(path, text):
    """Line numbers (1 based) naming a self-hosted runner, in a file of the workflows folder."""
    if not path.startswith(WORKFLOW_DIR):
        return []
    return [i + 1 for i, line in enumerate(text.split("\n")) if SELF_HOSTED.search(decode_escapes(line))]


def find_unhosted_runners(path, text):
    """Line numbers (1 based) of a "runs-on" that is not one label of HOSTED_LABELS, or not readable."""
    hits = []
    for number, line, rest in workflow_lines(path, text, ["runs-on"]):
        match = None if unverifiable(line) else RUNS_ON.match(line)
        if not match:
            hits.append(number)
            continue
        indent, value = match.group(1), (match.group(2) or "").strip()
        if not value:
            # Block form: exactly one "- label" item, indented deeper.
            items = []
            for following in rest:
                following = strip_comment(following)
                if following.strip() and len(following) - len(following.lstrip()) <= len(indent):
                    break
                if following.strip():
                    items.append(following.strip())
            value = items[0][2:].strip() if len(items) == 1 and items[0].startswith("- ") else ""
        if not hosted_label(value):
            hits.append(number)
    return hits


def find_unpinned_actions(path, text):
    """Line numbers (1 based) of a "uses" that is not a local action or an action pinned by a full commit SHA."""
    hits = []
    for number, line, _ in workflow_lines(path, text, ["uses"]):
        match = None if unverifiable(line) else USES.match(line)
        target = unquote(match.group(1)) if match else ""
        if target.startswith("./"):
            continue
        if not match or "/.github/workflows/" in target or not ACTION.match(target):
            hits.append(number)
    return hits


def find_unpinned_images(path, text):
    """Line numbers (1 based) of a "container" or "image" that is not pinned by a sha256 digest, or not readable."""
    hits = []
    for number, line, _ in workflow_lines(path, text, ["image", "container"]):
        if unverifiable(line):
            hits.append(number)
            continue
        image = IMAGE.match(line)
        container = CONTAINER.match(line)
        if image:
            value = unquote(image.group(1))
        elif container:
            if not container.group(1):
                continue
            value = unquote(container.group(1))
        else:
            hits.append(number)
            continue
        if not DIGEST.search(value):
            hits.append(number)
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
        problems += [f"{name}: line {n}: runner not hosted by GitHub" for n in find_unhosted_runners(name, text)]
        problems += [f"{name}: line {n}: action not pinned by a full commit SHA" for n in find_unpinned_actions(name, text)]
        problems += [f"{name}: line {n}: image not pinned by a sha256 digest" for n in find_unpinned_images(name, text)]
        problems += [f"{name}: {hit}" for hit in find_personal_data(name, text, patterns)]
    for p in problems:
        print(p)
    print(f"check_text: {len(files)} tracked files, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
