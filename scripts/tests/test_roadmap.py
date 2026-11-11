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
import counts  # noqa: E402

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


    def test_on_hold_and_needs_decision_are_states_of_their_own(self):
        lots = lots_of(md_row("001", 1), md_row("002", 2), md_row("003", 3))
        issues = [issue(1, labels=["status: on-hold"]), issue(2, labels=["status: needs-decision"]), issue(3, labels=["status: blocked"]),
                  issue(4, "closed", labels=["status: on-hold"])]
        st = sync_state.build(issues, [], lots)
        self.assertEqual((st["on_hold"], st["needs_decision"], st["ready"]), ([1], [2], []))


class Milestones(unittest.TestCase):
    def test_m5_membership_is_disjoint_and_complete(self):
        m = {"M1": generate.M1, "M2": generate.M2, "M3": generate.M3, "M4": generate.M4}
        for name, ids in m.items():
            self.assertFalse(ids & generate.M5, name)
        self.assertIn("LOT-110", generate.M5)  # a whole lot moved out of M2
        self.assertIn("LOT-145", generate.M5)  # a whole lot moved out of M4
        self.assertTrue(any(l in generate.M5 for l in ("LOT-174", "LOT-182")))  # the (b) halves of the splits
        self.assertIn("LOT-187", generate.M5)  # cache clearing, the M5 half left when LOT-179 went to M4
        self.assertEqual(len(generate.M1 | generate.M2 | generate.M3 | generate.M4 | generate.M5), len(generate.rows))

    def test_legacy_evolution_backports_are_in_m4(self):
        # Operator, 2026-11-09 on #655: in the legacy reference 2fe43da3, so parity (M4), not evolutions (M5).
        for lot in ("LOT-100", "LOT-101", "LOT-146", "LOT-147", "LOT-179"):
            self.assertIn(lot, generate.M4, lot)

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

    def test_an_on_hold_lot_is_its_own_state_neither_blocked_nor_ready(self):
        lot = next(l for l in sorted(generate.M4) if generate.deps(generate.rows[l]))
        n = generate.rows[lot]["issue"]
        quiet = dict(PRS={}, CLAIMED=set(), CLOSED=set(), CAPTURE={})
        with mock.patch.multiple(generate, **quiet), mock.patch.object(generate, "ON_HOLD", {n}), mock.patch.object(generate, "READY", {n}):
            self.assertEqual(generate.state(lot), ("todo", "⏸️ on hold (decision)"))
        with mock.patch.multiple(generate, **quiet), mock.patch.object(generate, "NEEDS_DECISION", {n}):
            self.assertEqual(generate.state(lot), ("todo", "❓ needs a decision"))
        with mock.patch.multiple(generate, **quiet), mock.patch.object(generate, "ON_HOLD", {n}), mock.patch.object(generate, "CLAIMED", {n}):
            self.assertEqual(generate.state(lot)[0], "ongoing")  # a claim outranks the hold
        legend = (ROADMAP / "render.py").read_text(encoding="utf-8")  # render.py writes the boards on import: read its source
        self.assertIn("| | ⏸️ on hold |", legend)
        self.assertIn("| | ❓ needs a decision |", legend)

    def test_unblocked_helper_skips_an_on_hold_lot(self):
        import tempfile, os
        lot, dep = next((l, d) for l, r in sorted(generate.rows.items()) for d in generate.deps(r)[:1]
                        if d in generate.rows and len([x for x in generate.deps(r) if x in generate.rows]) == 1 and l not in generate.M5)
        n, dn = generate.rows[lot]["issue"], generate.rows[dep]["issue"]
        root = Path(generate.__file__).parent
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "state.json"
            base = {"closed": [dn], "ready": [], "claimed": [], "external": [], "prs": {}, "merged_pr": {}, "capture": {}}
            outs = []
            for key, hold in (("on_hold", []), ("on_hold", [n]), ("needs_decision", [n])):
                f.write_text(json.dumps({**base, key: hold}))
                r = subprocess.run([sys.executable, str(root / "unblocked.py"), dep], capture_output=True, text=True, cwd=root,
                                   env={**os.environ, "ROADMAP_STATE": str(f)})
                self.assertEqual(r.returncode, 0, r.stderr)
                outs.append(r.stdout)
        self.assertIn(f"{lot} #{n}", outs[0])
        self.assertNotIn(f"{lot} #{n}", outs[1])
        self.assertNotIn(f"{lot} #{n}", outs[2])

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

    def test_reports_two_origin_labels_on_one_issue(self):
        issues = [issue(6, labels=["type: bug", "status: ready", "origin: parity", "origin: swift-feedback"]),
                  issue(7, labels=["type: bug", "status: ready", "origin: parity"])]
        _, reports = self.run_sweep(issues, [])
        text = "\n".join(reports)
        self.assertIn("#6: 2 labels on axis `origin` (origin: parity, origin: swift-feedback)", text)
        self.assertNotIn("#7:", text)

    def test_unblock_credits_the_merged_pr_and_flags_engine_lots_external(self):
        issues = [issue(1, "open"), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n"),
                  issue(4, labels=["status: blocked", "host: mac"], body="### Blocked by\n\n#1\n")]
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
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n")]
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
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n")]
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        late = {2: [{"body": "Labelled `status: blocked` on the signing assets.", "created_at": "2026-10-31T00:00:00Z"}]}
        actions, reports = self.run_sweep(issues, pulls, late)
        self.assertEqual(actions, [])
        self.assertTrue(any("#2 LOT-002" in r and "says it is blocked" in r for r in reports))
        early = {2: [{"body": "blocked on the dependency", "created_at": "2026-10-29T00:00:00Z"}]}
        actions, _ = self.run_sweep(issues, pulls, early)
        self.assertEqual([a["issue"] for a in actions], [2])  # the note predates the merge: stale

    def test_our_own_unblocked_by_comment_is_not_a_block_note(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n")]
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        own = {2: [{"body": "Unblocked by #10", "created_at": "2026-10-31T00:00:00Z"}]}
        actions, _ = self.run_sweep(issues, pulls, own)
        self.assertEqual([a["issue"] for a in actions], [2])

    @mock.patch.object(m5, "M5_OPEN", True)
    def test_once_m5_is_open_its_lots_follow_the_ordinary_sweep_rules(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1) + md_row("002", 2, deps="001", module="App"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n")]
        actions, _ = hygiene.analyze(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")], lots, {}, NOW)
        self.assertEqual([a["issue"] for a in actions], [2])

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_an_m5_lot_is_never_unblocked_and_a_blocked_one_is_reported_for_on_hold(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1) + md_row("002", 2, deps="001", module="App")
                                  + md_row("003", 3, deps="001", module="App"))
        issues = [issue(1), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n"), issue(3, labels=["status: on-hold"])]
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        for state in ("open", "closed"):  # with a dependency open or done: the M5_OPEN decision holds it either way
            issues[0]["state"] = state
            actions, reports = hygiene.analyze(issues, pulls, lots, {}, NOW)
            self.assertEqual([a for a in actions if a["kind"] == "unblock"], [])
            held = [r for r in reports if "M5_OPEN" in r]
            self.assertEqual(len(held), 1, reports)
            self.assertIn("`status: on-hold`", held[0])
            self.assertIn("LOT-002 #2", held[0])
            self.assertNotIn("#3", held[0])  # already on hold
            self.assertFalse(any("names no blocker" in r for r in reports))

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_an_m5_lot_labelled_ready_is_reported(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1, module="App"))
        issues = [issue(1, labels=["status: ready"])]
        _, reports = hygiene.analyze(issues, [], lots, {}, NOW)
        self.assertTrue(any("M5 lot labelled `status: ready`" in r and "#1" in r and "`status: on-hold`" in r for r in reports))

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_an_m5_lot_without_a_credited_pr_is_not_offered_for_a_hand_unblock(self):
        lots = lots_from_md.parse("## Phase 3 — engine\n\n" + HEAD + md_row("001", 1) + md_row("110", 2, deps="001", module="App"))
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body="### Blocked by\n\n#1\n")]  # LOT-110 is a moved M5 lot
        _, reports = hygiene.analyze(issues, [], lots, {}, NOW)
        self.assertFalse(any("unblock by hand" in r for r in reports))
        self.assertTrue(any("M5_OPEN" in r and "LOT-110 #2" in r for r in reports))

    @mock.patch.object(m5, "M5_OPEN", True)
    def test_once_m5_is_open_its_on_hold_lots_are_listed_never_moved(self):
        lots = lots_from_md.parse("## M5 · UX evolutions\n\n" + HEAD + md_row("001", 1, module="App"))
        actions, reports = hygiene.analyze([issue(1, labels=["status: on-hold"])], [], lots, {}, NOW)
        self.assertEqual(actions, [])
        self.assertTrue(any("M5 is open" in r and "LOT-001 #1" in r for r in reports))

    def test_blocked_by_section_is_read_like_the_harness_check(self):
        b = hygiene.blockers_of
        self.assertEqual(b("### Summary\nx\n\n### Blocked by\n\n#12\n#14\n\n### Other\ny"), ["#12", "#14"])
        self.assertEqual(b("### Blocked by\r\n\r\n- camera access from a third party\r\n"), ["camera access from a third party"])
        self.assertEqual(b("#### blocked by\n#3"), ["#3"])
        for body in ("", None, "Summary only", "### Blocked by", "### Blocked by\n\n   \n", "### Blocked by\n\nnone",
                     "### Blocked by\n\n_No response_", "### Blocked by\n\n### Next\nx", "I am blocked by nothing",
                     "Blocked by: #3", "### Blocked by this\n#3"):
            self.assertIsNone(b(body), body)

    def test_a_blocked_issue_without_a_blocked_by_section_is_reported_never_relabelled(self):
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"]), issue(50, labels=["type: bug", "status: blocked"])]
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])  # LOT-002's dependency is done, but nothing names it as the blocker
        text = "\n".join(reports)
        self.assertIn("names no blocker", text)
        self.assertIn("#2", text)
        self.assertIn("#50", text)
        self.assertIn("`status: on-hold`", text)  # the report says what to do when a decision holds it

    def test_unblock_only_when_every_blocker_of_the_section_is_closed(self):
        body = "### Summary\nx\n\n### Blocked by\n\n#1\n- #77\n"
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z"), pr(11, body="Closes #77", merged_at="2026-10-31T00:00:00Z")]
        issues = [issue(1, "closed"), issue(77), issue(50, labels=["type: bug", "status: blocked"], body=body)]
        actions, _ = self.run_sweep(issues, pulls)
        self.assertEqual([a for a in actions if a["kind"] == "unblock"], [])  # #77 still open
        issues[1]["state"] = "closed"
        actions, _ = self.run_sweep(issues, pulls)
        self.assertEqual([(a["kind"], a["issue"], a["pr"]) for a in actions if a["kind"] == "unblock"], [("unblock", 50, 11)])  # the last merge

    def test_a_merged_pr_named_as_blocker_counts_as_closed(self):
        issues = [issue(50, labels=["type: chore", "status: blocked"], body="### Blocked by\n\n#12\n")]
        actions, _ = self.run_sweep(issues, [pr(12, title="x", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual([(a["kind"], a["issue"], a["pr"]) for a in actions], [("unblock", 50, 12)])
        actions, _ = self.run_sweep(issues, [pr(12, title="x", state="open")])
        self.assertEqual(actions, [])

    def test_a_free_text_blocker_keeps_the_issue_blocked(self):
        body = "### Blocked by\n\n#1\ncapture of the MP page on the Mac\n"
        issues = [issue(1, "closed"), issue(50, labels=["type: bug", "status: blocked"], body=body)]
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])
        self.assertFalse(any("#50" in r for r in reports))  # a real external blocker: nothing to report

    def test_a_blocker_closed_not_planned_is_reported_and_keeps_the_issue_blocked(self):
        issues = [issue(1, "closed"), issue(50, labels=["type: bug", "status: blocked"], body="### Blocked by\n\n#1\n")]
        issues[0]["state_reason"] = "not_planned"
        actions, reports = self.run_sweep(issues, [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")])
        self.assertEqual(actions, [])
        self.assertTrue(any("#50" in r and "#1" in r and "not planned" in r for r in reports))

    def test_every_ref_of_a_line_must_be_closed_and_any_other_text_keeps_it_blocked(self):
        pulls = [pr(10, body="Closes #2", merged_at="2026-10-30T00:00:00Z")]
        for line in ("#2, #3", "- #2 and #3", "#2; the sub-domain choice.", "#2 and the operator go for the write",
                     "#2 (merged) then capture R55 on the Mac"):
            issues = [issue(2, "closed"), issue(3), issue(50, labels=["type: bug", "status: blocked"], body="### Blocked by\n\n" + line)]
            actions, _ = self.run_sweep(issues, pulls)
            self.assertEqual(actions, [], line)
        for line in ("#2", "#2 (LOT-002)", "- #2, #3", "#2 and #3"):  # refs, separators and a parenthesised note only
            issues = [issue(2, "closed"), issue(3, "closed"), issue(50, labels=["type: bug", "status: blocked"], body="### Blocked by\n\n" + line)]
            actions, _ = self.run_sweep(issues, pulls)
            self.assertEqual([a["issue"] for a in actions], [50], line)

    def test_a_lot_with_an_all_closed_section_stays_blocked_while_its_plan_holds_it(self):
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        sec = "### Blocked by\n\n#1\n"
        cases = {
            "open plan dependency": (lots_of(md_row("001", 1), md_row("009", 9), md_row("002", 2, deps="001, 009")), [issue(9)]),
            "open capture": (self.lots, [issue(60, labels=["host: mac"], body="### Wanted by\n\n#2\n")]),
            "gate sentence": (lots_of(md_row("001", 1), md_row("002", 2, deps="all parsing lots")), []),
            "unknown lot": (lots_of(md_row("001", 1), md_row("002", 2, deps="001, 999")), []),
        }
        for why, (lots, extra) in cases.items():
            issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body=sec)] + extra
            actions, _ = hygiene.analyze(issues, pulls, lots, {}, NOW)
            self.assertEqual([a for a in actions if a["kind"] == "unblock"], [], why)
        issues = [issue(1, "closed"), issue(2, labels=["status: blocked"], body=sec)]
        actions, _ = self.run_sweep(issues, pulls + [pr(11, body="Closes #2", merged_at="2026-10-31T00:00:00Z")])
        self.assertEqual([a["kind"] for a in actions], ["close"])  # pending close: closed, not unblocked

    def test_a_closed_unmerged_pr_on_another_base_is_reported(self):
        stub = {**issue(12, "closed"), "pull_request": {"merged_at": None}}
        issues = [stub, issue(50, labels=["type: bug", "status: blocked"], body="### Blocked by\n\n#12\n")]
        actions, reports = self.run_sweep(issues, [])
        self.assertEqual(actions, [])
        self.assertTrue(any("#50" in r and "#12" in r and "unmerged" in r for r in reports), reports)

    def test_a_lone_carriage_return_ends_the_section_like_the_harness(self):
        self.assertEqual(hygiene.blockers_of("### Blocked by\n#1\r### X\n#2"), ["#1"])

    def test_apply_takes_ready_back_when_blocked_cannot_be_removed(self):
        calls = []

        def fake(method, path, fields=()):
            calls.append((method, path))
            if method == "DELETE" and path.endswith("status:%20blocked"):
                raise RuntimeError("boom")
        got = subprocess.CompletedProcess([], 0, stdout=json.dumps({"state": "open", "labels": [{"name": "status: blocked"}]}), stderr="")
        out = io.StringIO()
        with mock.patch.object(hygiene.subprocess, "run", return_value=got), mock.patch.object(hygiene, "gh", fake), \
                contextlib.redirect_stdout(out):
            hygiene.apply([{"kind": "unblock", "issue": 2, "lot": "LOT-002", "pr": 10}])
        self.assertEqual(calls[-1], ("DELETE", "repos/ezzz/HFRnow/issues/2/labels/status:%20ready"))  # one status again
        self.assertNotIn(("POST", "repos/ezzz/HFRnow/issues/2/comments"), calls)
        self.assertIn("FAILED", out.getvalue())

    def test_an_on_hold_issue_is_never_moved_by_the_sweep(self):
        pulls = [pr(10, body="Closes #1", merged_at="2026-10-30T00:00:00Z")]
        for lb in (["status: on-hold"], ["status: on-hold", "status: blocked"], ["status: needs-decision", "status: blocked"]):
            issues = [issue(1, "closed"), issue(2, labels=lb, body="### Blocked by\n\n#1\n"),
                      issue(50, labels=["type: bug"] + lb, body="### Blocked by\n\n#1\n")]
            actions, reports = self.run_sweep(issues, pulls)
            self.assertEqual(actions, [], lb)
            if len(lb) > 1:
                self.assertTrue(any("#50: 2 labels on axis `status`" in r for r in reports), reports)

    def test_apply_never_unblocks_an_issue_that_holds_another_status_meanwhile(self):
        cur = {"state": "open", "labels": [{"name": "status: blocked"}, {"name": "status: on-hold"}]}
        calls, out = self._apply(cur, [{"kind": "unblock", "issue": 2, "lot": "LOT-002", "pr": 10}])
        self.assertEqual(calls, [])
        self.assertIn("skip (labels changed meanwhile)", out)

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


class ClassifyBlocked(unittest.TestCase):
    """#835 part 3: one proposed outcome per open `status: blocked` issue, from the tracker only."""
    def run_it(self, issues, comments=None):
        import classify_blocked
        lots = lots_of(md_row("001", 1), md_row("002", 2, deps="001"), md_row("003", 3, deps="001"))
        return {r["issue"]: r for r in classify_blocked.classify(issues, [], lots, comments or {}, {"M3": ["LOT-001", "LOT-002", "LOT-003"]})}

    def test_outcomes_from_the_blockers_found(self):
        rows = self.run_it([issue(1), issue(2, labels=["status: blocked"]), issue(3, labels=["status: blocked"]),
                            issue(50, labels=["status: blocked"], body="### Depends on\n\n- LOT-001 (#1)\n"),
                            issue(51, labels=["status: blocked"], body="nothing named"), issue(52, labels=["status: ready"])])
        self.assertEqual(rows[2]["outcome"], "blocked")
        self.assertEqual(rows[2]["blocked_by"], ["#1"])  # a bare `#n`, the only shape the sweep reads as closable
        self.assertEqual(rows[50]["outcome"], "blocked")
        self.assertEqual(rows[51]["outcome"], "needs-decision")
        self.assertNotIn(52, rows)
        rows = self.run_it([issue(1, "closed"), issue(2, labels=["status: blocked"])])
        self.assertEqual((rows[2]["outcome"], rows[2]["milestone"]), ("ready", "M3"))

    def test_a_dependency_closed_not_planned_is_a_question(self):
        dep = issue(1, "closed")
        dep["state_reason"] = "not_planned"
        rows = self.run_it([dep, issue(2, labels=["status: blocked"])])
        self.assertEqual(rows[2]["outcome"], "needs-decision")
        self.assertIn("#1 (closed not_planned)", rows[2]["question"])

    def test_a_free_text_line_of_the_section_is_never_dropped(self):
        body = "### Blocked by\n\n#1\nThe capture issue must land first.\n"
        rows = self.run_it([issue(1, "closed"), issue(70, labels=["status: blocked"], body=body)])
        self.assertEqual(rows[70]["outcome"], "needs-decision")
        self.assertIn("The capture issue must land first.", rows[70]["question"])
        rows = self.run_it([issue(1), issue(70, labels=["status: blocked"], body=body)])
        self.assertEqual(rows[70]["outcome"], "blocked")
        self.assertEqual(rows[70]["blocked_by"], ["#1", "The capture issue must land first."])  # bare `#n`: what the sweep reads

    @mock.patch.object(m5, "M5_OPEN", False)
    def test_m5_items_are_on_hold_with_the_decision_and_the_plan_says_what_to_write(self):
        import classify_blocked
        rows = self.run_it([issue(1), issue(60, labels=["status: blocked"]) | {"title": "[SwiftHFR] M5: a new idea"}])
        self.assertEqual(rows[60]["outcome"], "on-hold")
        self.assertIn("/issues/379", rows[60]["link"])
        plan = classify_blocked.plan(list(rows.values()))
        self.assertEqual({p["issue"]: p["to"] for p in plan}, {60: "status: on-hold"})
        self.assertIn("M5_OPEN", plan[0]["decision"]["sentence"])
        md = classify_blocked.markdown(list(rows.values()))
        self.assertIn("`on-hold` 1", md)


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

    def test_an_on_hold_lot_counts_in_its_own_bucket_neither_blocked_nor_ready(self):
        r = next(r for l, r in generate.rows.items() if generate.deps(r))
        lot = r["lot"]
        with mock.patch.object(generate, "CAPTURE", {}), mock.patch.object(generate, "CLOSED", set()), \
                mock.patch.object(generate, "CLAIMED", set()), mock.patch.object(generate, "PRS", {}):
            for miss in (["LOT-X"], []):
                with mock.patch.object(generate, "miss0", lambda row, miss=miss: miss):
                    self.assertEqual(progress.bucket(lot, {"status: on-hold"}), "hold")
                    self.assertEqual(progress.bucket(lot, {"status: on-hold", "host: mac", "priority: low"}), "hold")
            self.assertEqual(progress.bucket(lot, {"status: needs-decision"}), "human")
        self.assertIn("hold", progress.BUCKETS)
        for table in (progress.BUCKET_COLORS, progress.BUCKET_NAMES, progress.SHORT_BUCKET):
            self.assertEqual(set(table), set(progress.BUCKETS))

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


class WeeklyCounts(unittest.TestCase):
    def test_gap_total_is_read_from_the_counts_table_only(self):
        text = ("| Gap | Rows |\n|---|---|\n| **Total** | **9** |\n\n## Counts\n\n| Gap | Rows |\n|---|---|\n| same | 39 |\n"
                "| **Total** | **172** |\n\n## Convergence notes\n\n| **Total** | **1** |\n")
        self.assertEqual(counts.gap_total(text), 172)
        with self.assertRaises(ValueError):
            counts.gap_total("## Counts\n\n| same | 3 |\n")
        real = (ROADMAP.parent.parent / "docs" / "migration" / "GAP-LEGACY-VS-SWIFT.md").read_text(encoding="utf-8")
        self.assertGreater(counts.gap_total(real), 0)

    def test_changelog_counts_numbered_rows_not_header_separator_or_prose(self):
        text = "Intro | with a pipe\n\n| # | Section | Résumé |\n|---|---|---|\n| 1 | T | a |\n| 2 | UX | b |\n| 31 | T | c |\n|x| y |\n"
        self.assertEqual(counts.changelog_rows(text), 3)
        self.assertEqual(counts.changelog_rows(""), 0)

    def test_ci_count_at_the_api_cap_is_written_with_a_plus(self):
        self.assertEqual(counts.fmt_ci(216), "216")
        self.assertEqual(counts.fmt_ci(2499), "2\u202f499")
        self.assertEqual(counts.fmt_ci(2500), "2\u202f500+")
        self.assertEqual(counts.fmt_ci(10, cap=10), "10+")

    def test_state_older_than_six_hours_is_refused(self):
        now = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
        self.assertLess(counts.state_age_hours("2026-11-10 07:00 UTC", now), counts.STATE_MAX_AGE_H)
        self.assertGreater(counts.state_age_hours("2026-11-02 10:05 UTC", now), counts.STATE_MAX_AGE_H)
        self.assertEqual(counts.state_age_hours("", now), float("inf"))

    def test_daily_groups_never_count_the_credit_label_as_feedback(self):
        iss = [issue(1, labels=["beta-test finding"]), issue(2, "closed", labels=["beta-test finding"]),
               issue(3, labels=["moust4ki aka bybifok finding"]), {**issue(4), "title": "[Legacy 4.0.x] fix"},
               issue(5, labels=["origin: legacy-evolution"])]
        g = counts.daily_groups(iss)
        self.assertEqual([i["number"] for i in g["feedback"]], [1, 2])
        self.assertEqual(counts.open_closed(g["feedback"]), (1, 1))
        self.assertEqual([i["number"] for i in g["current"]], [4])
        self.assertEqual([i["number"] for i in g["backport"]], [5])

    def test_titles_on_slides_never_say_legacy(self):
        t = counts.clean_title("[SwiftHFR] Poll: results with a confirmation, as legacy 4.0.x (M4)")
        self.assertEqual(t, "Poll: results with a confirmation")
        self.assertEqual(counts.clean_title("[SwiftHFR] Legacy reference is behind"), "App courante reference is behind")
        self.assertNotIn("legacy", counts.clean_title("[SwiftHFR] MP badge where legacy (correct) shows 6").lower())
        self.assertEqual(counts.clean_title("[SwiftHFR] iPad split (bug report)"), "iPad split")

    def test_marketing_version(self):
        self.assertEqual(counts.marketing_version("MARKETING_VERSION = 5.0;\n MARKETING_VERSION = 5.0;"), "5.0")
        self.assertEqual(counts.marketing_version(""), "?")

    def test_build_refuses_a_stale_saved_state(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "state.json"
            f.write_text(json.dumps({"generated_at": "2026-11-02 10:05 UTC"}))
            r = subprocess.run([sys.executable, str(ROADMAP / "weekly" / "build.py"), d, "--state", str(f)], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("6 h", r.stderr)

    def test_dropped_lots_are_the_not_planned_and_duplicate_closures(self):
        iss = [issue(1, "closed"), {**issue(2, "closed"), "state_reason": "not_planned"}, {**issue(3, "closed"), "state_reason": "duplicate"},
               {**issue(4, "closed"), "state_reason": "completed"}, issue(5)]
        self.assertEqual(counts.dropped_issues(iss), {2, 3})

    def test_dropped_lots_leave_the_planned_count_and_every_milestone(self):
        rows = {"LOT-001": {"issue": 1}, "LOT-002": {"issue": 2}, "LOT-003": {"issue": 3}}
        self.assertEqual(counts.live_lots(rows, rows, {2}), {"LOT-001", "LOT-003"})
        self.assertEqual(counts.live_lots({"LOT-002"}, rows, {2}), set())
        self.assertEqual(len(counts.live_lots(rows, rows, set())), 3)

    def with_dropped(self, *lots):
        """build with the real lots, nothing done, and these lots' issues dropped (issue 784: every slide must agree)."""
        import build
        stack = contextlib.ExitStack()
        stack.enter_context(mock.patch.object(build, "G", generate))
        stack.enter_context(mock.patch.object(generate, "done", return_value=False))
        stack.enter_context(mock.patch.object(build, "DROPPED", {generate.rows[l]["issue"] for l in lots}))
        self.addCleanup(stack.close)
        return build

    def test_ms_lots_filters_the_dropped_lots(self):
        build = self.with_dropped("LOT-110")
        self.assertNotIn("LOT-110", build.ms_lots()["M5"])
        self.assertEqual(len(build.ms_lots()["M5"]), len(generate.M5) - 1)

    def test_card_pill_counts_live_lots_only(self):
        build = self.with_dropped("LOT-110")
        self.assertIn(f"À faire · {len(build.FEATURES['M5'][0][3]) - 1} lots", build.card_pill(build.FEATURES["M5"][0][3]))

    def test_left_card_lists_and_counts_live_lots_only(self):
        build = self.with_dropped("LOT-110")
        out = build.left_card("M5", {"titles": {}})
        self.assertIn(f"Reste à faire · {len(generate.M5) - 1}<", out)
        self.assertNotIn("<u>110</u>", out)

    def test_m5_slide_lists_no_dropped_lot_in_a_feature_card(self):
        build = self.with_dropped()
        label = build.lot_label("LOT-110")
        self.assertIn(f"<li>{build.esc(label)}</li>", build.m5_cards())
        build = self.with_dropped("LOT-110")
        self.assertNotIn(f"<li>{build.esc(label)}</li>", build.m5_cards())

    def test_m5_feature_cards_keep_the_authored_lot_order_and_skip_an_emptied_feature(self):
        build = self.with_dropped()
        out = build.m5_cards()
        nav = [f"<li>{build.esc(build.lot_label(f'LOT-{x:03d}'))}</li>" for x in build.FEATURES["M5"][0][3]]
        self.assertEqual([out.index(i) for i in nav], sorted(out.index(i) for i in nav))
        title = build.FEATURES["M5"][3][1]
        self.assertIn(f"<b>{title}</b>", out)
        build = self.with_dropped(*(f"LOT-{x:03d}" for x in build.FEATURES["M5"][3][3]))
        self.assertNotIn(f"<b>{title}</b>", build.m5_cards())

    def test_m5_slide_drops_the_empty_also_card_and_counts_the_rest(self):
        build = self.with_dropped("LOT-176")
        self.assertIn("Aussi dans M5 · 1<", build.m5_cards())
        self.assertNotIn("<u>176</u>", build.m5_cards())
        build = self.with_dropped("LOT-176", "LOT-183")
        self.assertNotIn("Aussi dans M5", build.m5_cards())

    def test_a_dropped_lot_does_not_count_in_unblocks(self):
        build = self.with_dropped()
        pair = next((d, y) for y, r in generate.rows.items() for d in generate.deps(r))
        before = build.dependents()[pair[0]]
        build = self.with_dropped(pair[1])
        self.assertEqual(build.dependents()[pair[0]], before - 1)

    def test_generate_reads_the_state_named_by_roadmap_state(self):
        import tempfile
        lot = next(iter(sorted(generate.rows)))
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "state.json"
            f.write_text(json.dumps({"closed": [generate.rows[lot]["issue"]], "ready": [], "claimed": [], "external": [], "prs": {},
                                     "merged_pr": {}, "capture": {}, "generated_at": "2026-11-10 22:00 UTC"}))
            code = f"import generate as G; print(G.GENERATED_AT, G.done({lot!r}), len(G.CLOSED))"
            r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, cwd=ROADMAP,
                               env={**__import__("os").environ, "ROADMAP_STATE": str(f)})
            self.assertEqual(r.stdout.split(), ["2026-11-10", "22:00", "UTC", "True", "1"], r.stderr)

    def test_a_slide_never_shows_the_word_legacy(self):
        import build
        h = build.page(1, "Legacy et legacy", "le legacy", "<p>LEGACY</p>")
        self.assertNotIn("legacy", re.sub(r"<style>.*?</style>", "", h, flags=re.S).lower())


if __name__ == "__main__":
    unittest.main()
