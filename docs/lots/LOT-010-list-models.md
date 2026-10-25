# LOT-010 — List models

- **Module:** HFRModels
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [B §2](../audit/B-list-parsing-models.md) (data models, proposal B1) and [redface2 comparison](../research/redface2-comparison.md) §4.3 E18.

| Legacy | What it gives the models |
|---|---|
| `Classes/Forum.h/.m:34-61` | forum title/URL, the hard-coded id table (kept out: it is a parser concern, audit B open question 2) |
| `Classes/Topic.h/.m`, `Classes/ObjCTopicListParser.m:281-464` | topic row fields: title, URLs, flag (`flag0.gif` red, `flag1.gif` blue, `favoris.gif` yellow, `:347-355`), read state (`sujetCase1` `alt="On"`, `:374-388`), sticky/closed/poll, last post, page counts |
| `Classes/Favorite.h/.m:31-210` | favourites section = one category with its topics |
| `Classes/ObjCTopicListParser.h:5-24` | list page state: navigation, tabs, new-topic URL, MP counter |
| `Classes/Constants.h:23-30,65`, `Classes/Forum.m:157-179` | `owntopic` values (0 all, 1 flagged, 2 read, 3 favourites) |
| `HFRswift/Swift/ForumSearchService.swift:129-200` | `ForumSearchPageInfo`, the closest typed page model |
| `HFRswift/Swift/Favorites.swift:502-519` | the ad-hoc section id that `FavoriteSection.id` replaces |

## Behaviour
Value types only, all `Sendable`, `Hashable` (except `TopicListFilter`/`ListPageFailure`, per audit) and `Codable` where the audit says so. No behaviour beyond identity and one invariant.

| Type | Role | Identity / invariants |
|---|---|---|
| `CategoryID` | `cat` value: `.forum(Int)` or `.privateMessages` (`prive`) | encodes as the query string; parser accepts ASCII digits or `prive` only |
| `TopicID` | category + topic number | HFR numbers topics per category, so the pair is the key |
| `ForumLink`, `ForumCategory` | home page forums and sub-forums | `ForumCategory.id` = `path` |
| `TopicSummary` | one list row (forum, MP, favourites, search) | `id` = `topic:<cat>-<topic>` when `topicID` is known, else `path:<path>`; `pageCount` >= 1 |
| `LastPost`, `SearchHit` | row parts | — |
| `TopicFlag`, `TopicReadState`, `TopicListFilter` | flag colour, unread marker, `owntopic` | `TopicReadState` replaces `Bool?` |
| `PageNavigation`, `TopicListTabs`, `TopicListPage` | pagination, tabs, whole list page | defaults = one page |
| `ForumListPage` | home page: forums + login/MP/`hash_check` facts | — |
| `FavoriteSection` | favourites category section | `id` = `cat:<id>` or `path:<forum path>` |
| `ListPageFailure` | typed list-page errors | `Error, Sendable, Equatable` |

Decisions taken here (audit B open question 1 and the Fable notes):

1. **URLs stay relative `String` paths** (as HFR serves them and as the audit proposes). Resolution against the base URL is the caller's job. The message models (LOT-011) use absolute `URL`s because ADR 0006 amendment 1 requires scheme-checked absolute URLs there.
2. **`CategoryID` is an enum, not an `Int`.** The audit sketched `TopicID.category: Int`, but private message topics use `cat=prive` (audit C 3.3, `ObjCTopicPageWorker.m:128`); an `Int` would force every MP topic into an optional or a sentinel. This is also the key that makes `numreponse` unique (E18).
3. **Identities are computed, never stored**, so they cannot drift from the fields they derive from and cannot be empty or random.
4. **Not in this lot** (and why): `Bookmark` is the MPStorage wire type, defined in LOT-013 (`MPStorageBookmark`); polls are in LOT-011; `hasNewMessageInTopic`, `isLocallyViewedInApp`, `isSuperFavorite`, `order`/hidden categories, cache flags, relative date labels and icon asset names are UI or storage state (audit B 2.2).
5. `hashCheck` on `ForumListPage` stays a `String?` (audit open question 4 is the maintainer's); it is documented as a secret, and `ForumListPage` prints and reflects it as `<redacted>` (a description, `debugDescription` and `customMirror`; `Codable` is not offered on this type).
6. "No results" is an empty `TopicListPage`, not a failure (audit B 2.2); add a field only if the UI needs the message.

`CategoryID` and `TopicID` are shared with LOT-011 (`PostID`). Both PRs carry the two files byte for byte so that neither depends on the other; git merges the identical additions without conflict.

## Edge cases
- `cat` values such as `""`, `-1`, `+5`, `1.5`, `Prive`, padded or overflowing numbers are rejected by `CategoryID(queryValue:)` (nil), never wrapped or defaulted.
- `pageCount` below 1 is raised to 1 by the initializer, by mutation and by decoding.
- A topic number reused in another category, or in private messages, gives a different `TopicSummary.id`.

## Fixtures
None (fixture-free lot). Differential tests against the oracle arrive with the parser lots (LOT-021, 022, 024).

## Intentional differences from legacy
- Reference types mutated by the UI become value types (audit B 2.1, "models as reference types mutated by the UI").
- `aID` empty string for home page forums becomes `categoryID == nil`.
- `isViewed` flip semantics (`On` means not viewed) become `TopicReadState`; favourites rows are `.unknown` instead of "viewed unless flagged" (`Favorite.m:167-173`).
- The "TU" title rewrite hidden in `Topic.setATitle:` (`Topic.m:90-94`) is not applied: `title` is the raw text.
- `Catcounter` is not ported (unused, audit B 2.1).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A model identity that two different pages must agree on (list row vs favourites row) cannot be the URL: it has to be the (category, topic) key, with the path only as a fallback.
