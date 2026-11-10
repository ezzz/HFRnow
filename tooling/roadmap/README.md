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
| `hygiene.py` | Tracker sweep, dry-run by default (`--apply` does the routine part): unblocks (`status: blocked` only), missing "Done in" closures, `status:*` labels left on closed issues (removed, counted), reports (including the blocked lots gated only by an open capture, every lot dependency done) |
| `../docs/fold.py` | Folds the fragments of `docs/changelog-legacy.d/` and `docs/migration/gap.d/` into `docs/CHANGELOG-LEGACY.md` and the GAP report, regenerates the H.1 lists and the Counts table (`--check` is the Docs consistency step, `--dry-run` writes nothing). Tests: `scripts/tests/test_docs_fold.py` ([#612](https://github.com/ezzz/HFRnow/issues/612)) |
| `weekly/build.py`, `weekly/shot.js` | The weekly deck data (`gather()`) and the earlier 6-slide fallback ([format](#weekly-report-format-operator-2026-11-10)): `build.py OUTDIR` writes HTML from git and the tracker, `shot.js OUTDIR` renders 2880×1620 JPEGs with Playwright. Delivered to the maintainer, never posted |

Tests: `scripts/tests/test_roadmap.py` (run by CI with the other `scripts/tests`).

## Where to run, what it reads

All paths resolve from the script's own directory, so any working directory works; the commands below are written from the repository root.
Inputs: `docs/LOTS.md` (plan), the tracker through `gh` with `GH_TOKEN` (or the saved JSON of `list_issues` and
`list_pull_requests`), and for the deck the full git history (`git fetch --unshallow` in a shallow clone). Python 3 standard library only;
`weekly/shot.js` needs Playwright (pre-installed in cloud sessions). `render.py` takes the snapshot date from `state.json`.

## Routine

```bash
python3 tooling/roadmap/lots_from_md.py        # only when LOTS.md changed
python3 tooling/roadmap/sync_state.py --fetch  # refresh state.json from the tracker
python3 tooling/roadmap/generate.py && python3 tooling/roadmap/render.py 324 OUTDIR   # boards for #166 and #324 (OUTDIR defaults to tooling/roadmap/out, git-ignored)
python3 tooling/roadmap/hygiene.py             # daily sweep (add --apply for the routine part)
python3 tooling/docs/fold.py                   # daily: fold the GAP and changelog fragments, then open one docs-only PR (merged on green CI, no adversarial review; hygiene.py reports and, with --apply, runs it)
```

M1/M2 membership is hand-kept in `generate.py`, and the whole lots moved to M5 in `m5.py`; the (b) halves of the splits are the lots of the `## M5 · UX evolutions` section of `docs/LOTS.md`. M3 is Phase 3 minus M1, M4 the rest (M4 = validated legacy parity, M5 = evolutions, operator 2026-11-02). The sweep never unblocks an M5 lot: M5 opens by the orchestrator's decision.

## Weekly report: format (operator, 2026-11-10)

The weekly report is a morning deck, ready when the maintainer wakes up. Since 2026-11-10 it is a claude.ai Slides artifact built by the orchestrator from the data of `weekly/build.py` (`gather()`), the tracker and the counts below. It is refreshed shortly before the morning and delivered as a private link, never posted. The six JPEG slides of `build.py` remain a fallback.

**Order of the slides**
1. **Overall**:
   - the three fronts, each with its count: test feedback (`beta-test finding`), fixing the current app (the `[Legacy …]` issues and the PRs on `master`), and the backport into Swift (`origin: legacy-evolution`);
   - a quick mention of the gaps (rows of the GAP report's Counts table) and of the changelog entries (`docs/CHANGELOG-LEGACY.md`).

   On every slide, the legacy app is called **the current app**, never "legacy".
2. **KPIs**: lots done over planned, duration (days since 2026-10-24), CI runs, failures and cancellations over 7 days, version (`MARKETING_VERSION`), issues (total and open, opened and closed that day), commits, merged PRs (total, 7 days, that day), Swift tests and lines.
3. **Milestones M1 to M5**: one progress bar each, with done/total and the end date.
4. **M1, M2, M3 and M4**: one feature-card slide each, explaining what the milestone contains, with its status pill.
5. **The app day to day**: test feedback, the current app, and the backport.
6. **M5**: the big features, as one feature-card slide.
7. **Today**: the decisions awaited from the operator, the Mac work, and what runs in the cloud.

**Design language**
- Apple release feature cards: a light grouped background (`#F2F2F7`) and rounded cards (radius 36-48).
- On each slide, one large gradient hero card next to small white cards, each with an icon and a short label.
- Big numbers in Inter Tight 800, body text in Inter.
- A touch of "Apple" and "iOS 26/27" (Liquid Glass, iOS 27 wording); keep the same look from week to week.
- French text, statuses stated in words as well as colour.

**Counting rules**
- Count only what a query names, and put the query in the speaker notes.
- A credit label such as `moust4ki aka bybifok finding` marks lots and issues credited to a contributor, mostly planned on 2026-10-27. It is not test feedback, so never add it to the feedback count.

Owner: `cloud/docs-steward` (see #368).
