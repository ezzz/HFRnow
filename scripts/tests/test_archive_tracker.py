"""Tests of the pure parts of scripts/archive_tracker.py (no network)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import archive_tracker as at  # noqa: E402

USER = {"login": "someone"}


class ArchiveTrackerTests(unittest.TestCase):
    def test_next_link(self):
        header = '<https://api.github.com/x?page=2>; rel="next", <https://api.github.com/x?page=9>; rel="last"'
        self.assertEqual(at.next_link(header), "https://api.github.com/x?page=2")
        self.assertIsNone(at.next_link('<https://api.github.com/x?page=1>; rel="prev"'))
        self.assertIsNone(at.next_link(None))

    def test_owner_path(self):
        url = "https://api.github.com/repositories/150941685/issues?per_page=100&page=2"
        self.assertEqual(at.owner_path(url, "/repos/ezzz/HFRnow"),
                         "https://api.github.com/repos/ezzz/HFRnow/issues?per_page=100&page=2")
        same = "https://api.github.com/repos/ezzz/HFRnow/pulls?page=3"
        self.assertEqual(at.owner_path(same, "/repos/ezzz/HFRnow"), same)

    def test_group_by_number(self):
        items = [{"issue_url": "https://api.github.com/repos/o/r/issues/12"},
                 {"issue_url": "https://api.github.com/repos/o/r/issues/7"},
                 {"issue_url": "https://api.github.com/repos/o/r/issues/12"}]
        self.assertEqual({k: len(v) for k, v in at.group(items, "issue_url").items()}, {12: 2, 7: 1})

    def test_merge_keeps_deleted_and_updates_edited(self):
        old = [{"id": 1, "created_at": "a", "body": "v1"}, {"id": 2, "created_at": "b", "body": "gone"}]
        new = [{"id": 1, "created_at": "a", "body": "v2"}, {"id": 3, "created_at": "c", "body": "new"}]
        self.assertEqual([c["body"] for c in at.merge_by_id(old, new)], ["v2", "gone", "new"])

    def test_render_pr_orders_events(self):
        pr = {"number": 5, "title": "T", "state": "closed", "merged_at": "2026-11-01T00:00:00Z",
              "merge_commit_sha": "abc", "user": USER, "created_at": "c", "updated_at": "u",
              "labels": [{"name": "type: lot"}], "html_url": "h", "body": "Body",
              "head": {"label": "fork:b", "sha": "123"}, "base": {"ref": "dev-swift"}}
        comments = [{"user": USER, "created_at": "2026-11-01T02:00:00Z", "body": "second"}]
        reviews = [{"user": USER, "state": "APPROVED", "submitted_at": "2026-11-01T01:00:00Z",
                    "commit_id": "deadbeef", "body": "first"}]
        text = at.render(pr, comments, reviews, [])
        self.assertIn("# PR #5: T", text)
        self.assertIn("(merged)", text)
        self.assertLess(text.index("first"), text.index("second"))


if __name__ == "__main__":
    unittest.main()
