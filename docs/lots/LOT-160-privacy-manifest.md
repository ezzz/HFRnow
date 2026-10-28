# LOT-160 — Privacy manifest, permissions and export compliance

- **Module:** App
- **Difficulty / model:** easy · Sonnet 5.5 → Opus
- **Issue:** [ezzz/HFRnow#250](https://github.com/ezzz/HFRnow/issues/250)
- **Inputs:** [LOT-071](LOT-071-third-party-services.md) (inventory T1–T8, D-071-1/2/3) · [ADR 0012](../adr/0012-app-project-file-strategy.md)

## Legacy sources
Read-only, `origin/master`: `HFRswift/Info.plist` (usage strings: camera, photo library, photo library add; background modes `fetch` and
`processing`; no `ITSAppUsesNonExemptEncryption`, no `NSAppTransportSecurity`), `HFRswift/HFRswift.entitlements` (associated domain
`webcredentials:forum.hardware.fr`).

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

### Collected data (App Privacy answers, draft for the operator in App Store Connect)
"Collected" is Apple's sense: data transmitted off the device to the developer or a third party and kept longer than it takes to service
the request (Apple excludes data the recipient discards right after answering). The project runs no server; the data below goes to the
services of LOT-071, whose retention is not audited (HFR posts and AQ entries are public by nature, an uploaded image is public, Giphy's
is unknown), so each is declared conservatively. A lot that adds a data flow assesses the recipient's retention before it adds a
declaration or changes an App Privacy answer. Never used for tracking, never for advertising; purpose App Functionality only. The manifest declares
what the MVP and the lots already specified send, so the answers do not need revising per lot.

| Manifest type | Linked | Why (LOT-071 row) |
|---|---|---|
| User ID | yes | the pseudo, sent to HFR on login and posting, and to AQ on creation (T3) |
| Other user content | yes | posts, private messages and drafts sent to HFR; the AQ title and comment (T3) |
| Photos or videos | no | an image uploaded to the Chevereto rehost (T4), no cookie, no account id |
| Search history | yes | search terms sent to HFR with the session cookies (`HFRNetwork/Endpoints/HFREndpoint+Search.swift`, `TopicSearchQuery`, `GlobalSearchQuery`: engine only, the search screen is a later lot) and, unlinked, to Giphy by the GIF picker (T5, LOT-098/155; not in the build yet, REST client without SDK). Linked because the forum request is authenticated |

Not declared: contact info, location, identifiers (IDFA, device id), diagnostics, usage data, purchases: nothing of the sort is sent (R5).
Password: sent only to `forum.hardware.fr` over HTTPS to log in, kept in the Keychain, never sent elsewhere (R1); like legacy it is
authentication to the forum, not data collected by the app, and no Apple data type matches it.

## Edge cases
- Images from third-party hosts in messages (T6) are requested by the reader on tap (D-071-1): they reveal the reader's IP to the host, which
  the manifest does not model (no data is *collected by the app*; same position as a browser).
- If a lot adds a data flow or an SDK (Giphy SDK, analytics), the manifest and this spec change in that lot's PR.

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
categories and reasons equal the table above; collected data never tracking and App Functionality only; usage strings non-empty and
`ITSAppUsesNonExemptEncryption` false. Each fails without the change (no manifest, no keys).

## Intentional differences from legacy
- `ITSAppUsesNonExemptEncryption` added (legacy answered the export question in App Store Connect each upload).
- Background modes and associated domains not carried over yet (above).

## Learnings
- Generated Info.plist: usage strings are `INFOPLIST_KEY_*` settings, so this lot touches the project file even though ADR 0012's
  folder-synchronization covers the manifest itself.
