"""Tests for tooling/roadmap: LOTS.md -> lots.json, tracker JSON -> state, hygiene sweep (no network)."""
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROADMAP = Path(__file__).resolve().parents[2] / "tooling" / "roadmap"
sys.path.insert(0, str(ROADMAP))

import generate  # noqa: E402
import hygiene  # noqa: E402
import lots_from_md  # noqa: E402
import sync_state  # noqa: E402

HEAD = "| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |\n|---|---|---|---|---|---|---|---|---|\n"
NOW = datetime(2026, 11, 1, tzinfo=timezone.utc)


def md_row(lot, issue, deps="—", module="HFRParsing", model="Sonnet → Opus", scope="Scope", star=""):
    return f"| LOT-{lot}{star} | {scope} | {module} | easy | {model} | {deps} | — | high | [#{issue}](https://github.com/ezzz/HFRnow/issues/{issue}) |\n"


def lots_of(*rows):
    return lots_from_md.parse("## Phase 3 — engine\n\n### Parsing\n\n" + HEAD + "".join(rows))


def issue(n, state="open", labels=(), body="", created="2026-10-01T00:00:00Z"):
    return {"number": n, "state": state, "labels": [{"name": x} for x in labels], "body": body, "title": f"t{n}", "created_at": created}


def pr(n, body="", title="", merged_at=None, base="dev-swift", draft=False, state="closed", sha="abcdef1234567"):
    return {"number": n, "body": body, "title": title, "merged_at": merged_at, "merged": bool(merged_at), "base": {"ref": base},
            "draft": draft, "state": state, "merge_commit_sha": sha}


class LotsFromMd(unittest.TestCase):
    def test_row_fields_section_and_star(self):
        r = lots_of(md_row("001", 38, star=" ★", scope="Anonymizer `a|b` kit"))[0]
        self.assertEqual((r["lot"], r["star"], r["issue"], r["sec"], r["sub"]), ("LOT-001", True, 38, "Phase 3 — engine", "Parsing"))
        self.assertEqual(r["scope"], "Anonymizer `a|b` kit")  # a pipe inside backticks is not a cell separator

    def test_bad_rows_are_refused(self):
        with self.assertRaises(ValueError):
            lots_from_md.parse("| LOT-001 | only | three |\n")
        with self.assertRaises(ValueError):
            lots_of(md_row("001", 1), md_row("001", 2))

    def test_real_plan_parses_and_ids_are_unique(self):
        rows = lots_from_md.parse((ROADMAP.parent.parent / "docs" / "LOTS.md").read_text(encoding="utf-8"))
        self.assertGreater(len(rows), 100)
        self.assertEqual(len({r["lot"] for r in rows}), len(rows))
        self.assertTrue(all(isinstance(r["issue"], int) for r in rows))


class SyncState(unittest.TestCase):
    def test_labels_prs_and_captures(self):
        lots = lots_of(md_row("001", 1), md_row("002", 2, model="Opus → Fable"), md_row("003", 3), md_row("004", 4))
        issues = [
            issue(1, "closed"),
            issue(2, labels=["status: ready", "external: ready"]),
            issue(3, labels=["status: claimed"], body="### Captures needed\n\n- #50\n- #51\n"),
            issue(4, labels=["status: blocked"]),
            issue(50, labels=["host: mac", "type: chore"]),
            issue(51, "closed", labels=["host: mac"]),
            issue(52, labels=["host: mac"], body="### Wanted by\n\nLOT-004 (#4)\n"),
            {**issue(99), "pull_request": {}},
        ]
        pulls = [pr(10, title="LOT-001: done", merged_at="2026-10-30T00:00:00Z"),
                 pr(11, title="LOT-002: wip", state="open", draft=True),
                 pr(12, body="LOT-003 too", state="open"),
                 pr(13, title="LOT-004: other base", merged_at="2026-10-30T00:00:00Z", base="master")]
        st = sync_state.build(issues, pulls, lots)
        self.assertEqual(st["closed"], [1, 51])
        self.assertEqual((st["ready"], st["claimed"], st["external"]), ([2], [3], [2]))
        self.assertEqual(st["prs"], {"LOT-002": [11, "draft", "Fable"], "LOT-003": [12, "review", "Opus"]})
        self.assertEqual(st["merged_pr"], {"LOT-001": 10})
        self.assertEqual(st["capture"], {"3": "#50", "4": "#52"})  # #51 is closed: no longer a blocker


    def test_capture_references_to_prs_or_unknown_numbers_do_not_block(self):
        lots = lots_of(md_row("001", 1))
        issues = [issue(1, labels=["status: ready"], body="### Captures needed\n\n- #77 (a PR)\n- #999\n")]
        st = sync_state.build(issues, [], lots)
        self.assertEqual((st["ready"], st["capture"]), ([1], {}))

    def test_capture_closed_not_planned_or_duplicate_still_blocks_for_triage(self):
        lots = lots_of(md_row("001", 1))
        for reason in ("not_planned", "duplicate"):
            cap = issue(50, "closed", labels=["host: mac"])
            cap["state_reason"] = reason
            issues = [issue(1, labels=["status: ready"], body="### Captures needed\n\n- #50\n"), cap]
            self.assertEqual(sync_state.build(issues, [], lots)["capture"], {"1": "#50"}, reason)

    def test_capture_blocked_lot_is_not_ready_and_state_has_a_snapshot_time(self):
        lots = lots_of(md_row("001", 1))
        issues = [issue(1, labels=["status: ready"], body="### Captures needed\n\n- #50\n"), issue(50, labels=["host: mac"])]
        st = sync_state.build(issues, [], lots)
        self.assertEqual((st["ready"], st["capture"]), ([], {"1": "#50"}))
        self.assertRegex(st["generated_at"], r"^\d{4}-\d\d-\d\d \d\d:\d\d UTC$")


class Milestones(unittest.TestCase):
    def test_m5_membership_is_disjoint_and_complete(self):
        m = {"M1": generate.M1, "M2": generate.M2, "M3": generate.M3, "M4": generate.M4}
        for name, ids in m.items():
            self.assertFalse(ids & generate.M5, name)
        self.assertIn("LOT-100", generate.M5)  # a whole lot moved out of M2
        self.assertIn("LOT-147", generate.M5)  # a whole lot moved out of M4
        self.assertTrue(any(l in generate.M5 for l in ("LOT-174", "LOT-182")))  # the (b) halves of the splits
        self.assertEqual(len(generate.M1 | generate.M2 | generate.M3 | generate.M4 | generate.M5), len(generate.rows))

    def test_no_lot_of_m1_to_m4_depends_on_an_m5_lot(self):
        outside = generate.M1 | generate.M2 | generate.M3 | generate.M4
        bad = [(l, d) for l in outside for d in generate.deps(generate.rows[l]) if d in generate.M5]
        self.assertEqual(bad, [])


class Hygiene(unittest.TestCase):
    def setUp(self):
        self.lots = lots_of(md_row("001", 1), md_row("002", 2, deps="001"), md_row("003", 3, deps="001, 002"),
                            md_row("004", 4, deps="001", module="App"), md_row("005", 5, deps="all parsing lots"))

    def run_sweep(self, issues, pulls, comments=None):
        return hygiene.analyze(issues, pulls, self.lots, comments or {}, NOW)

    def test_unblock_credits_the_merged_pr_and_flags_engine_lots_external(self):
        issues = [issue(1, "open"), issue(2, labels=["status: blocked"]), issue(4, labels=["status: blocked", "host: mac"])]
        issues[0]["state"] = "closed"
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        actions, reports = self.run_sweep(issues, pulls)
        self.assertEqual([(a["kind"], a["issue"], a["pr"]) for a in actions], [("unblock", 2, 10), ("unblock", 4, 10)])
        self.assertTrue(any("#2 LOT-002 unblocked engine lot" in r for r in reports))  # external: ready is the operator's call
        self.assertFalse(any("#4 LOT-004 unblocked engine lot" in r for r in reports))  # an App lot is not

    def test_no_unblock_when_a_dependency_is_open_or_a_capture_waits_or_claimed(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"]),
                  issue(3, labels=["status: blocked"]), issue(4, labels=["status: claimed"], created="2026-10-31T00:00:00Z"),
                  issue(5, labels=["status: blocked"])]
        issues.append(issue(60, labels=["host: mac"], body="### Wanted by\n\n#2\n"))
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])  # 2 waits on capture #60, 3 on open #2, 4 is claimed, 5 is a gate sentence
        self.assertTrue(any("gate sentence" in r and "#5" in r for r in reports))

    def test_unblock_without_a_known_pr_is_only_reported(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        actions, reports = self.run_sweep(issues, [])
        self.assertEqual(actions, [])
        self.assertTrue(any("#2" in r and "no merged PR" in r for r in reports))

    def test_missing_done_closure_uses_closes_only_and_dev_swift_only(self):
        issues = [issue(1), issue(2), issue(3)]
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z"),
                 pr(11, body="Refs #2", merged_at="2026-10-30T00:00:00Z"),
                 pr(12, body="Closes #3", merged_at="2026-10-30T00:00:00Z", base="master"),
                 pr(13, body="Closes #2", state="closed")]  # closed unmerged
        actions, _ = self.run_sweep(issues, pulls)
        self.assertEqual([(a["kind"], a["issue"], a["pr"], a["sha"]) for a in actions], [("close", 1, 10, "abcdef1")])

    def test_reports_axis_conflicts_missing_status_ready_with_open_dep_and_stale_claim(self):
        issues = [issue(1), issue(2, labels=["type: lot", "status: ready"]),
                  issue(3, labels=["type: lot", "status: claimed", "status: ready", "priority: low", "priority: high"], created="2026-10-01T00:00:00Z"),
                  issue(4, labels=["type: bug"])]
        _, reports = self.run_sweep(issues, [], {3: [{"created_at": "2026-10-20T00:00:00Z"}]})
        text = "\n".join(reports)
        self.assertIn("#2 LOT-002 is `status: ready` but depends on open #1", text)
        self.assertIn("#3: 2 labels on axis `status`", text)
        self.assertIn("#3: 2 labels on axis `priority`", text)
        self.assertIn("#3: both `status: ready` and `status: claimed`", text)
        self.assertIn("#3: claimed, silent for 12 days", text)
        self.assertIn("#4: no `status:` label", text)

    def test_recent_comment_keeps_a_claim_fresh(self):
        issues = [issue(3, labels=["type: lot", "status: claimed"], created="2026-10-01T00:00:00Z")]
        _, reports = self.run_sweep(issues, [], {3: [{"created_at": "2026-10-31T12:00:00Z"}]})
        self.assertFalse(any("silent" in r for r in reports))

    def test_closes_keyword_only_at_line_start(self):
        issues = [issue(1), issue(2), issue(3)]
        body = "This does not close #1.\nStacked on #9, which closes #2.\nCloses #3\n"
        actions, _ = self.run_sweep(issues, [pr(10, body=body, merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual([a["issue"] for a in actions], [3])

    def test_dependency_closed_not_planned_blocks_the_unblock(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        issues[0]["state_reason"] = "not_planned"
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])
        self.assertTrue(any("not planned" in r and "#1" in r for r in reports))
        self.assertEqual(sync_state.build(issues, [], self.lots)["closed"], [])

    def test_blocked_by_naming_an_open_issue_and_needs_triage_are_left_alone(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body="### Blocked by\n\nADR #77\n\n### Model\n"),
                  issue(3, labels=["status: needs-triage"]), issue(77)]
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])
        self.assertTrue(any("#2 LOT-002" in r and "#77" in r for r in reports))

    def test_a_later_comment_saying_blocked_keeps_the_lot_blocked(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        late = {2: [{"body": "Labelled `status: blocked` on the signing assets.", "created_at": "2026-10-31T00:00:00Z"}]}
        actions, reports = self.run_sweep(issues, pulls, late)
        self.assertEqual(actions, [])
        self.assertTrue(any("#2 LOT-002" in r and "says it is blocked" in r for r in reports))
        early = {2: [{"body": "blocked on the dependency", "created_at": "2026-10-29T00:00:00Z"}]}
        actions, _ = self.run_sweep(issues, pulls, early)
        self.assertEqual([a["issue"] for a in actions], [2])  # the note predates the merge: stale

    def test_our_own_unblocked_by_comment_is_not_a_block_note(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        own = {2: [{"body": "Unblocked by #10", "created_at": "2026-10-31T00:00:00Z"}]}
        actions, _ = self.run_sweep(issues, pulls, own)
        self.assertEqual([a["issue"] for a in actions], [2])

    def test_an_m5_lot_is_never_unblocked_by_the_sweep(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1) + md_row("002", 2, deps="001", module="App"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        actions, reports = hygiene.analyze(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")], lots, {}, NOW)
        self.assertEqual(actions, [])
        self.assertTrue(any("M5 lots with every dependency done" in r and "#2" in r for r in reports))

    def test_a_reopened_issue_is_not_closed_again(self):
        issues = [issue(1)]
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")],
                                          {1: [{"body": "Done in #10 (merged as abc)", "created_at": "2026-10-30T01:00:00Z"}]})
        self.assertEqual(actions, [])
        self.assertTrue(any("reopened" in r for r in reports))

    def test_dependency_missing_from_the_plan_keeps_the_lot_blocked(self):
        lots = lots_of(md_row("001", 1), md_row("002", 2, deps="001, 999"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        actions, reports = hygiene.analyze(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")], lots, {}, NOW)
        self.assertEqual(actions, [])
        self.assertTrue(any("LOT-999" in r for r in reports))

    def test_dependency_cell_parsing(self):
        self.assertEqual(hygiene.numeric_deps("030, ADR 0006"), None)
        self.assertEqual(hygiene.numeric_deps("#123"), None)
        self.assertEqual(hygiene.numeric_deps("—"), [])
        self.assertEqual(hygiene.numeric_deps("080, 043"), ["LOT-080", "LOT-043"])
        self.assertIsNone(hygiene.numeric_deps("all parsing lots"))


if __name__ == "__main__":
    unittest.main()
