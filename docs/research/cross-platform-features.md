# Cross-platform features: iOS, Android, web

Working table for the community effort to align the HFR clients (forum topic "HFR: web, android, ios", Programmation > Divers).
Goal: agree on **what** each client offers and **which data is shared** (MPStorage), then let each platform implement in its own way.

Sources: our legacy audit ([docs/audit](../audit/README.md)), the redface2 comparison ([redface2-comparison.md](redface2-comparison.md) §2), user feedback ([user-feedback-p450-510.md](user-feedback-p450-510.md)), the dev topic. MPStorage facts (format, blacklist, bookmarks, read/write flow): [HFR-PROTOCOL.md](../HFR-PROTOCOL.md) §3.3, audit [D §2.10](../audit/D-posting.md) and [E §2.6](../audit/E-storage-vendors.md). "?" = not known to us.

**iPhone and iPad are one target in SwiftHFR**: a single adaptive SwiftUI app with column navigation (forums → topics → messages), covering phones, iPads and foldable iPhones.

## Reading

| Feature | iOS legacy (SuperHFR+) | Android (redface2) | Web (userscripts) | SwiftHFR target | Shared data |
|---|---|---|---|---|---|
| Forum / topic lists | HTML | REST + HTML | site | REST with HTML fallback (LOT-057, 021, 022) | — |
| Read a topic | WebView + HTML rewriting | Compose from parsed AST | site | WebView + normalized, sanitized HTML (LOT-030–035, ADR 0006) | — |
| Resume at last read | flags page anchor | REST last-read id | site | flags + last-read id (LOT-024, 057) | read positions (MPStorage `lastRead`?) |
| Prefetch without marking read | no | anonymous client | — | anonymous client (LOT-045) | — |
| Flags and favourites | yes | yes, redesigned view | site | yes (LOT-024, 051) | — |
| Super-favourites | local | local per account | ? | local (LOT-064) | candidate for sync |
| Posts quoting me (egoquote) | unverified | yes (`quote_only=1`) | userscript | Phase 4 backlog, approach to decide | — |
| HFR link shown as "topic X page N" | no | no | userscript | Phase 4 | — |
| Links open the app | unverified | yes (intent filters) | — | Phase 4 link router (design assumption: universal links need an `apple-app-site-association` file on forum.hardware.fr, which we do not control) | — |
| Public profile | yes | yes | ? | LOT-027 | — |
| Staff role badge | no | yes (staff directory) | ? | not planned | — |
| Inline code / tables (Markdown-like) | no | no | idea | display only, if agreed | — |

## Writing

| Feature | iOS legacy | Android | Web | SwiftHFR target | Shared data |
|---|---|---|---|---|---|
| Reply, edit, delete, new topic | yes | yes (+ first post deletes topic) | site | yes, honest success detection (LOT-048) | — |
| Quote / multi-quote | cookie | client-side concatenation | site JS | one of both, decided with fixtures (LOT-049) | — |
| "+" reply carries selected quotes | yes (4.0.2 setting) | basket FAB | — | yes (Phase 4) | — |
| Emoji | sent as is, then truncated by HFR (users, [feedback](user-feedback-p450-510.md) p. 478; [comparison](redface2-comparison.md) §4.2 X9) | stripped | — | refused with a warning (Q-3) | — |
| Drafts | yes | yes | ? | yes (LOT-063) | — |
| Smileys (search, favourites) | yes | search | wiki + stats | yes (LOT-053, 064) | favourite smileys? |
| Image upload | Chevereto (key) | Diberie, Imgur (own key) | ? | host adapter table (LOT-056) | **uploaded images + deletion hashes** |
| Polls | read, vote | read, vote, close, create | site | read, vote (LOT-026, 054) | — |
| Moderator alert | yes | yes | site | LOT-050 | — |
| AQ (Alerte Qualitay) | yes | no | AQ scripts | LOT-055 with first-use notice (Q-4) | — |

## Private messages and sync

| Feature | iOS legacy | Android | Web | SwiftHFR target | Shared data |
|---|---|---|---|---|---|
| MP list, read, reply | yes | yes | site | yes (LOT-023, 048) | — |
| Group MP (MultiMP) members, mark unread | unverified | yes | multimp script | LOT-058 (added after the comparison report, which still says none) | MultiMP read tracking |
| Background MP check | yes | non-goal | — | yes (LOT-047, Phase 4) | — |
| Blacklist | local + MPStorage | local, no MPStorage sync found | scripts | local + MPStorage (LOT-061, 062) | `blacklist` |
| Whitelist | local | no | ? | local (LOT-061) | — |
| Bookmarks | MPStorage | planned | scripts | storage via MPStorage (LOT-038, 052, 062); UI in Phase 4 | `bookmarks` |
| MPStorage write | unchecked read-modify-write | opt-in, verify-after-write, size cap | DTCloud, multimp, … | conflict-aware, v1 compatible, ready for v2 (LOT-052, 062) | whole document |

## Platform

| Feature | iOS legacy | Android | Web | SwiftHFR target |
|---|---|---|---|---|
| Multi-account | yes | no (non-goal) | — | yes, posting as the selected account (Q-8) |
| Session expiry | partial | typed, re-login prompt | — | typed, never claims success (LOT-044, 048) |
| Themes, dark mode, text size | yes | yes (AMOLED, accents) | site | yes, Dynamic Type everywhere (Phase 4) |
| Offline reading | exists in legacy code, unused in HFRswift | caches only | — | yes (LOT-068) |
| Large screens, foldables | iPad landscape favourites side panel (users, [feedback](user-feedback-p450-510.md) p. 495–507; not in our code audit) | adaptive nav | — | one adaptive app, columns (Phase 5) |
