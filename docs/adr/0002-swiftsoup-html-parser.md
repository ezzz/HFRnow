# 0002 — SwiftSoup as the HTML parser

**Status:** Accepted — 2026-10-24

## Context
HFR exposes HTML, not an API. The legacy app used `HTMLParser` (libxml2 wrapper) and `RegexKitLite`, both unmaintained.
Options: SwiftSoup (mature, pure Swift, MIT, Linux-compatible), a custom libxml2 wrapper, or regex-only parsing.

## Decision
Use SwiftSoup, pinned to an exact version, **only inside `HFRParsing`**. Regex work uses Swift Regex.

## Consequences
- Parsers are pure Swift and run on Linux CI.
- SwiftSoup types never leak into public APIs; replacing it touches `HFRParsing` only.
- Upgrades go through Dependabot PRs and the dependency review.
