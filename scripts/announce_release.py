"""Announces a published release of Brimline in a Discord channel, through a webhook.

  python3 scripts/announce_release.py vX.Y.Z            posts the announcement
  python3 scripts/announce_release.py vX.Y.Z --dry-run  prints the JSON body, sends nothing

The release workflow calls it after the release is published (not as a draft). It reads the release
with the GitHub CLI (`gh`, GH_TOKEN), then the commits since the previous published release, and posts
one embed: the version, what changed, the link of the release and of the disk image.

The address of the webhook is the secret DISCORD_RELEASES_WEBHOOK_URL, read from the environment. It
is never printed, written or put in an error message. Without it, the script says so with a GitHub
"::warning::" and exits 0: the release does not depend on the announcement, and neither does any
other failure here (a message of Discord that is refused is reported, never raised). The message
does not set a name or an avatar: they are the webhook's own. No mention can ring (allowed_mentions
is empty). Limits of Discord kept: title 256, description 4096, field value 1024 characters.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

REPO = "ThanaelFontaine/Brimline"
APP = "Brimline"
DMG = "Brimline.dmg"
COLOR = 0x2ECC71
MAX_COMMITS = 12
MAX_LINE = 180
MAX_DESCRIPTION = 3800
TAG_PATTERN = re.compile(r"v(\d+\.\d+\.\d+)")
# The commit that bumps the version carries no news of its own: "Brimline 0.3.1 (#50)".
VERSION_COMMIT = re.compile(rf"{APP} \d+\.\d+\.\d+( \(#\d+\))?$")
WEBHOOK_PREFIXES = ("https://discord.com/api/webhooks/", "https://discordapp.com/api/webhooks/")
USER_AGENT = f"Brimline-release-announcer (https://github.com/{REPO})"


def clip(text, limit):
    """Cuts at `limit` characters, with an ellipsis when something was cut."""
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def change_lines(subjects):
    """Bulleted subjects of the commits: no version commit, no empty line, each one clipped, at most MAX_COMMITS."""
    kept = [s.strip() for s in subjects if s.strip() and not VERSION_COMMIT.fullmatch(s.strip())]
    lines = [f"- {clip(s, MAX_LINE)}" for s in kept[-MAX_COMMITS:]]
    if len(kept) > MAX_COMMITS:
        lines.insert(0, f"- ... et {len(kept) - MAX_COMMITS} changements plus anciens (voir la release)")
    return lines


def build_body(tag, release_url, subjects, previous_tag=None, published_at=None, repo=REPO):
    """The JSON body of the message (a dict): one embed, no mention, no name and no avatar."""
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError(f"not a version tag: {tag!r}")
    lines = change_lines(subjects)
    description = "\n".join(lines) if lines else "Le détail est dans les notes de la release."
    # Cut on a line boundary when the list is too long for one embed.
    if len(description) > MAX_DESCRIPTION:
        description = clip(description[:MAX_DESCRIPTION].rsplit("\n", 1)[0], MAX_DESCRIPTION)
    fields = [{"name": "Version", "value": clip(tag, 1024), "inline": True}]
    if previous_tag:
        fields.append({"name": "Précédente", "value": clip(previous_tag, 1024), "inline": True})
    moment = parse_time(published_at)
    if moment:
        fields.append({"name": "Publiée", "value": f"<t:{int(moment.timestamp())}:R>", "inline": True})
    dmg = f"https://github.com/{repo}/releases/download/{tag}/{DMG}"
    fields.append({"name": "Téléchargement", "value": clip(f"[{DMG}]({dmg})", 1024), "inline": False})
    embed = {
        "title": clip(f"{APP} {tag} est publiée", 256),
        "url": release_url,
        "description": description,
        "color": COLOR,
        "fields": fields,
        "footer": {"text": "Release créée par GitHub Actions"},
    }
    if moment:
        embed["timestamp"] = moment.strftime("%Y-%m-%dT%H:%M:%SZ")
    return {"allowed_mentions": {"parse": []}, "embeds": [embed]}


def parse_time(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def gh_json(args, run=subprocess.run):
    done = run(["gh", *args], capture_output=True, text=True, check=True)
    return json.loads(done.stdout)


def gather(tag, repo=REPO, run=subprocess.run):
    """(release url, published date, previous published tag, commit subjects since it) read with gh."""
    release = gh_json(["release", "view", tag, "--repo", repo, "--json", "url,isDraft,publishedAt"], run)
    if release.get("isDraft"):
        raise RuntimeError(f"release {tag} is still a draft: nothing to announce")
    releases = gh_json(["api", f"repos/{repo}/releases?per_page=30"], run)
    tags = [r["tag_name"] for r in releases if not r.get("draft")]
    previous = tags[tags.index(tag) + 1] if tag in tags and tags.index(tag) + 1 < len(tags) else None
    subjects = []
    if previous:
        commits = gh_json(["api", f"repos/{repo}/compare/{previous}...{tag}"], run)["commits"]
        subjects = [
            c["commit"]["message"].split("\n")[0] for c in commits if len(c.get("parents", [])) < 2
        ]
    return release["url"], release.get("publishedAt"), previous, subjects


def post(body, url):
    """Sends the body; returns None on success, else a short message that never holds the address."""
    if not url.startswith(WEBHOOK_PREFIXES):
        return "the address of the webhook is not a Discord webhook address"
    request = urllib.request.Request(
        url + ("&" if "?" in url else "?") + "wait=true",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30):
            return None
    except urllib.error.HTTPError as error:
        return f"Discord answered HTTP {error.code}"
    except Exception as error:  # the text of a network error can carry the address: say only its type
        return f"Discord could not be reached ({type(error).__name__})"


def main(argv, env=os.environ, run=subprocess.run, sender=post):
    args = [a for a in argv if a != "--dry-run"]
    dry_run = len(args) != len(argv)
    if len(args) != 1 or not TAG_PATTERN.fullmatch(args[0]):
        print("usage: announce_release.py vX.Y.Z [--dry-run]", file=sys.stderr)
        return 2
    tag = args[0]
    if tag == "v0.0.0":
        print("Version 0.0.0 is the development version: nothing to announce.")
        return 0
    url = env.get("DISCORD_RELEASES_WEBHOOK_URL", "")
    if not dry_run and not url:
        print("::warning::Secret DISCORD_RELEASES_WEBHOOK_URL is missing: the Discord announcement is skipped.")
        return 0
    try:
        release_url, published_at, previous, subjects = gather(tag, env.get("GITHUB_REPOSITORY", REPO), run)
        body = build_body(tag, release_url, subjects, previous, published_at, env.get("GITHUB_REPOSITORY", REPO))
    except Exception as error:
        print(f"::warning::Discord announcement skipped, the release could not be read: {error}")
        return 0
    if dry_run:
        print(json.dumps(body, ensure_ascii=False, indent=2))
        return 0
    problem = sender(body, url)
    if problem:
        print(f"::warning::Discord announcement of {tag} failed: {problem}")
        return 0
    print(f"Discord announcement sent: {APP} {tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
