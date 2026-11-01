# Roadmap tooling (boards #166 and #324, weekly visual)

Imported as-is from the steward session `ext/opus-helper1` (handover of 2026-11-01), so that any session can re-render
the milestone boards without an LLM re-deriving them ([#368](https://github.com/ezzz/HFRnow/issues/368), D.7).

| File | Role |
|---|---|
| `lots.json` | The lots of [LOTS.md](../../docs/LOTS.md) as data (scope, module, deps, routing, issue) |
| `state.py` | **Snapshot** of the tracker state (closed, ready, external issues, PRs). Stale by design: to be replaced by a sync from the GitHub API |
| `generate.py` | Milestone membership (M1–M4) and the state of each lot; writes `milestones.json` |
| `render.py` | Renders the board comments for #166 and #324 |
| `unblocked.py` | After a merge: the lots whose dependencies are now all done |
| `weekly/progress.html`, `weekly/shot.js` | The weekly 16:9 visual (Playwright screenshot at 1.5×, 2880×1620 JPEG) |

Owner: `cloud/docs-steward` (see #368), which turns `state.py` into a GitHub sync, derives `lots.json` from `LOTS.md`
and adds tests.
