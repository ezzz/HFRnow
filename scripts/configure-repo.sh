#!/usr/bin/env bash
# One-time repository configuration (ADR 0005). Run from a maintainer machine with the GitHub CLI:
#   gh auth login && ./scripts/configure-repo.sh
# Idempotent: safe to re-run after changing required checks.
set -euo pipefail

REPO="francoisgn/ios-app_SwiftHFR"
BRANCH="master"

echo "› Description, topics, merge settings"
gh api -X PATCH "repos/$REPO" \
  -f description="Native iOS client for the forum.hardware.fr (HFR) community — full Swift/SwiftUI rewrite of HFR+/HFRnow. Modular engine, iOS 27." \
  -F has_wiki=false -F has_projects=false \
  -F delete_branch_on_merge=true -F allow_auto_merge=true \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false >/dev/null
gh repo edit "$REPO" \
  --add-topic ios,swift,swiftui,hardware-fr,hfr,forum-client,ios-app,swift-package,community,ai-assisted

echo "› Security: Dependabot alerts + fixes, private vulnerability reporting, secret scanning + push protection"
gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null
gh api -X PUT "repos/$REPO/automated-security-fixes" >/dev/null
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" >/dev/null
gh api -X PATCH "repos/$REPO" --input - >/dev/null <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON

echo "› Workflow token: read-only by default, Actions cannot approve PRs"
gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null

echo "› Branch protection on $BRANCH"
# Check names must match the job names in .github/workflows (update here if a job is renamed).
gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" --input - >/dev/null <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "SwiftLint",
      "HFRKit tests (Linux)",
      "HFRKit tests (macOS) + iOS 27 build",
      "gitleaks",
      "Analyze (swift)",
      "Analyze (actions)",
      "review"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true,
    "require_last_push_approval": false
  },
  "required_conversation_resolution": true,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "restrictions": null
}
JSON

echo "› Labels (also synced by the 'Sync labels' workflow)"
gh workflow run labels.yml --repo "$REPO" || echo "  (run 'Sync labels' manually from the Actions tab)"

echo "✓ Done. Remaining manual step: install the CodeRabbit GitHub app on $REPO (https://github.com/apps/coderabbitai)."
