<p align="center">
  <img src="docs/assets/hero.jpg" alt="The HFR forum pulled into an iPhone running a native SwiftUI forum app" width="100%">
</p>

<h1 align="center">SwiftHFR</h1>

<p align="center">
  <strong>The <a href="https://forum.hardware.fr">forum.hardware.fr</a> community, rebuilt as a native iOS app in Swift &amp; SwiftUI.</strong>
</p>

<table align="center">
  <tr>
    <td align="right"><sub><b>BUILD &amp; SECURITY</b></sub></td>
    <td>
      <a href="https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/ci.yml"><img src="https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
      <a href="https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/codeql.yml"><img src="https://github.com/francoisgn/ios-app_SwiftHFR/actions/workflows/codeql.yml/badge.svg" alt="CodeQL"></a>
      <a href="https://scorecard.dev/viewer/?uri=github.com/francoisgn/ios-app_SwiftHFR"><img src="https://api.scorecard.dev/projects/github.com/francoisgn/ios-app_SwiftHFR/badge" alt="OpenSSF Scorecard"></a>
      <a href="https://github.com/francoisgn/ios-app_SwiftHFR/network/updates"><img src="https://img.shields.io/badge/Dependabot-enabled-025E8C?logo=dependabot&amp;logoColor=white" alt="Dependabot"></a>
      <a href="https://coderabbit.ai"><img src="https://img.shields.io/coderabbit/prs/github/francoisgn/ios-app_SwiftHFR?utm_source=oss&amp;utm_medium=github&amp;utm_campaign=francoisgn%2Fios-app_SwiftHFR&amp;labelColor=171717&amp;color=FF570A&amp;link=https%3A%2F%2Fcoderabbit.ai&amp;label=CodeRabbit+Reviews" alt="CodeRabbit Pull Request Reviews"></a>
    </td>
  </tr>
  <tr>
    <td align="right"><sub><b>STACK</b></sub></td>
    <td>
      <a href="Packages/HFRKit/Package.swift"><img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&amp;logoColor=white" alt="Swift 6.2"></a>
      <a href="Packages/HFRKit/Package.swift"><img src="https://img.shields.io/badge/iOS-27%2B-000000?logo=apple&amp;logoColor=white" alt="iOS 27+"></a>
      <a href="docs/ARCHITECTURE.md"><img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF?logo=swift&amp;logoColor=white" alt="SwiftUI"></a>
      <a href=".github/workflows/ci.yml"><img src="https://img.shields.io/badge/Xcode-27-147EFB?logo=xcode&amp;logoColor=white" alt="Xcode 27"></a>
      <a href="Packages/HFRKit"><img src="https://img.shields.io/badge/SwiftPM-modular-F05138?logo=swift&amp;logoColor=white" alt="SwiftPM"></a>
    </td>
  </tr>
  <tr>
    <td align="right"><sub><b>PROJECT</b></sub></td>
    <td>
      <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue.svg" alt="License: PolyForm Noncommercial 1.0.0"></a>
      <a href="https://github.com/francoisgn/ios-app_SwiftHFR/commits/master"><img src="https://img.shields.io/github/last-commit/francoisgn/ios-app_SwiftHFR" alt="Last commit"></a>
      <a href="https://github.com/francoisgn/ios-app_SwiftHFR/issues"><img src="https://img.shields.io/github/issues/francoisgn/ios-app_SwiftHFR" alt="Open issues"></a>
      <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome"></a>
    </td>
  </tr>
</table>

<p align="center">
  <a href="#why">Why</a> ·
  <a href="#goals">Goals</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#contributing">Contributing</a> ·
  <a href="#license-and-credits">License</a> ·
  <a href="#support">Support</a>
</p>

---

> [!NOTE]
> **Status: foundations laid, engine migration starting.** Nothing usable on a phone yet. Follow along in the [roadmap](docs/ROADMAP.md).

## Why

HFR has had a community iOS app for more than a decade: **HFR+ → SuperHFR+ → HFRnow**. Each time maintainers moved on, someone forked it and carried on.
The result works, but it is a mix of Objective-C, abandoned vendor libraries and newer SwiftUI screens.

SwiftHFR keeps the spirit and restarts on a clean foundation: **100 % Swift, modular, tested, secure by default**, ready for the next generation of iPhones.

## Goals

| | |
|---|---|
| **Native** | Swift 6.2 and SwiftUI, iOS 27+, strict concurrency. No Objective-C, no legacy vendor libraries. |
| **Modular** | A UI-free engine, `HFRKit`: models, HTML parsing, networking, storage, each in its own module. |
| **Faithful** | Behavioural parity with the legacy app, proven by differential tests against its parsers. |
| **Modern UI** | Built for today's devices, including column-based navigation: forums → topics → messages. |
| **Secure** | SAST, SCA, secret scanning and code review on every change. |

## Architecture

```
App (SwiftUI)
 └── HFRKit (Swift package, UI-free)
      ├── HFRModels   value types, no dependencies
      ├── HFRParsing  HTML → models (SwiftSoup), pure functions
      ├── HFRNetwork  URLSession, cookies, sessions, accounts
      └── HFRStorage  drafts, lists, local favorites, caches
```

Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the [Architecture Decision Records](docs/adr/).

## Getting started

The engine builds and tests on macOS or Linux with Swift 6.2+:

```sh
git clone https://github.com/francoisgn/ios-app_SwiftHFR.git
cd ios-app_SwiftHFR
swift test --package-path Packages/HFRKit
```

The iOS app target (Xcode 27) arrives before the app phase. See the [roadmap](docs/ROADMAP.md).

## Contributing

Humans and AI agents follow the same rules:

1. Read **[AGENTS.md](AGENTS.md)**, the operating manual, then [CONTRIBUTING.md](CONTRIBUTING.md).
2. Pick a free [migration lot](docs/LOTS.md) or an issue labelled `status: ready` ([label guide](AGENTS.md#7-labels-and-prioritization)).
3. Open a PR. CI, CodeQL and CodeRabbit review it.

Found a security issue? Please follow [SECURITY.md](SECURITY.md) and don't open a public issue.

## License and credits

Licensed under [PolyForm Noncommercial 1.0.0](LICENSE): free to use, modify and share for any noncommercial purpose. Commercial use is not allowed, and the copyright notice must be kept.

SwiftHFR stands on the shoulders of the previous apps and their authors: see [CREDITS.md](CREDITS.md).
It is an independent community project, not affiliated with Hardware.fr.

## Support

If SwiftHFR is useful to you, you can support its development:

<p align="center">
  <a href="https://buymeacoffee.com/francoisgn"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-%E2%98%95-FFDD00?style=for-the-badge&amp;logo=buymeacoffee&amp;logoColor=black" alt="Buy Me a Coffee"></a>
</p>
