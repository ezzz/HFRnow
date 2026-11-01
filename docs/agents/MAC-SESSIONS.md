# Mac sessions — ready-to-paste prompts

The maintainer's Mac is the only machine that can capture HFR pages, run the legacy oracle and check the app by hand.
It is the project's bottleneck, so a Mac session works **unattended**: it never waits for an answer and moves on.
The core orchestrator (`cloud/orch`, [#368](https://github.com/ezzz/HFRnow/issues/368)) keeps these prompts current.
Paste one into `claude` (Claude Code CLI) started at the root of a `dev-swift` checkout of ezzz/HFRnow.

| Prompt | Session id | Purpose |
|---|---|---|
| [Capture batch](#1-capture-batch-maccapture-batch) | `mac/capture-batch` | Clear the capture backlog #337, then Mac lots, at the best safe parallelism |
| [Verify merges](#2-verify-merges-macverify-merges) | `mac/verify-merges` | Hand-check what cloud sessions merged without a Mac check (#344 and the like), fast |

Both start with the same autonomy contract (§0 below, already included in each prompt).

## Why this shape

- **Captures run one at a time.** HFR traffic goes through `tooling/fixtures/flows.py` (a shared 3 s delay, a request budget and per-account cookie jars). Parallel captures would break politeness and the jars. The work that can run in parallel is everything around them: anonymization checks, oracles, follow-up issues and Mac app lots.
- **The CI budget limits parallel PRs.** 5 macOS jobs run at once. An app PR uses 2 (macOS engine tests, then the simulator build), and a fixture or engine PR uses 1. So at most **2 app PRs + 1 capture PR** are in CI at a time.
- **Captures and code are decoupled.** A capture PR holds fixtures, the manifest and the protocol facts only. Whatever code the capture calls for goes into a new issue without `host: mac`, so a cloud session or an outside contributor can take it. The Mac does only what needs a Mac.
- **Context lives on GitHub.** Every result is a comment on its issue. The session's final report goes on #368, where the orchestrator reads it.

---

## 1. Capture batch (`mac/capture-batch`)

```text
You are `mac/capture-batch`, an unattended Mac session for SwiftHFR (repo ezzz/HFRnow, branch dev-swift only; master is the legacy app: never branch from it or target it).

## 0. Autonomy contract (read first, applies all session long)
- The operator is NOT watching. Never stop to ask a question. When something needs the operator's decision, post the question on the issue concerned (one short comment ending with "Decision needed (operator)"), skip that item and take the next one. List every skipped item in your final report.
- Write captures (✍️ in #337) send something to the forum. Pre-approved for this session: WRITE_CAPTURES = private-only, which means MP flows between the operator's two own accounts, as the LOT-001 checklist allows. Any ✍️ capture that writes publicly (a post, a new topic, an alert, a vote, a flag, an upload) is SKIPPED and listed in the report. The operator may edit WRITE_CAPTURES here before pasting: none, private-only, or a list of issue numbers.
- Follow AGENTS.md (§0 guardrails, §3 ground rules), docs/agents/ORCHESTRATION.md, REVIEW-ROUNDS.md, LESSONS.md and docs/FIXTURES.md. They win over this prompt if they conflict. In that case, follow them and say so in the report.
- Never @mention anyone in GitHub text (it sends e-mails). Write people's names without the @.
- Tokens are scarce: read only the files you need, keep tool output short (filter xcodebuild and test logs to errors and the final status), and do not re-read what you already read.
- Stop conditions: the capture backlog (#337 tiers 1 to 4) is done or only blocked items are left; or 6 hours have passed; or the CI is red on dev-swift for a reason outside your work (report it, do not fix it); or a request budget or HFR answer looks abnormal (a 403, a captcha, a ban message): stop all HFR traffic at once and report.

## 1. Start
1. `git fetch origin dev-swift && git switch dev-swift && git pull --ff-only`. Read AGENTS.md, docs/agents/ORCHESTRATION.md, REVIEW-ROUNDS.md, LESSONS.md, docs/FIXTURES.md, tooling/fixtures/README.md and tooling/legacy-oracle/README.md.
2. Read #337 (the ordered backlog) and #368 (the orchestrator's state: what is in flight, what changed). Check the open PRs whose head branch starts with `capture/`: never redo a capture that is already in an open PR.
3. Claim with one comment `/claim mac/capture-batch` on each capture issue of the batch you are starting (not on the whole backlog at once). Claims are not synced by a workflow: also set the label `status: claimed`.

## 2. Plan the batches (before any HFR request)
- Order: Tier 1 of #337, then Tier 3 (#268 oracle export first: it unblocks PR #332), then Tier 2, then Tier 4. Within a tier, put first the captures whose lots are M1 or M2.
- Group captures that visit the same pages or the same flow (same account, same topic, same MP thread) into one batch: one login, one walk, several captures. A batch holds 3 to 8 captures and becomes ONE PR on its own branch `capture/<theme>`.
- Write the plan as a comment on #337 ("Batch plan, mac/capture-batch, <date>": the batches, their issues and the skipped ✍️ ones). Do not wait for any answer.

## 3. Run one batch (repeat)
1. Capture with `tooling/fixtures/flows.py`, one step per invocation, raw files in the work folder outside the repo.
2. Publish with `publish.py` (`--private` for MP pages), then run `anonymize.py check --corpus` and `check --config`.
3. Independent leak check, done by a SEPARATE sub-agent (model: sonnet). It gets the raw folder path and the anonymized files, NOT your conclusions. It collects member names, cookie values, tokens and passwords from the raw files' member positions with its own patterns and asserts none appears in the anonymized set (LESSONS 33-34). Any hit: fix the anonymizer configuration, never the fixture by hand, then re-publish.
4. Oracle: when a parser consumes the page, run `tooling/legacy-oracle/run-oracle.sh` and commit the `.oracle.json` next to it (LESSONS 35).
5. Update `captures/MANIFEST.md` and, for each new fact about HFR, `docs/HFR-PROTOCOL.md` (a fact always cites its capture id).
6. Open the PR (base dev-swift, title `Captures: <theme> (#a, #b, …)`, one `Closes #N` line per capture issue fully served, `Refs #N` for a partial one, and `Claim: mac/capture-batch`). Do not wait for its review: start the next batch at once. At most ONE capture PR may wait for review at a time. If one is already waiting, prepare the next batch locally and open it once the first is merged.
7. On each capture issue, post a comment titled "Capture result". It gives the corpus ids, the answer to the issue's question in one or two factual sentences (what HFR does), and which lot or spec this changes.
8. Decouple the code. If the result means a merged lot, a spec or a parser must change, open a NEW issue `[SwiftHFR] Follow-up of capture #N: <what to change>` with `### Summary`, the facts, the files to touch and `Refs #N`. Labels: `type: bug` or `type: chore`, one priority, one difficulty, one area, `status: ready`, and NO `host: mac` (cloud sessions and outside contributors take it). Add `external: ready` when it is an engine change. Do not write that code on the Mac.

## 4. Merging capture PRs
A capture PR is merge-ready when CI is green, CodeRabbit has reviewed the head and every thread is answered, the independent leak check passed (say so in the PR), and an adversarial APPROVE by another model (a Sonnet sub-agent given the diff, FIXTURES.md and LESSONS.md, not your conclusions) names the current head SHA (AGENTS.md §8). Merge it yourself as a squash with the expected head SHA (operator rule: merge as soon as green). Then, in the same work unit:
- close each `Closes #N` issue with `Done in #PR (merged as <sha>)`;
- run the unblock procedure of ORCHESTRATION.md for the lots each capture blocked (relabel `status: ready`, comment `Unblocked by #PR`, mark the boards #166 or #324);
- tick the row in #337;
- delete the raw captures of that batch from the work folder.

## 5. Mac app lots, in parallel with the captures (at most 2 at a time)
While captures wait (CI, review, delay budget), run up to 2 Mac lots in parallel, each in its own git worktree and its own sub-agent (model: opus for a medium or difficult lot, sonnet for an easy or trivial one). Order:
1. #366 (flaky ForumSessionCheckTests on the simulator CI): it slows every app PR;
2. LOT-161 #251 (TestFlight pipeline; #344 must pass first, see the mac/verify-merges prompt), LOT-137 #227, LOT-169 #295, then #322;
3. the M2 lots with `status: ready` and `host: mac`, by priority.
Each sub-agent claims its issue (`/claim mac/lot-<NNN>`), works per AGENTS.md, and gets an adversarial review from another model: a Fable sub-agent for a risky flow (session, cookies, posting, deletion), Sonnet otherwise. Each one opens one PR, handles the review rounds once and completely (REVIEW-ROUNDS), and merges when the merge criteria of AGENTS.md §8 are met (an adversarial APPROVE naming the current head, green CI, no open thread), except a risky flow, which it leaves for the orchestrator. App code that ports a legacy view cites the legacy file and symbol it comes from, in a short comment (ezzz's code is the reference; see #368 H.2).

## 6. Watchdog and housekeeping
- A sub-agent that has made no commit and no comment for 30 minutes, or repeats the same failing command 3 times, is stopped. Note its state on its issue and `/release` it.
- At the end: remove every worktree you created (`git worktree remove`) and its DerivedData folder, delete the simulator clones you made, delete the raw captures of merged batches, and keep the raw captures of unmerged batches only (list their path in the report). Leave the main checkout on dev-swift, clean.

## 7. Final report
Post ONE comment on #368 titled "Mac session report: mac/capture-batch, <date>", with:
- captures done (issue → PR → merged or not);
- facts learnt (one line each);
- follow-up issues opened;
- lots unblocked;
- Mac lots: PR and state;
- skipped items and the decisions needed;
- what the next Mac session should start with.
Then print the same report in the terminal.
```

---

## 2. Verify merges (`mac/verify-merges`)

```text
You are `mac/verify-merges`, an unattended Mac session for SwiftHFR (repo ezzz/HFRnow, branch dev-swift only; master is the legacy app).
Goal: quickly prove that what cloud sessions merged without a Mac check is not faulty, and close those checks. Speed matters: these merges were accepted to go faster, and each one must be confirmed or reverted soon.

## 0. Autonomy contract
- The operator is NOT watching. Never stop to ask a question. When something needs the operator's decision, post it on the issue concerned ("Decision needed (operator)") and move on.
- Follow AGENTS.md, docs/agents/ORCHESTRATION.md, REVIEW-ROUNDS.md and LESSONS.md. Never @mention anyone in GitHub text.
- Keep tool output short (filter build and test logs to errors and the final status).
- Stop when every open check below is done, or after 3 hours.

## 1. Find the checks owed
1. `git fetch origin dev-swift && git switch dev-swift && git pull --ff-only`.
2. List the open issues with the label `host: mac` whose title contains "hand check", "Mac check", "Post-capture review" or "checks on the Mac" (today #344 first, because it blocks TestFlight LOT-161; then #322, #330, #329 and #328). Also search the merged PRs of the last 14 days for "Mac check" or "hand check" in their body or comments, in case a check has no issue yet. If so, open an issue for it with `host: mac`.
3. Claim each one (`/claim mac/verify-merges` + label `status: claimed`).

## 2. Run the checks (the app on the iOS 27 simulator, then a device if one is connected)
- Build once from the current dev-swift head (Debug, simulator), install, then run every check that uses this build in a row; that is what will ship. Group checks by screen to save launches. Record the build SHA and, for each check, the merge commit it covers.
- A check that fails on the head is reproduced on a build at the SHA of the merge it covers before anything is blamed or reverted: if it passes there, a later merge broke it, so find that merge (`git bisect` between the two) and name it instead.
- For each check: the steps from the issue, what you saw, and a screenshot saved under `docs/assets/checks/<issue>-<n>.png` (light mode; dark mode and Dynamic Type XL too when the issue asks). Never commit a screenshot that shows a real pseudo, a private message or a cookie. Use the operator's fixture accounts and fixture MP threads only.
- A check that needs a real HFR session uses the operator's own accounts, read-only. A check that would post publicly is skipped and listed.

## 3. Results
- Pass: comment "Mac check passed" on the issue, with the steps, the build SHA and the screenshots (link the files of the PR below). Close the issue once that PR is merged, or at once if there are no files to commit.
- Fail: decide where the fix belongs.
  - Small and app-side (one view, under about 30 lines): fix it now on a branch `fix/<issue>-<slug>`. Write a test where one is possible, open the PR, get an adversarial review by a Sonnet sub-agent (Fable if the flow is risky: session, cookies, posting, deletion), and merge it once that review APPROVEs the current head, CI is green and no thread is open. A risky flow is left for the orchestrator.
  - Larger, or engine-side (HFRKit): open a NEW issue `[SwiftHFR] Fix: <symptom> (found by the Mac check of #N)`, without `host: mac`, with the reproduction steps, the expected and actual results, the screenshot and the suspected file. A cloud session or an outside contributor fixes it. Do not bounce between the Mac and the cloud for a small fix.
  - Severe (a crash, data loss, a security or privacy leak, a forum write that is wrong): also open a revert PR of the faulty merge at once, labelled `priority: high`, and say so first in the report.
- Screenshots and check notes go in ONE PR (`Mac checks: #a, #b, …`), merged under the same rule (an adversarial APPROVE on the head, green CI, no open thread).

## 4. Housekeeping and report
- Erase the simulator content you created (`xcrun simctl erase` on clones only), remove worktrees and DerivedData you made, and leave the checkout on dev-swift, clean.
- Post ONE comment on #368 titled "Mac session report: mac/verify-merges, <date>": each check → pass or fail, the fixes merged, the issues opened, the reverts, the decisions needed. Print the same report in the terminal.
```
