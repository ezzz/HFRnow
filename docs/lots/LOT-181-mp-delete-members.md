# LOT-181 — MP group members (M5)

- **Module:** App
- **Difficulty / model:** easy (Opus → Fable)
- **Issue:** [#421](https://github.com/ezzz/HFRnow/issues/421) · **Milestone:** M5 (UX evolutions)
- **Split from:** LOT-127 (#218), the (b) half; the (a) half keeps the legacy behaviour.
- **Scope change (operator, 2026-11-09, [#676](https://github.com/ezzz/HFRnow/issues/676)):** thread deletion left this lot. Legacy has it at `2fe43da3` (`4a4f493f`: "Supprimer" in the MP list row menu, confirmation, POST `modo/manageaction.php` with `action_reaction=valid_eff_prive`, `HFRswift/Swift/MPListView.swift:114-158, 711-722, 815-822` @ `2fe43da3`), so it is parity (a), done in M4 under #676 with LOT-094's flow. This lot keeps the group members only (GAP-118). The issue title and the file name still say "deletion" until the orchestrator renames them.

Stub created on 2026-11-02 with the operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): the evolutions of M1–M4 go to M5, never dropped. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None: this is an evolution, not a port. The legacy behaviour is cited in LOT-127 (MP actions).

## Legacy counterpart (app lots)
None @ 2440d79 nor @ 2fe43da3 for group members (new UX). The code says so in its `// Port of …` header: "none @ 2440d79" (AGENTS.md §4).

## UX evolutions (app lots)
- **UXD-20**, GAP 118 in `docs/migration/GAP-LEGACY-VS-SWIFT.md`: class `b`, optional, never the default: a setting or a separate entry keeps the legacy UX by default ([UX principles](../FEATURES.md#ux-principles-operator)).

## Behaviour
To write: inputs, outputs and rules, on top of the merged LOT-127. Every HFR fact also goes to `docs/HFR-PROTOCOL.md`.

## Edge cases
To write.

## Fixtures
To write (never hand-built in the cloud, LESSONS 36).

## Intentional differences from legacy
The whole lot is one: it is the evolution. Record what the legacy does and what changes.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
