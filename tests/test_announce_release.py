import io
import json
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import announce_release  # noqa: E402

URL = "https://github.com/ThanaelFontaine/Brimline/releases/tag/v1.2.3"
SECRET = "https://discord.com/api/webhooks/123/very-secret-token"


def fake_gh(published=True, extra_release_before=True):
    """A stand-in for subprocess.run that answers the three gh calls of gather() with canned JSON."""

    def run(cmd, capture_output, text, check):
        if cmd[1:3] == ["release", "view"]:
            out = {"url": URL, "isDraft": not published, "publishedAt": "2026-10-30T10:00:00Z"}
        elif cmd[2].startswith("repos/") and "/releases?" in cmd[2]:
            out = [
                {"tag_name": "v1.2.3", "draft": False},
                {"tag_name": "v1.3.0", "draft": True},
                {"tag_name": "v1.2.2", "draft": False},
                {"tag_name": "v1.2.1", "draft": False},
            ]
        elif "/compare/v1.2.2...v1.2.3" in cmd[2]:
            out = {"commits": [
                {"commit": {"message": "Say when hiding\n\nlong body"}, "parents": [1]},
                {"commit": {"message": "Merge branch x"}, "parents": [1, 2]},
                {"commit": {"message": "Brimline 1.2.3 (#9)"}, "parents": [1]},
            ]}
        else:
            raise AssertionError(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(out), stderr="")

    return run


class BodyTests(unittest.TestCase):
    def body(self, subjects, **kw):
        return announce_release.build_body("v1.2.3", URL, subjects, **kw)

    def embed(self, *a, **kw):
        return self.body(*a, **kw)["embeds"][0]

    def test_one_embed_without_mention_name_or_avatar(self):
        body = self.body(["Fix a thing"])
        self.assertEqual(body["allowed_mentions"], {"parse": []})
        self.assertEqual(len(body["embeds"]), 1)
        self.assertNotIn("username", body)
        self.assertNotIn("avatar_url", body)

    def test_embed_carries_version_link_changes_and_download(self):
        e = self.embed(["Fix a thing", "Add another"], previous_tag="v1.2.2", published_at="2026-10-30T10:00:00Z")
        self.assertEqual(e["title"], "Brimline v1.2.3 est publiée")
        self.assertEqual(e["url"], URL)
        self.assertEqual(e["description"], "- Fix a thing\n- Add another")
        fields = {f["name"]: f["value"] for f in e["fields"]}
        self.assertEqual(fields["Version"], "v1.2.3")
        self.assertEqual(fields["Précédente"], "v1.2.2")
        self.assertRegex(fields["Publiée"], r"^<t:\d+:R>$")
        self.assertIn("/releases/download/v1.2.3/Brimline.dmg", fields["Téléchargement"])
        self.assertEqual(e["timestamp"], "2026-10-30T10:00:00Z")

    def test_without_previous_release_or_date(self):
        e = self.embed(["Fix"])
        names = [f["name"] for f in e["fields"]]
        self.assertNotIn("Précédente", names)
        self.assertNotIn("Publiée", names)
        self.assertNotIn("timestamp", e)

    def test_version_commit_is_left_out_and_no_changes_falls_back(self):
        self.assertEqual(self.embed(["Brimline 1.2.3 (#9)", "Brimline 1.2.3"])["description"],
                         "Le détail est dans les notes de la release.")
        self.assertEqual(self.embed(["Brimline 1.2.3 (#9)", "Fix"])["description"], "- Fix")

    def test_long_commit_line_is_clipped(self):
        line = self.embed(["x" * 500])["description"]
        self.assertLessEqual(len(line), announce_release.MAX_LINE + 2)
        self.assertTrue(line.endswith("\u2026"))

    def test_many_commits_keep_the_newest_and_say_how_many_more(self):
        lines = self.embed([f"change {i}" for i in range(30)])["description"].split("\n")
        self.assertEqual(len(lines), announce_release.MAX_COMMITS + 1)
        self.assertIn("18 changements plus anciens", lines[0])
        self.assertEqual(lines[-1], "- change 29")

    def test_every_text_stays_under_the_limits_of_discord(self):
        e = self.embed(["y" * 5000] * 200, previous_tag="v" + "9" * 5000)
        self.assertLessEqual(len(e["title"]), 256)
        self.assertLessEqual(len(e["description"]), 4096)
        for f in e["fields"]:
            self.assertLessEqual(len(f["value"]), 1024)
        total = len(e["title"]) + len(e["description"]) + sum(len(f["name"]) + len(f["value"]) for f in e["fields"]) + len(e["footer"]["text"])
        self.assertLessEqual(total, 6000)

    def test_a_description_over_the_limit_is_cut_on_a_line(self):
        original = announce_release.MAX_LINE, announce_release.MAX_COMMITS
        announce_release.MAX_LINE, announce_release.MAX_COMMITS = 1000, 100
        try:
            description = self.embed(["z" * 900] * 50)["description"]
        finally:
            announce_release.MAX_LINE, announce_release.MAX_COMMITS = original
        self.assertLessEqual(len(description), announce_release.MAX_DESCRIPTION)
        self.assertTrue(all(l.startswith("- ") for l in description.split("\n")))

    def test_body_is_json_serializable(self):
        json.dumps(self.body(["Accentué é", "quote \" and \\"]))

    def test_malformed_tag_is_refused(self):
        with self.assertRaises(ValueError):
            announce_release.build_body("1.2.3", URL, [])


class GatherTests(unittest.TestCase):
    def test_previous_is_the_next_published_release_and_merges_are_skipped(self):
        url, published, previous, subjects = announce_release.gather("v1.2.3", run=fake_gh())
        self.assertEqual((url, published, previous), (URL, "2026-10-30T10:00:00Z", "v1.2.2"))
        self.assertEqual(subjects, ["Say when hiding", "Brimline 1.2.3 (#9)"])

    def test_a_draft_is_never_announced(self):
        with self.assertRaises(RuntimeError):
            announce_release.gather("v1.2.3", run=fake_gh(published=False))


class MainTests(unittest.TestCase):
    def call(self, argv, env, sender=None):
        sent = []
        out = io.StringIO()
        with redirect_stdout(out):
            code = announce_release.main(argv, env=env, run=fake_gh(), sender=sender or (lambda b, u: sent.append((b, u))))
        return code, out.getvalue(), sent

    def test_dry_run_prints_the_body_and_sends_nothing(self):
        code, out, sent = self.call(["v1.2.3", "--dry-run"], {"DISCORD_RELEASES_WEBHOOK_URL": SECRET})
        self.assertEqual(code, 0)
        self.assertEqual(sent, [])
        self.assertEqual(json.loads(out)["embeds"][0]["title"], "Brimline v1.2.3 est publiée")
        self.assertNotIn("very-secret-token", out)

    def test_dry_run_works_without_the_secret(self):
        code, out, sent = self.call(["v1.2.3", "--dry-run"], {})
        self.assertEqual(code, 0)
        self.assertIn("embeds", json.loads(out))

    def test_missing_secret_skips_with_a_warning(self):
        code, out, sent = self.call(["v1.2.3"], {})
        self.assertEqual(code, 0)
        self.assertEqual(sent, [])
        self.assertTrue(out.startswith("::warning::"))
        self.assertIn("DISCORD_RELEASES_WEBHOOK_URL", out)

    def test_version_zero_posts_nothing(self):
        code, out, sent = self.call(["v0.0.0"], {"DISCORD_RELEASES_WEBHOOK_URL": SECRET})
        self.assertEqual((code, sent), (0, []))

    def test_sends_the_body_to_the_address_and_never_prints_it(self):
        code, out, sent = self.call(["v1.2.3"], {"DISCORD_RELEASES_WEBHOOK_URL": SECRET})
        self.assertEqual(code, 0)
        self.assertEqual(sent[0][1], SECRET)
        self.assertEqual(sent[0][0]["embeds"][0]["url"], URL)
        self.assertNotIn("very-secret-token", out)

    def test_a_refused_message_is_a_warning_not_a_failure(self):
        code, out, sent = self.call(["v1.2.3"], {"DISCORD_RELEASES_WEBHOOK_URL": SECRET}, sender=lambda b, u: "Discord answered HTTP 400")
        self.assertEqual(code, 0)
        self.assertIn("::warning::", out)
        self.assertNotIn("very-secret-token", out)

    def test_a_release_that_cannot_be_read_is_a_warning_not_a_failure(self):
        def broken(cmd, capture_output, text, check):
            raise subprocess.CalledProcessError(1, cmd)

        out = io.StringIO()
        with redirect_stdout(out):
            code = announce_release.main(["v1.2.3"], env={"DISCORD_RELEASES_WEBHOOK_URL": SECRET}, run=broken, sender=lambda b, u: self.fail("sent"))
        self.assertEqual(code, 0)
        self.assertIn("::warning::", out.getvalue())

    def test_bad_usage_exits_2(self):
        out = io.StringIO()
        self.assertEqual(announce_release.main([], env={}), 2)
        self.assertEqual(announce_release.main(["1.2.3"], env={}), 2)


class PostTests(unittest.TestCase):
    def test_an_address_that_is_not_a_discord_webhook_is_refused_without_a_request(self):
        message = announce_release.post({}, "https://example.com/hook?token=abc")
        self.assertIn("not a Discord webhook", message)
        self.assertNotIn("abc", message)


if __name__ == "__main__":
    unittest.main()
