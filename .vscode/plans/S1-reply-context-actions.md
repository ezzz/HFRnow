# S1-R Reply and Contextual Actions

## Goal
Prioritize two user-facing parity gaps before continuing settings work:
1. `Répondre` composer parity (smileys + images).
2. In-topic contextual actions in `MessagesView` (quote/profile at post level).

## Scope lock (current sprint)
- Finish only quote/profile contextual actions and directly related hardening.
- Defer other per-post contextual actions (BL/WL, MP, Link, AQ, Bookmark, multi-quote toggle) to a later phase.
- After S1-R2 closure, move immediately to G18 (`Répondre` parity).

## Current state analysis (code-based)

### A. Reply composer (`Répondre`)
- Current SwiftUI composer is minimal text + send:
  - `HFRswift/Swift/AnswerView.swift:3`
  - no smiley panel, no favorites panel, no image/gif insertion actions.
- Posting backend is robust and should be preserved initially:
  - `HFRswift/Swift/ReplyService.swift:52` (`ForumReplyPostingService`)
  - `HFRswift/Swift/AccountSessionService.swift:12` (`ObjCAccountSessionService`)
- Legacy ObjC composer already has most required UX:
  - smiley panel + favorites + search via `SmileyViewController`:
    - `Classes/SmileyViewController.h:15`
    - `Classes/SmileyViewController.m:259`
    - `Classes/SmileyViewController.m:1020`
  - image/rehost panel via `RehostImageViewController`:
    - `Classes/RehostImageViewController.h:18`
    - `Classes/RehostImageViewController.m:277`
  - GIF insertion via Giphy:
    - `Classes/AddMessageViewController.m:737`
    - `Classes/AddMessageViewController.m:761`
  - text insertion hooks from smiley/image notifications:
    - `Classes/AddMessageViewController.m:951`
    - `Classes/AddMessageViewController.m:960`
    - `Classes/AddMessageViewController.m:970`
  - quote-specific prefill and selected-text handling:
    - `Classes/QuoteMessageViewController.m:464`
    - `Classes/QuoteMessageViewController.m:497`

### B. Messages contextual actions (quote/profile)
- The generated HTML still emits custom popup schemes for per-post actions:
  - `HFRswift/Wrapped/MessagesTableViewController.m:1940`
  - schemes:
    - `oijlkajsdoihjlkjasdopopupmessage://...`
    - `oijlkajsdoihjlkjasdopopupavatar://...`
- Legacy ObjC controller handles those schemes and builds menu actions:
  - scheme interception:
    - `HFRswift/Wrapped/MessagesTableViewController.m:2250`
  - action menu generation (includes Quote, Profil, etc):
    - `HFRswift/Wrapped/MessagesTableViewController.m:2380`
    - `HFRswift/Wrapped/MessagesTableViewController.m:2472`
  - action executors:
    - quote: `HFRswift/Wrapped/MessagesTableViewController.m:3127`
    - profile: `HFRswift/Wrapped/MessagesTableViewController.m:2618`
- Swift side now has an in-progress implementation:
  - popup schemes routed to `showPopupMenu` action:
    - `HFRswift/Swift/Common.swift:348`
    - `HFRswift/Swift/Common.swift:398`
  - ObjC->Swift bridge for per-message action URLs:
    - `HFRswift/Wrapped/MessagesTableViewController.h:249`
    - `HFRswift/Wrapped/MessagesTableViewController.m:3556`
  - `MessagesView` now presents contextual `Citer` / `Profil` actions:
    - `HFRswift/Swift/MessagesView.swift:419`
    - `HFRswift/Swift/MessagesView.swift:1063`
    - `HFRswift/Swift/MessagesView.swift:1066`

## Gap summary

### GAP-R1 Reply UI parity missing
- User impact:
  - no fast smiley insertion
  - no smiley favorites
  - no inline image/GIF insertion flow
- Regression risk if rushed rewrite:
  - composer state consistency (selection range, undo/redo, draft)
  - account/hash/cookie usage drift

### GAP-R2 Contextual post actions in progress
- User impact:
  - quote/profile path is partially restored and needs validation hardening.
- Remaining technical gap:
  - complete real-post validation and edge-case URL/index handling before closure.

## Proposed delivery strategy

### Track 1 - Reply composer (feature-first)
#### Step R1.1 (P0)
- Introduce a composer action bar in SwiftUI `AnswerView`:
  - open smileys default/favorites picker
  - open image insertion entrypoint
- Keep posting pipeline unchanged (`ReplyService`) for safety.

#### Step R1.2 (P0)
- Implement smiley insertion service adapters using existing ObjC non-UI/cache where possible:
  - default smileys + favorites
  - insertion into cursor position in `TextEditor` equivalent state.

#### Step R1.3 (P1)
- Implement image insertion flow:
  - minimal first: insert `[img]URL[/img]` from selected/uploaded image URL
  - retain/bridge rehost flow with wrapper if needed for parity.

#### Step R1.4 (P1)
- Add quote-prefill parity cases (normal/bold/exclusive selected text).

### Track 2 - Contextual actions in `MessagesView`
#### Step R2.1 (P0) - Done
- Extend `MessageWebAction` with popup actions (message/avatar).
- Parse popup URL payload (`yOffset`, `messageIndex`, action source).

#### Step R2.2 (P0) - Done
- Add action provider bridge from wrapped ObjC parser model:
  - expose post-level metadata for current page:
    - `urlQuote`
    - `urlProfil`
    - optional `MPUrl` for later extensions

#### Step R2.3 (P0) - In progress
- Present native SwiftUI contextual sheet/menu from `MessagesView`:
  - `Citer`
  - `Profil`
- Reuse existing navigation patterns:
  - quote -> open reply composer with prepared context
  - profile -> open profile route (ObjC host or web route fallback).
- Remaining to close:
  - validate on real posts/pages
  - tighten URL/index edge cases and fallback behavior
  - verify no regressions on page nav/open-link flow

#### Step R2.4 (P1) - Deferred
- Add optional actions after P0 validation:
  - multi-quote toggle
  - BL/WL, MP, Link, AQ, Bookmark.

#### Step R2.5 (Deferred UX)
- Keep the current stable contextual menu implementation for now.
- Plan a later UX pass to align `MessagesView` contextual menu style with SwiftUI topic-list context menus.
- Evaluate migration options during that pass (`WKUIDelegate` context menu or custom SwiftUI overlay menu).

## Risks and mitigations
- Risk: coupling UI to legacy ObjC view controllers.
  - Mitigation: bridge only non-UI metadata/services first; keep SwiftUI presentation native.
- Risk: context menu incorrect mapping due to stale message indexes.
  - Mitigation: bind action map lifetime to rendered page token.
- Risk: reply regression on account session.
  - Mitigation: keep `ReplyService` unchanged during UI parity work.

## Validation checklist
- Reply:
  - select smiley default -> inserted at cursor
  - select smiley favorite -> inserted at cursor
  - image insertion produces valid forum markup
  - post success flow unchanged
- Context menu:
  - tap header right action opens menu
  - quote action opens composer with expected context
  - profile action opens expected profile destination
  - no regression on page nav/links/refresh.

## Suggested execution order
1. Finish R2.3 quote/profile hardening and real-post validation.
2. Freeze R2.4 optional contextual actions in backlog (no delivery in this sprint).
3. Start R1.1 + R1.2 (smileys in composer).
4. Continue with R1.3 (image insertion), then R1.4 (quote-prefill parity).
