# LOT-183 — AQ first-use notice (M5)

- **Module:** App
- **Difficulty / model:** easy (Opus → Fable)
- **Issue:** [#423](https://github.com/ezzz/HFRnow/issues/423) · **Milestone:** M5 (UX evolutions)
- **Split from:** LOT-134 (#224), the (b) half; the (a) half keeps the legacy behaviour.

Stub created on 2026-11-02 with the operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): the evolutions of M1–M4 go to M5, never dropped. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None: this is an evolution, not a port. The legacy behaviour is cited in LOT-134 (AQ check).

## Legacy counterpart (app lots)
None @ 2440d79 (new UX). The code says so in its `// Port of …` header: "none @ 2440d79" (AGENTS.md §4).

## UX evolutions (app lots)
- none (no UXD row), GAP none in `docs/migration/GAP-LEGACY-VS-SWIFT.md`: class `b`, optional, never the default: a setting or a separate entry keeps the legacy UX by default ([UX principles](../FEATURES.md#ux-principles-operator)).

## Behaviour
To write: inputs, outputs and rules, on top of the merged LOT-134. Every HFR fact also goes to `docs/HFR-PROTOCOL.md`.

## Edge cases
To write.

## Fixtures
To write (never hand-built in the cloud, LESSONS 36).

## Intentional differences from legacy
The whole lot is one: it is the evolution. Record what the legacy does and what changes.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
