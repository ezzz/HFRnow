# App feature backlog

App-level features (Phase 4–5), alongside the engine lots of [LOTS.md](LOTS.md). How an entry moves: [COLLABORATION §3](COLLABORATION.md#3-from-an-idea-to-a-merged-feature).
An entry names who proposed it; the credit stays whoever implements it.

Statuses: `proposed` (idea recorded) · `spec` (spec being written) · `ready` (spec accepted, engine dependencies done or planned) · `in-progress` · `done` · `dropped` (with the reason).
Engine dependencies point to [LOTS.md](LOTS.md); `new` means a lot still to create. Priorities follow [AGENTS.md §7](../AGENTS.md#7-labels-and-prioritization).

## Proposed by Bybifok (2026-10-26)

Source: Bybifok's proposal message, PRs [ezzz/HFRnow#3–#6](https://github.com/ezzz/HFRnow/pulls) and prototype [moust4ki/ultra-hfr](https://github.com/moust4ki/ultra-hfr). Inventory and evidence: [research/bybifok-proposals.md](research/bybifok-proposals.md).

| Id | Feature | Engine dependencies | Open questions | Phase | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|
| FEAT-001 | **Home / "À suivre"**: resume last reading, unread MPs, super favourites, favourites, flags with news grouped by category, Alertes Qualitaÿ; first sidebar entry on iPad. Replaces the Favoris tab ("Tout" opens the current favourites screen) | 023, 024, 055, 064, **new** reading-position store (HFRStorage) | Migration of the legacy "start screen" and "favourites mode" settings (LOT-060/067) | 4 | high | — | proposed |
| FEAT-002 | **Page navigator** from the page number in the topic title: "Aller à la page…", first/last, ±5 around current, blocks of 50; all pages listed up to 30 | 033 | — | 4 | high | — | proposed |
| FEAT-003 | **Honest list paging**: "Page N" without a fake total in forum lists, "Dernière page" disabled when unknown; exact page count per topic row kept | 022, **new** `PageNavigation` exactness flag (HFRModels) | Protocol fact to capture (window pager vs `sujetCase4`) | 3–4 | high | — | proposed |
| FEAT-004 | **Page scrubber** on the right of a topic: bubble "p. N", jump on release, dot and snap at first-unread page, haptic every 100 pages | 022/024 (flag page), 033 | Accessibility (VoiceOver adjustable action) | 4 | medium | — | proposed |
| FEAT-005 | **"Vérifier HFR" App Intent**: background check of MPs and flags, local notification, run by Shortcuts automations | 044, 047, 065, **new** "check updates" flow (HFRClient) + "already notified" state (HFRStorage) | Minimum interval (politeness), never GET a topic page (flags), keep the legacy BGTask (LOT-047) | 4 | medium | — | proposed |
| FEAT-006 | **Quote tray and quick-reply bar**: count of checked quotes, reply takes them in topic order, tray emptied after a confirmed send | 042, 048, 049 | — | 4 | high | — | proposed |
| FEAT-007 | **"Nouveau" banner** at the first unread message; stable position while images load and after a network error | 022, 030 | — | 4 | high | — | proposed |
| FEAT-008 | **Uniform swipes** in every list: Lu (with "Annuler", stays until refresh), Dernière page, Super favori, Retirer | 045, 051, 064 | "Annuler" needs the previous flag URL | 4 | high | — | proposed |
| FEAT-009 | **Session expiry sheet**: draft kept, resent after re-login only when the server confirmed it was not posted | 037, 044, 048, 063 | Double-post risk | 4 | high | — | proposed |
| FEAT-010 | **Appearance**: darker dark (#0B0B0C), OLED black, 1 pt separators, compact mode, one-line message header, single accent colour, live preview in settings, seasonal themes | 060 | Keep the legacy brightness and accent settings or migrate them | 4–5 | medium | — | proposed |
| FEAT-011 | **Image loading setting**: never / Wi-Fi / always | 060 (`ImageDisplayMode` exists) | — | 4 | medium | — | proposed |
| FEAT-012 | **Emoji refusal with smiley suggestion** | 012, 048, **new** emoji→smiley table | HFR truncates at the first non-BMP character, BMP emoji untested | 3–4 | medium | — | proposed |
| FEAT-013 | **Preview before send** (exact BBCode rendering) | **new** BBCode renderer | Module (HFRParsing or app) — ADR needed | 4 | medium | — | proposed |
| FEAT-014 | **HD gallery** with swipe between images | 034, 056 | — | 4 | medium | — | proposed |
| FEAT-015 | **State restoration**: forum, topic, page, position on return, fold, multi-window | **new** reading-position store | — | 4–5 | medium | — | proposed |
| FEAT-016 | **iPhone Duo / iPad columns**: two columns unfolded, tabs in a rail folded, sidebar pinned or on demand | — | Phase 5 design documentation | 5 | high | — | proposed |
| FEAT-017 | **Continuous scrolling** (option, off by default, haptic per page) | 045, 030–034 | 🔴 Flag semantics: an authenticated GET moves the flag; prefetch without session then reload — two requests per page | 5 | low | — | proposed |
| FEAT-018 | **"On t'a cité"** in Home and in the FEAT-005 notification | capture of `quote_only=1` first | No server signal known; feasibility study before any promise | 5+ | low | — | proposed |
| FEAT-019 | **Upload history with server-side delete** on reho.st | 056, 071 | No delete API evidenced for guest uploads | 4+ | low | — | proposed |
| FEAT-020 | **Opening HFR links in the app** (share, clipboard, universal links) | 020 | Q-1 decided (update of `hfrplus.red.super`): the site's AASA already names this App ID, so universal links are possible — verify on device | 4 | high | — | proposed |
| FEAT-021 | **iPad keyboard shortcuts** (J, K, Q, R, ⌘F) and **Spotlight** for read topics (from ultra-hfr) | — | — | 5 | low | — | proposed |

## Not to lose (legacy features missing from the proposals)

Checked in the legacy code; they stay in scope even if no proposal mentions them: multi-account, blacklist / whitelist, MPStorage sync, bookmarks, post filter, MP actions (new, mark unread, delete), new topic, edit / delete own posts, moderator alert, AQ creation, poll vote and poll draft, archived drafts, "+" button modes, Giphy, **account deletion** (App Store 5.1.1(v)), start-screen setting, multi-window. Details: [research/bybifok-proposals.md §4](research/bybifok-proposals.md#4-legacy-features-the-proposals-do-not-mention).
