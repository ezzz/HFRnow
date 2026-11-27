# LOT-161 — Release pipeline: archive and TestFlight upload

- **Module:** App (tooling: `scripts/release-testflight.sh`)
- **Difficulty / model:** medium · Opus 5.5 → Fable (AGENTS.md §6)
- **Issue:** [ezzz/HFRnow#251](https://github.com/ezzz/HFRnow/issues/251)
- **Inputs:** [LOT-080](LOT-080-app-target.md) (app target, scheme `SwiftHFR`) · [LOT-160](LOT-160-privacy-manifest.md) (manifest,
  export compliance) · [ADR 0007](../adr/0007-third-party-api-keys.md) (keys outside the repository) · [ADR 0012](../adr/0012-app-project-file-strategy.md)

## Legacy sources
Read-only, ezzz/HFRnow `master` @ `21173e77`:
- `push_realease.md` (whole file): the legacy hand procedure. Bump `CURRENT_PROJECT_VERSION` of target `HFRswift` in the project file,
  manual signing with profile `iOS-Distribution-Profile-v2` and identity `iPhone Distribution`, a Release build check, a commit
  "Prepare build N", a tag `build#N`, push, then a French summary of the changes grouped by theme. Archive, export and upload were
  done in Xcode by hand ("À clarifier" section).
- `SuperHFRplus.xcodeproj/project.pbxproj:6056,6095,6098` (Debug) and `:6138,6173,6176` (Release): target `HFRswift`, bundle id
  `hfrplus.red.super`, `MARKETING_VERSION = 4.0.3`, `CURRENT_PROJECT_VERSION = 36`. The issue's floor (4.0.2 build 30) is older:
  the last legacy tag is `build#30`, but the project file went on to 4.0.3 (36).

## Behaviour
One Mac script, run by the maintainer (no `workflow_dispatch`: workflows only run from the legacy default branch, ADR 0010).

```sh
scripts/release-testflight.sh --version 5.0 --build 37 --dry-run [--unsigned]   # stops before the upload
scripts/release-testflight.sh --version 5.0 --build 37 --upload                 # operator only
```

Steps, in order (each failure stops the script):

| # | Step | Dry run | `--upload` |
|---|---|---|---|
| 1 | Arguments: `--version` and `--build` are required (no default), numeric, version strictly above the legacy floor `4.0.3` | checked | checked |
| 2 | Local settings: environment variables, then `~/.config/swifthfr/release.env` (or `--config`, `HFR_RELEASE_CONFIG`), parsed for known keys, never sourced; warns when group/other can read it | loaded | loaded |
| 3 | Preflight: Xcode ≥ 27; on `dev-swift`; clean tree; `HEAD` = freshly fetched `origin/dev-swift`; API key id, issuer and `.p8` present **and outside the repository**; manual signing names a profile, automatic signing has the provisioning opt-in, `--since` ref exists | warnings (a key file inside the repository, an unknown `--since` ref: hard failures) | hard failures |
| 4 | `xcodebuild archive` (scheme `SwiftHFR`, Release, `generic/platform=iOS`) with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` passed as overrides; `--unsigned` adds `CODE_SIGNING_ALLOWED=NO` | yes | yes (signed) |
| 5 | Archive checks: `CFBundleShortVersionString`/`CFBundleVersion` equal the parameters, `ITSAppUsesNonExemptEncryption` false and `PrivacyInfo.xcprivacy` present (LOT-160), `codesign --verify` when signed | yes | yes |
| 6 | `ExportOptions.plist`: `method` `app-store-connect`, `destination` `export`, `manageAppVersionAndBuildNumber` NO (the build number is ours), `uploadSymbols` YES, `signingStyle`, optional `teamID`, `testFlightInternalTestingOnly`, and for manual signing `provisioningProfiles` {bundle id → profile name} plus `signingCertificate` when `HFR_SIGNING_CERTIFICATE` is set (unset: Xcode's selector picks a distribution certificate); `plutil -lint` | yes | yes |
| 7 | `xcodebuild -exportArchive` → `.ipa` | signed only | yes |
| 8 | Release notes draft from `scripts/release-notes.template.md` (below) | yes | yes |
| 9 | Confirmation on `/dev/tty` (prompt and answer): the operator types `upload <version> (<build>)`; `/dev/tty` cannot be opened → refused at step 1, before any fetch or build | — | yes |
| 10 | `xcrun altool --upload-package <ipa> --api-key <id> --api-issuer <issuer> --p8-file-path <p8>` | never | after step 9 |

Flags checked against the local Xcode 27.2 (`xcrun altool --help`, altool 27.10.4; `xcodebuild -help`, export option keys), not
guessed. `altool --upload-app` is the older form; `--upload-package` is the documented one for an `.ipa`.

Output: `build/release/<version>-<build>/` (git-ignored `/build/`) or `--output DIR` (relative to the current directory, like `--config`): archive, `ExportOptions.plist`, `export/`,
release notes, and one log per long step (`archive.log`, `export.log`, `upload.log`); the console shows `error:` lines only.
Console: `[ok]` green, `[warn]` yellow, `[ko]` red, off without a TTY or with `NO_COLOR`; a spinner while a step runs on a TTY.

### Inputs the operator provides (never in the repository)
`scripts/release.env.example` lists them; copy it to `~/.config/swifthfr/release.env`, `chmod 600`.

| Setting | What | Needed for |
|---|---|---|
| `HFR_ASC_KEY_ID`, `HFR_ASC_ISSUER_ID` | App Store Connect API key id and issuer id (Users and Access → Integrations), role App Manager or higher | upload |
| `HFR_ASC_KEY_PATH` | path of `AuthKey_<id>.p8`, outside the repository (the script refuses a path inside it) | upload |
| `HFR_SIGNING_STYLE` | `manual` (default, legacy habit) or `automatic` | export |
| `HFR_SIGNING_CERTIFICATE` | certificate for manual signing; empty lets Xcode pick a valid distribution certificate (legacy used "iPhone Distribution") | export (optional) |
| `HFR_PROFILE_NAME` | name of the App Store provisioning profile for `hfrplus.red.super` (manual), installed in Xcode; its distribution certificate and private key are in the login keychain (see `HFR_SIGNING_CERTIFICATE`) | export |
| `HFR_TEAM_ID` | team id, when the archive's team is not the one to export with | export (optional) |
| `HFR_ALLOW_PROVISIONING_UPDATES` | `1` lets xcodebuild create or update profiles with the API key (`-allowProvisioningUpdates`, needed by `automatic`), on archive and export, so a signed dry run then contacts Apple too (signing only, no upload). Operator opt-in only: agents and CI never set it (AGENTS.md §11, LOT-080) | export (automatic) |
| `HFR_INTERNAL_ONLY` | `1` marks the build "TestFlight internal testing only" | optional |

The archive itself signs with the project's settings (automatic, team of `App/README.md`); the export re-signs for distribution.
Measured 2026-11-02 on the maintainer's Mac: a signed archive without the opt-in fails at once with "No profiles for
'hfrplus.red.super' were found … Automatic signing is disabled and unable to generate a profile" (no iOS App Development profile for
that bundle id is installed; nothing is sent to Apple). Before the first signed run the operator either installs one (open the
project in Xcode once with the team's account, or download it from the developer portal) or sets `HFR_ALLOW_PROVISIONING_UPDATES=1`.
The script never edits `project.pbxproj` nor the operator's signing settings: the version and build exist only in the archive.

### Version and build rule — OPEN QUESTION (operator)
App Store Connect refuses a version lower than the last one on the App Store and a build number already used for that version.
The highest legacy values found are 4.0.3 (36) (above); what App Store Connect actually holds is only visible to the operator
(TestFlight tab of the app record), and that is the real floor.

| Option | First upload | Later builds |
|---|---|---|
| A — continue the legacy counter (recommended) | `5.0` (`37`, or above the highest build in App Store Connect) | build +1 on every upload, never reset nor reused, across versions; version bumped per milestone (5.0 → 5.1 …) |
| B — restart per version | `5.0` (`1`) | build +1 within a version, back to 1 on each new version |

A keeps one monotonic counter, so a TestFlight crash report or a tester's "build N" never names two binaries; B is allowed by
App Store Connect but makes legacy build 1–36 and SwiftHFR build 1–36 ambiguous. Asked on #251; the script enforces only what is
certain (numeric values, version above 4.0.3) until the operator decides, then this section records the rule.

After an upload (by hand, operator-confirmed): record the version and build on #251 or the PR, paste the release notes in
TestFlight ("What to Test"), tag the commit `swifthfr-<version>-<build>` and push the tag (the next release notes start from it).

### Release notes template
`scripts/release-notes.template.md`: French sections from the legacy habit (Corrections, Améliorations de l'interface, Navigation
et stabilité, Recherche/favoris/messages, À tester en priorité), filled by the author, plus the raw `git log` since the last
`swifthfr-*` tag (or `--since REF`) for the author's eyes only. TestFlight's "What to Test" holds at most 4000 characters.

### Dry run vs operator-confirmed

| Action | Who |
|---|---|
| Dry run, unsigned (`--dry-run --unsigned`) | anyone, agents included |
| Dry run, signed (uses the keychain identity and installed profiles; contacts Apple only with `HFR_ALLOW_PROVISIONING_UPDATES=1`) | operator |
| `HFR_ALLOW_PROVISIONING_UPDATES=1` | operator |
| Upload (`--upload` + typed confirmation) | operator only (AGENTS.md §0) |
| Tag push, recording the build | operator-confirmed |

## Step 1 — internal TestFlight beta under its own bundle id (`--beta`)
Operator decision of 2026-11-27 on #251: a minimal internal TestFlight now, before the in-place update of
`hfrplus.red.super` (which stays the final release: ADR 0011 Q-1, ADR 0013 §5). Testers: ezzz and the operator, App Store
Connect users in an internal group (internal testing needs no Beta App Review).

### Configuration and scheme
- Build configuration **`Beta`** (a copy of `Release`, project and both targets) and shared scheme **`SwiftHFR Beta`**
  (run, profile and archive in `Beta`; test stays `Debug`, like `SwiftHFR`). `SwiftHFR` and its Debug/Release are unchanged.
- The beta's identity lives in `App/Config/Beta.xcconfig`, which includes `Shared.xcconfig` (so the API keys of
  `Secrets.xcconfig` reach the beta too): `PRODUCT_BUNDLE_IDENTIFIER = hfrplus-swift.red.super`,
  `INFOPLIST_KEY_CFBundleDisplayName = SwiftHFR β`, `DEVELOPMENT_TEAM = QMG83DG7YP`, `CODE_SIGN_STYLE = Automatic`. The
  target's `Beta` configuration does **not** set the bundle id nor the display name: a target setting would win over the
  xcconfig. `scripts/tests/test_beta_configuration.py` guards this, and that Debug/Release keep `hfrplus.red.super`.
- Same pattern as legacy's separate `hfrplus-legacy.red.super` (`SuperHFRplus.xcodeproj/project.pbxproj:6345,6410`
  @ `87fe0d1c`: its own bundle id, display name and build counter, `CURRENT_PROJECT_VERSION = 30`, `MARKETING_VERSION = 3.2`).
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are build-time overrides passed by the script, as for the store build.

### What reads the bundle id at run time
All derive from `Bundle.main.bundleIdentifier`, so the beta follows without code: the account keychain service
(`AccountServices.swift`, `LegacyImportServices.swift`), the YouTube player `Referer` (`VideoPlayerSheet.appReferer`, test
case added for the beta id). No app group, no notification category or background task identifier is derived from it
(`com.hfrplus.refresh_mp` is a fixed per-app identifier).

### Capabilities of the beta App ID (ezzz, #1134)
There is no entitlements file in the repository today: the iCloud key-value wiring (#447) is not merged, the keychain uses
the default access group (LOT-173: no capability), local notifications need no capability, and background refresh is
Info.plist only (`UIBackgroundModes` `fetch`, `BGTaskSchedulerPermittedIdentifiers`). So the first beta needs **no
capability** on the App ID. To enable now anyway, so #447 does not break the next beta: **iCloud, Key-value storage only**
(no CloudKit container). #447 adds `com.apple.developer.ubiquity-kvstore-identifier` =
`$(TeamIdentifierPrefix)$(CFBundleIdentifier)` (ADR 0013 line 115), which resolves to the beta id on the beta App ID
by itself. Not wanted: Push Notifications, Associated Domains (out of scope above), App Groups.

### Beta numbering rule
- The beta record is a new app: **no legacy floor**; `--version` is required (5.0 while `MARKETING_VERSION` is 5.0).
- **Its own build counter, from 1**, +1 per upload, never reused, across versions (option A's monotonic rule applied to the
  beta record; the legacy-counter question of #251 only concerns the final in-place update). Integers only.
- The last uploaded beta build is kept **outside the repository** in `~/.config/swifthfr/beta-build-number`
  (`HFR_BETA_COUNTER`, absolute path, refused inside the repository). Without `--build`, the script uses counter + 1
  (1 when the file is missing); `--build N` at or below the counter is warned in a dry run and refused with `--upload`.
  The script writes the counter only after a successful upload: a dry run never consumes a number. App Store Connect
  stays the authority: uploading from a second Mac needs that Mac's counter set by hand (or `--build`).
- Tags: `swifthfr-beta-<version>-<build>`; the release notes list the changes since the last `swifthfr-beta-*` tag.

### What `--beta` changes in the script
Scheme `SwiftHFR Beta`, configuration `Beta`; the archived bundle id must be `hfrplus-swift.red.super` (and
`hfrplus.red.super` without `--beta`: both runs now check it); default settings file `~/.config/swifthfr/release-beta.env`
(same keys, `HFR_PROFILE_NAME` names the profile of the beta id); `HFR_INTERNAL_ONLY` forced to 1
(`testFlightInternalTestingOnly`); output `build/release/beta-<version>-<build>/`. The upload prompt lists the app record,
scheme, version, build, commit, package and size, tester scope and API key id, then asks for the typed confirmation.

### Before the first upload
**ezzz** (#1134): create the explicit App ID `hfrplus-swift.red.super` on team `QMG83DG7YP` (iCloud KV storage enabled, see
above); create the App Store Connect app record on it (a unique name, e.g. « SwiftHFR β », primary language French, any
SKU); add the operator as a user (App Manager can upload with an API key; creating distribution profiles needs Admin,
#1134); create the internal testing group with ezzz and the operator. Then either he uploads from his Mac or the operator does.

**Operator** (or whoever uploads):
1. App Store Connect API key (Users and Access → Integrations, role App Manager or higher), saved as
   `~/.appstoreconnect/private_keys/AuthKey_<id>.p8`, `chmod 600`; never in the repository.
2. `cp scripts/release.env.example ~/.config/swifthfr/release-beta.env`, `chmod 600`, fill the key id, issuer and path.
3. Signing: an Apple Distribution certificate in the login keychain and an App Store profile for `hfrplus-swift.red.super`
   (`HFR_SIGNING_STYLE=manual`, `HFR_PROFILE_NAME`), plus a development profile for the archive's automatic signing (open
   the project once in Xcode with the team's account and the `SwiftHFR Beta` scheme); or the operator's opt-in
   `HFR_SIGNING_STYLE=automatic` + `HFR_ALLOW_PROVISIONING_UPDATES=1`. Agents never pass `-allowProvisioningUpdates`.
4. `App/Config/Secrets.xcconfig` filled on that Mac, or the beta ships with image upload and the GIF picker off.

### Dry-run procedure
1. Anyone, agents included: `scripts/release-testflight.sh --beta --version 5.0 --dry-run --unsigned` (archive, Info.plist
   and bundle-id checks, `ExportOptions.plist`, notes; nothing sent to Apple).
2. Operator: `scripts/release-testflight.sh --beta --version 5.0 --dry-run` on `dev-swift` = `origin/dev-swift`, clean tree
   (signed archive and export; nothing uploaded, counter untouched).
3. Operator only, confirmed: `scripts/release-testflight.sh --beta --version 5.0 --upload`, type `upload 5.0 (N)`. Then
   record the build on #251, add the build to the internal group if it is not automatic, paste the notes in "What to
   Test", tag `swifthfr-beta-5.0-N` (operator-confirmed push).

### Known limits of the beta id
- **No legacy data migration test**: the beta has its own container and keychain service, so it never sees the data of
  `hfrplus.red.super` (legacy HFR+); LOT-067/LOT-158 are tested on the in-place update only. Accounts are logged in again.
- **Its own iCloud key-value store** (ADR 0013 line 115 derives it from the bundle id): once #447 lands, beta settings do
  not sync with the store app's.
- Same app icon as the store build: the home screen tells them apart by the display name « SwiftHFR β »; both can be
  installed side by side.
- The counter is per Mac (above).

### Measured (2026-11-27, mac/mac-mbp-w251, Xcode 27.2)
Pending the build slot; filled before the PR leaves draft.

## Edge cases
- A build number already in App Store Connect: altool fails after the upload starts; the script cannot know it locally. Pick a
  higher one (the rule above).
- Archive folder already present: the script stops instead of overwriting (an uploaded build's archive is kept for its dSYMs).
- Manual signing without `HFR_PROFILE_NAME`: warned in a dry run, refused with `--upload`.
- No TTY (agent, CI): the upload is refused before any network call.

## Dry run (2026-11-02, mac/lot-161, Xcode 27.2)
`--version 5.0 --build 1 --dry-run --unsigned` on the lot branch: archive succeeded, Info.plist `hfrplus.red.super 5.0 (1)`,
`ITSAppUsesNonExemptEncryption` NO, manifest present, `ExportOptions.plist` linted, notes written; warned about branch, `HEAD` and
missing API key settings; nothing sent to Apple. Not run: signed archive, export, upload (need the operator's signing assets and key).

## Intentional differences from legacy
- No project-file bump, release commit nor `build#N` tag push by the script: the version and build are build-time overrides
  verified in the archive, and tagging stays an operator action.
- Upload from the command line with an API key instead of Xcode Organizer.
- `ITSAppUsesNonExemptEncryption` already answered by LOT-160, so no export question at each upload.

## Out of scope
- The App Store submission (LOT-165) and its metadata.
- Associated domains `webcredentials:forum.hardware.fr` (LOT-160 out of scope): needs the App ID capability and a profile including
  it; not added here.
- The iPad simulator run and the Organizer validation deferred by LOT-160: left to the operator's first signed run (Organizer, or
  `xcrun altool --validate-app <ipa>` with the same API key, before `--upload`).

## Learnings
- `xcodebuild -exportArchive` re-signs an automatically signed archive with cloud-managed certificates only with
  `-allowProvisioningUpdates`, which agents never pass: manual export signing (distribution certificate + App Store profile) is the
  default so the script does not need it.
