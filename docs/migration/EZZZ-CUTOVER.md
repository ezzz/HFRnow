# Cutover runbook — SwiftHFR to ezzz/HFRnow `dev-swift`

Decision: [ADR 0010](../adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md). Executed **once**, from the maintainer's Mac (Claude Code CLI or by hand) with the maintainer's own `git` and `gh` credentials.
Stop at the first unexpected result and report it. Never push to `master` of ezzz/HFRnow.

## Who does what

| Step | Actor | Why |
|---|---|---|
| Steps 1–8 | Maintainer (`francoisgn`) | `write` collaborator on ezzz/HFRnow: push, force push before the ruleset exists, PRs, labels, Actions secrets. Admin of `francoisgn/ios-app_SwiftHFR` (the mirror) |
| Step 9: rulesets, security settings, merge of PR #7 | **ezzz** (owner) | Admin only: on a personal-account repository collaborators are `write`, never `admin` |

State on 2026-10-27: Claude GitHub app installed by ezzz; CodeRabbit reportedly installed (checked in step 4); `dev-swift` exists as a placeholder copy of the legacy `master` (`9f15513`); PR [ezzz/HFRnow#7](https://github.com/ezzz/HFRnow/pull/7) adds `.github/dependabot.yml` to `master`, unmerged.

## Prompt for the Mac session

> Read `docs/migration/EZZZ-CUTOVER.md` on branch `claude/ezzz-dev-swift-setup-iiao14` of francoisgn/ios-app_SwiftHFR and execute steps 1 to 8 from a fresh clone in `~/dev/swifthfr-cutover`.
> Use my git and `gh` credentials. Ask me before every step marked **[confirm]**. Stop and report at the first unexpected result. Never push to `master` of ezzz/HFRnow, never bypass push protection.
> At the end, print the checklist of step 8 with each box ticked or not, and the message of step 9 ready to post.

## 0. Before the cutover (francoisgn/ios-app_SwiftHFR)

- [ ] In-flight PRs there are merged or closed (as of 2026-10-26: #40, #45, #46, #50, #52, #53, #54). Merged code reaches `dev-swift` with the history and is never re-reviewed. What stays open is moved in step 7.
- [ ] Freeze: no merge on `francoisgn/ios-app_SwiftHFR` from step 2 onwards; it becomes a mirror in step 6.

## 1. Checks

```sh
gh auth status
gh api repos/ezzz/HFRnow --jq .permissions              # expect "push": true
gh api repos/francoisgn/ios-app_SwiftHFR --jq .permissions.admin   # expect true
git ls-remote --heads https://github.com/ezzz/HFRnow dev-swift     # expect 9f15513… (placeholder)
command -v yq jq >/dev/null || brew install yq jq
```

## 2. Prepare the clone

```sh
git clone https://github.com/francoisgn/ios-app_SwiftHFR.git ~/dev/swifthfr-cutover && cd ~/dev/swifthfr-cutover
git remote add ezzz https://github.com/ezzz/HFRnow.git
git fetch origin master claude/ezzz-dev-swift-setup-iiao14
git fetch ezzz dev-swift
git switch -c chore/ezzz-envelope origin/claude/ezzz-dev-swift-setup-iiao14
git rebase origin/master          # only changes something if master moved; resolve, keep both sides
swift test --package-path Packages/HFRKit
```

## 3. Import the history (force push) **[confirm]**

```sh
git push --force-with-lease=dev-swift:9f15513d9c74ab1e1eeec295e1456f42ca36e537 ezzz origin/master:refs/heads/dev-swift
```

- Replaces the placeholder. The lease refuses the push if someone pushed to the placeholder meanwhile: then stop and report.
- A direct push opens no PR, so **CodeRabbit reviews nothing**: the code was reviewed on the old repository.
- Expected on ezzz/HFRnow → Actions: only **Secret scan** runs (CI and CodeQL still target `master` in that snapshot). It must be green.
- Push protection rejecting the push = a secret in the history: stop, do not bypass.

## 4. The envelope PR: CI, AppSec, SAST, SCA, CodeRabbit **[confirm before merging]**

```sh
git push ezzz chore/ezzz-envelope
gh pr create -R ezzz/HFRnow --base dev-swift --head chore/ezzz-envelope \
  --title "chore: host SwiftHFR on ezzz/HFRnow dev-swift (ADR 0010)" \
  --body "Retargets CI, CodeQL, CodeRabbit, Dependabot and docs from francoisgn/ios-app_SwiftHFR to this branch; adds the rulesets (importable JSON) and the mirror workflow. ADR 0010."
gh pr checks --watch -R ezzz/HFRnow chore/ezzz-envelope
```

CodeRabbit needs nothing else: its configuration is `.coderabbit.yaml` in the branch (`base_branches: ^dev-swift$`).

| Check | Covers | Expected |
|---|---|---|
| SwiftLint | Lint | ✅ |
| HFRKit tests (Linux), HFRKit tests (macOS) + iOS 27 build | Build and tests (`xcode-27` runner) | ✅ |
| Docs consistency, Fixture tooling tests | Lot rules, markdown, fixture anonymization | ✅ |
| Analyze (actions), Analyze (swift) | **SAST** (CodeQL) | ✅ — if the upload fails with "default setup is enabled", ezzz turns CodeQL default setup off (step 9) |
| gitleaks | **AppSec**: secrets in the history | ✅ |
| review | **SCA**: dependency review | ✅ |
| CodeRabbit | Review of **this diff only** | A review comment. If it says the review is skipped because the base is not the default branch, ezzz adds `dev-swift` under CodeRabbit → HFRnow → Settings → Reviews → Auto review → Base branches; then comment `@coderabbitai review` |
| Mirror from ezzz/HFRnow | — | Not triggered on PRs (schedule and manual only) |

Address CodeRabbit's findings in the PR if any, then **[confirm]** squash-merge (`gh pr merge --squash -R ezzz/HFRnow chore/ezzz-envelope`). The push to `dev-swift` then runs CI and CodeQL: both green.

## 5. Labels and secrets

```sh
git fetch ezzz dev-swift && git switch --detach ezzz/dev-swift
./scripts/configure-repo.sh         # write access: syncs labels, skips the admin parts and says so
gh secret list -R francoisgn/ios-app_SwiftHFR
```

Recreate each listed secret on ezzz/HFRnow (`gh secret set NAME -R ezzz/HFRnow`) from its source (ADR 0007: the local untracked configuration). Secret values cannot be exported. None is needed by the current workflows.

## 6. Mirror back to francoisgn/ios-app_SwiftHFR **[confirm]**

The old repository becomes a **read-only mirror** of `dev-swift`, updated hourly by `.github/workflows/mirror-from-ezzz.yml` (fast-forward only).
A deploy key is used because `GITHUB_TOKEN` cannot push commits that touch workflow files.

```sh
MIRROR=francoisgn/ios-app_SwiftHFR
# 6a. Bootstrap: master of the mirror = dev-swift (fast-forward: dev-swift is master + the envelope commit)
git fetch ezzz dev-swift && git push origin ezzz/dev-swift:refs/heads/master

# 6b. Deploy key with write access, private half as an Actions secret, then delete the local copy
ssh-keygen -t ed25519 -N "" -C "swifthfr-mirror" -f ~/.ssh/swifthfr-mirror
gh repo deploy-key add ~/.ssh/swifthfr-mirror.pub -R "$MIRROR" --allow-write --title "Mirror from ezzz/HFRnow"
gh secret set MIRROR_DEPLOY_KEY -R "$MIRROR" < ~/.ssh/swifthfr-mirror
rm ~/.ssh/swifthfr-mirror ~/.ssh/swifthfr-mirror.pub

# 6c. Protection: classic branch protection would block the deploy key; a ruleset lets only it and admins update master
gh api -X DELETE "repos/$MIRROR/branches/master/protection"
gh api -X POST "repos/$MIRROR/rulesets" --input .github/rulesets/mirror-master.json >/dev/null

# 6d. Quiet the mirror: no Dependabot security PRs, a description that says what it is
gh api -X DELETE "repos/$MIRROR/automated-security-fixes"
gh repo edit "$MIRROR" --description "Read-only mirror of ezzz/HFRnow (branch dev-swift). Issues and PRs go there."

# 6e. First run
gh workflow run mirror-from-ezzz.yml -R "$MIRROR" && sleep 20 && gh run list -R "$MIRROR" -w mirror-from-ezzz.yml -L 1
```

Expected: the run succeeds and does nothing (already in sync). On the mirror, only **Secret scan** runs on each sync; CI and CodeQL target `dev-swift` and stay quiet (CodeQL keeps its weekly scheduled scan there).

## 7. What stayed open **[confirm]**

- Remaining PRs of the old repository: `git push ezzz origin/<branch>:refs/heads/<branch>`, rebase on `ezzz/dev-swift` if needed, `gh pr create -R ezzz/HFRnow --base dev-swift`, body `Moved from francoisgn/ios-app_SwiftHFR#N`. If its review was complete there, add `@coderabbitai ignore` to the body. Then close the old PR with a link to the new one.
- Open issues (#14): recreate on ezzz/HFRnow with a link to the original, close the original with a link to the new one.
- Then disable issues on the mirror: `gh repo edit francoisgn/ios-app_SwiftHFR --enable-issues=false`.

## 8. Checklist before handing over to ezzz

- [ ] `dev-swift` = SwiftHFR history + the envelope commit, CI and CodeQL green on it
- [ ] CodeRabbit reviewed the envelope PR
- [ ] Labels present on ezzz/HFRnow
- [ ] Secrets recreated (or none needed)
- [ ] Mirror run green, `francoisgn/ios-app_SwiftHFR` master = `ezzz/HFRnow` dev-swift
- [ ] Open PRs and issues moved

Then post the step 9 message (forum, plain text).

## 9. Owner actions (ezzz), after the message

- **Rulesets** (Settings → Rules → Rulesets → New ruleset → Import a ruleset):
  - [`dev-swift.json`](https://github.com/ezzz/HFRnow/blob/dev-swift/.github/rulesets/dev-swift.json) — mandatory.
  - [`legacy-master.json`](https://github.com/ezzz/HFRnow/blob/dev-swift/.github/rulesets/legacy-master.json) — optional; it also blocks direct pushes to `master` by `write` collaborators (`francoisgn`, `moust4ki` / Bybifok).
- **Code security**: Dependabot alerts, private vulnerability reporting, secret scanning and push protection on; Dependabot security updates **off**; CodeQL **default setup off** (the repository uses the `codeql.yml` workflow).
- **Actions → General → Workflow permissions**: read repository contents.
- **Merge [#7](https://github.com/ezzz/HFRnow/pull/7)** (Dependabot for `dev-swift`).
- Alternative to the web UI: `./scripts/configure-repo.sh --repo-wide [--guard-master]` with the GitHub CLI.

Afterwards, by the maintainer: check Settings → Rules shows `SwiftHFR dev-swift` active (a direct push to `dev-swift` must now be refused), Insights → Dependency graph → Dependabot lists the two `dev-swift` entries, then a PR on `dev-swift`: ADR 0010 → Accepted, learnings in AGENTS.md §11.

## Later, owner's decision (ezzz)

Issue forms and `issue-triage.yml` (ADR 0010 table): issues are shared with the legacy app, so they only land on `master` if ezzz wants them, through a PR he merges.
