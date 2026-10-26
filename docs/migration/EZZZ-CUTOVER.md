# Cutover runbook — SwiftHFR to ezzz/HFRnow `dev-swift`

Decision: [ADR 0010](../adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md). Executed **once**, from the maintainer's Mac (Claude Code CLI or by hand), because cloud sessions cannot write to ezzz/HFRnow until its owner installs the Claude GitHub app.
Every step is idempotent or checked first. Stop at the first unexpected result and report it.

## Who does what

| Step | Actor | Why |
|---|---|---|
| Install the Claude and CodeRabbit GitHub apps on ezzz/HFRnow | **ezzz** (owner) | On a personal-account repository only the owner can install apps |
| Agree to the repository-wide security settings (`--repo-wide`) | **ezzz** | They also apply to the legacy `master` |
| Everything else below | Maintainer (`francoisgn`) | Collaborator with admin rights on the repository (checked in step 1) |

## Prompt for the Mac session

> Read `docs/migration/EZZZ-CUTOVER.md` on branch `claude/ezzz-dev-swift-setup-iiao14` of francoisgn/ios-app_SwiftHFR and execute it step by step from a fresh clone in `~/dev/swifthfr-cutover`.
> Use my git and `gh` credentials. Ask me before steps marked **[confirm]**. Stop and report at the first unexpected result. Never push to `master` of ezzz/HFRnow.

## 0. Before the cutover (francoisgn/ios-app_SwiftHFR)

- [ ] Land or close the in-flight PRs there first (as of 2026-10-26: #40, #45, #46, #50, #52, #53, #54). Code merged before the cutover arrives on `dev-swift` with the history and is never re-reviewed. Whatever stays open is moved in step 7.
- [ ] Freeze: no merge on `francoisgn/ios-app_SwiftHFR` `master` from step 3 onwards.

## 1. Checks

```sh
gh auth status
gh api repos/ezzz/HFRnow --jq .permissions          # expect "admin": true, otherwise ezzz runs step 4
git ls-remote --heads https://github.com/ezzz/HFRnow dev-swift   # expect nothing
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

- A direct push opens no PR, so **CodeRabbit reviews nothing**: the code was reviewed on the old repository.
- Expected on ezzz/HFRnow → Actions: only **Secret scan** runs (CI and CodeQL still target `master` in that snapshot). It must be green.
- Push protection rejecting the push = a secret in the history: stop, do not bypass.

## 4. Configure the branch **[confirm]**

```sh
./scripts/configure-repo.sh                 # ruleset on dev-swift + labels
./scripts/configure-repo.sh --repo-wide     # only once ezzz agreed (message sent separately)
```

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

## 6. Secrets and environments

- [ ] `gh secret list -R francoisgn/ios-app_SwiftHFR` — recreate each one on ezzz/HFRnow (`gh secret set NAME -R ezzz/HFRnow`) from its source (ADR 0007: the local untracked configuration). Secret values cannot be exported.
- [ ] Claude Code cloud environment: new sessions use **ezzz/HFRnow** as the only source named HFRnow (two sources named `hfrnow` collide in one checkout directory), same setup script (`scripts/cloud-setup.sh`). Sessions start on the legacy `master`: AGENTS.md §10 makes them switch to `dev-swift`.

## 7. What stayed open **[confirm]**

- Remaining PRs: `git push ezzz origin/<branch>:refs/heads/<branch>`, rebase on `ezzz/dev-swift` if needed, `gh pr create -R ezzz/HFRnow --base dev-swift`, body `Moved from francoisgn/ios-app_SwiftHFR#N`. If its review was complete there, add `@coderabbitai ignore` to the body to skip a second review.
- Open issues (#14): recreate on ezzz/HFRnow with a link to the original (no transfer across owners).
- `docs/LOTS.md` claims stay valid; PR links in it keep the old `#N` and are read as `francoisgn/ios-app_SwiftHFR#N`.

## 8. Close the old repository **[confirm]**

- PR on francoisgn/ios-app_SwiftHFR adding at the top of the README: "Moved to [ezzz/HFRnow, branch dev-swift](https://github.com/ezzz/HFRnow/tree/dev-swift)".
- Then Settings → Archive this repository.
- PR on `dev-swift`: ADR 0010 → Accepted, learnings added to AGENTS.md §11.

## Later, owner's decision (ezzz)

Files GitHub only reads from the default branch (ADR 0010 table): `.github/dependabot.yml` with `target-branch: dev-swift` (recommended), issue forms + `issue-triage.yml` (issues are shared with the legacy app). Proposed as PRs into `master`, merged by ezzz.
