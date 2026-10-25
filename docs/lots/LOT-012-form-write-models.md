# LOT-012 — Form and write models

- **Module:** HFRModels
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [D §2.1, §2.5-2.7, §3, §8 (D1, D2, D9, D10)](../audit/D-posting.md), [HFR-PROTOCOL §3](../HFR-PROTOCOL.md).

| Legacy | What it gives the models |
|---|---|
| `HFRswift/Swift/ReplyService.swift:311-365, 489-502` | form harvesting: inputs (checkbox/radio/other), selects (selected or first option), `<form name="hop">` |
| `ReplyService.swift:267-268, 392-414` | `isSubjectEditable`, `isSubcategoryEditable`, `subcat` options |
| `ReplyService.swift:504-555`, `QuoteMessageViewController.m:146-205` | `#dynamic_smilies` favourite smileys |
| `ReplyService.swift:579-695`, `AddMessageViewController.m:594-622` | `.hop` text, success/rejection, meta refresh URL and anchor |
| `ReplyService.swift:1524-1531`, `AlerteModoViewController.m:132-140` | "already alerted" |
| `ReplyService.swift:1866-1892`, `RehostImage.m:230-320` | `RehostUploadedImage` and the BBCode snippets |
| `SuperHFRplus/commonsmile.plist` | bundled smiley catalogue (59 entries, 35 with `editor=true`) |
| `HFRswift/Swift/AQPlusView.swift:12-23, 100-170`, `MessagesView.swift:381-399`, `MessagesTableViewController.m:2338-2460` | AQ feed item, AQ listing format, `addAlerte` fields |

## Behaviour
Value types, `Sendable`, `Hashable`, `Codable`.

| Type | Role |
|---|---|
| `ForumForm`, `FormField`, `FormInputKind`, `FormSelect`, `FormOption` | what the `hop` form contains, undecided: which fields to send is a later pure function (D1) |
| `ForumSmiley` | `alt` code + image URL, for `#dynamic_smilies` and smiley search results |
| `HopResponse` (`Kind`: success, rejected, loggedOut, alreadyAlerted, unrecognized) | outcome of a write |
| `RehostedImage`, `RehostImageVariant`, `RehostBBCodeMode` | uploaded image, its renditions, snippet formatting |
| `AQFeedItem`, `AQAlert`, `AQNewReport` | AQ feed entry, existing AQ, data of a new report |
| `CommonSmiley`, `CommonSmileyCatalog` | bundled catalogue loaded from `Resources/CommonSmileys.json` |

Decisions:

1. **Derived form facts are computed** (`isSubjectEditable`, `isSubcategoryEditable`, `subcategories`, `recipient`, `FormSelect.effectiveValue`), not stored, so they cannot disagree with the fields.
2. **Unchecked checkbox semantics are not decided here.** `FormField` keeps `kind` and `isChecked`; whether an unchecked box is sent as `"0"` (legacy) or omitted (browser, redface2) is LOT-048's decision (HFR-PROTOCOL §3.1).
3. **`HopResponse.refreshAnchor` has no leading `#`** (the legacy regex kept it, the Swift port did not; audit D 2). `.unrecognized` exists so that nothing is reported as success without evidence.
4. **`RehostedImage`** drops the always-nil `previewURL`; the fallback chain is mini, medium, full. `RehostBBCodeMode` raw values are the legacy `rehost_use_link` values (0, 1, 2) so migration is a no-op. The maximum-dimension setting lives with the other settings enums in LOT-013.
5. **Catalogue resource.** `Package.swift` gets `resources: [.process("Resources")]` for the HFRModels target (the only change outside `Sources/HFRModels` besides tests). `CommonSmileys.json` is a converted copy of the legacy plist, same order; keys `code`, `url` (plist `src`), `resource`, `editor`. Loading uses `Bundle.module`.
6. **AQ.** The listing format of `getAlertesByTopic.php` is the XML in a legacy comment (`<alerte id nom pseudoInitiateur date postsIds/>`); the audit's `pseudo=...&post_id=` reading is a different shape. It is unverified on `aq.super-h.fr`, so `AQAlert` stays minimal until LOT-055 captures it. `isNew` of the legacy feed item is derived from the last check date: app logic, not modelled.
7. **Secrets.** Hidden and password `FormField` values (`hash_check`) are redacted in `description`, `debugDescription` and `customMirror`; `Codable` keeps them.
8. Not here: the form-building function, `verifrequet`, field dropping rules, form encoding (LOT-036, LOT-048).

## Edge cases
- Select with no `selected` option: first option is the effective value; no options: nil.
- `type` missing or empty: text; unknown types: `.other`; matching is case-insensitive.
- A hidden `sujet` input does not make the subject editable.
- Smiley codes keep exactly what the page serves (spaces, `:N` suffixes); duplicates are allowed, so `ForumSmiley` is not `Identifiable`.
- Two uploads of one image are two history entries (identity includes the upload instant).

## Fixtures
None. The real `hop` form field list and `.hop` texts are still to be captured (audit D §9).

## Intentional differences from legacy
- Attribute values are expected entity-decoded by the parser (legacy bug B1: not decoded).
- The legacy parser took only inputs with both `name` and `value`; `FormField` keeps every named input.
- `previewURL` is dropped.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A bundled resource in `HFRModels` needs a `resources:` entry in `Package.swift`; test it through `Bundle.module` so a packaging mistake fails on Linux CI.
