# LOT-027 — Public profile page parser

- **Module:** HFRParsing
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`; audit item F4)

Reads a member's public profile page, `/hfr/profil-<id>.htm` (HFR-PROTOCOL R9): labelled fields in sections, avatar, personal
smileys and link rows. A pure function, `UserProfileParser.parse(html:) throws(ParsingError) -> UserProfile`. Fetching the page is
LOT-045 and later; the avatar of the **logged-in account** (edit-profile page 5) is not this page and not this lot.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Oracle: [LOT-005](LOT-005-small-parsers-oracle.md), kind `profile`
(cases R56a, R56b).

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/UserProfileView.swift:113-430` `UserProfileHTMLParser.parse` (rows, sections, fields, summary) | `UserProfileParser.parse`, `read(row:)`, `readCells` |
| `:296-334` `action(from:…)` (link rows and their kind) | `action(in:sectionTitle:)` |
| `:336-345` `extractAvatarURL` | `avatarURL(in:)` |
| `:347-372` `extractSmilies` | `smileys(in:)`, `codeBefore` |
| `:374-415` `cleanText`, `cleanTitle`, `decodeEntities` | `UserProfileText` (the DOM already decodes entities) |
| `:417-428` `resolvedURL` | `resolved` over `HFRURL.absolute` |
| `:21-95` the view models (`UserProfile`, `…Section`, `…Field`, `…Smiley`, `…Action`, `…SummaryItem`) | the same names in `HFRParsing/Profile/` |

The service half of the file (`UserProfileService`, `:115-137`: GET with a 20 s timeout, UTF-8 then Latin-1 then CP1252 decoding) is a
fetcher concern (LOT-045); the parser takes a decoded string. The result types live next to the parser, as `TopicPageMetadata` does,
because they have no other producer.

## Behaviour

The page is cut by rows of the first `table.main` (the whole document when there is none). Class tests on rows and cells are
**substring** tests, like the legacy regexes.

| Row | Rule |
|---|---|
| `tr` with `cBackHeader` | opens a section titled by the cleaned header text; skipped when empty. Id `section\|<title>\|<n>` where `n` is the number of sections opened before it (headers with an empty title open none), counted before empty sections are removed, as legacy |
| `tr` with `profil` | everything below, in this order |
| avatar | first `img` with a `src` inside the first `avatar_center` element of any `profil` row; the first row that has one wins. Never "the first image of the page" (legacy LOT-005 Q1 concerns the login service, not this parser) |
| personal smileys | every `img` of the row whose `src` contains `/images/perso/`; code = the `[:…]` text right before the image (only whitespace between), else `[:<title>]`, else the file name; title = `title`, else `alt`. A smiley is added once (same code and URL) |
| rows before the first header | contribute an avatar or smileys but no field or action |
| `td.profilCase3[colspan]` | a link row: first `a[href]`; text = cleaned cell; dropped without a link or text. Kind by the lower-cased text: contains `message privé` → `privateMessage`; `tous ses messages` → `allMessages`; `liste de contacts` → `addContact`; section title or text contains `transaction` → `transaction`; else `link`. `subtitle` = the section title |
| `td.profilCase2` + `td.profilCase3` | a field. Title = cleaned label without trailing `:` and blanks; value = cleaned text of the value cell (empty stays empty); `url` = first link of the value cell. A row whose title contains `Configuration` (accents and case ignored) **and** has a link becomes an action of kind `configuration` (title = the row title, no subtitle) and is not a field |
| cleaning | `br` and the end of `p` and `div` are line breaks; U+00A0 is a space; runs of spaces and tabs collapse; every line is trimmed; empty lines are dropped |

After the loop: sections without a field are removed; actions are unique by id; the page is refused (`missingElement`) when there is
no section, no pseudo, no avatar and no smiley.

| Output | Rule |
|---|---|
| `pseudo` | value of the field titled `Pseudo`, zero-width spaces removed (`HFRText.normalizedPseudo`); `""` when absent |
| `status` | value of the field titled `Statut`; nil when absent or empty |
| `summary` | `messageCount`, `joinDate`, `lastMessageDate` items (field titles `Nombre de messages postés`, `Date d'arrivée sur le forum`, `Date du dernier message`), each only when the field has a value; `value` is the printed text |
| `messageCount` | the summary text read as a number (ASCII digits, spaces ignored); nil otherwise |
| `joinDate` | `dd/MM/yyyy` as midnight `Europe/Paris` (through `HFRDate`, which also rejects 31/02); nil otherwise |
| `lastMessageDate` | `dd-MM-yyyy à HH:mm` through `HFRDate.date(from:)`; nil otherwise |
| action URLs | the first link of a link row or of the `Configuration` row, accepted only by the rule of `HFRURL.forumRelativePath` (LESSONS 37) and made absolute against the forum root: `https`, host `forum.hardware.fr`, no user info, no port other than 443, no `//host` path. Anything else drops the action (a configuration row with such a link is then neither action nor field). The app may follow these with the session |
| other URLs | field links, avatar and smiley images go through `HFRURL.absolute`: resolved against `https://forum.hardware.fr/`, `http(s)` only, `http` to the forum upgraded to `https`, user info refused. A raw space in a path is percent-encoded first |

Ids (`field|<section>|<title>`, `action|<kind>|<url>`, `smiley|<code>|<url>`) reproduce the legacy strings; they are opaque keys, not
a format to parse.

## Edge cases
- The page is the same for a visitor and a member in the captures; the "Envoyer un message privé" row, the transactions rows and the
  "tous ses messages" row are present in both (R56a, R56b), so they are not a sign of being logged in.
- `Profile field removed.` is a value that HFR prints for fields the member removed: it is not empty and stays a field value.
- A cell that holds only `&nbsp;` (R56b date of birth, quote) is empty.
- The `Configuration matérielle` row exists on R56b only (member with a configuration), as the first action: rows are read in page order.
- A repeated title in one section gives two fields with the same id (as legacy); no capture has it.

## Fixtures
Captures (`Fixtures/captures/`) with their LOT-005 oracles (`Fixtures/LOT-005/`), both compared **in full** by
`UserProfileOracleTests` (pseudo, status, avatar, summary, every section and field, smileys, actions, ids). The first test fails when
`oracle-map.json` gains a `profile` case that is not in the list.

| Id | Covers |
|---|---|
| R56a | member's own profile as a visitor: no avatar, no smiley, 2 sections (7 + 6 fields), empty values, 4 actions (2 transactions, message, all messages) |
| R56b | another member: avatar, 4 personal smileys, `Configuration matérielle` action, `&nbsp;`-only values, `Profile field removed.` |

`UserProfileParserTests` adds expectations written from reading the captures (dates as instants, action order, no configuration field,
only `https` URLs on two hosts, unique ids) and small inline pages for rules no capture exercises: other URL schemes in the avatar,
smileys, fields and links, the avatar being the `avatar_center` image only, code fallback, a raw space in a smiley path, duplicates,
invalid figures, a header without rows, whole-title matching, line breaks, a page that is not a profile. They state our rules, not facts
about HFR.

**Pending capture** (nothing hand-built): a profile seen **logged in** (does the row set change? is there an `addContact` row, the
"liste de contacts" link legacy looks for?), a profile of a **banned or deleted member**, a profile with a **real birth date and
signature** (HTML or BBCode in a value cell, links in values), a member with a **status other than `Membre`** (modérateur, admin),
a personal smiley with an **apostrophe or space in its file name** (seen on the smiley search, R53b, not on a profile), and an
avatar on a non-`jpg` extension.

## Intentional differences from legacy
1. **Typed figures.** `messageCount`, `joinDate`, `lastMessageDate` are added (`Int`, `Date`); legacy kept strings only. The strings stay
   in the fields and the summary, so nothing is lost.
2. **No display text in the model.** Legacy replaced an empty value by the French text "Non renseigné" and stored `isPlaceholder`; here
   `value` is `""` and `isPlaceholder` is `value.isEmpty`. Summary items carry a `kind`, not a French title and an SF Symbol name
   (`Messages`/`text.bubble`, `Arrivée`/`calendar`, `Dernier`/`clock`). The differential test rebuilds both from the kind.
3. **URLs are `http(s)` only** (ADR 0006 amendment 1), and **action links are forum-only** (`https://forum.hardware.fr`, `forumRelativePath` rule); field links (a member's website) stay any `http(s)` URL, documented as external, never to be requested with the session. Legacy kept any scheme that parsed (`javascript:`, `file:`, `ftp:`), resolved
   relative links against the forum root, and left `http` forum links as they were. Same results on the captures (all `https`, actions on the forum). Tests mutate action hrefs in memory: other host, `//evil.example`, `http://forum.hardware.fr:80/`, `https://forum.hardware.fr//evil.example/x`, user info, other port, `javascript:`.
4. **Pseudo without U+200B.** `pseudo` goes through `HFRText.normalizedPseudo`; the printed field keeps the text as is. Legacy trimmed only.
5. **Titles are matched whole** (case and accents ignored) to find `Pseudo`, `Statut` and the three summary fields. Legacy used a
   substring test, so `Citation personnelle associée au pseudo` could stand in for an empty `Pseudo` row. Same result on the captures.
6. **A repeated smiley is dropped inside a row too**; legacy compared only with earlier rows. Nothing in the captures repeats.
7. **A raw space in a smiley or avatar path is percent-encoded**, so the URL parses everywhere (legacy relied on the platform's lenient
   `URL(string:)`).
8. **DOM instead of regexes.** Cells are the children of their row (a nested table cannot be mistaken for a cell), entities are all
   decoded by the HTML parser (legacy decoded a fixed list), and a line break is a `br` or the end of a `p`/`div` only. Same text on
   both captures. The legacy fallback to the whole document when there is no `table.main` is kept.
9. **A failure is a typed error** (`ParsingError.missingElement`), where legacy threw `UserProfileLoadingError.invalidProfile` with the
   message "Profil impossible à lire."; the wording is the app's.
10. **The source URL is not a parameter.** Legacy resolved relative links against its `sourceURL` only as a fallback after
    `k.forumURL()`; both are the forum root for a profile page.

## Learnings
To copy into AGENTS.md §11 when the lot closes.

- The legacy `profile` oracle stores display texts (French placeholder, SF Symbol names). Keep them out of the model and rebuild them in
  the differential test's mapping, so the test still compares every legacy field.
- A legacy `</p>`-only line break means `a<p>b</p>c` reads `ab` then `c` on a new line: port the rule as written, test it on the real shape.
