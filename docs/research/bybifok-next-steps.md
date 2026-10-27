# Bybifok — what to dig next, and how to start an agent on it

For Bybifok (GitHub [`moust4ki`](https://github.com/moust4ki)). Everything Bybifok proposed is recorded, with credit, in [bybifok-proposals.md](bybifok-proposals.md) and [FEATURES.md](../FEATURES.md) (FEAT-001…021).
This page says which of those ideas need work first, and gives a prompt to paste into an agent session.

## Where the project stands (2026-10-27)

- SwiftHFR lives on **`ezzz/HFRnow`, branch `dev-swift`**. `master` is the shipped Objective-C app: SwiftHFR work never targets it.
- The engine (`Packages/HFRKit`) is being ported lot by lot ([LOTS.md](../LOTS.md)); the iOS app target is about to be created (LOT-080). Most features need engine lots that are not done yet, so **the useful work now is facts and specs, not app code**.
- Every PR on `dev-swift` goes through [COLLABORATION.md](../COLLABORATION.md): issue → `FEATURES.md` entry → spec → PR meeting the entry criteria, one approval by someone else.

## What to dig, in this order

### 1. HFR protocol facts (highest value: they unblock lots)
Bybifok found them; they enter [HFR-PROTOCOL.md](../HFR-PROTOCOL.md) only with a **captured, anonymized page** as evidence ([FIXTURES.md](../FIXTURES.md)), credited to Bybifok.

| Fact | Feature / lot it unblocks |
|---|---|
| P2 list paging only through `liste_sujet-<n>.htm` | FEAT-003, LOT-041 |
| P1 forum-list pager is a window, last link is a lower bound | FEAT-003, LOT-022 |
| P3 search ignores words under 4 letters; P5 search GET parameters, member posts URL | LOT-046 |
| P6 "Mes drapeaux" content and the `suppressflag.php` link | FEAT-008, LOT-024 |
| P7 `closedb_new` icon and theme-dependent icon paths | LOT-022 |
| P8 `[non lu]` in the MP list means the correspondent has not read it | FEAT-001, LOT-023 |
| P9 old `forum2.php3` links, "Achats & Ventes" first sub-forum | FEAT-020 |
| P10 recount the home page categories (20 rows vs 19 links) | HFR-PROTOCOL §6b |
| P4 AQ RSS entities | LOT-025 |

Captures need a logged-in session on a Mac; anonymization is checked by an independent reviewer **before** the push (a past corpus PR leaked pseudos).

### 2. Feasibility studies (answer before anyone promises the feature)
- FEAT-018 "On t'a cité": is there any server signal (`quote_only=1`)? Capture first.
- FEAT-019 reho.st upload deletion: is there a delete API for guest uploads?
- FEAT-012 emoji: does HFR accept BMP emoji (non-BMP truncates the message)?
- FEAT-017 continuous scrolling: request plan that never moves a flag behind the reader.
- FEAT-005 "Vérifier HFR" intent: minimum interval, never GET a topic page.

Each answer goes into the feature's spec with its evidence.

### 3. Specs for the features Bybifok designed
One spec per feature, `docs/features/FEAT-XXX.md`: what and why, screens and states (light, dark, Dynamic Type XL, iPad), HFR facts used, edge cases, the engine lots it needs, the legacy settings it must keep. Attach the Imgur boards to the feature issue.
Start with the high-priority ones: **FEAT-002** page navigator, **FEAT-001** Home, **FEAT-006** quote tray, **FEAT-008** swipes, **FEAT-007** "Nouveau" banner, **FEAT-009** session expiry; then **FEAT-010** appearance (tokens and contrast targets from PR #5's design document) and **FEAT-016** iPhone Duo / iPad columns (from PR #4).
Keep in scope the legacy features the proposals did not mention ([bybifok-proposals.md §4](bybifok-proposals.md#4-legacy-features-the-proposals-do-not-mention)): a spec that removes one says so and why.

### 4. Not now
- App code for these features: it waits for the app target and the engine lots it depends on.
- PRs #3–#6 on `master`: they concern the shipped app, ezzz decides. Their bug fixes (#3) become non-regression tests in SwiftHFR.
- Copying `ultra-hfr` files: they are MPL-2.0. Either port the idea through a lot, or contribute your own code by PR under this project's licence ([ADR 0011](../adr/0011-contribution-model-and-feature-intake.md)).

## Prompt to paste into your agent

```text
You work on SwiftHFR, a native iOS client for forum.hardware.fr.
Repository: https://github.com/ezzz/HFRnow — branch dev-swift ONLY. The default branch master is the legacy app: never branch from it, never target it, and ignore its CLAUDE.md.

Setup:
1. Fork ezzz/HFRnow, clone your fork, then: git fetch origin dev-swift && git switch dev-swift
2. Read, in this order, and follow them: AGENTS.md, docs/COLLABORATION.md, docs/FEATURES.md,
   docs/research/bybifok-proposals.md, docs/research/bybifok-next-steps.md, docs/HFR-PROTOCOL.md, docs/FIXTURES.md.
3. Create every branch from dev-swift, open every PR against dev-swift on ezzz/HFRnow.

Task: <ONE item from bybifok-next-steps.md, e.g. "spec FEAT-002 page navigator" or "capture P2">.

Rules:
- One item per PR. Open or reuse the GitHub issue first, and link it.
- Never guess how HFR behaves: every URL, form field, cookie or selector comes from the legacy code (master branch) or a captured page. If it is not documented, stop and tell me what to capture.
- Captured pages are anonymized (docs/FIXTURES.md) and checked by someone else before any push. No secrets, cookies or real pseudos anywhere.
- For a spec: docs/features/FEAT-XXX.md with screens and states, HFR facts with their source, edge cases, engine lots needed, legacy settings kept.
- For code (later): tests first (Swift Testing), view logic in testable view models, AGENTS.md §4 conventions.
- Before opening the PR, check it against the entry criteria of docs/COLLABORATION.md §4 and list them ticked in the PR body. Name the model that wrote it.
- Then I ask a second agent, on a different model, to review the diff adversarially. Do not merge: a maintainer approves.
```
