# Implementation Plan - HFRswift Continuation

## Summary
Target outcome:
- Migrate UI to modern SwiftUI while keeping ObjC non-UI treatment logic during phase 1.
- End state: all app UI is SwiftUI; Objective-C remains only for non-UI processing where migration risk is high.

New mandatory constraints:
1. Do not port `OfflineMessagesTableViewController` or offline topic-page storage flow.
2. For `MessagesView`, keep file-based WebView rendering (local file + read access URL) and do not reintroduce inline HTML loading.
3. Avoid `OfflineStorage` outside the mandatory message-rendering file path and deprecated-flow cleanup.
4. Keep a minimal automated test floor on wrapped ObjC classes and critical navigation/opening policies (feature-first mode).
5. Add SwiftUI previews with mock data whenever possible.
6. Remove settings dependency on legacy COTS (`InAppSettingsKit`) and migrate to native modern SwiftUI capabilities.
7. iPad is lower priority; do necessity study first.
8. Remove XIB/NIB usage from migrated `HFRswift` user flows and do not add new XIB/NIB-based UI in the migration path.
9. Use `Favorites.swift` migration style as baseline (SwiftUI screen + ObjC processing adapter), and mutualize topic-list row rendering across screens.

## Scope
In scope:
- SwiftUI feature migration for active user flows.
- ObjC wrapper stabilization with lean, high-value test coverage only.
- Settings modernization away from legacy COTS.
- Progressive removal of XIB/NIB-backed UI dependencies from migrated flows.

Out of scope (phase 1):
- Porting offline topic-page storage UI/flow (`OfflineMessagesTableViewController`).
- Any broad reimplementation of ObjC treatment internals.

## Public interfaces and planned additions
| Interface/Type | Purpose |
|---|---|
| `AppRoute` | Typed app navigation for tabs and deep links. |
| `ForumsService` | Forum/category loading and filter modes. |
| `TopicsService` | Topic list loading and page actions. |
| `MessagesHTMLService` | Topic HTML retrieval from wrapped ObjC pipeline. |
| `MessageWebActionHandler` | Swift-side routing for custom WebView actions. |
| `ReplyPostingService` | Unified reply GET-form + POST with robust errors. |
| `AccountSessionService` | Wrap `MultisManager` account/cookie/hash behavior. |
| `SettingsStore` | Native Swift settings persistence and feature flags. |
| `FeatureParityChecklist` | Feature-level done criteria and parity checks. |

## Architecture guardrails
1. No migration work should reintroduce `OfflineMessagesTableViewController` paths.
2. `MessagesView` must keep file-based loading (`WKWebView.loadFileURL`) and must not use inline HTML loading.
3. Any `OfflineStorage` use outside `MessagesView` rendering must have a short-lived justification note and removal follow-up.
4. SwiftUI screens should depend on service interfaces, not directly on ObjC controllers.
5. Keep wrapped ObjC classes thinly adapted and testable.
6. New settings screens must be native SwiftUI and modern APIs only.
7. In `HFRswift`, do not introduce new XIB/NIB or storyboard-based UI.
8. For migrated topic lists, use shared SwiftUI row primitives to avoid duplicated behavior/UI drift.
9. `SDWebImage` is legacy/transition dependency: keep it only for remaining ObjC/UIKit screens; for new SwiftUI screens prefer native image loading (`AsyncImage` or equivalent), and remove `SDWebImage` once ObjC call sites are migrated.

## Delivery mode: feature-first with safety net
1. Prioritize user-visible feature parity and bug fixes before broad test expansion.
2. Keep mandatory tests only on high-regression-risk seams:
   - wrapped ObjC adapters called by SwiftUI
   - topic opening policy (`TopicOpenPolicy`)
   - known lifecycle regressions already fixed (MP initial load and tab restore behavior)
3. Defer non-critical UI/integration test expansion until S2+.
4. Keep manual validation checklists short and focused per delivered feature.

## Roadmap

### Phase S0 - Foundation and constraints lock
Objectives:
- Lock non-goals and migration boundaries before more feature work.

Work:
1. Finalize GAP list and constraint decisions (including offline de-scope).
2. Add adapter interfaces for wrapped ObjC classes.
3. Define lean test harness focused on wrapped ObjC classes and policy logic only.
4. Document `OfflineStorage` temporary-use policy.
5. Create preview policy and mock fixture conventions for SwiftUI.

Exit criteria:
- Constraints are explicit and enforced in docs/checklists.
- Adapter layer baseline exists.
- Minimal wrapper/policy test floor runs locally and is easy to run before push.

### Phase S1 - Core P0 parity
Objectives:
- Recover critical navigation and topic interactions.

Work:
1. Re-enable categories path and topic quick actions.
2. Implement WebView action routing parity (`MessageWebActionHandler`).
3. Stabilize reply posting with session-safe behavior.
4. Move account/session flows behind `AccountSessionService`.
5. Add mock previews for newly migrated SwiftUI screens.
6. Introduce shared Topic list/row building blocks and apply to active SwiftUI lists.

Exit criteria:
- P0 reading/reply/session paths validated via targeted tests + manual smoke checks.
- New SwiftUI screens include preview coverage where feasible.

### Phase S2 - Favorites/MP and settings modernization
Objectives:
- Close frequent-usage gaps and remove settings COTS.

Work:
1. Complete favorites advanced behavior parity.
2. Complete MP advanced behavior parity.
3. Replace `InAppSettingsKit` based settings with native SwiftUI settings stack.
4. Add only critical regression tests for wrapper-backed settings dependencies and migration safety.
5. Migrate remaining Favorites/MP list UI details away from legacy UIKit/XIB dependencies.
6. Start `SDWebImage` reduction by removing usage from migrated SwiftUI flows and documenting remaining ObjC call sites.

Exit criteria:
- Favorites and MP parity validated.
- Settings no longer depend on legacy COTS.

### Priority pivot (agreed)
Immediate focus shifts from settings to message composition and in-topic contextual actions:
1. Reply composer parity (`Répondre`) with smileys + image insertion.
2. Messages WebView contextual actions for per-post quote/profile.
3. Settings modernization continues later (kept in backlog, not current sprint critical path).

### Phase S1-R - Reply and Message Contextual Actions (new)
Objectives:
- Restore high-value posting UX parity before resuming settings migration.
- Re-enable post-level contextual power actions inside the SwiftUI `MessagesView`.
- Lock current contextual-action sprint scope to quote/profile and related hardening only.

Work package S1-R1 (`Répondre` parity):
1. Define target feature set for the SwiftUI reply flow:
   - default smileys list
   - favorite smileys list
   - image/GIF insertion entry points
2. Introduce a dedicated reply composer architecture with explicit non-UI adapters:
   - smiley providers
   - insertion toolbar actions
   - image upload/rehost hooks
3. Implement in staged mode:
   - stage A: functional parity first (selection/insertion and posting continuity)
   - stage B: UX polish and behavioral parity (draft, undo/redo, fullscreen panels if retained)
4. Keep existing posting reliability path (`ForumReplyPostingService`) unchanged for first integration.

Work package S1-R2 (Messages contextual actions):
1. Stop ignoring popup schemes generated by message HTML:
   - `oijlkajsdoihjlkjasdopopupmessage`
   - `oijlkajsdoihjlkjasdopopupavatar`
2. Recreate per-post action surface with minimum P0 actions first:
   - `Répondre/Citer`
   - `Profil`
3. Define URL/action metadata bridge from parsed ObjC message model to Swift action layer.
4. Add test coverage for routing decisions and URL decoding edge cases.

Current status S1-R2:
- Done: popup scheme routing in Swift web action handler.
- Done: ObjC->Swift action metadata bridge (`messageIndex` to `quote/profile` URLs).
- In progress: production hardening of quote/profile contextual flow (real-post validation + edge cases).
- Deferred: non-P0 contextual actions (BL/WL, MP, Link, AQ, Bookmark, multi-quote toggle).

Exit criteria S1-R:
- Reply sheet supports smiley + image insertion with successful publish flow.
- Contextual menu from message header opens quote/profile actions on real posts.
- No regression on existing page navigation/open-link behavior in `MessagesView`.

Immediate execution order (agreed):
1. Finish S1-R2 quote/profile contextual actions and related hardening only.
2. Keep other contextual actions in backlog for later phase.
3. Start G18 (`Répondre` parity) right after S1-R2 closure.

Deferred UX note:
- `MessagesView` contextual menu visual modernization is postponed.
- Keep current stable implementation (`UIEditMenuInteraction`) during S1.
- Revisit later with a dedicated UX pass to align style with other SwiftUI context menus.

### Phase S3 - Plus completion and lifecycle hardening
Objectives:
- Finalize Plus migration and stabilize runtime behavior.

Work:
1. Complete remaining Plus routes in SwiftUI.
2. Validate startup/background behavior parity.
3. Remove obsolete wrappers that are fully replaced.
4. Keep `Recherche forum` explicitly deferred to a later step (post-S3), after core Plus parity and stability are complete.

Exit criteria:
- No open P0/P1 gaps in core phone flows.
- Lifecycle checks pass.

### Phase S4 - iPad decision then optional implementation
Objectives:
- Handle iPad only if product value justifies scope.

Work:
1. Run iPad necessity study (usage impact, UX delta, engineering cost).
2. If approved, implement split/master-detail parity as separate effort.
3. If not approved, document deferral with rationale.

Exit criteria:
- Decision documented.
- Implementation done only when justified.

## Test strategy (minimal baseline for speed)

### Mandatory now (keep)
1. `TopicOpenPolicy` decisions for `.forum(.all/.favorites/.tracked/.read)`, `.favorites`, `.messages`.
2. Wrapper adapter smoke tests for:
   - favorites loading bridge
   - MP loading bridge
   - topic page loading bridge
3. Regression test for MP initial cancellation handling fallback.
4. Regression test for selected tab restore in same process lifecycle.

### Deferred (later phases)
1. Broad end-to-end UI tests.
2. Exhaustive Plus/settings integration matrix.
3. Non-critical wrapper permutations.

### Preview requirements
For each migrated SwiftUI screen, add previews when feasible:
1. happy path
2. loading
3. empty
4. error

Use deterministic mock fixtures and avoid runtime network in previews.

## Risk management
| Risk | Mitigation |
|---|---|
| Offline legacy feature accidentally reintroduced | Explicit do-not-port guardrail and checklist gate. |
| Overuse of OfflineStorage workaround | Mandatory justification + follow-up removal task. |
| Wrapper regressions | Minimal mandatory wrapper/policy tests on each high-risk change. |
| Settings migration regressions | Parallel native SwiftUI settings implementation with parity checks. |
| Scope creep from iPad | Separate decision gate before implementation. |
| Delayed `SDWebImage` removal | Track as explicit deferred backlog item and remove only when ObjC image-loading call sites are migrated/replaced. |

## Acceptance criteria
1. No implementation task targets `OfflineMessagesTableViewController`.
2. No new `OfflineStorage` usage without explicit mandatory note.
3. Minimal mandatory tests (wrapper/policy/lifecycle regressions) are present and run before push.
4. New SwiftUI screens include mock previews when feasible.
5. Settings COTS dependency removed.
6. iPad has documented decision before engineering work starts.
7. For migrated `HFRswift` flows, no XIB/NIB-backed UI remains in the execution path.

## Assumptions and defaults
1. `SuperHFRplus` remains behavior oracle for parity.
2. Phone flows are prioritized over iPad.
3. Migration is incremental with wrappers removed only after parity pass.
4. Temporary workaround debt must be tracked and retired.
5. `Favorites.swift` pattern is the reference migration template for list-based screens.
6. Test effort stays intentionally minimal until core S1/S2 feature parity is complete.
