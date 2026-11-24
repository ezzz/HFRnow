# LOT-159 — App Review policy and UGC compliance

- **Module:** App
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** ezzz/HFRnow#249
- **Depends on:** LOT-082 (#100, forum list), LOT-115 (#206, search screen), LOT-118 (#209, blocklist), LOT-133 (#223, AQ
  feed and badge), LOT-135 (#225, moderator alert)

The App Store update must pass App Review guideline 1.2 (user-generated content) and keep the legacy App Review workarounds of
decision Q-7 ([audit README](../audit/README.md) Q-7). Most of it was built by the lots this one depends on; this lot checks
every rule against the code, ties each rule to a test, closes the one gap found (the filtered posts had no message menu, so a
message read there could be neither reported nor blocked) and drafts the App Review notes.

## Guideline 1.2, as Apple states it

Read on 2026-11-24 at <https://developer.apple.com/app-store/review/guidelines/#user-generated-content> (re-read before quoting
it in a PR or in App Store Connect): apps with user-generated content "must include: a method for filtering objectionable
material from being posted to the app; a mechanism to report offensive content and timely responses to concerns; the ability to
block abusive users from the service; published contact information so users can easily reach you". Guideline 2.1(a) asks for
demo account information when the app has a login; 2.3.1(a) asks that features be described with specificity in the Notes for
Review, and 2.3.1(b) closes with "if you're dishonest, we don't want to do business with you".

## Legacy sources

Legacy reference `legacy/duo-inner-cover` @ `87fe0d1c` (AGENTS.md §2).

| Legacy @ `87fe0d1c` | What it does |
|---|---|
| `Classes/ObjCForumsParser.m:33-46` | "logged in" = the home page has a non-empty `hash_check` |
| `Classes/ObjCForumsParser.m:77-80`, `:516-518` | "censure Apple": a logged-out home page drops the forum titled `Apple` (its sub-forums and the forum itself are never appended) |
| `Classes/ForumsTableViewController.m:271-272` | the same rule in the older forum list |
| `Classes/Forum.m:42`, `:71`, `:108` | `/hfr/apple/liste_sujet-1.htm` is category 25 (`cat-apple`) |
| `Classes/ObjCForumSearchWorker.m:149-156` | a search whose lowercased text contains `jailbreak`, `cydia`, `pengu` or `apple jb` is replaced by a fixed base64 sentence; applied to every viewer |
| `Classes/TopicsSearchViewController.m:167-174`, `:816-828` | the same list in the older search screen |
| `Classes/AQTableViewController.m:332-347` | the AQ feed drops every item whose link contains `&cat=25&post` when no account is main or the main account's pseudo, lowercased, is `applereview` |
| `HFRswift/Swift/AQPlusView.swift:52-57` | `shouldFilterCategory25`: no current pseudo, or pseudo `applereview` |
| `HFRswift/Swift/AQPlusView.swift:69-87`, `:174-180`, `:298-314` | the same filter for the Plus tab badge count (`nb_aq`) and for the list |
| `HFRswift/Swift/PlusTab.swift:11-60` (`PlusHomeView`) | the Plus menu: Réglages, Rechercher sur le forum, Bookmarks, Alertes Qualitay (badge `nb_aq`, `:14`, `:40`), Crédits, Charte du forum, Supprimer mon compte |
| `SuperHFRplus/Assets/HTML/credits.html:7-14` | "Mentions légales": the app is not made by the hardware.fr team; contact "Sur le forum" (the app's topic, `sujet_1711`, in the Apple category) and "En privé" (the maintainer's forum profile) |
| `SuperHFRplus/Assets/HTML/charte.html` | the forum charter |
| `HFRswift/Swift/MessagesView.swift:197-260` (`MessagePopupMenuPolicy`) | "Alerter" on another member's message (alert link, else permalink); "Blacklist" / "Whitelist" in the author menu |
| `HFRswift/Swift/MessagesView.swift:2011-2030` (`presentPopupMenu`) | the menus read `messageActionsByIndex` |
| `HFRswift/Swift/MessagesView.swift:4767-4791` (`renderFavoritePostFilterResult`) | the filtered posts are shown by the same `MessagesView` with their `messageActionsByIndex`: every menu, "Alerter" and "Blacklist" included, works on a filtered post |
| `HFRswift/Swift/FavoritePostFilterService.swift:248-280` | the filtered batch carries the actions (alert link, permalink…) of each kept message |

## Legacy counterpart (app lots)

- `App/SwiftHFR/Navigation/ForumVisibility.swift`: `Classes/ObjCForumsParser.m` (the Apple rule) and
  `HFRswift/Swift/AQPlusView.swift (AQSupport.shouldFilterCategory25)` @ `87fe0d1c` (LOT-082, LOT-133).
- `App/SwiftHFR/FilteredPosts/FilteredPostsMenuModel.swift` (new): `HFRswift/Swift/MessagesView.swift (presentPopupMenu,
  presentAvatarActionSheet, in the favourite post filter mode)` @ `87fe0d1c`.
- Everything else this lot checks is ported by its own lot: search (LOT-115), AQ (LOT-133), alert (LOT-135), lists (LOT-118),
  Plus menu, credits and charter (LOT-120, LOT-170).

## Q-7 and guideline 1.2: checklist

One line per rule, the code that applies it and the test that fails when it is broken. "Mutation" means the test was shown red
by breaking that code (log paths in the PR), because the behaviour predates this lot.

| # | Rule | Source | Code | Test |
|---|---|---|---|---|
| R1 | One review-account configuration: the hidden category (25) and the account name (`applereview`, case-insensitive) live in `ForumVisibility`, built once per session in `AppEnvironment.make` and handed to the forum list, the search picker (through the forum list) and the AQ list and badge | Q-7 decision ("the review account name is configuration") | `ForumVisibility`, `AppEnvironment.visibility`, `RootModel.init(environment:)` | `ReviewAccountConfigurationTests` (new): one custom configuration reaches the forum list, the search picker and the AQ badge (mutation: a default `ForumVisibility()` in `RootModel`) |
| R2 | Apple category hidden from the forum list when logged out | `ObjCForumsParser.m:77-80` | `ForumVisibility.visible`, `ForumListContent` | `ForumVisibilityTests.hidesTheAppleCategoryWhenLoggedOut`, `aLoggedInSessionWithoutKnownNameIsTreatedAsLoggedOut` |
| R3 | … and for the review account, whatever its case (Q-7 extends legacy, whose forum list hid it only logged out) | Q-7 decision | same | `ForumVisibilityTests.hidesItForTheReviewAccountWhateverTheCase`, `ForumListModelTests.theReviewAccountDoesNotSeeTheAppleCategory` |
| R4 | Shown to every other logged-in account | `ObjCForumsParser.m:77-80` | same | `ForumVisibilityTests.showsItToAnotherLoggedInAccount`, `ForumListModelTests.appliesTheAppleRuleAndResolvesSources` |
| R5 | The category is recognised by id or by its path | `Forum.m:42` | `ForumVisibility.category(of:)` | `ForumVisibilityTests.recognisesTheCategoryByPathWhenTheIDIsMissing` |
| R6 | The search picker never offers the Apple category to the logged out or the review account | `ObjCForumsParser.m:77-80` (the picker lists the home page's forums) | `ForumSearchModel.setCategories` over `ForumListContent` | `ForumSearchModelTests.theAppleCategoryIsNotOfferedLoggedOutOrToTheReviewAccount` |
| R7 | Banned search words (`jailbreak`, `cydia`, `pengu`, `apple jb`), any case, for every viewer: refused with a warning, nothing sent | `ObjCForumSearchWorker.m:149-156`; Q-7 decision (refuse, no substitution, GAP of LOT-046) | `GlobalSearchFlow.bannedWords`, `ForumSearchModel.search` | `GlobalSearchFlowTests` "A banned word refuses the search before any request (Q-7)", `ForumSearchModelTests.aBannedWordIsRefusedWithAWarningAndSendsNothing` |
| R8 | AQ list and Plus badge hide category 25 for the logged out and the review account, count included | `AQTableViewController.m:332-347`, `AQPlusView.swift:52-57`, `:69-87` | `QualityAlertsModel` with `ForumVisibility.hidesCategory` | `QualityAlertsVisibilityTests` (4 tests) |
| R9 | "Alerter" (report) on every message of another member: HFR's alert form with an account, else the mail to the moderators | guideline 1.2 (report); `MessagesView.swift:197-260` | `MessageMenuPolicy`, `ModeratorAlertModel` | `ModeratorAlertModelTests` (LOT-135) |
| R10 | The mail fallback always ships: the committed build setting reaches the app | Q-10, LOT-135 | `Shared.xcconfig` `MODERATOR_ALERT_MAIL_ADDRESS` | `ModeratorAlertModelTests.theCommittedBuildSettingReachesTheApp` |
| R11 | "Blacklist" (block) on every message of another member, for an account: hides that member's posts | guideline 1.2 (block); `MessagesView.swift:204-216` | `PseudoListActionHandler`, the author menu, the profile sheet | LOT-118 tests (`PseudoListTests`, `UserProfileModelTests`) |
| R12 | Report and block also on the filtered posts (the favourite post filter, LOT-114), as in legacy | `MessagesView.swift:4767-4791` | `FilteredPostsMenuModel` (new), `FilteredPostsView` | `FilteredPostsMenuModelTests` (new, red without the change) |
| R13 | The forum charter is one tap from the Plus menu | `PlusTab.swift:11-60` | `PlusEntry.charter`, `StaticPage.charter` | `StaticPageTests` (LOT-120) |
| R14 | Contact: the app's forum topic is linked from Crédits | `credits.html:7-14` | `AboutTopicLink` | `AboutModelTests` (LOT-120); see decision D1 |
| R15 | Account deletion from the Plus menu | guideline 5.1.1(v); `PlusTab.swift:11-60` | `PlusEntry.deleteAccount` | `AccountDeletionTests` (LOT-157) |

**Not in the app, on HFR's side:** "filtering objectionable material from being posted" is HFR's moderation (the charter, the
moderators the alerts reach); the app posts through HFR's own forms and adds no channel of its own.

## Behaviour

### R1, one configuration

`AppEnvironment.make` builds one `ForumVisibility()` per session; `RootModel.init(environment:)` hands it to the forum list
and to the AQ model, and the search picker takes its forums from the forum list's filtered content. Changing the review account
name is one edit: `ForumVisibility.reviewAccountName`. The account name compared is the current account's (`md_user`, the
account list), the "logged in" signal is the page's (forum list) or the session's (AQ), as LOT-082 and LOT-133 decided.

"Home" in the issue's scope is read as the Plus tab (legacy `PlusHomeView`), whose AQ badge is R8; HFR's home page is the
forum list (R2-R4). See D4.

### R12, the filtered posts

The filtered posts sheet (LOT-114) now draws the reader's "+" button and makes authors tappable, like the reader, with the
UGC entries only:

- message menu: "Link" (the message's permalink) and "Alerter";
- author menu: "Blacklist" and "Whitelist" (for an account; the allowlist logged out too, as LOT-118).

The posts are read cookie-less (LOT-093), so they carry no toolbar link: no alert link, no edit link. Hence:

- the permalink of a message is built from the page it was read on: `HFREndpoint.topicPage(topic:page:anchor:)`
  (`forum2.php?config=hfr.inc&cat=…&post=…&page=…#t<numreponse>`, HFR-PROTOCOL R5), the URL legacy's `permalinkURLForPostID`
  gives once HFR redirects it;
- "Alerter" is the moderators' mail with that permalink (LOT-135's fallback, R10); with an account and no alert link the reader
  does the same;
- a message is the user's own when its author is the current account's pseudo (`PseudoListManager.isOwn`, the LOT-072 comparison): no "Alerter", no
  "Blacklist", no "Whitelist" on it (the reader reads the edit link instead, which a cookie-less page never has);
- a change to the lists rebuilds the sheet's document, so a blocked member's posts are hidden at once (the reader does the same);
- the confirmations ("Lien copié", the lists' sentences) show in the reader's banner and are announced to VoiceOver, as in the reader.

The other actions of the reader's menus (quote, reply, edit, favourite, bookmark, AQ, profile, MP) are not offered there: the
sheet stays read-only, as LOT-114 decided.

## Edge cases

- A filtered message whose page is unknown (never: every kept post carries its page) gets no permalink, so neither "Link" nor
  the mail "Alerter".
- A menu tap from a document that is no longer shown (a newer batch) opens nothing (token check, as the reader).
- Logged out: no blocklist anywhere (LOT-118, per-account lists); see D3.

## Fixtures

None new: the menu model is tested on batches built by `FilteredPostsModel.result(of:)` from made-up `FilteredPost`s; the AQ and forum list tests reuse LOT-133's `T01` and LOT-082's fakes.

## UX evolutions (app lots)

None: same UX as legacy. R12 restores a legacy behaviour SwiftHFR lacked (the filtered posts had no menu since LOT-114); the
entries offered there are a subset of legacy's (the read-only sheet of LOT-114).

## Intentional differences from legacy

1. The forum list hides the Apple category for the review account too (legacy: logged out only): decision Q-7, already in
   LOT-082.
2. Banned search words are refused with a warning instead of being silently replaced (decision Q-7, LOT-046/115).
3. In the filtered posts, "Alerter" is always the mail (no alert link on a cookie-less page) and only the UGC entries are
   offered (LOT-114's read-only sheet).

## Open decisions (operator)

- **D1 — contact.** Legacy's credits had a "Mentions légales" block: "not developed by the hardware.fr team… contact us: on the
  forum (the app's topic) / in private (the maintainer's profile)". SwiftHFR's Crédits screen links the app's topic
  (`[TU] Super HFR+`, topic 1711) and the beta topic, without a "contact" heading or the "not made by hardware.fr" sentence. For
  guideline 1.2 ("published contact information"): keep as is and point App Review at Crédits, or add a « Nous contacter » row
  (which target: the topic, a GitHub issue form, a mail address?) and the sentence? Not changed here.
- **D2 — terms.** Apple often asks UGC apps for an explicit agreement to terms ("zero tolerance"). Legacy has none (the charter
  is a page). Keep parity, or add an agreement at first login? Not changed here.
- **D3 — blocking logged out.** The blocklist is per account (LOT-118), so a logged-out reader can report (mail) but not block.
  The review account is logged in. Keep?
- **D4 — "Home".** Read as the Plus tab (`PlusHomeView`) badge. Confirm.
- **D5 — what the review account sees (🟠).** Q-7 hides the Apple category and the AQ alerts of category 25 from the
  `applereview` account specifically. Guideline 2.3.1 asks for features to be described in the review notes and states
  "if you're dishonest, we don't want to do business with you". A filter keyed on the reviewer's account and not disclosed can
  be read as showing App Review a different app. The notes below disclose it as an optional paragraph; whether to keep the
  account-specific part of the rule, and whether to disclose it, is the operator's call (Q-7 is his decision).

## App Review notes (draft for the operator, App Store Connect › App Review Information › Notes)

No credential here: the sign-in name and password go in App Store Connect's "Sign-in required" fields only.

> SwiftHFR is a free, volunteer-made client for the French forum forum.hardware.fr ("HFR"). It is not made by the
> hardware.fr team. All content comes from the forum; the app adds no channel of its own and posts only through the forum's
> own forms.
>
> Demo account: see the "Sign-in required" fields. Sign in from the account button (top left of every tab).
>
> User-generated content safeguards (guideline 1.2):
> - Report: on any message, tap "+" then « Alerter ». With an account, this sends the forum's own moderator alert (a reason is
>   asked); otherwise it prepares an email to the forum's moderation address. HFR's moderators handle the reports.
> - Block: tap a member's name or avatar: their profile opens with « Ajouter à la liste noire » (or, when the forum gives no
>   profile link, a menu with « Blacklist »). That member's posts are then hidden (masked, or removed with Plus › Réglages ›
>   « Masquer les pseudos blacklistés »); Plus › Réglages › « Liste noire » lists and removes them.
> - Rules: Plus › Charte du forum shows the forum charter.
> - Contact: Plus › Crédits links the app's topic on the forum.
> - Account deletion: Plus › Supprimer mon compte prepares the deletion request to the forum.
>
> Optional (D5): Some forum sections are not shown when signed out or with the review account: the "Apple" forum category
> (jailbreak discussions) and the corresponding quality alerts; searches for jailbreak-related words are refused.

## Learnings

To copy into AGENTS.md §11 when the lot closes: a sheet that renders forum messages with the reader's document builder must
also carry the UGC entries (report, block); a new message surface gets `FilteredPostsMenuModel`'s pattern, never a bare
document.
