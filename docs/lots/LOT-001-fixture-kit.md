# LOT-001 — Legacy build and fixture capture kit

- **Module:** tooling (`tooling/fixtures/`, Python stdlib only) + legacy app build (local, never pushed)
- **Difficulty / model:** medium (Sonnet draft, Opus integration → Fable review; Opus-authored lots are reviewed by Fable, see LOTS.md)
- **Owner:** mac/opus M1 (2026-10-26)

## Legacy sources
Repo <https://github.com/francoisgn/hfrnow> @ `2440d79` (read-only for the lot; local-only edits are allowed for build fixes and exporter patches, never committed or pushed there).

| Subject | Legacy `file:line` |
|---|---|
| Host `https://forum.hardware.fr` | `Classes/k.m:13-15` (`ForumURL`), `:37-40` (`RealForumURL`) |
| Login POST, success marker, profile page 5 for `hash_check` + avatar, cookie clearing before validation | `HFRswift/Swift/LoginService.swift:48-129` (POST body `:62-67`, marker `login_redirection.php` `:72`, `clearCookies()` first `:49`) |
| Obfuscated quote/edit URL decoder (drop 20 chars, pairs over `0A12B34C56D78E9F`, high nibble first) | `SuperHFRplus/Helpers/RangeOfCharacters.m:92-114` (`decodeSpanUrlFromString`) |
| Same for list pagers (drop 12 chars) | `SuperHFRplus/Helpers/RangeOfCharacters.m:116-137` (`decodeSpanUrlFromString2`); callers `Classes/ObjCTopicListParser.m:192,211,232-245`, `Classes/ProfilViewController.m:865,886` |
| Decode guard (`length > 20`, no `/`, no `http`, `@try`) | `Classes/ObjCMessageActionsBuilder.m:80-89` |
| Where the obfuscated strings come from (CSS `class` of the parent of `<img alt="answer">` / `alt="edit"`) | `HFRswift/Wrapped/ParseMessagesOperation.m:371-375` |
| Other per-message links captured in fixtures: `modo.php`, `addflag`, `quoter('hardwarefr'`, MP `dest=` | `HFRswift/Wrapped/ParseMessagesOperation.m:377-390` |
| Home / list / favourites / MP list / topic / search / smiley / profile endpoints | see `docs/HFR-PROTOCOL.md` §1-2 (each row cites its own legacy line) |
| Write forms and responses | `HFRswift/Swift/ReplyService.swift:145-183, 294-365, 579-719`, `Classes/MPStorage.m:23-25, 769-828` (see PROTOCOL §3) |
| Smiley wiki detail | `Classes/SmileyAlertView.m:151-152`, `HFRswift/Swift/MessagesView.swift:3319` |

## Behaviour

### 1. Legacy app builds and runs on the Mac (review F7)
Prerequisites (recorded here; FIXTURES.md links the tooling README for the capture side):
1. Xcode 27.1 (check `xcodebuild -version`), `brew install carthage` (build tool, not a linter).
2. In `~/Git/hfrnow`: `carthage bootstrap --platform iOS --use-xcframeworks` (`Carthage/Build` is not committed, audit E §6.1).
3. Open points from the review to confirm while building: libxml2 header search path of the HFRswift target (audit E Q12); `HFRswiftTests` smoke test known stale (audit C §6.17, open question 13) — do not count it as a regression.
4. Acceptance: the app launches in a simulator (iOS version used, device name prefix `agent-m1-`) and the unit-test target compiles; local patches live in `tooling/legacy-oracle/hfrnow.patch`, which comes with LOT-002 (#37), not with this branch.

**Build result** (2026-10-26, Mac M1 session): Xcode 27.1 (27A9275), Carthage 0.40.0, macOS 27.2.
- `carthage bootstrap --platform iOS --use-xcframeworks` fails twice on Xcode 27: InAppSettingsKit 3.6 declares `IPHONEOS_DEPLOYMENT_TARGET = 10.0` (Xcode 27 accepts 15.0–27.1), then `statusBarStyle` deprecations break the build under `-Werror`. Fix without touching the checkouts: `XCODE_XCCONFIG_FILE` pointing to an xcconfig with `IPHONEOS_DEPLOYMENT_TARGET = 15.0` and `GCC_TREAT_WARNINGS_AS_ERRORS = NO` (shipped in `tooling/legacy-oracle/` with LOT-002, #37). Produces `InAppSettingsKit.xcframework`, `SimpleKeychain.xcframework`; GiphyUISDK and SDWebImage are vendored in `Frameworks/`.
- `xcodebuild -scheme HFRswift -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`: **succeeds** (warnings only). The app launches on an iOS 27.0 iPhone 18 Pro simulator (`agent-m1-iphone`; the iOS 27.1 runtime refuses that device type).
- `HFRswiftTests` did not compile: `ForumTopicsLoaderSpy` (`HFRswiftTests/AccountsStoreTests.swift:270`) predates the `pageURL:` parameter and `ForumTopicsLoadResult.pageInfo`. Local patch (4 lines, part of `tooling/legacy-oracle/hfrnow.patch`, LOT-002 #37). After it: **150 tests pass, 10 fail** (`ObjCWrappedClassesSmokeTests`, `ObjCWrapperLoaderBehaviorTests`: pre-existing, reflection-based wrappers), not a regression and not used by the oracle.

### 2. Capture and anonymization tooling — `tooling/fixtures/`
Python 3 standard library only (no new dependency, AGENTS.md rule 3). Usage, config formats and safety rules: [tooling/fixtures/README.md](../../tooling/fixtures/README.md) (single source; not repeated here).

| Tool | Role |
|---|---|
| `capture.py` | GET-only capture of a manifest; refuses an output dir inside a git work tree; ≥ 3 s between requests; stops on 429/5xx; `--dry-run` |
| `flows.py` | One step per run (login, get, post, form GET → POST with `legacy` or `browser` checkbox semantics, peek); jars and request budget persisted in the work dir; every redirect hop recorded; stops on 429/5xx, captcha, budget; printed output anonymized |
| `anonymize.py` | Decodes the three crypt prefixes (alphabet `0A12B34C56D78E9F`), redacts, **re-encodes with the same prefix**; member pseudos in every live member position (post headers, quotes, lists, MP list titles, smileys, REST) in raw/`%`/entity/JSON forms → `userN`, then in free text when specific enough; member ids through one id table; tokens, cookies, personal profile fields → `REDACTED`; `--private` replaces message bodies; refuses a page whose markup changed; `check` (config optional, `--corpus`) runs two independent verifiers and the CLI refuses to write a leaking output |
| `publish.py` | Raw captures → corpus files and metas from `corpus.json` (page and meta share one alias table; member names of the whole corpus replaced in every file's free text) |

Credentials stay outside the repo (JSON in the task work folder, `chmod 600`); real pseudos only in a git-ignored local config.
The legacy **oracle is generated from the anonymized HTML**, never from a raw capture (LOT-002..004).

### 3. Tests and CI
`python3 -m unittest discover tooling/fixtures/tests` (synthetic HTML and a loopback HTTP server only, no real data) and `anonymize.py check --corpus` on the committed corpus (no config), both in the `fixture-tooling` CI job. `tests/test_positions.py` has one test per member position, on a page where only that position holds the name; each asserts the verifier's label for it and the anonymizer's output. Mutation runs (review rounds 1-2): dropping each of the 23 `DISCOVER` entries and neutralizing each of the 27 verifier rules and DOM branches fails the tests of that position (50 of 50); reverting each finding-level fix fails its test (47 of 47).

Acceptance (review F8, tightened after the PR #38 reviews):
- `check --corpus` and `check --config` clean on every committed file.
- Independent grep of the corpus: member names are collected from the **raw** files' member positions with other patterns than `DISCOVER`. Whole names and, separately, each word (3+ characters, function words excluded) of multi-word names are searched in every file, and each hit is classified by context. Accepted: no hit in a member position. Hits in prose, titles or site markup are reported as counts and reviewed; in round 2 they were ordinary-word collisions (product, place or language names that are also part of a pseudo).
- 0 hits for both pseudos, both passwords, the jars' cookie values and every raw `hash_check`/`codehex` value.
- An adversarial agent pass on the final corpus, folded in (rounds 1-2; round 2 found a pseudo ending with `'` cut in its `href`, now kept whole, plus a verifier rule for a link whose text and parameter carry different aliases).
Pre-commit hooks are tracked separately (#14).

### 4. Capture checklist and corpus
The operator-approved checklist is [LOT-001-capture-checklist.md](LOT-001-capture-checklist.md) (linked from `docs/FIXTURES.md`). The anonymized corpus and its index are in `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/` (`MANIFEST.md`); new protocol facts are in `docs/HFR-PROTOCOL.md` (live notes, §6b, §7 Result column).

## Edge cases
- Obfuscation is intermittent (E7): the same page can come back with plain URLs; keep both shapes when seen.
- Anonymous vs authenticated URL shape differs (E7): capture the same topic page in both states.
- Browser-saved pages run site JavaScript and are misleading: capture raw bytes only.
- A pseudo with spaces, accents, `&`, zero-width space (audit C F24): the mapper must work on decoded entities and re-escape.
- Member names are printed far beyond post headers (live corpus): MP list titles (unread-by, recipients, correspondents, lock, ignore), list author and last-poster columns, home last poster and moderator links, contact-list titles, the review under the reply form, the description meta, personal smileys, REST authors; ids also in `adduser=`, avatars and `[quotemsg]`. List pages insert U+200B after the 10th character. A member called like a common word (`Le`, `follow`) must not rewrite prose or markup: free-text replacement skips short and common names, tag and attribute names, internal paths and scripts.
- Odd-length / non-alphabet crypt payload: legacy crashes or yields garbage (callers outside `ObjCMessageActionsBuilder` have no `@try`, e.g. `MessagesTableViewController.m:1074`); anonymizer rejects, parser lots must define behaviour.
- Redirect chains and final URL are part of the fixture (`currentPage` depends on them, audit C §8).

## Fixtures
This lot produces no parser fixture of its own; it delivers the kit, `capture-checklist.md` (ids `R*`, `W*`, `N*`) and the anonymized corpus consumed by LOT-002..004 and Phase 3 lots. Synthetic fixtures for what cannot be captured are listed in the checklist section (c).

## Intentional differences from legacy
| Legacy | Here | Why |
|---|---|---|
| Cookies cleared before login validation (`LoginService.swift:49`) | staging jar, committed on success only | no logged-out window on failed login (PROTOCOL §5, X5) |
| Success = body marker only | marker **and** `Set-Cookie: md_user` | both recorded to settle X5 |
| Decoder: 20 or 12 chars, no validation | three prefixes, even-length + alphabet check, round-trip assertion | E7; a silent garbage decode would leak or corrupt |

## Learnings
To copy into AGENTS.md §11 when the lot closes:
- Carthage on Xcode 27 needs `XCODE_XCCONFIG_FILE` (deployment target 15.0, no `-Werror`); the iOS 27.1 simulator runtime refuses iPhone 18 Pro, use iOS 27.0.
- Live login sets `md_user`, `md_passs` (three s), `md_id`; no `md_pass`/`md_forum`. Logged-in action links keep the anonymous `message.php?…&numrep=&ref=` shape inside `md_noclass_cryptlink` spans; `md_blank_cryptlink` not seen.
- Topic URLs redirect in two 301 hops (the second adds the sub-category), plus a 302 to the last page beyond the end.

## Docs-vs-legacy discrepancies found while drafting
1. `docs/HFR-PROTOCOL.md` §4 and `REVIEW-fable.md` F8 cite `RangeOfCharacters.m:92-114` without a directory; the file is `SuperHFRplus/Helpers/RangeOfCharacters.m` (there is no `Classes/RangeOfCharacters.m`).
2. PROTOCOL §4 says list pager links use the 12-character prefix: confirmed (`decodeSpanUrlFromString2`, `RangeOfCharacters.m:116`), but legacy also uses it for profile-page pagers (`ProfilViewController.m:865,886`), not listed in the audit. The 18-character `md_blank_cryptlink` of E7 has **no legacy decoder**.
3. PROTOCOL §4 says "decode only if length > 20 and ...": the guard exists only in `ObjCMessageActionsBuilder.m:84`; the direct callers (`MessagesTableViewController.m:1074, 2757, 2764`, `OnlineMessagesTableViewController.m:523-544, 2521, 2715-2722`) call `decodeSpanUrlFromString` unguarded.
4. `docs/lots` / LOTS.md said the checklist lives in `docs/FIXTURES.md`, and FIXTURES.md said capture uses "a harness in the legacy app"; this lot uses standalone Python tooling (the legacy harness remains for the oracle, LOT-002..004). Fixed: FIXTURES.md now describes the capture and links the checklist.
