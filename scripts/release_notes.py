"""Version and release notes for the release workflow.

  python3 scripts/release_notes.py version        prints the version from VERSION
  python3 scripts/release_notes.py notes X.Y.Z    prints the "## [X.Y.Z]" section of CHANGELOG.md

Fails when the version is malformed or its changelog section is missing or empty: a release never
gets a generic note.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def version():
    v = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", v):
        sys.exit(f"VERSION is not X.Y.Z: {v!r}")
    return v


def notes(v):
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    match = re.search(rf"^## \[{re.escape(v)}\][^\n]*\n(.*?)(?=^## \[|\Z)", text, re.S | re.M)
    body = match.group(1).strip() if match else ""
    if not body:
        sys.exit(f"CHANGELOG.md has no notes for {v}: write the ## [{v}] section first")
    return body


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "version":
        print(version())
    elif len(sys.argv) == 3 and sys.argv[1] == "notes":
        print(notes(sys.argv[2]))
    else:
        sys.exit(__doc__)
