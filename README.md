# SwiftHFR

[![CI](https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/ci.yml/badge.svg)](https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/ci.yml)
[![CodeQL](https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/codeql.yml/badge.svg)](https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/francoisgn/ios-app_SwiftHFR/badge)](https://scorecard.dev/viewer/?uri=github.com/francoisgn/ios-app_SwiftHFR)
[![License: PolyForm Noncommercial](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/francoisgn/ios-app_SwiftHFR?utm_source=oss&utm_medium=github&utm_campaign=francoisgn%2Fios-app_SwiftHFR&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

Native iOS client for the [forum.hardware.fr](https://forum.hardware.fr) (HFR) community, written from the ground up in Swift and SwiftUI.

SwiftHFR is the next generation of the community app **HFR+ → SuperHFR+ → HFRnow**: each time maintainers moved on, the community forked and carried on. This project keeps that spirit and rebuilds the app on a modern, modular, fully Swift foundation.

> **Status: Phase 0 — foundations.** Nothing usable yet. See the [roadmap](docs/ROADMAP.md).

## Goals

- **100 % Swift / SwiftUI**, iOS 27+, strict concurrency. No Objective-C, no legacy vendor libraries.
- **A modular engine** (`HFRKit`) independent from the UI: models, HTML parsing, networking, storage.
- **Behavioural parity** with the legacy app, proven by differential tests against its parsers.
- **A UI designed for today's devices**, including a column-based navigation (forums → topics → messages).
- **Secure by default**: SAST, SCA, secret scanning and code review on every change.

## Architecture

```
App (SwiftUI)
 └── HFRKit (Swift package, UI-free)
      ├── HFRModels   value types, no dependencies
      ├── HFRParsing  HTML → models (SwiftSoup), pure functions
      ├── HFRNetwork  URLSession, cookies, sessions, accounts
      └── HFRStorage  drafts, lists, local favorites, caches
```

Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the [ADRs](docs/adr/).

## Getting started

Engine (macOS or Linux, Swift 6.2+):

```sh
swift test --package-path Packages/HFRKit
```

The iOS app target requires Xcode 27 and is created in Phase 0 (see the roadmap).

## Contributing

Humans and AI agents follow the same rules: start with **[AGENTS.md](AGENTS.md)**, then [CONTRIBUTING.md](CONTRIBUTING.md).
Work is organized in [migration lots](docs/LOTS.md) and prioritized with [labels](AGENTS.md#7-labels-and-prioritization).

Security issues: please follow [SECURITY.md](SECURITY.md) — do not open a public issue.

## License and credits

[PolyForm Noncommercial 1.0.0](LICENSE): free to use, modify and share for any noncommercial purpose; commercial use is not allowed; the copyright notice must be kept.
SwiftHFR stands on the shoulders of the previous apps and their authors — see [CREDITS.md](CREDITS.md).

SwiftHFR is an independent community project, not affiliated with Hardware.fr.
