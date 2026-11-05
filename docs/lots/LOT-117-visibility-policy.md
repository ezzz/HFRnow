# LOT-117 — Blacklist / whitelist in the reader (visibility policy)

- **Module:** App (`App/SwiftHFR/Reader/`)
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#208](https://github.com/ezzz/HFRnow/issues/208), GAP-066; "Egopost / Egoquote" acceptance criteria added in the issue (HFR+ topic, 2026-10-28)
- **Depends on:** LOT-061 (pseudo lists), LOT-083 (reader), LOT-032 (quote analysis): all merged. The lists reach the reader through `PseudoLists`, filled by LOT-118.

## Legacy sources
Legacy repository <https://github.com/ezzz/HFRnow> at `2440d79`, read only.

| Legacy | Used for |
|---|---|
| `HFRswift/Wrapped/LinkItem.m:26-28, 44-53` | message class: `mode` (author is "Modération"), then `me` (own pseudo, case-insensitive), then `whitelist` (`isWL:`), then `bl` (`isBL:`) |
| `LinkItem.m:80-93` | a blocklisted author's quote: a "pseudo a écrit :" line with a ▼ button, the quote itself hidden; with `blacklist_hide_pseudo` the line reads "Citation masquée" |
| `LinkItem.m:277-296` | a blocklisted message: collapsed to a line holding the pseudo (empty with `blacklist_hide_pseudo`) and a ▼ button that shows it |
| `HFRswift/Wrapped/ParseMessagesOperation.m:205-224` | quote tables classed by author: `citation_me_quoted` (own pseudo, "Egoquote"), else `citation_whitelist`, else `citation_blacklist` |
| `Classes/BlackList.m:110-143` | `isBL`, `isWL` (false for a blocklisted pseudo), matching (LOT-061/072) |
| `HFRswift/Wrapped/MessagesTableViewController.m:1401` | comment "Ego quote not applyed on MP" |
| `SuperHFRplus/Assets/HTML/style-liste-light.css:14-24, 145, 314-325, 359-390` and `HFRswift/Swift/MessagesView.swift:2397-2410` | the tints: own = action colour at 3 % with a 2 px bar, whitelist = love colour, quote of me / whitelisted / blocklisted, moderation |
| `HFRswift/Swift/Common.swift:438-441`, `Classes/ThemeColors.m:376-382` | default love colours (day, night) and the moderation background (day, night) |
| `HFRswift/Swift/AppSettingsView.swift:100, 408` | the setting `blacklist_hide_pseudo` ("Masquer les pseudos blacklistés"), key `SettingKey.hideBlocklistedPosts` |

## Behaviour
Code in `Reader/VisibilityPolicy.swift`, `TopicHTMLBuilder`, `reader.css`, `reader.js`; tests in `SwiftHFRTests/Reader/Visibility*Tests.swift`.

- **`VisibilityPolicy`** (pure, `Equatable`, `Sendable`): `post(by:)` answers `moderation`, `own`, `allowlisted`, `blocked` or `normal`, `quote(by:)` answers `ofMe`, `allowlisted`, `blocked` or `normal` (nil author = anonymous quote = normal). Precedence is legacy's. Pseudos compare by `PseudoNormalizer.comparisonForm` (LOT-072), the rule of the lists. A blocklisted pseudo is never allowlisted.
- **Inputs**: `ReaderSettings.live(store:isOnWiFi:pseudo:pseudoLists:)` builds the policy each time a document is built: the account's pseudo (`AppEnvironment.accountName`, nil logged out), `PseudoLists` (blocklist of the account, global allowlist) and `blacklist_hide_pseudo`. A change makes `ReaderRenderOptions` differ, so `applyDisplaySettings()` rebuilds the shown page without a request. `AppEnvironment` passes empty lists until LOT-118 reaches them: own and quoted-me highlights already work.
- **Messages** (`TopicHTMLBuilder.article`): class `me`, `whitelist`, `mode` or `blocked` on the `article`. A blocked message is a native `<details class="blocked-post">` whose `<summary>` is "pseudo · Message masqué" (no pseudo, and `aria-label` "Message masqué", with the hide setting). The whole message, its `⋯` menu included, sits inside: once opened it can be reported ("Alerter") like any other; no script is needed.
- **Quotes**: `ReaderMessage.quotes` (LOT-032's `MessageQuoteAnalyzer`, read when the page is built) lists the quote tables of the content in document order; `QuoteMarkup.annotate` adds `quote-me`, `quote-allowed` or `quote-blocked` (plus `quote-hide-author`) to the class attribute of the matching `<table>` start tag. The i-th quote table of the sanitized HTML is the i-th typed quote; a count that differs (never seen on the corpus, test over six captures) leaves the content untouched. A blocked quote shows its header row only, with ▼/▲ drawn by CSS; `reader.js` opens it on any tap (the header link does not navigate while collapsed) and a tap on the header line outside its link closes it again.
- **Private messages**: own highlights (`me`, `quote-me`) are off there (`withoutOwnHighlights()`, applied by `TopicHTMLBuilder.document` from the page's category); the lists still apply.
- **Where**: the topic reader, the private message reader and the filtered posts view all build their document with the same builder and options.

## Edge cases
- Own message that is on the account's own blocklist: shown, highlighted (legacy also drew the collapsed header above a `me` message, `LinkItem.m:282`; here the author's own message is never collapsed).
- "Modération" is compared exactly, as legacy (`LinkItem.m:44`); a moderator never counts as own, allowlisted or blocklisted.
- A quote inside a blocked quote keeps its own class; opening the outer one shows it collapsed or tinted by its own author.
- Continuation copies of the previous page's last message follow the same policy as the original.
- A blocked message the reader is sent to by a link (`#t<n>`) scrolls to its collapsed line.

## Intentional differences from legacy
- **Egopost / Egoquote not on private messages**: legacy's comment says so (`MessagesTableViewController.m:1401`) but its `isMP:` argument is never read by `LinkItem.toHTML`, so legacy highlighted there too; the issue's acceptance criterion asks for the commented behaviour ([CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md)).
- The author's own message is never collapsed (above).
- A native `<details>` and a CSS arrow replace the legacy inline `onclick` scripts (the page runs no script, ADR 0006 and LOT-083); pseudos compare by LOT-072's rule rather than "U+200B removed, lower-cased".
- Colours are the legacy defaults in `reader.css` (`--love`, `--love-border`, `--modo`); the user-chosen love colour (`theme_*_color_love`) is not read yet: LOT-121 owns the colours and only has to set `--love` on the document. The border of a quote of me and its light variant are the action colour at 100 % and the quote colour, not legacy's `tintLightColorNoAlpha` (not read).
- Hidden blocked-author avatars still load (the avatar is in the collapsed body), as legacy loaded them.

## Fixtures
No new capture. The quote markup comes from the LOT-001 corpus (`R20`, `R21`, `R22a`, `R26`, `R27`, `R28`); every other case is a synthetic snippet marked as such in the tests. No HFR fact is added.

## Tests
`VisibilityPolicyTests` (policy cases, quote markup incl. nested, other tables, hostile attribute, count mismatch; documents for own / allowlisted / moderation / blocked, hide setting, private messages; settings; six captured pages) and `VisibilityWebTests` (real web view: blocked quote opens and closes without following its link, tinted quotes and messages, a blocked message is closed until its summary is tapped, hidden pseudo not drawn). The web tests fail without the `reader.css` and `reader.js` changes (shown in the PR).

## Learnings
- Quote tables of the sanitized content can be classed from LOT-032's typed quotes by position, without a second HTML parse in the app; verify the count on real pages, not on snippets only.
