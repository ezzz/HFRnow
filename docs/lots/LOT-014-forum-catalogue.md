# LOT-014 — Forum catalogue

- **Module:** HFRModels
- **Difficulty / model:** trivial (Haiku → Sonnet)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>. Audit: [B §5 B2](../audit/B-list-parsing-models.md).

| Legacy | What it gives the catalogue |
|---|---|
| `Classes/Forum.m:34-60` | `getHFRID`: 22 forum paths to `cat` ids, plus the absolute `ia` alias (`:57-58`, `https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm`). Exact `isEqualToString:` matching; unknown path returns `0` |
| `Classes/Constants.h:65` | `kCatTemplateURL`: `/forum1.php?config=hfr.inc&cat=$1&page=1&subcat=$2&owntopic=$3` |
| `Classes/Forum.m:157-179` | `URLforType:` fills `$2` with an empty string and `$3` with the filter: `kALL` 0, `kFlag` 1, `kRed` 2, `kFav` 3 |
| `Classes/Constants.h:67` | Comment on the `owntopic` values; it disagrees with the code (`2=fav, 3=red`). The code wins, and it matches `docs/HFR-PROTOCOL.md` R2 |

Display names are not in the legacy table: the home page provides them at runtime (`ForumCategory.title`), so none are hard-coded here. Icons stay in the app (`Forum.m:63-128`).

## Behaviour
- `ForumCatalogue.entries`: 23 rows in legacy order (22 forums plus the absolute `ia` alias), each `ForumCatalogueEntry(path, categoryID)`.
- `ForumCatalogue.categoryID(forPath:) -> CategoryID?`: exact string match; nil when unknown.
- `ForumCatalogue.forumPath(for:) -> String?`: canonical relative path of a category (the first row carrying it, never the absolute alias); nil when unknown.
- `ForumCatalogue.topicListPath(categoryID:filter:page:) -> String?`: `/forum1.php?config=hfr.inc&cat=<n>&page=<p>&subcat=&owntopic=<filter raw value>`, relative, as `kCatTemplateURL` builds it.
  - `page` defaults to 1. Returns nil for `page < 1`, so a bad page never turns into a silent first page.
  - Returns nil for `.privateMessages`: the MP list has its own URL (protocol R4) and is not built by this template.
  - `TopicListFilter` raw values (0 all, 1 flagged, 2 read, 3 favourites) are the legacy `owntopic` values.

## Edge cases
- Unknown paths (other forums, other pages, paths without the leading slash, or differently cased paths) → nil. Matching is exact, as in legacy, so `/hfr/Apple/...` is unknown.
- Two rows for category 32 (`ia`): the relative and the absolute form. Both resolve to `.forum(32)`; the reverse lookup returns the relative one.
- The 22 categories are distinct; `CategoryID` values never collide.

## Fixtures
None. The table is checked against the legacy source in the tests (`ForumCatalogueTests.legacyRows`, copied from `Forum.m:34-60`). The audit's suggested check against the home page fixture is for the parsing lots (LOT-021 onward), once fixtures exist.

## Intentional differences from legacy
- Lookup returns `CategoryID?` instead of `0` for unknown paths (`ForumCategory.categoryID` is already nil in that case).
- The topic list builder returns nil for `page < 1` and for private messages (a different list URL, protocol R4) instead of building a URL for them.
- The legacy hard-coded `page=1` is a parameter here, defaulting to 1.

## Learnings
- `Forum.m:34-60` lists 22 forums and an `ia` alias in absolute form. Count the rows with the alias: 23 rows, 22 categories.
- The `owntopic` comment in `Constants.h:67` is wrong (`2=fav, 3=red`); the code (`Forum.m:157-179`) gives 2 read and 3 favourites.
