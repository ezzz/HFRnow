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
| 3 | Preflight: Xcode ≥ 27; on `dev-swift`; clean tree; `HEAD` = freshly fetched `origin/dev-swift`; API key id, issuer and `.p8` present **and outside the repository**; manual signing names a profile | warnings | hard failures |
| 4 | `xcodebuild archive` (scheme `SwiftHFR`, Release, `generic/platform=iOS`) with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` passed as overrides; `--unsigned` adds `CODE_SIGNING_ALLOWED=NO` | yes | yes (signed) |
| 5 | Archive checks: `CFBundleShortVersionString`/`CFBundleVersion` equal the parameters, `ITSAppUsesNonExemptEncryption` false and `PrivacyInfo.xcprivacy` present (LOT-160), `codesign --verify` when signed | yes | yes |
| 6 | `ExportOptions.plist`: `method` `app-store-connect`, `destination` `export`, `manageAppVersionAndBuildNumber` NO (the build number is ours), `uploadSymbols` YES, `signingStyle`, optional `teamID`, `testFlightInternalTestingOnly`, and for manual signing `signingCertificate` "Apple Distribution" + `provisioningProfiles` {bundle id → profile name}; `plutil -lint` | yes | yes |
| 7 | `xcodebuild -exportArchive` → `.ipa` | signed only | yes |
| 8 | Release notes draft from `scripts/release-notes.template.md` (below) | yes | yes |
| 9 | Confirmation on `/dev/tty`: the operator types `upload <version> (<build>)`; no TTY → refused | — | yes |
| 10 | `xcrun altool --upload-package <ipa> --api-key <id> --api-issuer <issuer> --p8-file-path <p8>` | never | after step 9 |

Flags checked against the local Xcode 27.2 (`xcrun altool --help`, altool 27.10.4; `xcodebuild -help`, export option keys), not
guessed. `altool --upload-app` is the older form; `--upload-package` is the documented one for an `.ipa`.

Output: `build/release/<version>-<build>/` (git-ignored `/build/`) or `--output DIR`: archive, `ExportOptions.plist`, `export/`,
release notes, and one log per long step (`archive.log`, `export.log`, `upload.log`); the console shows `error:` lines only.
Console: `[ok]` green, `[warn]` yellow, `[ko]` red, off without a TTY or with `NO_COLOR`; a spinner while a step runs on a TTY.

### Inputs the operator provides (never in the repository)
`scripts/release.env.example` lists them; copy it to `~/.config/swifthfr/release.env`, `chmod 600`.

| Setting | What | Needed for |
|---|---|---|
| `HFR_ASC_KEY_ID`, `HFR_ASC_ISSUER_ID` | App Store Connect API key id and issuer id (Users and Access → Integrations), role App Manager or higher | upload |
| `HFR_ASC_KEY_PATH` | path of `AuthKey_<id>.p8`, outside the repository (the script refuses a path inside it) | upload |
| `HFR_SIGNING_STYLE` | `manual` (default, legacy habit) or `automatic` | export |
| `HFR_PROFILE_NAME` | App Store provisioning profile for `hfrplus.red.super` (manual), installed with an "Apple Distribution" certificate in the login keychain | export |
| `HFR_TEAM_ID` | team id, when the archive's team is not the one to export with | export (optional) |
| `HFR_ALLOW_PROVISIONING_UPDATES` | `1` lets xcodebuild create or update profiles with the API key (`-allowProvisioningUpdates`, needed by `automatic`). Operator opt-in only: agents and CI never set it (AGENTS.md §11, LOT-080) | export (automatic) |
| `HFR_INTERNAL_ONLY` | `1` marks the build "TestFlight internal testing only" | optional |

The archive itself signs with the project's settings (automatic, team of `App/README.md`); the export re-signs for distribution.
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
| Dry run, signed (uses the keychain identity and installed profiles) | operator |
| `HFR_ALLOW_PROVISIONING_UPDATES=1` | operator |
| Upload (`--upload` + typed confirmation) | operator only (AGENTS.md §0) |
| Tag push, recording the build | operator-confirmed |

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
