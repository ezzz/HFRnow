# LOT-174 — Composer formatting toolbar (M4)

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#414](https://github.com/ezzz/HFRnow/issues/414) · **Milestone:** M4 (moved from M5 by the operator, 2026-11-07, after the beta-test finding [#592](https://github.com/ezzz/HFRnow/issues/592))
- **Split from:** LOT-085 (#177), the (b) half; the (a) half keeps the legacy behaviour.

Stub created on 2026-11-02 with the operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): the evolutions of M1–M4 go to M5, never dropped. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None: this is an evolution, not a port. The legacy behaviour is cited in LOT-085 (composer insertion engine).

## Legacy counterpart (app lots)
None @ 2440d79 (new UX). The code says so in its `// Port of …` header: "none @ 2440d79" (AGENTS.md §4).

## UX evolutions (app lots)
- **UXD-18**, GAP 084, 085, 086 in `docs/migration/GAP-LEGACY-VS-SWIFT.md`: class `b`, optional, never the default: a setting or a separate entry keeps the legacy UX by default ([UX principles](../FEATURES.md#ux-principles-operator)).

## Behaviour
Delivered by #598 (the first slice; the rest of the lot is still to write), on top of the merged LOT-085:
- **Size** (`ComposerBarMetrics`): a cell is 48 pt in regular density and 40 pt in compact, times the text scale; the colour swatch is half a cell, the symbol 0.4 of it.
- **`[url]`**: with a selection, today's path (clipboard link → `[url=<clip>]sel[/url]`). With nothing selected and a clipboard text, the alert offers both legacy forms (`HFRTextView.m:205-262`, `:327-350` @ 2440d79): `[url=<clip>][/url]` with the caret between the tags, or `[url]<clip>[/url]`; "Sans le presse-papiers" writes the empty `[url][/url]`.
- **Icons**: the top upload button is `photo.badge.plus`; the bottom `[img]` tag keeps `photo`.

## Edge cases
- The `[url=…]` form is typed, not validated: the clipboard text goes in as is (as legacy). The clipboard is offered once per change count.

## Fixtures
To write (never hand-built in the cloud, LESSONS 36).

## Intentional differences from legacy
The whole lot is one: it is the evolution. Record what the legacy does and what changes.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
