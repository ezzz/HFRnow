# LOT-179 — Cache sizes and clearing (M5)

- **Module:** App
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#419](https://github.com/ezzz/HFRnow/issues/419) · **Milestone:** M5 (UX evolutions)
- **Split from:** LOT-120 (#211), the (b) half; the (a) half keeps the legacy behaviour.

Stub created on 2026-11-02 with the operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): the evolutions of M1–M4 go to M5, never dropped. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None: this is an evolution, not a port. The legacy behaviour is cited in LOT-120 (maintenance and about).

**Legacy at `2fe43da3`** (catch-up of #655): the sizes are legacy now. Réglages > Maintenance shows "Caches de l'app" (total) and "Pages HTML" (size and file count) with a footer on the 7-day / 50 MB rule (`HFRswift/Swift/AppSettingsView.swift:547-575` @ `2fe43da3`, `c7693a88`); clearing is still not reachable (the "Vider le cache ?" alert at `:637` is never presented: `showClearCacheConfirmation` is never set). So the sizes half of this lot is parity at the reference; whether it moves to M4 is the operator's call (#655), clearing stays an evolution.

## Legacy counterpart (app lots)
None @ 2440d79 (new UX). The code says so in its `// Port of …` header: "none @ 2440d79" (AGENTS.md §4).

## UX evolutions (app lots)
- none (no UXD row), GAP 152 in `docs/migration/GAP-LEGACY-VS-SWIFT.md`: class `b`, optional, never the default: a setting or a separate entry keeps the legacy UX by default ([UX principles](../FEATURES.md#ux-principles-operator)).

## Behaviour
To write: inputs, outputs and rules, on top of the merged LOT-120. Every HFR fact also goes to `docs/HFR-PROTOCOL.md`.

## Edge cases
To write.

## Fixtures
To write (never hand-built in the cloud, LESSONS 36).

## Intentional differences from legacy
The whole lot is one: it is the evolution. Record what the legacy does and what changes.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
