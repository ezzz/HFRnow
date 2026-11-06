# Handling a review round (CodeRabbit, CodeQL, humans)

Each round costs a CI run, a re-review and tokens. Do it once, completely.

1. **Read everything first**: inline comments, "Outside diff range", nitpicks, the "Prompt for AI agents" block, every open thread on the PR.
2. **A finding is a claim to verify, not an order.** Trace a real path (input/caller → failure).
   Real and the fix is proportionate → fix. Far-fetched or the fix costs more than it buys → reply in its thread with the traced path and why not, and tell the maintainer.
   **Security findings stay open until the maintainer decides.**
3. **Fix the class, not the instance**: list neighbouring cases (other entry points, other parsers/endpoints with the same pattern, reverse order, other limits) and fix them all, one test per case.
4. **Every test is shown to fail without the fix** (revert the core change, watch it fail) and drives the real entry point, not only a helper. A filtered test run must report tests actually executed.
5. **Adversarial check before pushing**: a separate agent gets the finding, the diff and [LESSONS.md](LESSONS.md) — not your conclusion — and is told to find what the fix misses or breaks. Fold its findings in.
6. **One commit + one push per round**, every finding handled. Never push finding by finding.
7. **Then one reply per thread** (fixing commit, or why not), in the same work unit as the push. A push alone is not an answer. Outside-diff findings: one PR comment addressed to the bot.
8. **Optional findings** (nit, suggestion): never start a push for them. One-line reply; fold them into the next push that touches those files.
9. **After the round**: compare findings with [LESSONS.md](LESSONS.md). Already listed = the self-review missed it, tighten that step. New kind = new row.

CodeRabbit can skip a review ("Review skipped") or pause on a branch: after pushing, check that it reviewed the new head, and if not, ask for `@coderabbitai review`. From cloud sessions `@mentions` are altered, so the operator posts it. Check again afterwards: the round is complete only when CodeRabbit has reviewed the pushed head.

CI noise vs real failure: a check failing in seconds with no log (missing token, unavailable service) is not "CI red" — say so and point to the real checks (build, tests, lint, CodeQL). "Flaky" is not a cause: one re-run at most, then investigate.
