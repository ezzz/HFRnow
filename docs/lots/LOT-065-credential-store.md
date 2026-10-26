# LOT-065 — Account & credential store

- **Module:** HFRStorage
- **Difficulty / model:** difficult (Opus → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [A §4.2–4.3, NET-05](../audit/A-network-sessions.md), [E §2.1, §5, E-6](../audit/E-storage-vendors.md); decision Q-9 ([audit README](../audit/README.md)).

| Legacy | Behaviour |
|---|---|
| `Classes/Constants.h:115-121` | one Keychain item `HFR_COMPTES_KEY`; per account `PSEUDO`, `PSEUDO_DISPLAY`, `COOKIES`, `HASH`, `AVATAR`, `MAIN` |
| `Classes/MultisManager.m:43-47` | every read unarchives the whole blob (`NSKeyedUnarchiver`, insecure coding) |
| `Classes/MultisManager.m:49-86` | add: first account becomes main; duplicate detected by `md_user`, then **silently dropped** with its fresh cookies |
| `Classes/MultisManager.m:88-105` | set main: one `MAIN` flag |
| `Classes/MultisManager.m:125-153` | delete: when the deleted account was main (or no main is left), the first remaining account becomes main |
| `HFRswift/Swift/AccountSessionService.swift:61-75` | pseudo trimmed and required; the new account becomes main after login |
| `HFRswift/Swift/AccountSessionService.swift:143-163` | lookup by pseudo, then display name, case- and diacritic-insensitive |
| `Carthage/Checkouts/SimpleKeychain/SimpleKeychain/A0SimpleKeychain.m:45, 230-231` | accessibility `AfterFirstUnlock` (not this-device-only) |

## Behaviour
- **`AccountBook`** (value type): the accounts in insertion order with exactly one main account whenever there is any.
  - `add(_:makeMain:)`: pseudo normalised (surrounding whitespace and Unicode format characters, category Cf such as U+200B and U+FEFF, removed); empty or `deleted` in any case (the logged-out `md_user` value, A §4.1) → `CredentialStoreError.invalidPseudo`. When the cookies hold `md_user`, it must name the same pseudo (ignoring case, raw or percent-decoded): legacy takes the pseudo from it (`MultisManager.m:55-60`), so a mismatch → `pseudoMismatch`, and `md_user=deleted` (logged-out session) → `invalidPseudo`. Same pseudo ignoring case → the stored account is refreshed in place: new cookies replace the old ones, a nil `hashCheck` or `avatarData` keeps the stored one, the stored spelling of the pseudo and the main flag stay, and a display name equal to the stored one or to the pseudo ignoring case (a re-login typed in lower case) keeps the stored display name. `makeMain` (default true, as the legacy login flow) makes it main; the first account is always main.
  - `setMain(pseudo:)`, `remove(pseudo:)` (promotes the first remaining account when the main one goes), `replace(_:)`, `account(matching:)`: lookup by exact pseudo, then pseudo ignoring case, then display name ignoring case.
  - `init(accounts:)` repairs what it loads: duplicate pseudos keep the first, several mains keep the first, no main makes the first one main.
- **`CredentialStore`** protocol: `load()`, `update(_:)` (read, edit, write only if changed, as one step under the store's lock), `removeAll()`; extension helpers `accounts()`, `mainAccount()`, `save(_:makeMain:)`, `setMain(pseudo:)`, `deleteAccount(pseudo:)`.
- **`CredentialEnvelope`**: `{"version":1,"accounts":[<Account Codable>]}`, keys sorted. Version above 1 → `unsupportedVersion(n)`; anything else unreadable → `corrupted`. Neither is ever overwritten by `update`: the only way out is an explicit `removeAll()` decided by the app (the "never overwrite with empty" rule of E-2 applied to accounts).
- **`KeychainCredentialStore`** (`#if canImport(Security)`): one generic-password item, `kSecAttrService` = the app's bundle identifier (passed in), `kSecAttrAccount` = `hfr.accounts.v1`, optional access group; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (Q-9) re-applied on every write; not synchronizable; data-protection Keychain. Update the item, add it when missing. A distinct item from legacy `HFR_COMPTES_KEY`, which LOT-067 imports and never deletes.
- **`FileCredentialStore`** (Linux, tests): directories it creates are `0700`; one JSON file written to a sibling temporary file opened with `O_CREAT|O_EXCL` and mode `0600` before any byte is written; leftover `.<name>.<uuid>.tmp` siblings (regular files with a UUID in the middle only; a crash between write and rename leaves one, with credentials inside) are swept on every write and by `removeAll()` (complete-until-first-authentication protection on iOS), then `rename(2)`.
- **`InMemoryCredentialStore`** (tests, previews): keeps the envelope bytes, so versioning and corruption behave as in the persistent stores.

## Secrets
- No password field exists (E §5.1); the envelope test checks no `password` key is written.
- `CredentialStoreError` never wraps a decoding error (whose context could quote stored bytes) nor carries values; `Account` and `StoredCookie` descriptions already hide secrets (LOT-013). Nothing in this lot logs.
- Test accounts use fake values only.

## Edge cases
- `update` holds the store's lock while its closure runs: the closure must not call the same store.
- Two `FileCredentialStore` instances on one file are not serialized (one instance per file in practice). Keychain writes from two processes (app + extension) are last-writer-wins on the item.
- The avatar bytes live in the Keychain item with the cookies, as in legacy. Fine for forum avatars (a few KiB); a large image should be cached elsewhere (LOT-066).
- The real Keychain cannot run on Linux, nor in a plain macOS `swift test` binary (the data-protection Keychain needs an entitlement): `KeychainCredentialStoreTests` runs only with `HFR_KEYCHAIN_TESTS=1` from a signed host. **The Keychain store is therefore not exercised by CI yet** (only compiled by the macOS and iOS jobs); follow-up: run that suite from the app target's test bundle once it exists (Mac session). Every rule is tested on all platforms through the in-memory and file stores, which share `AccountBook` and `CredentialEnvelope` with it.

## Fixtures
None: synthetic accounts with fake cookie values.

## Tests
`AccountBookTests` (first account main, add makes main, refresh in place keeping token and spelling, invalid pseudos, promotion on delete, lookup, diacritics significant, repair on load, replace, format characters stripped, `md_user` cross-check, display name kept on a lower-case re-login) and `CredentialStoreTests`, each behaviour run against the in-memory and the file store: empty store writes nothing, every field survives a reload, dedupe/promotion/main selection through the store, versioned envelope without password, newer envelope neither read nor overwritten, six corrupted envelopes never replaced, a throwing edit writes nothing, 40 concurrent saves serialized, file owner-only with no temporary leftovers, created directories `0700`, crash leftovers swept on write and `removeAll`, errors without secrets.

## Intentional differences from legacy
- Re-adding an existing account refreshes its cookies (legacy dropped them, A §4.3).
- `Codable` versioned envelope instead of `NSKeyedArchiver` insecure coding (E §5.2).
- This-device-only accessibility (Q-9; legacy tokens travelled in backups, E §5.3).
- Lookup is no longer diacritic-insensitive: two pseudos differing by an accent are two accounts. Invisible format characters are ignored instead.
- A corrupted item is reported, never silently replaced by an empty list (legacy returned an empty array, `MultisManager.m:46`, and the next add overwrote everything).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- swift-corelibs-foundation: `FileManager.replaceItemAt` fails with "file doesn't exist" on Linux and a missing file reports `fileNoSuchFile` (4) where Apple reports `fileReadNoSuchFile` (260). Use `rename(2)` and accept both codes.
