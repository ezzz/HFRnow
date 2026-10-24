# 0001 — Modular engine as local Swift packages

**Status:** Accepted — 2026-10-24

## Context
The legacy app mixes UI, networking, parsing and storage in Objective-C view controllers and workers. Several humans and AI agents will work in parallel.
A Java-style "classpath" modularity (runtime-pluggable implementations) was considered: Swift packages are resolved at compile time and linked statically, and iOS forbids loading code at runtime, so runtime pluggability would only add registries and factories with no benefit.

## Decision
- The engine is one local Swift package, `HFRKit`, with four library targets: `HFRModels`, `HFRParsing`, `HFRNetwork`, `HFRStorage`.
- Dependencies point only to `HFRModels`; sibling modules never import each other. The app orchestrates them.
- The engine is Foundation-only (no UI frameworks) and must build on Linux.
- Protocols only at boundaries with a realistic second implementation (HTTP transport, HTML backend, persistence).

## Consequences
- Clear ownership per module, few merge conflicts, offline testing of the riskiest code.
- Feature modules may be added later if the app grows; not created upfront.
