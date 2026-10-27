# Contributing

Thanks for helping! Humans and AI agents follow the same process.

1. Read **[AGENTS.md](AGENTS.md)** — rules, conventions, migration loop, labels, definition of done.
2. Pick work: an issue labelled `status: ready`, or a free lot in [docs/LOTS.md](docs/LOTS.md). Claim it before starting.
3. Branch from `dev-swift` and target it in your PR (`lot/…`, `fix/…`, `feat/…`, `chore/…`, `docs/…`).
4. Run `swift test --package-path Packages/HFRKit` and SwiftLint locally when you can.
5. Open a PR with the template. CI and CodeRabbit must be green, and every review comment answered.

Opening issues: use the forms (bug, feature, task). They set type, priority, difficulty and area labels automatically.
Security problems go through [SECURITY.md](SECURITY.md), never a public issue.

By contributing you agree that your contribution is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE), except contributions to `docs/HFR-PROTOCOL.md` and to fixtures under `Packages/HFRKit/Tests/**/Fixtures/`, which are licensed under [CC BY 4.0](LICENSE-docs.md).
