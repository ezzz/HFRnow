# Roadmap tooling (boards #166 and #324, weekly visual)

Imported as-is from the steward session `ext/opus-helper1` (handover of 2026-11-01), so that any session can re-render
the milestone boards without an LLM re-deriving them ([#368](https://github.com/ezzz/HFRnow/issues/368), D.7).

| File | Role |
|---|---|
| `lots_from_md.py` | Derives `lots.json` from [LOTS.md](../../docs/LOTS.md) (the plan): `python3 tooling/roadmap/lots_from_md.py` |
| `lots.json` | Generated: the lots as data (scope, module, deps, routing, issue). Never edited by hand |
| `sync_state.py` | Builds `state.json` from the tracker (`--fetch` uses `gh api`, or give it the saved JSON of `list_issues` and `list_pull_requests`) |
| `state.json` | Generated: closed, ready, claimed, external issues, open and merged lot PRs, capture blockers |
| `generate.py` | Milestone membership (M1–M4) and the state of each lot; writes `milestones.json` |
| `render.py` | Renders the board comments for #166 and #324 |
| `unblocked.py` | After a merge: the lots whose dependencies are now all done |
| `hygiene.py` | Tracker sweep, dry-run by default (`--apply` does the routine part): unblocks (`status: blocked` only), missing "Done in" closures, reports |
| `weekly/build.py`, `weekly/shot.js` | The weekly 5-slide deck: `build.py OUTDIR` writes HTML from git and the tracker, `shot.js OUTDIR` renders 2880×1620 JPEGs with Playwright. Delivered to the maintainer, never posted |

Tests: `scripts/tests/test_roadmap.py` (run by CI with the other `scripts/tests`).

## Routine

```bash
python3 tooling/roadmap/lots_from_md.py        # only when LOTS.md changed
python3 tooling/roadmap/sync_state.py --fetch  # refresh state.json from the tracker
python3 tooling/roadmap/generate.py && python3 tooling/roadmap/render.py   # boards for #166 and #324
python3 tooling/roadmap/hygiene.py             # daily sweep (add --apply for the routine part)
```

M1/M2 membership is the only hand-kept data (`generate.py`); M3 is Phase 3 minus M1, M4 the rest.

Owner: `cloud/docs-steward` (see #368).
