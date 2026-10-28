import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import release_notes  # noqa: E402

BASE = "https://github.com/ThanaelFontaine/Brimline/blob/v1.2.3/"


class AbsoluteLinksTests(unittest.TestCase):
    def rewrite(self, text):
        return release_notes.absolute_links(text, "1.2.3")

    def test_relative_link_points_to_the_tag(self):
        self.assertEqual(self.rewrite("[a](docs/providers.md)"), f"[a]({BASE}docs/providers.md)")

    def test_anchor_is_kept(self):
        self.assertEqual(self.rewrite("[a](docs/accounts.md#several-accounts)"), f"[a]({BASE}docs/accounts.md#several-accounts)")

    def test_root_file(self):
        self.assertEqual(self.rewrite("[s](SECURITY.md)"), f"[s]({BASE}SECURITY.md)")

    def test_dot_segments_are_resolved_from_the_root(self):
        self.assertEqual(self.rewrite("[a](./docs/a.md) [b](../providers.md) [c](docs/../x.md)"), f"[a]({BASE}docs/a.md) [b]({BASE}providers.md) [c]({BASE}x.md)")

    def test_absolute_links_anchors_and_mailto_are_unchanged(self):
        text = "[a](https://example.com/x) [b](http://e.org) [c](mailto:me@example.com) [d](#top) [e](/root)"
        self.assertEqual(self.rewrite(text), text)

    def test_several_links_in_a_line(self):
        self.assertEqual(self.rewrite("[a](a.md) and [b](https://x.y) and [c](b/c.md#d)"), f"[a]({BASE}a.md) and [b](https://x.y) and [c]({BASE}b/c.md#d)")

    def test_plain_text_in_parentheses_is_unchanged(self):
        self.assertEqual(self.rewrite("see (docs/a.md) or ]( spaced)"), "see (docs/a.md) or ]( spaced)")


if __name__ == "__main__":
    unittest.main()
