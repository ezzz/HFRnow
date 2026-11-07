## Issue
<!-- Closes #N (Refs #N for partial work: say what is left), then on its own line Claim: <session-id> (AGENTS.md §8).
     A lot also names it (LOT-XXX). Small fix without an issue: Direct-PR: <reason>. Dependabot: not needed. -->
Closes #
Claim:
LOT-

## What and why

## How it was verified
<!-- Tests added, fixtures used, differential results, device checks -->

## Checklist (AGENTS.md §9)
- [ ] Module boundaries respected (no sibling imports in HFRKit, no UI framework in HFRKit)
- [ ] Tests added/updated — differential tests for ported logic
- [ ] No secrets; fixtures anonymized
- [ ] Docs updated (lot spec, HFR-PROTOCOL.md §6c, ADR); if the PR says `Closes #N`, after the merge that issue is closed by hand with `Done in #PR (merged as <sha>)` and checked closed (ORCHESTRATION)
- [ ] Author model: … / Reviewer model: … (must differ)
- [ ] Fixes or changes a legacy-app behaviour, adds or changes a gap row? A `### Ledger` section in this body (see `tooling/docs/README.md`) and the label `ledger`. The PR never touches `docs/CHANGELOG-LEGACY.md`, `docs/migration/GAP-LEGACY-VS-SWIFT.md`, `docs/changelog-legacy.d/` or `docs/migration/gap.d/` (the steward folds the entries after the merge).
