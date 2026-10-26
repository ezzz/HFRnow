# Legacy oracle exporter

Runs the **real** Objective-C parsers of the legacy app ([hfrnow](https://github.com/francoisgn/hfrnow),
pinned at `2440d79`) offline on saved HTML pages and writes one `<case>.oracle.json` per page. These files
are the expected values of the differential tests in `HFRParsing` (AGENTS.md §5 step 5).
Specs: list parsers [LOT-002](../../docs/lots/LOT-002-list-oracle.md), topic pages [LOT-003](../../docs/lots/LOT-003-topic-oracle.md).

Local tooling for the maintainer's Mac. It is not part of CI (Xcode 27 + Carthage + simulator).

## Contents

| File | Use |
|---|---|
| `hfrnow.patch` | Local edits to hfrnow: the `OracleExport` test class (`OracleExport.swift`, topic kind in `OracleExportTopic.swift`) and its Objective-C helper in `HFRswiftTests`, plus the spy-signature fix in `AccountsStoreTests.swift` that the tests need to compile |
| `run-oracle.sh` | Checks the legacy commit, applies the patch, bootstraps Carthage, creates or reuses the simulator, runs the export, reports counts |
| `carthage-xcode27.xcconfig` | Build settings Carthage needs on Xcode 27 (see below) |
| `samples/` | Synthetic pages (fake pseudos, fake hash) and their `oracle-map.json`, to prove the harness end to end (`topic-*` for LOT-003) |

## Run

```sh
tooling/legacy-oracle/run-oracle.sh                       # samples/ -> out/ (git-ignored)
tooling/legacy-oracle/run-oracle.sh -i DIR_WITH_HTML -o OUT_DIR
```

`HFRNOW` (default `~/Git/hfrnow`) and `HFR_ORACLE_WORK` (DerivedData and step logs, default `.work/`) can be
overridden. Colors are off without a terminal or with `NO_COLOR`. A run takes about a minute once Carthage is
built. The script exits non-zero if the build fails or `errors.json` is not empty.

The exporter writes into `$HFR_ORACLE_WORK/export`; the files move to the output folder only once the export completed
(`errors.json` written). A failed build leaves the output folder as it was, and only the cases of the run are replaced, so
the output folder can be the input folder (oracles committed beside their pages). The script warns when the legacy checkout
has changes outside the files of `hfrnow.patch`: they would be part of the oracle.

`DIR_WITH_HTML` holds the `.html` pages and an `oracle-map.json`:

```json
{
  "home.html": "forums",
  "page2.html": { "kind": "topics", "currentURL": "/forum1.php?config=hfr.inc&cat=13&page=2&subcat=&owntopic=0" }
}
```

Optional entry keys: `path` (the page, relative to the map folder: the oracle folder can sit next to the map while the pages stay in the shared
corpus, e.g. `"path": "../captures/R04-list-cat13-p1-anon.html"`; the case name is still the key without extension) and `now` (ISO-8601: the clock
the legacy code sees, needed when the output depends on the date, as the list parser's relative dates do).

Kinds: `forums`, `topics`, `favorites`, `mp`, `search` (LOT-002) and `topic` (one topic page, LOT-003). `currentURL` is
optional (the parsers take it as input; defaults are in the specs). A `topic` entry also takes `anchor`, `ownPseudo`,
`blacklist`, `whitelist`, `settings`, `avatarFetch` and `filter` ([LOT-003](../../docs/lots/LOT-003-topic-oracle.md#inputs)). An unknown kind, an unreadable file, or an input file (`.html`, `.json`) missing from the map
is listed in `errors.json` (`oracle-map.json`, `errors.json` and `*.oracle.json` are not inputs).

## How it works

- The patch adds `OracleExport` (XCTest) to the `HFRswiftTests` target. It does nothing unless
  `HFR_ORACLE_IN` and `HFR_ORACLE_OUT` are set, so normal test runs are unaffected. The script passes them as
  `TEST_RUNNER_HFR_ORACLE_*`, which `xcodebuild` forwards to the simulator process.
- Parsers are reached through the Objective-C runtime, exactly like the loader workers call them. An
  Objective-C helper (`OracleObjCSafe.m`) turns a raised `NSException` into data: the legacy parsers raise on
  malformed pages, and Swift cannot catch that.
- State the parsers touch (`hash_check` on the app delegate, `nb_mp` and the favorites category order in
  `UserDefaults`, status notifications) is reset before each case and captured in `sideEffects`.
- Topic cases run with a fixed settings set, an in-memory blacklist and whitelist, and runtime hooks for the case:
  the account list returns the case's pseudo, `ASIHTTPRequest` never touches the network (avatar requests are
  recorded and completed according to `avatarFetch`, on the main thread as ASIHTTPRequest does, so no download races the
  parser; quirk Q33), and the avatar queue of `ParseMessagesOperation` is serial (requests in message order). Everything is
  restored after the case.
- Output uses sorted keys and no run-time timestamps. Dates are UTC ISO-8601; relative display strings
  ("il y a 5 min") depend on the run date: without `now` they are exported as `null`; with `now` the clock is
  frozen at that instant and they are exported unchanged.

## Why the xcconfig

Carthage builds the dependencies with their own project settings, which Xcode 27 rejects:

- some frameworks still target iOS 10.0, below the minimum Xcode 27 accepts, so the file sets
  `IPHONEOS_DEPLOYMENT_TARGET = 15.0`;
- InAppSettingsKit has deprecation warnings that fail under `-Werror`, so it sets
  `GCC_TREAT_WARNINGS_AS_ERRORS = NO` and `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`.

It is passed to Carthage only (`XCODE_XCCONFIG_FILE`), never to the app build.

## Rules

hfrnow is local only: never commit, push or open a PR there. The patch is how its changes travel. After editing
the exporter in hfrnow, regenerate it:

```sh
git -C ~/Git/hfrnow add -N HFRswiftTests/OracleExport.swift HFRswiftTests/OracleExportTopic.swift HFRswiftTests/OracleObjCSafe.m
git -C ~/Git/hfrnow diff --no-color > tooling/legacy-oracle/hfrnow.patch
```

Samples are synthetic. Real captures are anonymized first ([FIXTURES](../../docs/FIXTURES.md)); never put a
real pseudo, cookie or hash in this folder.
