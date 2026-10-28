"""Version and release notes for the release workflow.

  python3 scripts/release_notes.py version        prints the version from VERSION
  python3 scripts/release_notes.py notes X.Y.Z    prints the "## [X.Y.Z]" section of CHANGELOG.md

Relative Markdown links are rewritten to absolute links on the tag (a release page has no repository
folder to resolve them against); the changelog itself keeps them relative.

Fails when the version is malformed or its changelog section is missing or empty: a release never
gets a generic note.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/ThanaelFontaine/Brimline"
# ](target) where the target is not absolute (a scheme such as https: or mailto:), not an anchor alone, not a root path.
RELATIVE_LINK = re.compile(r"\]\((?![a-zA-Z][a-zA-Z0-9+.-]*:|#|/|\s)([^)\s]*)\)")


def absolute_links(body, v):
    """Rewrites each relative link to the blob of tag vX.Y.Z (anchor kept, ./ and ../ resolved from the root)."""

    def rewrite(match):
        path, sep, anchor = match.group(1).partition("#")
        parts = []
        for part in path.split("/"):
            if part == "..":
                if parts:
                    parts.pop()
            elif part not in ("", "."):
                parts.append(part)
        return f"]({REPO_URL}/blob/v{v}/{'/'.join(parts)}{sep}{anchor})"

    return RELATIVE_LINK.sub(rewrite, body)


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
    return absolute_links(body, v)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "version":
        print(version())
    elif len(sys.argv) == 3 and sys.argv[1] == "notes":
        print(notes(sys.argv[2]))
    else:
        sys.exit(__doc__)
