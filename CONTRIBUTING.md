# Contributing

Thanks for helping! Humans and AI agents follow the same process.

1. Read **[AGENTS.md](AGENTS.md)** — rules, conventions, migration loop, labels, definition of done.
2. Read **[docs/COLLABORATION.md](docs/COLLABORATION.md)** — where to push (branch or fork), how an idea becomes a feature, and the entry criteria a PR must meet before review.
3. Pick work: an issue labelled `status: ready`, or a free lot in [docs/LOTS.md](docs/LOTS.md). Claim it before starting.
4. Branch from `dev-swift` and target it in your PR (`lot/…`, `fix/…`, `feat/…`, `chore/…`, `docs/…`).
5. Run `swift test --package-path Packages/HFRKit` and SwiftLint locally when you can.
6. Open a PR with the template. CI and CodeRabbit must be green, every review comment answered, and someone other than you approves it.

Ideas and mock-ups are welcome: open a feature issue; a maintainer adds it to [docs/FEATURES.md](docs/FEATURES.md) with your name.

Opening issues: use the forms (bug, feature, task). They set type, priority, difficulty and area labels automatically.
Security problems go through [SECURITY.md](SECURITY.md), never a public issue.

By contributing you agree that your contribution is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE), except contributions to `docs/HFR-PROTOCOL.md` and to fixtures under `Packages/HFRKit/Tests/**/Fixtures/`, which are licensed under [CC BY 4.0](LICENSE-docs.md).
