"""One grammar for the `Closes #N` / `Refs #N` lines of a PR body (#1198): the claim check, the sweep and the ledger agree."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tooling" / "roadmap"))
sys.path.insert(0, str(ROOT / "tooling" / "docs"))
sys.path.insert(0, str(ROOT / "tooling" / "common"))

import pr_refs  # noqa: E402
import issue_claims  # noqa: E402
import ledger  # noqa: E402

PR = 999  # the ledger falls back to the PR number when the body names no issue

# body -> (issues the PR closes, issues it links: what the claim check requires)
BODIES = {
    "LOT-012 · Closes #45": ([45], [45]),
    "- Closes #77": ([77], [77]),
    "**Closes #12**": ([12], [12]),
    "Closed #9": ([9], [9]),
    "Fixes #123": ([123], [123]),
    "Refs #893 for the device check.\n\nCloses #50": ([50], [50]),
    "Closes #50, #51": ([50, 51], [50, 51]),
    "Closes #7\r\nClaim: mac/x": ([7], [7]),
    "Refs #12\n": ([], [12]),
    "Closes #4\nCloses #4": ([4], [4]),
    "Also fixes #12 in passing": ([], []),
    "<!-- Closes #1 -->\nDirect-PR: typo fix": ([], []),
    "No link here": ([], []),
    # #1289 review, round 1: prose is not a reference
    "**Why `Refs #152` and not `Closes #152`:** UXD-08 split it.\nThe issue's \"last lot, Closes #152\" line predates the split.": ([], []),
    "Refs #594 (partial: fixed here). Closes #594 only once that check shows Citer.": ([], [594]),
    "This keeps legacy, fixes #12 only partly.": ([], []),
    "The crash came from the cache. Fixes #12 will need a capture.": ([], []),
    "Fixes #3. Closes #1, resolves #3.": ([3, 1], [3, 1]),
    "```\nCloses #3\n```\nRefs #5": ([], [5]),
    "Refs #237 #160": ([], [237, 160]),
    "Closes #106 #107 and #108": ([106, 107, 108], [106, 107, 108]),
    "LOT-012 — Closes #45": ([45], [45]),
    "LOT-012 – Closes #46": ([46], [46]),
    # round 2: a clause opens only after another reference
    "This keeps legacy, fixes #12 (only partly).": ([], []),
    "Not done; closes #12, maybe.": ([], []),
    "Refs #368 (directive H.1–H.3), Refs #379 (M5 proposal)": ([], [368, 379]),
    "Closes #1, resolves #2 — both.": ([1, 2], [1, 2]),
    "Fixed it; closes #8 — later": ([], []),
}


class PrRefsAgreeTests(unittest.TestCase):
    def test_pr_refs_agree(self):
        for body, (closes, linked) in BODIES.items():
            with self.subTest(body=body):
                self.assertEqual(issue_claims.linked_issues(body), linked, "claim check")
                self.assertEqual(pr_refs.closing_issues(body), closes, "sweep: closes")
                primary = linked[0] if linked else PR
                self.assertEqual(ledger.issue_number(body, PR), primary, "ledger")


if __name__ == "__main__":
    unittest.main()
