# Architecture

## Layers

```
App (SwiftUI, iOS 27)                 composition root, navigation, views, view models
  │
  ├── Feature modules (later)          Forums, Topic, Composer, PrivateMessages, …
  │
  └── HFRKit (Packages/HFRKit)         UI-free engine, Foundation-only
        ├── HFRModels                  value types (Forum, Topic, Message, …). No dependencies.
        ├── HFRParsing   → HFRModels   HTML → models. Pure functions. SwiftSoup inside only.
        ├── HFRNetwork   → HFRModels   URLSession client, cookies, session, accounts, typed endpoints
        ├── HFRStorage   → HFRModels   drafts, blacklist/whitelist, local favorites, caches
        └── HFRClient    → HFRModels, HFRParsing, HFRNetwork
                                       multi-step flows: login, posting, search, MPStorage… (ADR 0008)
```

## Dependency rules (enforced by `Package.swift`)

1. `HFRModels` depends on nothing.
2. `HFRParsing`, `HFRNetwork`, `HFRStorage` depend only on `HFRModels` — **never on each other**.
   Multi-step flows are composed in `HFRClient`; the app persists their results with `HFRStorage`.
3. `HFRClient` sits above Parsing and Network to compose multi-step flows; it never depends on `HFRStorage` ([ADR 0008](adr/0008-hfrclient-orchestration-module.md)).
4. Nothing in `HFRKit` imports SwiftUI, UIKit or WebKit. The engine must build and test on Linux.
5. Third-party code is confined: SwiftSoup is visible only inside `HFRParsing` ([ADR 0002](adr/0002-swiftsoup-html-parser.md)).

## Linux rules

The engine is tested on Linux CI, so Apple-only APIs are isolated:
- `URLSession`, `HTTPCookie`, `HTTPCookieStorage` come from `FoundationNetworking` on Linux: `#if canImport(FoundationNetworking) import FoundationNetworking #endif` in `HFRNetwork`.
- Cookies cross module boundaries only as the Codable value type `StoredCookie` (HFRModels), never as `HTTPCookie`.
- Keychain (`Security`) is used only behind a protocol, with the Keychain implementation under `#if canImport(Security)` and in-memory/file implementations for Linux tests.
- `XMLParser` (RSS) comes from `FoundationXML` on Linux.

## Abstractions

Protocols exist only where a second implementation is realistic ([ADR 0001](adr/0001-modular-swift-packages.md)):

| Boundary | Why |
|---|---|
| HTTP transport (`HFRNetwork`) | mock transport in tests |
| HTML backend (`HFRParsing`) | SwiftSoup replaceable without touching parsers' callers |
| Persistence (`HFRStorage`) | in-memory store in tests |

## Why this shape

- **Parallel work**: several agents can work in different modules without conflicts; contracts are explicit.
- **Testability**: parsing is the riskiest part of the migration and is fully testable offline on fixtures.
- **Replaceability**: the legacy vendor libraries are what made the old app hard to evolve; we confine every dependency.
