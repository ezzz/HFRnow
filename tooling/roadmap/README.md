# Roadmap tooling (boards #166 and #324, weekly visual)

Imported as-is from the steward session `ext/opus-helper1` (handover of 2026-11-01), so that any session can re-render
the milestone boards without an LLM re-deriving them ([#368](https://github.com/ezzz/HFRnow/issues/368), D.7).

| File | Role |
|---|---|
| `lots_from_md.py` | Derives `lots.json` from [LOTS.md](../../docs/LOTS.md) (the plan): `python3 tooling/roadmap/lots_from_md.py` |
| `lots.json` | Generated: the lots as data (scope, module, deps, routing, issue). Never edited by hand |
| `sync_state.py` | Builds `state.json` from the tracker (`--fetch` uses `gh api`, or give it the saved JSON of `list_issues` and `list_pull_requests`) |
| `state.json` | Generated: closed, ready, claimed, external, on-hold and needs-decision issues, open and merged lot PRs, capture blockers |
| `generate.py` | Milestone membership (M1–M4) and the state of each lot; writes `milestones.json` |
| `render.py` | Renders the board comments for #166 and #324 |
| `unblocked.py` | After a merge: the lots whose dependencies are now all done (an M5 lot while M5 is closed and a `status: on-hold` lot are skipped) |
| `hygiene.py` | Tracker sweep, dry-run by default (`--apply` does the routine part): unblocks (an issue whose single status is `status: blocked` and whose every `### Blocked by` line holds only `#n` (separators and a short id note such as `(LOT-057)` allowed), all closed; a line with other text keeps it blocked; never `status: on-hold`), `status: claimed` (and the other `status:` labels dropped) on an open issue cited by `Closes`/`Refs` of an open PR (#826; `type: roadmap` trackers, held M5 lots and `status: on-hold`/`needs-decision` issues excepted: reported only), missing "Done in" closures, `status:*` labels left on closed issues (removed, counted), reports (claims with no open PR and no comment for 72 h are listed, never released; including the blocked lots gated only by an open capture, every lot dependency done; the `status: blocked` issues without a `### Blocked by` section; the M5 lots to relabel `status: on-hold`) |
| `classify_blocked.py` | Dry run of #835 part 3: one outcome per open `status: blocked` issue (`on-hold`, `blocked` with its `### Blocked by` lines, `ready`, `needs-decision`), as a Markdown table and a JSON plan; reads the tracker, writes nothing to it |
| `../docs/fold.py` | Folds the fragments of `docs/changelog-legacy.d/` and `docs/migration/gap.d/` into `docs/CHANGELOG-LEGACY.md` and the GAP report, regenerates the H.1 lists and the Counts table (`--check` is the Docs consistency step, `--dry-run` writes nothing). Tests: `scripts/tests/test_docs_fold.py` ([#612](https://github.com/ezzz/HFRnow/issues/612)) |
| `weekly/build.py`, `weekly/progress.py`, `weekly/counts.py`, `weekly/shot.js` | The 6-slide report deck (French, #892), below: `build.py OUTDIR` fetches the tracker and writes HTML, `shot.js OUTDIR` renders 2880×1620 JPEGs with Playwright and checks them. Delivered to the maintainer, never posted |

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

M1/M2 membership is hand-kept in `generate.py`, and the whole lots moved to M5 in `m5.py`; the (b) halves of the splits are the lots of the `## M5 · UX evolutions` section of `docs/LOTS.md`. M3 is Phase 3 minus M1, M4 the rest (M4 = validated legacy parity, M5 = evolutions, operator 2026-11-02). The sweep never unblocks an M5 lot: M5 opens by the orchestrator's decision (`m5.M5_OPEN`), so while it is closed every M5 lot is `status: on-hold` and the sweep reports one that is not (#835).

Owner: `cloud/docs-steward` (see #368).

## Weekly deck

```bash
python3 tooling/roadmap/weekly/build.py OUTDIR --since <date 7 days ago>   # fetches the tracker (gh), writes OUTDIR/slides/*.html
node tooling/roadmap/weekly/shot.js OUTDIR                                  # OUTDIR/swifthfr-semaine-NN.jpg; exits 1 on a failed check
```

`build.py` fetches the issues and PRs first and writes the state to `OUTDIR/state.json` (`generate.py` reads it through
`ROADMAP_STATE`): the committed `state.json` is a stale snapshot and is never used nor rewritten by the deck. `--state FILE`
reuses a saved state, refused when its `generated_at` is older than 6 h. Never commit a regenerated `state.json` or
`milestones.json` from a deck run.

The routine runs it on Monday and Thursday at 05:30 Europe/Paris (#892). Slides, in order:

1. **Où en est SwiftHFR**: KPI strip (lots planned and done, merged PRs, commits, tests, issues), commits per day, three cards
   (feedback de test, fixing de l'app courante, backport dans Swift: open and closed), the gap count and the changelog entries.
2. **Indicateurs**: version, days since 2026-10-24, merged PRs over 7 days and 24 h, CI runs over 7 days with failures and
   cancellations; cumulative commits, merged PRs per day by step, one donut per step.
3. **Aujourd'hui**: difference with the `--since` date; the M1 to M5 bars against it, plus a **Hors jalon** bar (SwiftHFR
   issues outside every milestone: done / total and the issues done since); the organisation of the work (`ORCH`).
4. **M1 · M2 · M3**: one pile of tiles per milestone, a head tile (done / total, closing date) and one tile per main
   feature (`FEATURES`) with its lot count computed from its lots. The title says « terminés » only when all three are.
5. **M4 en détail**: the M4 lots (done, in progress, to do) and the M4 issues outside lots; the M4 lots closed since the
   `--since` date; the test feedback (every `beta-test finding` issue, as on slide 1) by status (`counts.issue_status`: ouvert, réclamé, fait,
   écarté) and the ones added since; a radar of where it concentrates (all and open); bottom right, one tile per end-of-M4
   review (`REVIEWS`: #774, #775, #836, #326, #866) with its goal and the issues labelled with its `m4-review:` label.
6. **M5 en détail**: the M5 lots and issues as tiles by category (the radar axes; past six categories the smallest share
   the last tile, none is dropped; a `FEAT-0xx` intake issue is left out, its lot stands for it), a category radar, and a bottom band
   listing the open SwiftHFR issues outside every milestone, by kind, hidden when there is none.

Tiles are solid blue → violet gradients stacked like mah-jong tiles (`.tile`, `.pile`): a visible edge drawn by offset
shadows, a slight overlap; the layout takes its feel from a keynote overview grid (large rounded tiles, one idea each, a
bold title), with no third-party artwork, icon or trademark. `shot.js` fails a tile whose text lies under another tile.

Milestone of an issue (`counts.issue_milestone`, first rule that applies): a lot issue takes its lot's milestone, a
follow-up of `m5.FOLLOWUPS` its own, an end-of-M4 review tracker (`counts.REVIEW_ISSUES`) M4, a `FEAT-0xx` intake issue M5
(FEAT-016 M4, as `docs/ROADMAP.md` says), then a tag in the title (`M4: …`, `(M4)`, `(UXD-03, M2)`), then a lot named in the
title (`LOT-097 renderer: …`), then the labels (`beta-test finding` and `m4-review: …` are M4, `experimental` is M5).
« SwiftHFR issues » (`counts.is_swift_issue`) leave out `[Legacy …]` titles without SwiftHFR, `type: roadmap` trackers and
issues closed as not planned or duplicate. Radar axes (`counts.AXES`, `counts.axis_of`): lecteur, listes, composer, MP,
navigation, réglages et thèmes, performance, autre; performance is read first, then the axis whose pattern matches
earliest in the title (so the subject before the first « : » decides when it names one). Both have tests in
`scripts/tests/test_roadmap.py` (`ReportDeck892`).

Format rules (operator, 2026-11-10):
- Keep the style: white background, Inter, blue → violet gradient accents, KPI strip, bar, line, donut and radar charts,
  footer. Rounded cards (24 px) with a very light shadow or a light grey background, one inline SVG icon per card, and the
  mah-jong tiles of slides 4 to 6.
- French; the legacy app is « l'app courante » on every slide, never « legacy » (`shot.js` fails a slide that shows the word,
  `counts.clean_title` rewrites tracker titles). No member pseudo; nothing names or ranks a person.
- No text under 20 px at the 1920 base, no overflow, no overlapping blocks: `shot.js` checks all three.
- Counts: « feedback de test » = issues labelled `beta-test finding` (never the credit label `moust4ki aka bybifok finding`,
  which credits planned lots); « l'app courante » = issues whose title starts with `[Legacy`, plus open PRs with base
  `master`; « backport » = issues labelled `origin: legacy-evolution`. The gap count is the Total row of the `## Counts`
  table of `docs/migration/GAP-LEGACY-VS-SWIFT.md`, the changelog count the numbered rows of `docs/CHANGELOG-LEGACY.md`.
  The Actions API caps `total_count` of `actions/runs` at 2 500: a capped count shows « 2 500+ ».

