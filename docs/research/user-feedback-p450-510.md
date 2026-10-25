# User feedback on the legacy iOS app, topic 1711, pages 450-510

Research note, not normative. Nothing here changes `LOTS.md` or `HFR-PROTOCOL.md`. Written 2026-10-25.
See also `docs/research/redface2-comparison.md` (Android client study).

## 0. Scope, method, limits

| Item | Value |
|---|---|
| Source | Official support topic "Super HFR+ l'app du forum pour iOS [Topic Unique]", category Apple (cat 25), topic id 1711 |
| Pages | 450 to 510 inclusive (61 pages, fetched sequentially on 2026-10-25, page 510 is the last page at fetch time and holds 11 posts) |
| Date range | 8 Feb 2021 to 24 Oct 2026 |
| Rendered post rows | 2,471 (41 per page, 11 on page 510) |
| Unique posts | **2,411** (each page after 450 starts with a copy of the previous page's last post, 60 copies) |
| Distinct authors | 170 (maintainers included) |
| Posts per calendar year | 2021: 320, 2022: 191, 2023: 233, 2024: 167, 2025: 738, 2026 (to 24 Oct): 762 |
| Ad rows | 3 per page (`Publicité`), ignored |

Method. All pages were read in order, quoted text ignored for attribution. Frequencies are **approximate counts of distinct user messages** (maintainer replies not counted), obtained by reading plus keyword cross-checks; treat them as orders of magnitude (plus or minus 25 %). "Status" is what the thread itself shows by p. 510, not what we verified on a device. Pseudonyms are deliberately absent: people are described by role ("the maintainer", "the image-host admin", "an Android-client developer"). French fragments are kept to a few words where the wording matters.

Raw pages were fetched on 2026-10-25 into a temporary directory and not kept (they contain members' content). Protocol notes in §4 were observed in those pages unless labelled *reported*; they become verified only through anonymized LOT-001 fixtures.

### 0.1 Storyline in eight lines

1. 2021 to 2023: a small crew ships yearly fixes (2.1.16 to 2.1.22) and the community is mostly happy; recurring pain is stale sessions, the volunteer-run image host and iOS-version regressions.
2. May 2024 and Feb 2025: the app vanishes from the App Store twice (the original publisher's developer account apparently lapsed). The current maintainer takes the app over (p. 474) and rebuilds the release pipeline.
3. Apr 2025, 3.0 "Blue Edition": dependency cleanup, settings pruning, new default post layout, blue icon. First wave of "it was better before" (p. 478-480).
4. Jul 2025 to Jan 2026: 3.1 adds forum search and quote splitting; iOS 26 adds Liquid Glass; iPad launch crash after 3.2 (p. 490-491); swipe-back conflicts on iOS 18/26.
5. 25 Mar 2026: beta of 4.0, a complete SwiftUI rewrite (p. 493). 4 Jun 2026: 4.0 ships (p. 495). Roughly balanced reaction: appreciation, many muscle-memory regressions, and a heated argument about tone (p. 497-500).
6. The maintainer publishes a numbered backlog (HFR-001 to HFR-035, p. 501) and ships 4.0.1 (p. 504) then 4.0.2 (p. 507) within two months; most P1 items are closed.
7. Sep to Oct 2026: iPad split navigation, image-host dependence, YouTube embeds and the iPhone Duo (foldable) dominate; an outside contributor opens four pull requests (p. 509-510).
8. An Android-client (Redface 2) developer is now an active participant (p. 497-509): cross-pollination between the two clients is visible.

## 1. Versions mentioned

| Version | Date | Announced on | What it was |
|---|---|---|---|
| 2.1.15 | Apr 2021 | p. 450 (user report) | Installed base at the start of the range |
| 2.1.16 | 23 Jun 2021 | **p. 453** | Photo upload fix, signature videos no longer embedded, iPad horizontal swipe fix |
| 2.1.17 | 29 Oct 2021 | **p. 455** | Smiley code and keyword lookup, cache purge fix, moderator alert on iPad, iOS 15 |
| 2.1.18 (post says "2.1.8") | 20 Dec 2021 | **p. 455** | Favourite smileys in two taps, new favourites section, time placement fix; Christmas theme |
| 2.1.20 | 23 Dec 2022 | **p. 462** | New MP screen, new link-share screen, iOS 16 support, smiley popup and quote-redirect fixes |
| 2.1.21 (104) | by Feb 2023 | p. 463 (user report) | Presumably carries the three fixes announced on p. 463 (spell-check, IMG tags when editing, copy image link) |
| 2.1.22 (107) | by Feb 2025 | p. 474 (user report) | Last version of the previous publisher |
| 3.0 "Blue Edition" | 12 Apr 2025 | **p. 478** | First release by the new maintainer |
| 3.0.1 (15) | 24 Apr 2025 | **p. 482** | Fix release |
| 3.1 (29) | 14 Jul 2025 | **p. 484** | Forum search, quote splitting, manual blacklist entries |
| 3.2 (42) | 28 Dec 2025 | p. 489 (TestFlight), p. 490 (store) | Christmas theme back, iOS 26 fixes |
| 3.2.1 (44 to 46) | 31 Dec 2025 to 4 Jan 2026 | **p. 491** | iPad launch crash fix, previous/next page in topic menu |
| 4.0 (beta build 2) | 25 Mar 2026 | **p. 493** | SwiftUI rewrite, beta |
| 4.0 | 4 Jun 2026 | **p. 495** | SwiftUI rewrite, store release, iOS 17 to 26 |
| 4.0.1 (21 beta, 26 store) | 14 Jun beta, 30 Jun 2026 store | p. 502 (beta), **p. 504** (store) | 22 listed fixes |
| 4.0.2 (30) | beta late Aug, store 30 Aug 2026 | p. 507 | iPad split navigation, rich editor |

Platform versions that triggered breakage: iOS 15 (p. 454-455), iOS 16 (p. 459-462), iOS 16.4 (p. 463), iOS 17 (p. 465-467), iOS 18 (p. 471-473, 487-491), iOS 26 (p. 485-491, 504-507), iOS 27 (works on 4.0.2, p. 508).

---

## 2. Tables

Columns: topic, what users say, frequency (about the number of distinct user messages), first and last page where it appears, status at the end of the range. Statuses: **fixed**, **open**, **unclear** (no report after some point, cause not stated).

### 2.1 New in recent versions (what appeared, how it was received)

| Topic | What users say | Freq | Pages | Status |
|---|---|---|---|---|
| 2.1.16 fixes (upload, signature videos, iPad swipe) | Relief; "the swipe is back" for iPad readers; some had to update before upload worked | ≈10 | 453 (to 454) | fixed |
| 2.1.17 smiley code and keywords lookup | Called great (p. 455); keyword title bug found later (see 2.2) | ≈6 | 455 | fixed (title bug fixed in 3.0, p. 477) |
| 2.1.18 favourite smileys and Christmas theme | Warm welcome, many thanks; about ten asked to keep the festive theme all year; green camera dot was the auto-theme light-sensor trick (by design) | ≈40 | 455-457 | delivered; theme only in December |
| 2.1.20 new MP screen and share-link screen | MP screen with avatars liked; the split of actions (tap left = user, "+" = message) judged less ergonomic by a few, most expected to get used to it | ≈15 | 462 | accepted |
| Filter posts (quoted at least 3 times, plus love-list posts) | Requesters delighted when told it already existed; discoverability poor (long-press a favourite) | ≈8 | 466, 469 | delivered; broken again p. 492; present in 4.0 (p. 500) |
| 3.0 default "modern" post layout, blue icon, pruned settings | Thanks ≈14, but ≈25 messages on the layout (lost horizontal space, thin separators; most switched to "classique"), ≈11 on the blue icon, ≈8 on a manual theme not persisting | ≈70 | 478-483 (echo 509) | mostly fixed in 3.0.1 and 3.1 |
| 3.0.1 | Thanks; password-manager fields, manual theme, in-topic search panel fixed | ≈4 | 482 | fixed |
| 3.1 forum search, quote splitting, manual blacklist entries, Classic Red icon | Enthusiastic about quote splitting and the old icon; splitting breaks code and fixed-width blocks | ≈15 | 484-485 | delivered; split inside code unclear |
| iOS 26 build, 3.2, 3.2.1 | Look: "Android-like", dead space under the tab bar (≈6) vs a few positive; iPad crash at launch after 3.2 (≈10 reports), fixed by 3.2.1; sub-category button removed on iPad (≈4) | ≈45 | 485, 490-492 | partly fixed |
| **4.0 SwiftUI rewrite** | Roughly 100 messages of appreciation (look, fluidity, image sending, "last 3 pages" picker, swipe works again), ≈85 reporting regressions (see 2.2, 2.7), ≈65 about tone and etiquette | ≈520 posts in 13 pages | 493-505 | ongoing |
| 4.0.1 (22 fixes) | "Impeccable", third-party keyboard back, swipe-back reliable; multi-quote still confusing, setting added to make "+" include multi-quotes | ≈15 | 502-505 | mostly fixed |
| 4.0.2 | iPad users happy about the returned left navigation, then ≈5 state bugs on iPad | ≈15 | 507-509 | partly fixed |
| iPhone Duo (foldable) support | Enthusiasm; internal screen shows the phone layout; a contributor submits native Duo support | ≈10 | 508-510 | open |

### 2.2 Complaints (bugs, regressions, UX pain; whole range)

| Topic | What users say | Freq | Pages | Status |
|---|---|---|---|---|
| Stale session | Favourites visible but MP or Apple category missing ("not a member of this category"); posting shows the success page but the post never appears; "you must be registered to post"; cure is remove the account and log in again | ≈30 | 450-491 | open as workaround, no report after p. 491 (unclear) |
| Token expiry | Session lapses after about 29-30 days unused; the app still looks logged in; the "expires in N days" label confuses newcomers | ≈12 | 450, 454, 463, 470-471, 481 | open (maintainer: security feature) |
| Login and password edge cases | Hyphen or special characters rejected; password changed on the site breaks the app and no screen updates it | ≈6 | 450-451, 454, 459, 477 | unclear |
| Image host failures | Invalid API key (p. 452), "Erreur 0 (null)" (p. 460), disk full (p. 470), AI-moderation false "adult content" and connection refused (p. 469-470), migrations (p. 458, 471-473, 489), page load blocked when the host is down (p. 506) | ≈28 | 452-506 | recurring, fixed server-side each time |
| Cannot delete uploaded images | Deleting in the app only clears the local list; uploads are anonymous (guest API); users want a disclaimer or real deletion | ≈14 | 450, 458, 461 (×5), 466-467, 469, 480-481, 489 | open (backlog, p. 489); API may return a delete URL (p. 481) |
| Thumbnails open blurry | Tap shows the enlarged thumbnail; workaround is long-press "open link"; hi-res depends on the host | ≈12 | 461, 470, 476-477, 482, 509 | open by design, per-host heuristics |
| Crash after uploading small images | Reply screen crashes until reinstall | ≈10 | 471-472 | fixed (upload-site parameter, p. 472) |
| Image gallery lost | After removing the photo-viewer library, no swiping between images of a post; close button stuck on iPad | ≈9 | 479-483, 485, 503, 505 | partly open |
| Wrong content after resume | Topic title and body mismatched; MP and favourites tabs show the same topic after the app was in background | ≈12 | 451-474 | unclear (not reported after p. 474) |
| Last-read position | Opens at the top, lands on own reply instead of last read, shifts when images load, flag tap jumps to page top | ≈14 | 454, 467, 468, 479, 497-498, 504 | partly fixed in 4.0.1 |
| Swipe and back conflicts | iOS 18/26 sends right-swipe to the topic list instead of previous page; edge-swipe unreliable in 4.0 | ≈20 | 488-492, 500-501 | mitigated (menu buttons p. 491; edge swipe fixed in 4.0.1) |
| Pull-to-refresh | Missing in the 4.0 beta, then needs a longer pull than before | ≈14 | 493-496, 501-503 | fixed (p. 503) |
| Dead quote links | "X a écrit" links and internal post links do nothing | ≈8 | 451, 455, 460-461 | fixed in 2.1.20 |
| Favourites list behaviour | Topic vanishes once read; no way to list read favourites; cannot unfollow from category tabs; list not refreshed on return | ≈20 | 452-454, 458, 466, 468, 507, 509 | by design, partly unclear |
| Multi-quote and "+" reply | "+" does not carry selected quotes any more; leftovers remain after posting; quote and quote-without-quote unclear | ≈35 | 497-505 | setting plus fixes; leftovers open (p. 505) |
| Composer glitches | Text area hidden by keyboard or smiley panel, cursor jumps, sheet swipe-down destroys the draft, last line unreachable | ≈14 | 451, 454, 498-499, 501, 504, 506 | partly fixed; open p. 506 |
| Keyboards | External keyboard shortcuts (p. 455-456), third-party keyboards such as SwiftKey reset to the Apple one (p. 457, 496-497) | ≈10 | 455-457, 496-497 | fixed in 4.0.1 |
| Spell-check, translate, link paste | Spell-check dead (p. 462), translate crash (p. 473, not reproducible), paste-link helper lost (p. 497) | ≈8 | 462, 473, 497 | fixed / unclear |
| YouTube embeds | No full screen or open-in-YouTube (p. 451, 466, 477), error 153 on iOS 26 (p. 489), preview black with error in 4.0 (p. 494) | ≈25 | 451-508 | open; replaced by plain links in a 2026 beta (p. 509) |
| Smiley UI | Stale keyword title, apostrophe path bug on iOS 18, scroll not reset, history lost, search missing in 4.0 beta | ≈14 | 450-501 | fixed |
| Options removed in 3.0 | Image loading mode (never, Wi-Fi), system-browser choice, full-black theme | ≈20 | 481-488, 509 | partly restored in betas |
| Theme not saved | Manual dark or light resets at relaunch | ≈8 | 458, 478-481 | fixed in 3.0.1 |
| Icon | Blue icon unwanted, dark-mode icon variants broken on iOS 26 | ≈19 | 478-482, 487-489, 493 | red restored (3.1, 4.0); dark variant open |
| iOS-version regressions | Invisible scrollbar (iOS 15), white menus (iOS 16), heavy arrows (16.4), MP tab broken (26.5 beta) | ≈25 | 454-464, 504-507 | fixed or tracked as OS bugs |
| Crashes | New-topic sub-category picker, link icon on iPad, iPad launch (3.2), last page of this topic (p. 508, not reproducible) | ≈25 | 465, 472-473, 487-488, 490-491, 508 | mostly fixed |
| Performance | Sticky lists, first row long-press in low-power mode, favourites lag in 3.x (p. 492), page waits for images (p. 506) | ≈14 | 452, 466, 492, 506 | partly |
| Account deletion mail | A user believed the app mailed a deletion request on its own; code only opens a compose sheet, required by App Review | ≈4 | 483 | by design |
| Blacklist | Lost on update (p. 483), cannot report a blacklisted user's post (p. 458), rows could be hidden entirely (p. 483, 494) | ≈6 | 458, 483, 494 | fixed (manual add p. 484, hide option p. 495) |
| 4.0 density and look | Less content per screen, dark mode too grey, flag dots replaced by tinted rows, new-post separator less visible | ≈30 | 494-499, 504 | backlog P3 (HFR-012 to 016), partly open |

### 2.3 Still complained about at the end of the range (p. 505-510 and unresolved themes)

| Topic | What users say | Freq | Pages | Status |
|---|---|---|---|---|
| Multi-quote leftovers | Selected quotes persist after posting; an edit may re-post a quote | ≈4 | 505 | open (maintainer could not reproduce) |
| iPad state handling | Detail pane empty or stale after app switch; tapping a favourite marks it read but does not open it; side menu retracts; MP sheet from a profile missing; list always visible in portrait | ≈8 | 507-509 | open |
| Embedded YouTube | Black player or dead "watch on YouTube" | ≈3 | 508 | beta replaces embeds with links |
| Blurry thumbnails | Tap on a thumbnail opens the thumbnail; ask for a hi-res lookup | ≈3 | 509 | open by design |
| Image host dependence | A host outage froze page loading; avatars only appear after a refresh on first sight | ≈6 | 505-506, 510 | beta fix for loading (p. 507); avatars by design |
| Cache growth | App storage keeps growing and there is no purge control | ≈3 | 490, 508 | open (automatic purge promised, p. 508) |
| Read favourites hidden | Opened topic disappears at refresh; the "show empty categories" button does nothing when "sorted by category" is off | ≈6 | 507, 509 | cause understood (p. 507) |
| Editing | Cursor jumps to end after the first inserted character; reply field scroll bug returned | ≈2 | 506 | open |
| Phantom AQ badge | Red badge for new Alertes Qualitay although none | ≈3 | 506, 509 | cleared by itself (p. 509) |
| Theme details | No full-black dark theme; untranslated label | ≈2 | 508-509 | unclear |
| Foldable | iPhone Duo shows the phone layout on the inner screen | ≈4 | 508-510 | open |
| Search by date | No way to search a topic from an approximate date | ≈1 | 507-508 | not possible on the site |

### 2.4 Open bugs (reproducible issues still reported in the last pages)

| Topic | What users say (repro hint) | Freq | Pages | Status |
|---|---|---|---|---|
| Multi-quote leftovers | Tick "citer" on several posts, post, reopen the reply sheet: old quotes are back | ≈4 | 505 | open |
| In-app link browser returns to the list | Open a link in the sheet, press the Safari button, return: app lands on the topic list (iPad Pro, iOS 26) | ≈2 | 506-507 | open; maintainer reproduced on an old iPad |
| iPad selection and restoration | Choose category, topic, switch app, return: "no topic selected"; or row tap ignored but topic marked read | ≈3 | 508-509 | open |
| iPad profile MP sheet | After tapping a profile, "MP" opens nothing until the sidebar is toggled | ≈1 | 507 | open (fixed in beta, p. 509) |
| Embedded YouTube | Error 153 or black player on iOS 26 | ≈9 | 489-508 | beta disables embeds |
| Composer | Cursor jumps to the end on mid-text edit; scroll does not follow cursor on long text | ≈3 | 506 | open |
| Gray block at the bottom | Keyboard background remnant after keyboard closes (also in Messages) | ≈3 | 507 | iOS behaviour, workaround reopen keyboard |
| Page load hang | A pending image request keeps the whole page blank | ≈5 | 506 | beta fix |
| Avatars missing on first sight | Some posters show no avatar until refresh | ≈2 | 505, 510 | by design (cache) |
| Favourites toggle button | "Show empty or collapsed categories" does nothing when sorting by category is off | ≈4 | 507 | understood, fix pending |

### 2.5 Expectations and feature requests

| Topic | What users say | Freq | Pages | Status |
|---|---|---|---|---|
| Global search and search inside a category | Missing since Apple removed it (jailbreak results); ask to show it only when logged in | ≈14 | 460-476 | delivered in 3.1 (p. 484), in 4.0.x (p. 505-506); date filter requested (p. 507) |
| Open forum links in the app | Universal links, Safari extension, clipboard detection; Android client did it | ≈13 | 455, 464 (×7), 473-474 (×4), 481 | open; the site's association file is in an old format and shows no banner (p. 474) |
| Notification when quoted, push for followed topics | Needs server-side info the forum does not give; a manual or foreground scan is considered | ≈10 | 451, 468, 470, 487 (×5), 494 | open |
| Unfollow or mark read from every list | Swipe actions in category tabs | ≈8 | 454, 458, 466, 468 | unclear (read-marking fixed in 3.0.1, p. 482) |
| Page count in header, jump-to-page | Total pages near the title; page picker | ≈6 | 469-470, 502 | delivered in 4.0 (p. 498) |
| Image tools | Delete own uploads, hi-res from thumbnail, browse a series, choose when to load images, paste from clipboard | ≈30 | 450-509 | partly delivered |
| iPad and big screens | Multi-window, persistent topic list, forced columns in portrait, Mac app, Mac font zoom, Apple Watch | ≈25 | 450, 458, 461, 466-467, 480, 484, 496, 500, 507 | multi-window in 4.0.1; Mac and Watch not delivered |
| Foldable | iPhone Duo native layout | ≈10 | 508-510 | open |
| Font size and Dynamic Type | Larger text in lists and composer; later, also smaller | ≈10 | 472, 477, 486, 495, 496 | partly delivered (3.0, p. 478) |
| Seasonal and custom themes | Keep the Christmas theme all year or add one per season; auto-enable; colour choices; full black | ≈25 | 456-457, 464, 468, 474, 490, 509 | Christmas returned in 3.2; rest open |
| Reply UX | Preview before send (p. 452), visible reply button (≈10, p. 475-477), quick-reply bar above the tab bar (p. 484), BBCode toolbar (p. 505), keep drafts safe | ≈20 | 452, 475-477, 484, 498-505 | partly delivered |
| Infinite scroll | Maintainer floats it; reactions split: a few in favour, about eight want it optional or not at all | ≈14 | 475, 479-480, 501-505 | pending |
| Launch screen and tab behaviour | Choose the start tab; keep the footer bar; reduce bar on scroll | ≈8 | 484, 497-498, 502 | delivered in 4.0.1 |
| Filter posts options | Include moderation posts; local search in the flag list; filter categories by flag | ≈4 | 483, 486, 495 | open |
| Blacklist control | Manual add, hide fully, sync with the shared MP-storage document | ≈6 | 472, 483, 494 | delivered |
| Usage analytics | A user suggests measuring feature use; maintainer cites GDPR and App Review | ≈2 | 486 | declined for now |
| Quote and formatting editor | Quote splitting, tag buttons, colours, clipboard insertion | ≈6 | 484, 505, 507 | delivered |
| Donations | Platform debates (PayPal, Leetchi, in-app purchase refused for the 30 % fee) | ≈65 | 451-509 | cash pot, app stays free |

### 2.6 Praise of the Android app (Redface, Redface 2) and what users envy

Direct envy is scarce (about eight user messages). Most mentions are identity (the red icon) or developers comparing notes.

| Topic | What users say | Freq | Pages | Status |
|---|---|---|---|---|
| Readability with colour | Two newcomers from Android miss the colourful red theme, with coloured category names, and ask for it | ≈2 | 454, 464 | partly (custom colours later) |
| Links open the app | On Android a forum link from a browser opened the client; iOS needs site cooperation | ≈2 | 464 | open |
| Highlight posts that quote me | Request to match the Android client | ≈1 | 466 | exists (action colour) |
| Automatic seasonal theme | Another Android client switches itself on | ≈1 | 468 | partly |
| Red icon and "red face" identity | Users keep the red face as a badge; many asked for it back after the blue 3.0 icon | ≈14 | 479-482, 484, 487-488, 495 | restored (Classic Red 3.1; red icon in 4.0) |
| Liquid Glass "looks like Android" | Said as a criticism of iOS 26 menus | ≈3 | 485 | n/a |
| Android-client developer input | Declared a quote notification infeasible in a mobile client (request cost, battery, per-minute limits, p. 487); describes anonymous page prefetch into a cache, a recoverable draft system, a hi-res image viewer with a host adapter table, a shared mock-up for the topic view (p. 502-509) | ≈10 | 487, 497, 502-509 | information |

### 2.7 Nostalgia for previous versions

| Topic | What users say | Freq | Pages | Status |
|---|---|---|---|---|
| Classic post layout | Banner above each post, full width text, clear separators; "modern" wastes a column (iOS 3.0 default) | ≈25 | 478-481, 486, 490 | classic mode kept |
| iPad left favourites panel | Landscape iPad lost the left list in 4.0; asked back in a dozen messages | ≈15 | 495-496, 500, 507 | returned in 4.0.2 (p. 507) |
| Old "+" reply behaviour | The reply button used to carry selected quotes; the 4.0 "Citer" must be pressed on the last quote | ≈25 | 497-505 | setting added (p. 504) |
| Footer: refresh and page controls | First, previous, page number, next, last; double-tap on the star to refresh favourites | ≈12 | 494-497, 502 | menu entries; partly |
| Flag dots | Coloured dots were easier to read than tinted rows | ≈4 | 497, 504 | open (P3) |
| Dotted new-post separator | More visible than the 4.0 line | ≈5 | 495, 497, 499 | open (backlog P3, HFR-015); end-of-page cue improved in 4.0.1 (HFR-008) |
| Image browsing | Swiping through a series of images | ≈6 | 479, 482, 505 | open |
| Removed settings | Image loading mode, system browser, full black | ≈15 | 481-488, 509 | partly restored |
| Seasonal charm | Christmas snow and theme missing some years | ≈10 | 462, 468, 474 | returned |
| "Perfect at 95 %" | Some users felt the rewrite brought no new feature | ≈6 | 498-499 | maintainer: technical debt first |
| Old app on the store | Request to publish 3.2.1 alongside 4.x (duplicates are rejected by App Review) | ≈2 | 508 | declined |

---

## 3. Implications for SwiftHFR

Legend. **Covered**: a LOT clearly owns the engine part. **Partial**: engine part exists, app behaviour or a detail is missing. **Missing**: no LOT or backlog line.

### 3.1 Coverage matrix (important items)

| # | Finding (pages) | Plan coverage | Comment |
|---|---|---|---|
| 1 | Stale sessions and false "posted" pages (≈30, p. 450-491) | Covered: LOT-042, 043, 044, 037, 048, 065 | Make the classifier treat "success page but no new post" and "read ok, write refused" as a session fault, re-login silently from the Keychain, add fixtures for each; surface an expiry date once, with a plain-language label |
| 2 | Login and form encoding (accents, hyphen, password change) | Covered: LOT-040 (encoding), LOT-043 | Add a "update password" action for an existing account |
| 3 | Apple category and search hidden for reviewers | Covered: LOT-021, 046, 055, Phase 4 App Review policy (Q-7) | Same trigger (logged out or review account) must hide Apple category and the search entry point |
| 4 | Global and in-topic search (≈14) | Covered: LOT-046 | Also model sub-category scope and the "view in unfiltered topic" jump from results (bug p. 489) |
| 5 | Quote, multi-quote, quick reply (≈35 in 4.0) | Covered: LOT-049, 036, 042 (multi-quote cookie), 048 | Default "reply" must include selected quotes; always offer a reply without quote; decode HTML entities in the prefill (the `&#034;` leak, p. 494); editor niceties (split quote, tag toolbar, link paste) are Phase 4 and **not listed** |
| 6 | Image upload and anonymity (≈42) | Covered: LOT-056, 012, 071, ADR 0007 | Keep API key injectable; plan human-readable errors, timeouts, retry, size choice, upload history; capture a delete URL if the API returns one (p. 481); disclose that uploads are anonymous and permanent; note the host once used a third-party AI moderation service (p. 469-470) |
| 7 | Thumbnail to hi-res (≈12) and image viewer | Partial: LOT-034 (typed images) | No lot owns a host table (`.th`, `.md` suffix removal, hot-link blocks on third-party apps p. 479); app-side viewer with gallery and long-press "open link" is Phase 4 and not listed |
| 8 | YouTube embeds (≈25) | Partial: LOT-035 (embed detection) | Add a fallback: when the embed fails (error 153), degrade to a link; make embed vs link a setting |
| 9 | Favourites and flags management (≈20) | Covered at engine level: LOT-024, 051, 064, 010 | App rules to adopt: swipe unfollow and mark read in every list, show read favourites, collapse categories, keep reading position; MP "mark unread" and "delete MP" (done in 4.0.1) are **not** in LOT-048/051 |
| 10 | Reading position and back stack (≈14 + 20) | Partial: LOT-033, 045, Phase 4 page shell (C13) | Drop the repeated first post of each page ("Reprise du message précédent"), anchor on the post id (`#t<id>`), do not wait for images before showing the page (p. 506), keep a navigation stack that survives iOS killing the app |
| 11 | Filter posts (quoted at least 3 times, love-list) | Covered: Phase 4 C11, LOT-032 | Needs sequential fetching of all pages between flag and last page: throttle, cache, manual trigger first (maintainer's own conclusion, p. 487) |
| 12 | Quoted-me alert, followed-topic push (≈10) | Partial: LOT-047 (MP poll), C11 | No server, so no real push; allow an in-app badge after a manual or foreground scan; background poll every 20 minutes for MP (p. 486) |
| 13 | AQ feed (host moved in 2023, p. 463-466; links broken in 4.0, p. 495-504) | Covered: LOT-055 (blocked on Q-4) | Feed URL must be configuration, links must jump to the flagged post, optional badge (p. 506) |
| 14 | Blacklist, love list, MP-storage sync (≈10) | Covered: LOT-061, 062, 052, 038 | LOT-067 (legacy import) is dropped, so MP storage is the only migration path: raise its priority; validate page >= 1 before writing (page 0 overwrite bug, p. 474); "never overwrite with empty" matches the loss reported on p. 483 |
| 15 | Smileys (≈14) | Covered: LOT-053, 064, 012 | Percent-encode apostrophes in smiley URLs (p. 472); forum favourites capped at about ten, local list unlimited (p. 466) |
| 16 | Drafts | Covered: LOT-063 | Users want both: keep text after accidental dismissal, and a clear way to discard (p. 498, 504) |
| 17 | Polls | Covered: LOT-026, 054 | Poll creation (HFR-028, p. 501) is not in the plan |
| 18 | New topic, sub-category picker crash | Covered: LOT-048, 014 | Add UI test for the picker |
| 19 | Account deletion mail | Covered: Phase 4 (Q-10) | Show what will be sent before opening the compose sheet (p. 483) |
| 20 | iPad and foldable (≈45) | Partial: Phase 5 (column navigation, foldable) | Persistent favourites and topics column in landscape, multi-window scenes, restoration per column, a two-pane layout on the Duo inner screen |
| 21 | Open forum links in the app (≈13) | **Missing** | Needs an inbound URL router (use LOT-041 shapes) plus the site's association file; interim: clipboard detection |
| 22 | Dynamic Type for post content (≈10) | **Missing** as a requirement | Message HTML builder and page shell (C12, C13) must scale text with system settings and offer smaller sizes |
| 23 | Themes, icons, seasonal theme (≈40) | Partial: Phase 4 "alternate icons" | Dark and tinted icon variants must come from the asset catalog (maintainer failed with PNG overrides, p. 489); seasonal theme is not listed |
| 24 | Non-BMP characters (emoji) lost by the forum (p. 478) | **Missing** | Warn or transcode outgoing text before posting |
| 25 | Offline reading (LOT-068) | Covered | Very low demand: two reports and a maintainer doubting usage (p. 472) |
| 26 | Haptics, tab bar settings UI, static pages | Covered: Phase 4 backlog | Haptics asked on p. 486 |
| 27 | Background MP badge after notification permission change (p. 488) | Covered: LOT-047 plus app scheduling (NET-13) | Re-check permission on launch |
| 28 | Throttling and prefetch | Partial: LOT-045 | An Android client prefetches the next page anonymously into a cache (p. 502); consider after parity |

### 3.2 Gaps to consider adding to the plan

1. Inbound link router and share targets (finding 21).
2. Editor features: split quote, tag toolbar, outgoing-text sanitiser for non-BMP characters (24).
3. Image host adapter table and viewer (7).
4. MP maintenance flows: mark unread, delete (9).
5. Navigation state restoration contract for Phase 4 (10, 20).
6. Dynamic Type requirement for the page shell (22).
7. Poll creation (17), low priority.

### 3.3 Top 10 priorities

1. **Honest write path and session life cycle.** One concept for "logged in" that survives expiry, password change and half-valid cookies; never show "posted" unless the post exists (LOT-042, 043, 044, 037, 048, 065). It is the most persistent pain for five years.
2. **Reply, quote and multi-quote that match muscle memory.** The 4.0 split between "+" and "Citer" produced the largest sustained thread; the old behaviour (reply carries all selected quotes) should be the default (LOT-049, 036, 042, 048, 063).
3. **Reading flow fidelity.** Reliable last-read position, new-post separator, back stack, page controls; never block rendering on images (LOT-033, 045, 030, page shell).
4. **Favourites and flags parity.** Swipe actions everywhere, read favourites visible, category collapse, mark-read synchronisation, flag colours (LOT-024, 051, 064, 010).
5. **Image pipeline and resilience.** Upload client with clear errors, size choice, history, anonymity notice; thumbnail to hi-res; gallery; no dependence of page load on the image host (LOT-056, 071, 034, 066).
6. **Search and filter posts.** Global, in-topic, sub-category; filter for heavily quoted posts with throttled sequential fetching (LOT-046, C11).
7. **iPad, landscape and foldable layout.** Keep a favourites and topics column, support multiple windows and restoration (Phase 5; the 4.0 rollout shows how loudly this is missed).
8. **Awareness without push.** MP badge poll, quoted-me badge on refresh, AQ badge optional (LOT-047, 055, C11).
9. **Blacklist and personal data continuity.** MP-storage sync is the migration path since legacy import is dropped (LOT-061, 062, 052, 038).
10. **Accessibility and personalisation.** Dynamic Type for post content, full-black theme, seasonal theme, dark icon variants, a small set of settings people actually missed: image loading policy, system or in-app browser, classic vs modern layout, start tab, "+" behaviour (LOT-060, Phase 4).

### 3.4 Process lessons from the 4.0 rollout

- Changing defaults silently (3.0 layout, 4.0 navigation) cost more goodwill than any bug. Ship a "what changed" screen and keep a classic option for at least one release.
- A public numbered backlog (p. 501) and a fast fix cadence (22 items in two weeks) calmed the thread; the beta channel was too small to surface muscle-memory regressions (p. 498-500).
- Users answered best to concise, cold, reproducible reports; plan an in-app "send diagnostics" path (a user praised the existing one, p. 487).
- Pruned settings are the second biggest source of complaints; do not delete without replacement.
- The publisher account is a single point of failure (two store disappearances); document account ownership and renewal for SwiftHFR.

---

## 4. Protocol notes (facts visible in the fetched HTML)

- **URL shape.** `https://forum.hardware.fr/hfr/<category-slug>/<topic-slug>-sujet_<topicId>_<page>.htm`. The slug is not authoritative: a wrong slug returns **301** to the canonical URL; a page number beyond the last returns **302 Found** (with a `Status: 404 Not found` header) to the last page. LOT-045 must follow redirects and read the final URL.
- **Encoding.** `Content-Type` charset UTF-8 in the meta tag.
- **Messages.** Each post is a `table.messagetable` with `tr.message.cBackCouleurTab1/2`; pseudonym in `b.s2`, anchor `<a name="t<postId>">` (also `title="n°<postId>"`), date in `.toolbar .left` as `Posté le dd-mm-yyyy à hh:mm:ss`, body in `div#para<postId>`.
- **Ad rows.** Three extra `messagetable` rows per page with pseudonym `Publicité` and no `div#para…`; skip rows without the body id.
- **Repeated post.** From page 2 on, the first post of a page repeats the previous page's last post, prefixed in bold by `Reprise du message précédent :`; 40 new posts per page. A parser that counts posts or advances an "unread" cursor must drop it.
- **Pseudonyms.** A zero-width space (U+200B) is injected into long names (for example after about ten characters or after a space); strip it before comparing identities. Deleted accounts show `Profil supprimé`, no profile link.
- **Profile.** `/hfr/profil-<userId>.htm`. The mood line sits in `span.MoodStatus`.
- **Quotes.** `div.container > table.citation` with header `b.s1 > a.Topic` pointing to `/hfr/<cat>/<slug>-sujet_<id>_<page>.htm#t<postId>` (the page number is baked in; if it differs from the reader's own pagination the anchor misses, which plausibly explains the dead "X a écrit" links). Spoilers are `table.spoiler` with `div.Topic.masque`; code is `table.code` with `ol.olcode`; fixed-width is `table.fixed`. `oldcitation` does not occur in this range.
- **Edited marker.** `div.edited` contains `Message cité N fois` (link to `/forum2.php?config=hfr.inc&cat=25&post=1711&page=1&p=1&sondage=&owntopic=&trash=&trash_post=&print=&numreponse=<postId>&quote_only=1&new=0&nojs=0`) and `Message édité par … le dd-mm-yyyy à hh:mm:ss`.
- **Stable permalink.** Users on p. 460-461 point out that `forum2.php?...&numreponse=<postId>` is page-size independent whereas `…_<page>.htm#t<postId>` is not; the legacy app shared the second form. Prefer the first for sharing.
- **Obfuscated links.** Action links such as quote are `span.md_noclass_cryptlink<HEX>` (and `md_cryptlink<HEX>` in menus), the target URL is hex-encoded (matches the decoder in LOT-020).
- **Signature.** `span.signature` after a line of dashes, always at the end of the body; strip before content analysis. Smileys are `img` from `forum-images.hardware.fr/icones/*.gif` with the code in `alt`.
- **Pagination block.** `tr.cBackHeader.fondForum2PagesHaut` lists pages 1 to 5, the neighbours of the current page (in `<b>`), and the last five; `div.pagepresuiv` carries previous and next links; a "go to page" form posts `page`, `post`, `cat`, `config`, `p`, `sondage`, `owntopic`.
- **Search forms.** The form at the top of the topic page (apparently the in-topic search) is `form action="/transsearch.php"` with hidden `post`, `cat`, `config`, `hash_check` (empty when logged out); the global search page is `search.php` (a link with `…&subcat=0` was shown on p. 475).
- **Multi-quote cookie.** The page script clears the list through a cookie named like `quoteshardwarefr-<cat>-<topic>` (value shown in `vider_liste('quoteshardwarefr-25-1711')`), consistent with the per-topic cookie rule in LOT-042.
- **Session behaviour** (*reported by users, unverified*). Login cookie lasts about 29 days; with a half-valid session reads succeed, MP and restricted categories answer "you are not a member of this category", and a post returns the success page ("hooray!") without creating the post; a site message "Désolé, vous devez être enregistré pour poster" appears in the other variant. Fixtures for both are worth capturing (LOT-037).
- **Image hosts.** The app's own host (`img3`) exposes `.th` (thumbnail) and `.md` (medium) suffixes; removing them yields the full image (p. 460, 477, 509). Another community host hot-link-protects its images, so third-party apps get a placeholder (p. 451, 479). The app's host is Chevereto-based, uploaded anonymously with an API key; the host dropped the AI moderation service after false positives (p. 470).
- **Emoji.** The forum drops every character outside the Basic Multilingual Plane (legacy 3-byte MySQL collation), and everything after it (p. 478).
- **MP storage.** A private-message document stores JSON for synchronisation; shared lists look like `blacklist: {sourceName, list: [{createDate, username}], active, lastUpdate}` (p. 472); the legacy app wrote page 0 into a stored position after a page-number error (p. 474).
- **Rate limits** (*reported, unverified*). An Android-client developer believes the forum limits calls per minute (p. 487); the iOS maintainer plans one topic every ten seconds for background scans. Nothing was measured here.
- **Forum engine.** Footer of the site shows an engine version dated 2010 (p. 487); the admins add features rarely (multi-recipient MP is cited) and the site does not expose "who quoted me" data.
- **Site chrome.** The site title tag carries the current topic title (4.0.2) on every page, so use the redirect result, not the title, as identity.

---

## 5. Caveats

- Counts are impressions backed by keyword checks; a message mixing two themes is counted once per theme.
- The thread is a support channel: it over-represents bugs and enthusiasts, under-represents silent users. 170 authors over five years is a small, loyal, mostly adult community (a recurring joke in the thread).
- Behaviour of iOS 26 and 27 is as reported by users, not tested.
- No personal data, pseudonyms or long quotes are kept in this note.
