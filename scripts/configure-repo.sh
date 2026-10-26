#!/usr/bin/env bash
# Repository configuration for SwiftHFR on ezzz/HFRnow, branch dev-swift (ADR 0005, ADR 0010).
# Run from a maintainer machine with the GitHub CLI:
#   gh auth login && ./scripts/configure-repo.sh              # dev-swift scope: ruleset + labels
#   ./scripts/configure-repo.sh --repo-wide                   # + repository-wide security settings
#   ./scripts/configure-repo.sh --guard-master                # + ruleset keeping apps and non-admins off master
# The default branch (master) is the legacy app. Options that touch it or the whole repository only run
# after the owner (ezzz) agreed.
# Idempotent: safe to re-run after changing required checks.
set -euo pipefail

REPO="ezzz/HFRnow"
BRANCH="dev-swift"
RULESET="SwiftHFR dev-swift"
REPO_WIDE=false
GUARD_MASTER=false
for arg in "$@"; do
  case "$arg" in
    --repo-wide) REPO_WIDE=true ;;
    --guard-master) GUARD_MASTER=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v yq >/dev/null || { echo "yq is required for the label sync (brew install yq)" >&2; exit 1; }

echo "› Permissions of $(gh api user --jq .login) on $REPO"
if [[ "$(gh api "repos/$REPO" --jq .permissions.admin)" != "true" ]]; then
  echo "  Admin access is required for rulesets and security settings: ask the owner to run this script." >&2
  exit 1
fi

if $REPO_WIDE; then
  echo "› Security: Dependabot alerts, private vulnerability reporting, secret scanning + push protection"
  # Dependabot security updates stay off: they only open PRs against the default branch, i.e. the legacy master.
  gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null
  gh api -X PUT "repos/$REPO/private-vulnerability-reporting" >/dev/null
  gh api -X PATCH "repos/$REPO" --input - >/dev/null <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON

  echo "› Workflow token: read-only by default, Actions cannot approve PRs"
  gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
fi

echo "› Ruleset '$RULESET' on $BRANCH"
# A ruleset scoped to dev-swift rather than repository-wide merge settings, so the legacy master keeps its own rules.
# Check names must match the job names in .github/workflows (update here if a job is renamed).
RULESET_JSON=$(cat <<JSON
{
  "name": "$RULESET",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/$BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "SwiftLint" },
          { "context": "HFRKit tests (Linux)" },
          { "context": "HFRKit tests (macOS) + iOS 27 build" },
          { "context": "gitleaks" },
          { "context": "Analyze (swift)" },
          { "context": "Analyze (actions)" },
          { "context": "review" }
        ]
      }
    }
  ]
}
JSON
)
RULESET_ID=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET\") | .id")
if [[ -n "$RULESET_ID" ]]; then
  gh api -X PUT "repos/$REPO/rulesets/$RULESET_ID" --input - >/dev/null <<<"$RULESET_JSON"
else
  gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null <<<"$RULESET_JSON"
fi

if $GUARD_MASTER; then
  echo "› Ruleset 'Legacy master' on the default branch"
  # Only repository admins (the owner) may update master; GitHub apps (Claude, CodeRabbit, Dependabot) may not.
  MASTER_JSON='{"name":"Legacy master","target":"branch","enforcement":"active",
    "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
    "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}],
    "rules":[{"type":"update"},{"type":"deletion"},{"type":"non_fast_forward"}]}'
  MASTER_ID=$(gh api "repos/$REPO/rulesets" --jq '.[] | select(.name == "Legacy master") | .id')
  if [[ -n "$MASTER_ID" ]]; then
    gh api -X PUT "repos/$REPO/rulesets/$MASTER_ID" --input - >/dev/null <<<"$MASTER_JSON"
  else
    gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null <<<"$MASTER_JSON"
  fi
fi

echo "› Labels (the 'Sync labels' workflow cannot be dispatched from a non-default branch)"
yq -o=json '.' "$(dirname "$0")/../.github/labels.yml" | jq -c '.[]' | while read -r label; do
  gh label create "$(jq -r .name <<<"$label")" --repo "$REPO" \
    --color "$(jq -r .color <<<"$label")" \
    --description "$(jq -r .description <<<"$label")" \
    --force
done

echo "✓ Done. The CodeRabbit and Claude GitHub apps are installed by the owner (docs/migration/EZZZ-CUTOVER.md)."
