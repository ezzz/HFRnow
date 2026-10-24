# Migration lots

Single tracking table for the engine migration. Rules: [AGENTS.md §5](../AGENTS.md#5-the-migration-loop-one-lot).
Claim a lot by setting yourself as owner and status `in-progress` in your first commit.

Statuses: `todo` · `in-progress` · `review` · `done` · `blocked`

| Lot | Scope | Module | Difficulty | Model (author → reviewer) | Owner | Status | Spec |
|---|---|---|---|---|---|---|---|
| LOT-000 | Phase 1 audit: map legacy engine into lots | docs | difficult | Opus → Fable | — | todo | — |

The table is filled by LOT-000. One spec per lot in [`lots/`](lots/), named `LOT-XXX-short-name.md` (template: [`lots/TEMPLATE.md`](lots/TEMPLATE.md)).
