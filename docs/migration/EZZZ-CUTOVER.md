# Cutover runbook — SwiftHFR to ezzz/HFRnow `dev-swift`

Decision: [ADR 0010](../adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md). Executed **once**, from the maintainer's Mac (Claude Code CLI or by hand) or from a cloud session that has ezzz/HFRnow as a source (the Claude GitHub app is installed since 2026-10-27).
Every step is idempotent or checked first. Stop at the first unexpected result and report it.

## Who does what

| Step | Actor | Why |
|---|---|---|
| Install the Claude and CodeRabbit GitHub apps on ezzz/HFRnow | **ezzz** (owner) | On a personal-account repository only the owner can install apps |
| Agree to the repository-wide security settings (`--repo-wide`) and, if wanted, the `master` guard (`--guard-master`) | **ezzz** | They also apply to the legacy `master` |
| Merge the Dependabot PR into `master` (step 6) | **ezzz** | It is his branch |
| Rulesets and security settings (step 4) | **ezzz** | Admin only; on a personal-account repository collaborators have `write`, never `admin` |
| Everything else below | Maintainer (`francoisgn`) | `write` collaborator: push, force push before the ruleset exists, labels, PRs |

## Prompt for the Mac session

> Read `docs/migration/EZZZ-CUTOVER.md` on branch `claude/ezzz-dev-swift-setup-iiao14` of francoisgn/ios-app_SwiftHFR and execute it step by step from a fresh clone in `~/dev/swifthfr-cutover`.
> Use my git and `gh` credentials. Ask me before steps marked **[confirm]**. Stop and report at the first unexpected result. Never push to `master` of ezzz/HFRnow.

## 0. Before the cutover (francoisgn/ios-app_SwiftHFR)

- [ ] Land or close the in-flight PRs there first (as of 2026-10-26: #40, #45, #46, #50, #52, #53, #54). Code merged before the cutover arrives on `dev-swift` with the history and is never re-reviewed. Whatever stays open is moved in step 7.
- [ ] Freeze: no merge on `francoisgn/ios-app_SwiftHFR` `master` from step 3 onwards.

## 1. Checks

```sh
gh auth status
gh api repos/ezzz/HFRnow --jq .permissions          # expect "push": true ("admin" is the owner's only)
git ls-remote --heads https://github.com/ezzz/HFRnow dev-swift   # nothing, or the placeholder created from the web UI (see step 3)
brew list yq >/dev/null 2>&1 || brew install yq
```

## 2. Prepare the clone

```sh
git clone https://github.com/francoisgn/ios-app_SwiftHFR.git ~/dev/swifthfr-cutover && cd ~/dev/swifthfr-cutover
git remote add ezzz https://github.com/ezzz/HFRnow.git
git fetch origin master claude/ezzz-dev-swift-setup-iiao14
git switch -c chore/ezzz-envelope origin/claude/ezzz-dev-swift-setup-iiao14
git rebase origin/master          # only changes something if master moved; resolve, keep both sides
swift test --package-path Packages/HFRKit
```

## 3. Import the history **[confirm]**

```sh
git push ezzz origin/master:refs/heads/dev-swift
```

If a placeholder `dev-swift` was created from the web UI (a copy of the legacy `master`), the push is refused as non-fast-forward. Replace it, before step 4 adds the ruleset that forbids force pushes:

```sh
git fetch ezzz dev-swift
git push --force-with-lease=dev-swift:ezzz/dev-swift ezzz origin/master:refs/heads/dev-swift
```

- A direct push opens no PR, so **CodeRabbit reviews nothing**: the code was reviewed on the old repository.
- Expected on ezzz/HFRnow → Actions: only **Secret scan** runs (CI and CodeQL still target `master` in that snapshot). It must be green.
- Push protection rejecting the push = a secret in the history: stop, do not bypass.

## 4. Configure the branch **[confirm]**

Maintainer (write access): labels only, the script skips the admin parts.

```sh
./scripts/configure-repo.sh
```

ezzz (admin), **right after the force push**, either from the web UI:
- Settings → Rules → Rulesets → New ruleset → **Import a ruleset** → `.github/rulesets/dev-swift.json` (from the `dev-swift` branch) → Create.
- If he asked for the `master` guard: same with `.github/rulesets/legacy-master.json`. It also blocks direct pushes to `master` by `write` collaborators (`francoisgn`, `moust4ki` / Bybifok): they go through PRs merged by ezzz.
- Settings → Code security: enable Dependabot alerts, private vulnerability reporting, secret scanning and push protection; leave Dependabot security updates **off**. Settings → Actions → General → Workflow permissions: read repository contents.

or with the GitHub CLI: `./scripts/configure-repo.sh --repo-wide` (add `--guard-master` if wanted).

Check in Settings → Rules → Rulesets: `SwiftHFR dev-swift` active, 7 required checks.

## 5. The envelope PR

```sh
git push ezzz chore/ezzz-envelope
gh pr create -R ezzz/HFRnow --base dev-swift --head chore/ezzz-envelope \
  --title "chore: host SwiftHFR on ezzz/HFRnow dev-swift (ADR 0010)" \
  --body "Retargets CI, CodeQL, CodeRabbit, Dependabot and docs from francoisgn/ios-app_SwiftHFR to this branch. ADR 0010."
```

Expected:
- [ ] The 7 required checks run and pass (this proves the ruleset and the runners, `xcode-27` included).
- [ ] CodeRabbit reviews **only this diff**. If it says the review is skipped because the base is not the default branch, ezzz adds `dev-swift` under CodeRabbit → repository settings → Reviews → Auto review → Base branches, then comment `@coderabbitai review` on the PR.
- [ ] **[confirm]** Squash-merge. The push to `dev-swift` then runs CI and CodeQL: both green.

## 6. Dependabot PR into `master` **[confirm]**

Dependabot reads its configuration from the default branch only. The file only declares `dev-swift` targets, so it never opens a PR against `master`.

```sh
git fetch ezzz master
git switch -c chore/dependabot-dev-swift ezzz/master
mkdir -p .github && git show chore/ezzz-envelope:.github/dependabot.yml > .github/dependabot.yml
git add .github/dependabot.yml && git commit -m "Enable Dependabot version updates for dev-swift only"
git push ezzz chore/dependabot-dev-swift
gh pr create -R ezzz/HFRnow --base master --head chore/dependabot-dev-swift \
  --title "Dependabot : mises à jour pour dev-swift uniquement" \
  --body "Ajoute .github/dependabot.yml. Dependabot ne lit ce fichier que sur la branche par défaut, d'où cette PR sur master. Les deux entrées (package Swift HFRKit, GitHub Actions) ciblent \`dev-swift\` : aucune PR Dependabot ne visera master, et aucun fichier de l'app legacy n'est modifié. À merger par ezzz."
```

Once merged: Insights → Dependency graph → Dependabot lists both entries for `dev-swift`.

## 7. Secrets and environments

- [ ] `gh secret list -R francoisgn/ios-app_SwiftHFR` — recreate each one on ezzz/HFRnow (`gh secret set NAME -R ezzz/HFRnow`) from its source (ADR 0007: the local untracked configuration). Secret values cannot be exported.
- [ ] Claude Code cloud environment: new sessions use **ezzz/HFRnow** as the only source named HFRnow (two sources named `hfrnow` collide in one checkout directory), same setup script (`scripts/cloud-setup.sh`). Sessions start on the legacy `master`: AGENTS.md §10 makes them switch to `dev-swift`.

## 8. What stayed open **[confirm]**

- Remaining PRs: `git push ezzz origin/<branch>:refs/heads/<branch>`, rebase on `ezzz/dev-swift` if needed, `gh pr create -R ezzz/HFRnow --base dev-swift`, body `Moved from francoisgn/ios-app_SwiftHFR#N`. If its review was complete there, add `@coderabbitai ignore` to the body to skip a second review.
- Open issues (#14): recreate on ezzz/HFRnow with a link to the original (no transfer across owners).
- `docs/LOTS.md` claims stay valid; PR links in it keep the old `#N` and are read as `francoisgn/ios-app_SwiftHFR#N`.

## 9. Close the old repository **[confirm]**

- PR on francoisgn/ios-app_SwiftHFR adding at the top of the README: "Moved to [ezzz/HFRnow, branch dev-swift](https://github.com/ezzz/HFRnow/tree/dev-swift)".
- Then Settings → Archive this repository.
- PR on `dev-swift`: ADR 0010 → Accepted, learnings added to AGENTS.md §11.

## Later, owner's decision (ezzz)

Issue forms and `issue-triage.yml` (ADR 0010 table): issues are shared with the legacy app, so they only land on `master` if ezzz wants them, through a PR he merges.
