# LOT-160 — Privacy manifest, permissions and export compliance

- **Module:** App
- **Difficulty / model:** easy · Sonnet 5.5 → Opus
- **Issue:** [ezzz/HFRnow#250](https://github.com/ezzz/HFRnow/issues/250)
- **Inputs:** [LOT-071](LOT-071-third-party-services.md) (inventory T1–T8, D-071-1/2/3) · [ADR 0012](../adr/0012-app-project-file-strategy.md)

## Legacy sources
Read-only, `origin/master`: `HFRswift/Info.plist` (usage strings, lines 198-203: camera, photo library, photo library add; background modes `fetch` and
`processing`, lines 211-215; no `ITSAppUsesNonExemptEncryption`, no `NSAppTransportSecurity`), `HFRswift/HFRswift.entitlements` (associated domain
`webcredentials:forum.hardware.fr`, line 7).

## Behaviour
- `App/SwiftHFR/PrivacyInfo.xcprivacy` (folder-synchronized, copied into the app bundle; `project.pbxproj` needs no resource entry).
- Info.plist keys through `INFOPLIST_KEY_*` build settings of the app target (the plist is generated; this is why the project file gains
  four lines in both configurations): `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`
  with the legacy French wording (strings only: image upload is LOT-102, save to Photos LOT-109), and `ITSAppUsesNonExemptEncryption = NO`
  (the app only uses the system's HTTPS and the Keychain; grep of `CryptoKit|CommonCrypto|SHA256|SecKey` over `App/SwiftHFR` and
  `HFRKit/Sources`: no hit).
- `NSPrivacyTracking` false, no tracking domains: R5 of LOT-071 (no analytics, crash-reporting or advertising SDK), no IDFA, no
  `AppTrackingTransparency`.

### Required-reason APIs (grep of `App/SwiftHFR`, `Packages/HFRKit/Sources`, SwiftSoup 2.14.3, 2026-10-28)

| Category | Reason | Evidence |
|---|---|---|
| UserDefaults | `CA92.1` (app's own data) | `HFRStorage/Settings/UserDefaultsSettingsStore.swift` (`UserDefaults.standard`, legacy keys) |
| File timestamp | `C617.1` (files inside the app container) | `HFRStorage/Caches/CacheEvictor.swift:77` and `AvatarCache.swift:36` (`.contentModificationDateKey` on cache files); `FileCredentialStore.swift:103` (`attributesOfItem`, reads `.type` only) |
| System boot time | not declared | no `systemUptime`, `mach_absolute_time`, `ProcessInfo.systemUptime`; SwiftSoup uses `ProcessInfo.environment` only (`DebugTrace.swift`) |
| Disk space | not declared | no `volumeAvailableCapacity*`, `systemFreeSize`, `attributesOfFileSystem` (`fileSizeKey` in `CacheEvictor` is a file size, not a volume) |
| Active keyboard | not declared | no `activeInputModes` |

SwiftUI/SwiftSoup ship no manifest of their own to merge: SwiftSoup is a pure-Swift package without required-reason calls and is not on
Apple's list of SDKs that must carry a manifest. A new dependency or API use updates this table in its own PR.

### Collected data: "Data Not Collected" (operator decision 2026-10-28)
`NSPrivacyCollectedDataTypes` is empty and the App Privacy answer in App Store Connect is "Data Not Collected".

Reasoning: the app is a client. The project runs no server and embeds no third-party SDK (LOT-071 R5: no analytics, crash reporting or
advertising; no Giphy SDK, the GIF picker is a REST client, LOT-098/155). What the user types goes to the services of LOT-071 (HFR, AQ,
the Chevereto rehost, Giphy), which are the user's chosen destinations, not the developer or an SDK acting for the developer.
A first draft declared User ID, Other user content, Photos or videos and Search history; the Opus review asked whether EXIF/GPS in
uploaded images and the AQ per-topic check changed that, and the operator chose the minimal label instead.

Re-check trigger: reassess the label (and this section) when any of these lands: an embedded SDK (for example a Giphy SDK in LOT-155 or
LOT-098), analytics or crash reporting, or a server run by the project. A PR that adds one updates the manifest in the same change.

Password: sent only to `forum.hardware.fr` over HTTPS to log in, kept in the Keychain, never sent elsewhere (R1).

## Edge cases
- Images from third-party hosts in messages (T6) are requested by the reader on tap (D-071-1): they reveal the reader's IP to the host, which
  the manifest does not model (same position as a browser).
- See the re-check trigger above.

## Out of scope / not carried over
- **Associated domains** (`webcredentials:forum.hardware.fr`): needs the capability on the App ID and an entitlement in the signed
  provisioning profile, and `apple-app-site-association` on hardware.fr; an entitlement without the capability breaks signed builds. Left
  to the signing lot (LOT-161) with the operator.
- **Background modes** (`fetch`, `processing`): legacy used them for the MP poll; declared by the lot that schedules it (LOT-047 consumer),
  since an unused mode draws a review question.
- **Archive validation in Organizer** (issue criterion 1): needs signing; the manifest's presence in the built bundle is checked instead
  (see Tests) and the Organizer run is left to the operator at LOT-161.

## Fixtures
None.

## Tests
`App/SwiftHFRTests/PrivacyManifestTests.swift` (app-hosted, reads `Bundle.main`): manifest present with tracking false; required-reason
categories and reasons equal the table above; no collected data types declared; usage strings non-empty and
`ITSAppUsesNonExemptEncryption` false. Each fails without the change (no manifest, no keys).

## Intentional differences from legacy
- `ITSAppUsesNonExemptEncryption` added (legacy answered the export question in App Store Connect each upload).
- Background modes and associated domains not carried over yet (above).

## Learnings
- Generated Info.plist: usage strings are `INFOPLIST_KEY_*` settings, so this lot touches the project file even though ADR 0012's
  folder-synchronization covers the manifest itself.
