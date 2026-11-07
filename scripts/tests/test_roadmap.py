"""Tests for tooling/roadmap: LOTS.md -> lots.json, tracker JSON -> state, hygiene sweep (no network)."""
import contextlib
import io
import json
import re
import subprocess
import sys
import unittest
from unittest import mock
from datetime import date, datetime, timezone
from pathlib import Path

ROADMAP = Path(__file__).resolve().parents[2] / "tooling" / "roadmap"
sys.path.insert(0, str(ROADMAP))
sys.path.insert(0, str(ROADMAP / "weekly"))

import generate  # noqa: E402
import hygiene  # noqa: E402
import m5  # noqa: E402
import lots_from_md  # noqa: E402
import sync_state  # noqa: E402
import progress  # noqa: E402

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


class Boards(unittest.TestCase):
    def test_closed_m5_lots_show_as_not_opened_and_followups_belong_to_a_milestone(self):
        with mock.patch.object(m5, "M5_OPEN", False):
            self._closed_m5_assertions()

    def test_an_open_m5_lot_with_dependencies_done_goes_to_triage_like_any_lot(self):
        with mock.patch.object(m5, "M5_OPEN", True):
            states = [generate.state(l)[1] for l in generate.M5 if not generate.done(l)]
        self.assertFalse(any(x.startswith("⏸️") for x in states))

    def test_closed_m5_lot_labelled_ready_is_not_advertised_as_ready(self):
        lot = "LOT-175"
        issue = generate.rows[lot]["issue"]
        closed = {generate.rows[d]["issue"] for d in generate.deps(generate.rows[lot]) if d in generate.rows}
        with mock.patch.object(m5, "M5_OPEN", False), mock.patch.object(generate, "READY", {issue}), \
                mock.patch.object(generate, "PRS", {}), mock.patch.object(generate, "CLAIMED", set()), \
                mock.patch.object(generate, "CLOSED", closed):
            self.assertTrue(generate.state(lot)[1].startswith("⏸️"))

    def test_unblocked_helper_knows_m5_and_skips_it_while_closed(self):
        import subprocess, sys, pathlib
        root = pathlib.Path(generate.__file__).parent
        out = subprocess.run([sys.executable, str(root / "unblocked.py"), "LOT-084"], capture_output=True, text=True, cwd=root)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertNotIn("[M5]", out.stdout)

    def _closed_m5_assertions(self):
        self.assertTrue(all(m in ("M1", "M2", "M3", "M4") for m, _ in m5.FOLLOWUPS.values()))  # not lots: never M5-only
        self.assertEqual(m5.FOLLOWUPS[432][0], "M4")
        text = generate.followups_block("M4")
        self.assertIn("#432", text)
        self.assertNotIn("#424", text)
        waiting = [l for l in generate.M5 if generate.state(l)[1].startswith("⏸️")]
        self.assertTrue(all(not generate.done(l) for l in waiting))


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

    def test_blocked_lot_with_every_dependency_done_but_a_capture_open_is_reported(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"]), issue(60, labels=["host: mac"], body="### Wanted by\n\n#2\n")]
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])  # the capture still gates it, so nothing is unblocked
        self.assertTrue(any("gated only by an open capture" in r and "LOT-002 #2" in r and "#60" in r for r in reports))

    def test_a_closed_issue_loses_its_status_labels_and_an_open_one_keeps_them(self):
        issues = [issue(1, "closed", labels=["status: ready", "type: lot"]), issue(2, "closed", labels=["type: lot"]),
                  issue(3, "open", labels=["status: ready"]), issue(4, "closed", labels=["status: claimed", "status: blocked"])]
        actions, _ = self.run_sweep(issues, [])
        self.assertEqual([(a["kind"], a["issue"], a["labels"]) for a in actions if a["kind"] == "unlabel"],
                         [("unlabel", 1, ["status: ready"]), ("unlabel", 4, ["status: blocked", "status: claimed"])])  # 2 has none, 3 is open

    def _apply(self, current, actions):
        calls = []
        got = subprocess.CompletedProcess([], 0, stdout=json.dumps(current), stderr="")
        out = io.StringIO()
        with mock.patch.object(hygiene.subprocess, "run", return_value=got), \
                mock.patch.object(hygiene, "gh", lambda method, path, fields=(): calls.append((method, path))), contextlib.redirect_stdout(out):
            hygiene.apply(actions)
        return calls, out.getvalue()

    def test_apply_deletes_each_status_label_with_its_encoded_path_and_counts_them(self):
        closed = {"state": "closed", "labels": [{"name": "status: ready"}, {"name": "status: needs-triage"}, {"name": "type: lot"}]}
        act = {"kind": "unlabel", "issue": 5, "labels": ["status: ready", "status: needs-triage", "status: claimed"]}
        calls, out = self._apply(closed, [act])
        self.assertEqual(calls, [("DELETE", "repos/ezzz/HFRnow/issues/5/labels/status:%20needs-triage"),
                                 ("DELETE", "repos/ezzz/HFRnow/issues/5/labels/status:%20ready")])  # `claimed` is not on the issue any more: no call
        self.assertIn("status labels removed from closed issues: 2", out)

    def test_apply_leaves_an_issue_reopened_meanwhile_alone(self):
        calls, out = self._apply({"state": "open", "labels": [{"name": "status: ready"}]}, [{"kind": "unlabel", "issue": 5, "labels": ["status: ready"]}])
        self.assertEqual(calls, [])
        self.assertIn("skip (reopened meanwhile)", out)
        self.assertIn("removed from closed issues: 0", out)

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

    @mock.patch.object(m5, "M5_OPEN", True)
    def test_once_m5_is_open_its_lots_follow_the_ordinary_sweep_rules(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1) + md_row("002", 2, deps="001", module="App"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        actions, _ = hygiene.analyze(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")], lots, {}, NOW)
        self.assertEqual([a["issue"] for a in actions], [2])

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_an_m5_lot_is_never_unblocked_by_the_sweep(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1) + md_row("002", 2, deps="001", module="App"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]
        actions, reports = hygiene.analyze(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")], lots, {}, NOW)
        self.assertEqual(actions, [])
        self.assertTrue(any("M5 lots with every dependency done" in r and "#2" in r for r in reports))

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_an_m5_lot_labelled_ready_is_reported(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1, module="App"))
        issues = [issue(1, labels=["status: ready"])]
        _, reports = hygiene.analyze(issues, [], lots, {}, NOW)
        self.assertTrue(any("M5 lot labelled `status: ready`" in r and "#1" in r for r in reports))

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_an_m5_lot_without_a_credited_pr_is_not_offered_for_a_hand_unblock(self):
        lots = lots_from_md.parse("## Phase 3 — engine\n\n" + HEAD + md_row("001", 1) + md_row("100", 2, deps="001", module="App"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"])]  # LOT-100 is a moved M5 lot; no merged PR credited
        _, reports = hygiene.analyze(issues, [], lots, {}, NOW)
        self.assertFalse(any("unblock by hand" in r for r in reports))
        self.assertTrue(any("M5 lots with every dependency done" in r for r in reports))

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


class ProgressSlide(unittest.TestCase):
    def test_audit_is_lot_000_to_005_and_other_lots_take_their_milestone(self):
        self.assertEqual(progress.step_of_lot("LOT-000"), "Audit")
        self.assertEqual(progress.step_of_lot("LOT-005"), "Audit")
        self.assertEqual(progress.step_of_lot("LOT-080"), "M1")
        self.assertEqual(progress.step_of_lot(next(iter(sorted(generate.M5)))), "M5")

    def test_a_pr_goes_to_the_step_of_the_first_lot_of_its_title_then_its_body_else_infra(self):
        self.assertEqual(progress.step_of_pr({"title": "LOT-080: app target", "body": "LOT-137"}), "M1")
        self.assertEqual(progress.step_of_pr({"title": "docs: fix a typo", "body": "Refs LOT-080"}), "M1")
        self.assertEqual(progress.step_of_pr({"title": "chore: ci", "body": "Direct-PR"}), progress.OTHER)
        self.assertEqual(progress.step_of_pr({"title": "LOT-999: unknown lot", "body": ""}), progress.OTHER)

    def test_a_blocked_lot_whose_lot_dependencies_are_all_done_needs_a_human_not_other_lots(self):
        r = next(r for l, r in generate.rows.items() if generate.deps(r))
        lot = r["lot"]
        with mock.patch.object(generate, "CAPTURE", {}), mock.patch.object(generate, "CLOSED", set()):
            with mock.patch.object(generate, "miss0", lambda row: ["LOT-X"]):
                self.assertEqual(progress.bucket(lot, {"status: blocked"}), "blocked")
            with mock.patch.object(generate, "miss0", lambda row: []):
                self.assertEqual(progress.bucket(lot, {"status: blocked"}), "human")

    def test_a_pr_naming_an_unknown_lot_then_a_known_one_goes_to_the_known_step(self):
        self.assertEqual(progress.step_of_pr({"title": "LOT-999 / LOT-080", "body": ""}), "M1")

    def test_data_bins_by_utc_day_then_week_and_never_drops_a_late_day(self):
        pulls = [{"merged_at": "2026-11-07T01:00:00Z", "title": "LOT-080", "body": ""}, {"merged_at": "2026-11-05T10:00:00Z", "title": "ci", "body": ""}]
        d = progress.data(pulls, [], per_day={"2026-11-05": 2, "2026-11-06": 1}, today=date(2026, 11, 6))  # a PR dated after "today"
        self.assertFalse(d["weekly"])
        self.assertEqual(list(d["bins"]), ["2026-11-05", "2026-11-06", "2026-11-07"])
        self.assertEqual(d["bins"]["2026-11-07"], {"M1": 1})
        self.assertEqual(d["cum"][-1], ("2026-11-07", 3))  # cumulative up to the latest day seen
        old = [{"merged_at": "2026-09-30T10:00:00Z", "title": "ci", "body": ""}]  # a Wednesday: its bin is the Monday before
        w = progress.data(old, [], per_day={"2026-09-30": 1}, today=date(2026, 11, 6))
        self.assertTrue(w["weekly"])
        self.assertEqual(next(iter(w["bins"])), "2026-09-28")
        self.assertEqual(w["bins"]["2026-09-28"], {progress.OTHER: 1})

    def test_data_without_commits_or_prs_does_not_crash_and_the_charts_say_so(self):
        d = progress.data([], [], per_day={}, today=date(2026, 11, 6))
        self.assertEqual((d["cum"], d["bins"]), ([], {}))
        self.assertIn("Aucun commit", progress._line_chart(d["cum"]))
        self.assertIn("Aucune PR", progress._stacked(d["bins"], d["weekly"]))
        self.assertIn("0 %", progress._donut("M5", {}))  # zero lots in a step

    def test_a_lot_closed_not_planned_is_left_out_of_its_step(self):
        lot = "LOT-087"
        i = {"number": generate.rows[lot]["issue"], "state": "closed", "state_reason": "not_planned", "labels": []}
        before = sum(progress.data([], [], per_day={}, today=date(2026, 11, 6))["steps"][progress.step_of_lot(lot)].values())
        after = sum(progress.data([], [i], per_day={}, today=date(2026, 11, 6))["steps"][progress.step_of_lot(lot)].values())
        self.assertEqual(after, before - 1)

    def test_a_lot_counts_in_exactly_one_bucket_by_priority(self):
        m4_app = next(l for l in sorted(generate.M4) if generate.rows[l]["module"] == "App")  # not coded by the cloud yet
        m2_app = next(l for l in sorted(generate.M2) if generate.rows[l]["module"] == "App")  # the cloud codes these (2026-11-05)
        n4, n2 = generate.rows[m4_app]["issue"], generate.rows[m2_app]["issue"]
        quiet = (mock.patch.object(generate, "CLOSED", set()), mock.patch.object(generate, "CAPTURE", {}),
                 mock.patch.object(generate, "CLAIMED", set()), mock.patch.object(generate, "PRS", {}))
        with quiet[0], quiet[1], quiet[2], quiet[3]:
            self.assertEqual(progress.bucket(m4_app, {"host: mac"}), "mac")
            self.assertEqual(progress.bucket(m2_app, {"host: mac"}), "ready")  # a host: mac App lot of M2 the cloud can code
            self.assertEqual(progress.bucket(m4_app, set()), "ready")
            self.assertEqual(progress.bucket(m4_app, {"priority: low"}), "low")
            self.assertEqual(progress.bucket(m4_app, {"priority: low", "host: mac"}), "mac")  # mac outranks low
            self.assertEqual(progress.bucket(m4_app, {"status: needs-triage", "host: mac"}), "human")  # human outranks mac
            with mock.patch.object(generate, "CAPTURE", {n4: "#1"}):
                self.assertEqual(progress.bucket(m4_app, set()), "mac")  # a capture is Mac-only work
            with mock.patch.object(generate, "CLAIMED", {n4}):
                self.assertEqual(progress.bucket(m4_app, {"host: mac", "status: blocked"}), "progress")  # claimed: never macOS nor ready
            with mock.patch.object(generate, "PRS", {m2_app: (1, "review", "Opus")}):
                self.assertEqual(progress.bucket(m2_app, {"host: mac"}), "progress")  # an open PR names the lot
        with mock.patch.object(generate, "CLOSED", {n2}), mock.patch.object(generate, "CLAIMED", {n2}):
            self.assertEqual(progress.bucket(m2_app, {"status: blocked", "host: mac"}), "done")  # done outranks everything


class FoldFragmentsTest(unittest.TestCase):
    """hygiene.py reports pending docs fragments (dry-run) and folds them only with --apply (#612)."""

    def layout(self):
        import shutil
        import tempfile
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        repo = Path(__file__).resolve().parents[2]
        for rel in ("docs/CHANGELOG-LEGACY.md", "docs/migration/GAP-LEGACY-VS-SWIFT.md"):
            (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(repo / rel, tmp / rel)
        lay = hygiene.docs_fold.Layout(tmp)
        lay.changelog_dir.mkdir()
        lay.gap_dir.mkdir()
        return lay

    def test_ledger_report_is_a_dry_run(self):
        lay = self.layout()
        self.assertEqual(hygiene.ledger_pending([], lay), ["ledger: none pending"])
        ok = {"number": 5, "body": "Closes #9\n\n### Ledger\n\n```changelog\n| T | Résumé. | LOT-9 | preuve |\n```\n"}
        before = lay.changelog.read_text(encoding="utf-8")
        self.assertIn("1 pending (#5)", hygiene.ledger_pending([ok], lay)[0])
        self.assertEqual(lay.changelog.read_text(encoding="utf-8"), before)
        out = hygiene.ledger_pending([{"number": 6, "body": "### Ledger\n\nprose"}], lay)
        self.assertIn("0 foldable, 1 refused", out[0])
        self.assertIn("PR #6 refused", out[1])
        with mock.patch.object(hygiene.docs_ledger, "fetch_pending", side_effect=hygiene.docs_ledger.LedgerError("gh down")):
            self.assertEqual(hygiene.ledger_pending(None, lay), ["ledger: cannot report: gh down"])

    def test_dry_run_reports_and_apply_folds(self):
        lay = self.layout()
        self.assertEqual(hygiene.fold_fragments(False, lay), ["docs fragments: none pending"])
        (lay.changelog_dir / "9999.md").write_text("| T | Résumé. | LOT-9 | preuve |\n", encoding="utf-8")
        before = lay.changelog.read_text(encoding="utf-8")
        out = hygiene.fold_fragments(False, lay)
        self.assertIn("1 pending (9999.md)", out[0])
        self.assertEqual(lay.changelog.read_text(encoding="utf-8"), before)
        self.assertIn("folded 1", hygiene.fold_fragments(True, lay)[0])
        self.assertIn("| 9999 | T |", lay.changelog.read_text(encoding="utf-8"))
        self.assertFalse((lay.changelog_dir / "9999.md").exists())

    def test_stale_tallies_do_not_block_apply(self):
        lay = self.layout()
        hygiene.docs_fold.fold(lay)  # baseline: the committed file may itself carry stale tallies (direct edits of other PRs)
        text = lay.gap.read_text(encoding="utf-8")
        total = re.search(r"^\| \*\*Total\*\* \| \*\*\d+\*\* \|$", text, re.M).group(0)  # whatever the committed total is
        stale = "| **Total** | **1** |"
        self.assertNotEqual(total, stale)
        lay.gap.write_text(text.replace(total, stale), encoding="utf-8")
        (lay.changelog_dir / "9999.md").write_text("| T | Résumé. | LOT-9 | preuve |\n", encoding="utf-8")
        self.assertIn("folded 1", hygiene.fold_fragments(True, lay)[0])
        self.assertEqual(lay.gap.read_text(encoding="utf-8"), text)  # the fold restored the generated total

    def test_duplicate_fragment_numbers_are_reported_not_raised(self):
        lay = self.layout()
        for n in ("7.md", "007.md"):
            (lay.changelog_dir / n).write_text("| T | Résumé. | LOT-9 | preuve |\n", encoding="utf-8")
        self.assertIn("NOT foldable", hygiene.fold_fragments(True, lay)[0])

    def test_duplicate_row_in_a_shared_file_blocks_apply(self):
        lay = self.layout()
        text = lay.gap.read_text(encoding="utf-8")
        first = next(l for l in text.split("\n") if l.startswith("| GAP-001 |"))
        lay.gap.write_text(text.replace(first, first + "\n" + first), encoding="utf-8")  # GAP-001 twice
        (lay.changelog_dir / "9999.md").write_text("| T | Résumé. | LOT-9 | preuve |\n", encoding="utf-8")
        self.assertIn("NOT foldable", hygiene.fold_fragments(True, lay)[0])
        self.assertTrue((lay.changelog_dir / "9999.md").exists(), "no fragment removed while a duplicate remains")

    def test_malformed_fragment_is_reported_not_folded(self):
        lay = self.layout()
        (lay.gap_dir / "GAP-9999.md").write_text("not a fragment\n", encoding="utf-8")
        out = hygiene.fold_fragments(True, lay)
        self.assertIn("NOT foldable", out[0])
        self.assertTrue((lay.gap_dir / "GAP-9999.md").exists())


if __name__ == "__main__":
    unittest.main()
