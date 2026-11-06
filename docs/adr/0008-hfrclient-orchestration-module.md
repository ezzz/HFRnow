# 0008 — HFRClient: a module for multi-step forum flows

**Status:** Accepted — 2026-10-24 (LOT-000 review, finding F1)

## Context
ADR 0001 forbids `HFRNetwork` from importing `HFRParsing` and lets "the app orchestrate".
The audit shows that most forum operations are multi-step flows: fetch a page → parse a form or a token → submit → classify the response (login, posting, edit/delete, alerts, flags, search, MPStorage, poll vote).
Leaving these flows to the app would put the riskiest logic where it cannot be tested on Linux CI; putting them in `HFRNetwork` breaks the module rules.

## Decision
Add a fifth engine target, **`HFRClient`**, depending on `HFRModels`, `HFRParsing` and `HFRNetwork`:
- it owns multi-step flows and their policies (e.g. `hash_check` refresh from parse results, form-value-first token policy, retries on MPStorage conflicts);
- it is Foundation-only and tested on Linux with the mock transport and fixtures;
- it **does not depend on `HFRStorage`**: the app passes stored values in (account, cookies, MPStorage document) and persists what flows return.

`HFRNetwork` keeps transport, endpoints, per-account sessions/cookies and raw page fetchers only. `HFRParsing` stays pure.

## Consequences
- Lots whose scope is "GET → parse → POST → classify" move to `HFRClient` (LOTS.md).
- The dependency rules of ADR 0001 are unchanged for the four original modules; `HFRClient` is a layer above them, not a sibling.
- The app becomes thinner: views and view models call `HFRClient` flows and `HFRStorage` stores.
