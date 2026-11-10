# LOT-173 — Opt-in iCloud Keychain account sync and Face ID / code app lock

- **Module:** HFRStorage (`Sources/HFRStorage/AccountSync/`: the envelope, the rules, the Keychain items) and App (`App/SwiftHFR/Accounts/`, `App/SwiftHFR/AppLock/`, Settings)
- **Difficulty / model:** medium, security-routed (Opus 5.5 author → Fable reviewer, AGENTS.md §6)
- **Issue:** [#312](https://github.com/ezzz/HFRnow/issues/312) · implements [ADR 0013](../adr/0013-storage-tiers.md) §6 (Q12, operator 2026-10-28, residual risks accepted 2026-10-29)
- **Depends on:** LOT-065 (#90, credential store), LOT-081 (#99, `AccountsModel`), LOT-119 (#210, settings screen), LOT-160 (#250, Info.plist keys), all done.

## Legacy sources
Legacy reference `87fe0d1c` (AGENTS.md §2):

| Legacy | Behaviour |
|---|---|
| `Classes/MultisManager.m:43-47` | one Keychain item `HFR_COMPTES_KEY` holding every account, read whole |
| `Carthage/Checkouts/SimpleKeychain/SimpleKeychain/A0SimpleKeychain.m:45` | accessibility `AfterFirstUnlock`, not synchronizable |

Legacy has **no** account sync and **no** app lock: `git grep -n -i "LAContext\|LocalAuthentication\|kSecAttrSynchronizable" 87fe0d1c` finds nothing in the app's code (only Carthage symbol maps). The legacy item is read by LOT-067 and never made synchronizable.

## Legacy counterpart (app lots)
- `App/SwiftHFR/AppLock/AppLockModel.swift`, `AppLockCover.swift`: none @ 87fe0d1c.
- `App/SwiftHFR/Accounts/AccountsModel+Sync.swift`, `App/SwiftHFR/Settings/SecuritySettingsSections.swift`: none @ 87fe0d1c.
- The two rows of the settings screen: none @ 87fe0d1c (`HFRswift/Swift/AppSettingsView.swift` has neither).

## UX evolutions (app lots)
Two new options, both off by default (operator decision Q12, 2026-10-28), already in the gap report: `GAP-168` (iCloud keychain sync) and `GAP-169` (app lock), `new`, `b·operator`. No ledger entry: the rows say what this lot does.

## Behaviour — account sync

### Items
| Item | `kSecAttrAccount` | Accessibility | Synchronizable | Holds |
|---|---|---|---|---|
| device-only (LOT-065, unchanged) | `hfr.accounts.v1` | `AfterFirstUnlockThisDeviceOnly` | no | the accounts: the **master** |
| synchronizable (new) | `hfr.accounts.sync.v1` | `AfterFirstUnlock` (`ThisDeviceOnly` classes cannot sync) | yes | the **sync envelope** below |
| sync state (new) | `hfr.accounts.sync-state.v1` | `AfterFirstUnlockThisDeviceOnly` | no | this device's switch and dates (below) |

All three: generic password, `kSecAttrService` = bundle identifier, data-protection Keychain. The accessibility class is re-applied on every write; a write is update-then-add. The background MP check (LOT-140) runs while the device is locked: every class is `AfterFirstUnlock`. The state item holds no secret but names the accounts (lower-cased pseudos), so it stays in the device-only Keychain rather than in `UserDefaults` (backed up). It is a separate item because a device that honours a tombstone at bootstrap must create **no** device-only accounts item (ADR §6 *Bootstrap*).

No new entitlement: a synchronizable generic-password item in the app's default access group needs iCloud Keychain on the device, not a capability (issue #312). The Mac check confirms that `SecItemAdd` returns `errSecSuccess`, not `errSecMissingEntitlement` (−34018), on a signed build.

### Sync envelope (`AccountSyncEnvelope`, version 1, keys sorted)
- Full: `{"version":1,"enabledAt":<d>,"updatedAt":<d>,"accounts":[{"account":<Account>,"credentialsAt":<d>,"consentAt":<d>}],"removed":{"<account key>":<d>}}`.
- Tombstone: `{"version":1,"deletedAt":<d>,"accounts":[]}`: no credential, no `enabledAt`.
- Dates are `JSONEncoder`'s default (seconds since 2001, `Double`), compared exactly. `updatedAt` = the newest of the `credentialsAt` and `removed` dates (information only: the rules below never compare it).
- A version above 1 → `unsupportedVersion`; anything else unreadable → `corrupted`; neither is ever overwritten by a push, a repair or a switch-on (only switching off writes a tombstone over it). Errors carry no stored byte (LOT-065 rule).
- Account identity is the frozen account key (ADR §7: U+200B removed, then lower-cased, `AccountKey.make`).

### Device state (`AccountSyncState`)
`isOn`, `enabledAt` (the logical version while on), `honouredDeletedAt` (newest tombstone acted on), `provisional` (`enabledAt` of the envelope a bootstrap came from, nil when not provisional), `imported` (account keys lent by that envelope), `stamps` (per account key: `credentialsAt`, `consentAt`), `removed` (per account key: date; recorded only while on). An absent or unreadable state item reads as **off** with nothing known (fail closed).

### Per-account dates (decisions D1, D2)
- `credentialsAt`: the date of the last change of the account's credentials on any device (login, re-login, a cookie or token refresh written back by the session check, a new avatar).
- `consentAt`: the date of the last **explicit login** of that account on any device. A refresh never moves it.
- Recorded by this device at each local change, sync on or off, so a later switch-on has dates to merge. An account with no stamp (stored before this lot, or by the legacy import) has both dates at `distantPast`.
- A removal while on records `removed[key] = now`. A removal while off records nothing: it is this device's own business, and switching on adopts the shared set.

### Merge (one function, used by switch-on and by every read with equal `enabledAt`)
For each account key on either side or in either `removed` map: the copy kept is the one with the later `credentialsAt` (a tie keeps the item's copy, so both devices converge on the same bytes); its `consentAt` is the later of the two; the removal date is the later of the two. If a removal date exists and is **not earlier** than the kept `consentAt`, the account is removed and the marker kept; else the account is kept and the marker dropped. The local order is kept, new accounts are appended; the **main flag stays this device's** (D3): the local main account if still present, else `AccountBook.init(accounts:)` repair.

This settles the two second-order criteria of #312:
- **`updatedAt` tie** (D1, the second option of the issue): with equal `enabledAt`, *Divergence* merges **per account** instead of "newest envelope wins": every read with equal `enabledAt` merges, so a tie on the envelope's `updatedAt` never leaves the other device's accounts unshared, whichever device reads the union.
- **Per-account consent** (D2): a removal marker beats every copy whose `consentAt` is not later than it, so a merge never brings back an account deleted on another device, even when the copy that comes back had its cookies refreshed after the deletion (a refresh is not a consent). An explicit login after the deletion brings it back.

### Operations
Every write to the synchronizable item is a read-compare-write: the item is read, the decision is made, the item is read again just before the write and the write happens only if it still holds the same bytes (Keychain has no conditional write: this narrows the window, the *Race repair* closes it).

**Reconcile** (at launch before the accounts are read, at every foreground, and, as the push, after every local change; only the launch and foreground reads can confirm a provisional bootstrap):

| Switch | Item | Action |
|---|---|---|
| on | absent | nothing (retried at the next reconcile; never re-created by a push) |
| on | unreadable | nothing, reported |
| on | tombstone, `deletedAt >= enabledAt` | switch off, `honouredDeletedAt = deletedAt`; provisional → delete the imported accounts |
| on | tombstone, `deletedAt < enabledAt` | re-write this device's full envelope over it (superseded opt-out) |
| on | full, `enabledAt >` mine | switch off (fail closed, ADR *Divergence*); provisional → delete the imported accounts |
| on | full, `enabledAt <` mine | re-write this device's full envelope (raced or stale) |
| on | full, equal `enabledAt` | merge; write the device-only item and the item when each changed; at launch or foreground, provisional and `enabledAt` = the bootstrap's → provisional ends (*confirming read*) |
| off | full, `enabledAt <= honouredDeletedAt` | *Race repair*: re-write the tombstone `honouredDeletedAt` |
| off, no local account | full with accounts, `enabledAt >` every known `deletedAt` | *Bootstrap*: import, switch on, adopt `enabledAt`, provisional, imported = its keys |
| off, no local account | tombstone | `honouredDeletedAt = max(honouredDeletedAt, deletedAt)`; no device-only item |
| off | anything else | nothing |

**Switch on** (the user's toggle): item unreadable → refused, nothing changes. Item absent, tombstone, or a full envelope whose `enabledAt` is not later than `honouredDeletedAt` (a raced envelope, D5) → a new `enabledAt` = `max(now, deletedAt + 1 ms, honouredDeletedAt + 1 ms)` and a full envelope of this device's accounts only. Full envelope otherwise → adopt its `enabledAt`, merge, write both. Never provisional.

**Switch off** (the user's toggle): writes the tombstone `deletedAt = max(now, enabledAt)` (a tie switches the other devices off) over whatever the item holds, records it as `honouredDeletedAt`, clears the switch, the stamps of removals and the provisional state. Provisional → deletes the imported accounts first. Never deletes an account entered on the device.

**Local change** (login, re-login, refresh, removal written by `AccountsModel`; a refresh only when the stored copy really changed): records the stamp (login: both dates; refresh: `credentialsAt`; removal: drops the stamp, and while on adds `removed[key]`), then reconciles (the push). A login or re-login takes that account out of the imported set: it was entered on this device and is never dropped (D8). Choosing the main account is not a change (D3).

### Provisional bootstrap
As ADR §6 *Bootstrap*, with one change (D8): the imported accounts are deleted only if the device switches off (a tombstone, a later `enabledAt`, its own switch-off) **before** its first confirming read (the next launch or foreground that finds the envelope it bootstrapped from). A login on the device does not end the window; it takes the account it logs in out of the imported set, so a provisional switch-off deletes the imported accounts only and keeps every account entered on the device (#312 acceptance criterion). The push of a local change is not a confirming read. After the window a switch-off deletes nothing (*Late repair*, accepted residual risk).

### App side
- `AccountsModel` takes an optional `AccountSyncing` (the engine; nil in tests that do not need it). It reconciles before its first read at launch and at each foreground, and reports each successful store write (login, refresh, avatar, removal) to it.
- A report that replaced or added accounts rebuilds their sessions from the stored cookies and checks them; a report that removed accounts drops their sessions; a switch-off by another device is shown once in the settings section ("La synchronisation a été désactivée sur un autre appareil.").
- Settings, section "Comptes" (`SecuritySettingsSections`): the toggle "Synchroniser mes comptes via le trousseau iCloud" and its explanation (text below, to be reviewed by the operator before merge).

> Vos comptes (cookies de session et jeton `hash_check`, jamais de mot de passe) sont copiés dans votre trousseau iCloud, chiffré de bout en bout par Apple, et apparaissent sur vos autres appareils où l'option est activée. Désactiver l'option retire la copie iCloud sur tous vos appareils ; chaque appareil garde les comptes qui y sont connectés.

## Behaviour — app lock
- Settings, section "Sécurité": "Verrouiller l'app (Face ID / code)" (`app_lock_enabled`, device scope, default off) and the picker "Verrouiller" (`app_lock_grace_seconds`: 0 "Immédiatement" (default), 60 "Après 1 minute", 300 "Après 5 minutes"; any other value reads as 0). Device scope: a lock is a property of the device (ADR 0013 appendix E has no row for these keys yet; they follow its "device capability" rule).
- `LocalAuthentication`, policy `deviceOwnerAuthentication` (biometrics, then the device passcode). No PIN of our own. The toggle only turns on when the device can evaluate the policy (a passcode is set); otherwise it stays off with "Définissez un code sur l'appareil pour utiliser le verrouillage."
- **When:** locked at launch when on; at each return to the foreground when the app spent at least the grace delay in the **background** (`inactive` alone, e.g. the Face ID sheet itself, Control Center, never locks). Turning the option on does not lock immediately.
- **Cover:** one `AppLockModel` for the app; each scene gets a window of its own at level `.alert + 1` holding `AppLockCover`, so sheets and alerts are covered too. Shown while locked, and while the app is not `active` when the option is on (so the app switcher snapshot shows the cover, not a topic). The content stays mounted under the cover (no navigation, draft or scroll state lost) and is hidden from VoiceOver (`accessibilityHidden`) while covered; the cover is modal (`accessibilityViewIsModal`, `.isModal`) with one button "Déverrouiller". No animation at all: the cover must be in place before the system takes the snapshot, so Reduce Motion has nothing to reduce.
- Authentication starts by itself once when the app becomes active while locked, never again after a failure or a cancel (no loop between the system sheet and the scene phase); the button retries. A failed or cancelled authentication keeps the cover. If the device no longer has a passcode (`passcodeNotSet`), the app unlocks (the lock has nothing to rely on; D6) and the option stays on.
- The lock is UI only: nothing in the engine waits on it, so the background MP check (LOT-140) and the session checks run while locked.
- `NSFaceIDUsageDescription` = "Utilisé pour déverrouiller l'app lorsque le verrouillage est activé." (both build configurations).

## Edge cases
- Two items (accounts and state) cannot be written atomically. Order: switch-off writes the tombstone, then deletes the imported accounts of a provisional bootstrap, then writes the state; a crash in between leaves the device on with a tombstone to honour at the next read. Bootstrap writes the state (on, provisional) before the accounts: a crash in between leaves an "on" device without accounts, which merges them at the next read.
- iCloud Keychain may deliver the envelope after the tombstone, or not at all: absence never acts, a raced envelope is repaired by any switched-off device.
- A device whose switch is on but whose iCloud Keychain is off keeps writing an item that never leaves it: harmless; turning iCloud Keychain off is the user's choice.
- The legacy import (LOT-158) and the LOT-157 wipe write the device-only item without going through `AccountsModel`: an account they add is shared at the next reconcile (it has no stamp: any removal marker beats it); an account the LOT-157 wipe removes must be reported as a removal (`AccountSyncing.localChange(.removed)`) or it comes back from the envelope at the next merge (noted on #312 by LOT-157; LOT-157 is not merged yet, so its PR wires it).
- Clock skew (accepted, ADR §6).

## Fixtures
None: synthetic accounts with fake cookie values (`HFRModels` test helpers).

## Tests
- Engine (`Packages/HFRKit/Tests/HFRStorageTests/AccountSync/`, every platform, in-memory items and a fixed clock): envelope round-trip, tombstone shape, versions and corruption; every row of the reconcile table; switch-on over absent/tombstone/full/raced/unreadable; switch-off (tombstone written over everything, imported dropped only while provisional); the ADR interleaving (stale read, tombstone 150, stale write 160, repair, switch-off) through a scripted item that writes in between the re-read and the write; tie `deletedAt == enabledAt`; later `enabledAt` refuses a push; two devices that each hold accounts stay on; the `updatedAt` tie read by the device holding the newest account; per-account consent (D switched off holding y, y deleted on B, D on again: y does not return; a refresh after the deletion does not bring it back; a login does); late repair on both sides of the provisional window.
- Keychain attributes: the three item descriptors (accessibility, synchronizable, account name) on every platform; on Apple platforms, the query dictionaries passed to a scripted `KeychainCalls` double (`kSecAttrSynchronizable`, `kSecAttrAccessible`, data-protection Keychain, update-then-add). The real Keychain only runs on a signed host (`HFR_KEYCHAIN_TESTS=1`, LOT-065).
- App (`App/SwiftHFRTests/`): `AppLockModel` (launch lock, grace delays 0/60/300 on both sides, `inactive` never locks, failed and cancelled authentication keep the cover, no automatic retry, unavailable policy refuses the toggle), `AccountsModel` + sync (a report rebuilds and drops sessions, local changes are reported with their kind, the switch reflects the engine).

## Mac checks (two devices, one Apple ID, iCloud Keychain on)
1. Device A: log in, switch on. Device B (fresh install): launch → the accounts appear without login, switch on.
2. B: re-login one account → A gets the new cookies at its next foreground.
3. A: switch off → B switches off at its next foreground and keeps its accounts.
4. App lock on A: background 2 min with "1 minute" → cover and Face ID; cancel keeps the cover; the app switcher shows the cover; VoiceOver reads only "Déverrouiller"; Reduce Motion on: no animation.
5. `xcodebuild build test` on the iPhone 18 Pro and an iPad simulator (iOS 27.0); `HFR_KEYCHAIN_TESTS=1` suite on a signed host.

## Decisions needed (defaults implemented)
- **D1** `updatedAt` tie: per-account merge whenever `enabledAt` is equal (the issue's second option) instead of newest-envelope-wins.
- **D2** per-account consent: removal markers in the envelope, beaten only by a later explicit login (`consentAt`), not by a refresh.
- **D3** the main account is per device and not synced; a bootstrap takes the envelope's.
- **D4** grace delay choices 0 / 1 / 5 min, default immediate; both lock settings device-only.
- **D5** switch-on over a raced envelope (`enabledAt <= honouredDeletedAt`) treats it as a tombstone: a new `enabledAt`, this device's accounts only.
- **D6** a device whose passcode was removed unlocks instead of locking the user out.
- **D7** the ADR rules as written above (the maintainer confirms them here, ADR §6 last line).
- **D8** a login during the provisional window does not end it (ADR §6 says it does): it only marks the logged-in account as the device's own, so a provisional switch-off still drops the lent accounts, as #312's acceptance criterion asks. The window ends at the first launch or foreground read that confirms the envelope.
- **D9** ADR 0013 appendix E has no row for `app_lock_enabled` and `app_lock_grace_seconds`: they are catalogued `.device` (the device-capability rule); the row is an ADR edit left to the maintainer.

## Intentional differences from legacy
New features; legacy had neither.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
