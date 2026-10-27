"""Tests for scripts/issue_claims.py: claim replay and the PR link check."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import issue_claims as ic  # noqa: E402


def comment(body, association="OWNER"):
    return {"body": body, "author_association": association}


OPEN = {"state": "open"}


class ParseCommandTests(unittest.TestCase):
    def test_first_non_empty_line_only(self):
        self.assertEqual(ic.parse_command("\n/claim cloud/c1-sonnet\nworking on it"), ("claim", "cloud/c1-sonnet"))
        self.assertIsNone(ic.parse_command("I will /claim cloud/c1 later"))
        self.assertIsNone(ic.parse_command("/claimed cloud/c1"))

    def test_release_with_and_without_id(self):
        self.assertEqual(ic.parse_command("/release"), ("release", None))
        self.assertEqual(ic.parse_command("/release mac/M1"), ("release", "mac/M1"))


class ReplayTests(unittest.TestCase):
    def test_first_claim_wins_and_second_is_refused(self):
        state = ic.replay([comment("/claim cloud/a"), comment("/claim cloud/b")])
        self.assertEqual(state.holder, "cloud/a")
        self.assertEqual(state.refused, [("cloud/b", "cloud/a")])

    def test_release_frees_then_next_claim_holds(self):
        state = ic.replay([comment("/claim cloud/a"), comment("/release"), comment("/claim cloud/b")])
        self.assertEqual(state.holder, "cloud/b")

    def test_release_naming_another_session_is_ignored(self):
        state = ic.replay([comment("/claim cloud/a"), comment("/release cloud/b")])
        self.assertEqual(state.holder, "cloud/a")

    def test_reclaim_by_holder_is_not_a_refusal(self):
        state = ic.replay([comment("/claim cloud/a"), comment("/claim cloud/a")])
        self.assertEqual((state.holder, state.refused), ("cloud/a", []))

    def test_outsiders_do_not_count(self):
        state = ic.replay([comment("/claim cloud/evil", "NONE"), comment("/claim cloud/a", "CONTRIBUTOR")])
        self.assertIsNone(state.holder)
        state = ic.replay([comment("/claim cloud/a"), comment("/release", "NONE")])
        self.assertEqual(state.holder, "cloud/a")

    def test_malformed_session_id_is_not_a_claim(self):
        state = ic.replay([comment("/claim"), comment("/claim Cloud A"), comment("/claim noslash")])
        self.assertIsNone(state.holder)
        self.assertEqual(len(state.invalid), 2)  # "/claim Cloud A" is not a command at all


class PullRequestCheckTests(unittest.TestCase):
    def check(self, body, issues, comments, author="francoisgn"):
        claims = {n: ic.replay(comments.get(n, [])) for n in issues}
        return ic.pr_errors(body, author, issues, claims)

    def test_passes_with_link_and_matching_claim(self):
        errors = self.check("Closes #7\n\nClaim: cloud/a", {7: OPEN}, {7: [comment("/claim cloud/a")]})
        self.assertEqual(errors, [])

    def test_refs_is_accepted_for_partial_work(self):
        self.assertEqual(self.check("Refs #7\nClaim: cloud/a", {7: OPEN}, {7: [comment("/claim cloud/a")]}), [])

    def test_missing_link_and_claim_line(self):
        errors = self.check("No link here", {}, {})
        self.assertEqual(len(errors), 2)

    def test_claim_held_by_another_session(self):
        errors = self.check("Closes #7\nClaim: cloud/b", {7: OPEN}, {7: [comment("/claim cloud/a")]})
        self.assertIn("claimed by `cloud/a`", errors[0])

    def test_unclaimed_closed_missing_and_pull_request(self):
        issues = {1: OPEN, 2: {"state": "closed"}, 4: {"state": "open", "pull_request": {}}}
        errors = self.check("Closes #1, closes #2, closes #3, refs #4\nClaim: cloud/a", issues, {})
        self.assertEqual(len(errors), 4)
        self.assertTrue(any("not claimed" in e for e in errors))
        self.assertTrue(any("#2 is closed" in e for e in errors))
        self.assertTrue(any("#3 does not exist" in e for e in errors))
        self.assertTrue(any("#4 is a pull request" in e for e in errors))

    def test_claim_line_must_be_its_own_line(self):
        errors = self.check("Closes #7 — Claim: cloud/a", {7: OPEN}, {7: [comment("/claim cloud/a")]})
        self.assertTrue(any("Claim: <session-id>" in e for e in errors))

    def test_crlf_body_from_the_web_editor(self):
        errors = self.check("Closes #7\r\n\r\nClaim: cloud/a\r\n", {7: OPEN}, {7: [comment("/claim cloud/a")]})
        self.assertEqual(errors, [])

    def test_links_inside_html_comments_do_not_count(self):
        body = "<!-- e.g. Closes #7\nClaim: cloud/a -->\nCloses #\nClaim: "
        self.assertEqual(ic.linked_issues(body), [])
        self.assertEqual(len(self.check(body, {}, {})), 2)

    def test_direct_pr_break_glass(self):
        self.assertEqual(self.check("Direct-PR: fix the CI badge", {}, {}), [])
        self.assertEqual(self.check("direct-pr: typo in README\r\n", {}, {}), [])
        self.assertEqual(ic.pr_errors("No link", "someone", {}, {}, frozenset({"direct-pr"})), [])

    def test_direct_pr_needs_a_reason_and_its_own_line(self):
        self.assertIn("needs a short reason", self.check("Direct-PR:   ", {}, {})[0])
        self.assertIn("needs a short reason", self.check("Direct-PR: .", {}, {})[0])
        self.assertEqual(len(self.check("See Direct-PR: inline", {}, {})), 2)
        self.assertEqual(len(self.check("<!-- Direct-PR: hint -->", {}, {})), 2)

    def test_dependabot_is_exempt(self):
        self.assertEqual(self.check("Bumps x", {}, {}, author="dependabot[bot]"), [])

    def test_linked_issues_dedupes_and_keeps_order(self):
        self.assertEqual(ic.linked_issues("Fixes #3. Closes #1, resolves #3, refs #2"), [3, 1, 2])
        self.assertEqual(ic.linked_issues("see #4, PR#5"), [])


if __name__ == "__main__":
    unittest.main()
