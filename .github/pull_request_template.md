## Issue and claim
<!-- Required, checked by CI ("Issue and claim", AGENTS.md §8). One issue per PR, claimed BEFORE coding with a `/claim <session-id>` comment on it.
     Use `Refs #N` instead of `Closes #N` for partial work. The Claim line must be on its own line and equal the issue's active claim.
     Break-glass (small fixes, foundations, contributors not using issues): replace both lines by `Direct-PR: <reason>`. -->
Closes #
Claim: 

## What and why
<!-- LOT-XXX if it is a lot. -->

## How it was verified
<!-- Tests added, fixtures used, differential results, device checks -->

## Checklist (AGENTS.md §9)
- [ ] Module boundaries respected (no sibling imports in HFRKit, no UI framework in HFRKit)
- [ ] Tests added/updated — differential tests for ported logic
- [ ] No secrets; fixtures anonymized
- [ ] Docs updated (lot spec, HFR-PROTOCOL.md §6c, ADR; after opening, the lot's own row in LOTS.md set to `done (#<this PR>)`)
- [ ] Author model: … / Reviewer model: … (must differ)
