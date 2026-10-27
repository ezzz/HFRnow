#!/usr/bin/env bash
# Repository configuration for SwiftHFR on ezzz/HFRnow, branch dev-swift (ADR 0005, ADR 0010).
# Run from a machine with the GitHub CLI (gh auth login):
#   ./scripts/configure-repo.sh                   # labels (write access) + dev-swift ruleset (admin)
#   ./scripts/configure-repo.sh --repo-wide       # + repository-wide security settings (admin)
#   ./scripts/configure-repo.sh --guard-master    # + ruleset keeping apps and non-admins off master (admin)
# On a personal-account repository only the owner (ezzz) is admin. Without admin rights the script syncs the
# labels and skips the rest; the owner can import .github/rulesets/*.json from Settings → Rules → Rulesets
# instead. The default branch (master) is the legacy app: the --repo-wide and --guard-master options only run
# after the owner agreed. Idempotent: safe to re-run after changing required checks.
set -euo pipefail

REPO="ezzz/HFRnow"
RULESETS="$(dirname "$0")/../.github/rulesets"
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

# Creates the ruleset from its JSON file, or updates the existing one with the same name.
apply_ruleset() {
  local file="$1" name id
  name=$(jq -r .name "$file")
  id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
  if [[ -n "$id" ]]; then
    gh api -X PUT "repos/$REPO/rulesets/$id" --input "$file" >/dev/null
  else
    gh api -X POST "repos/$REPO/rulesets" --input "$file" >/dev/null
  fi
  echo "  ruleset '$name' applied"
}

echo "› Labels (the 'Sync labels' workflow cannot be dispatched from a non-default branch)"
yq -o=json '.' "$(dirname "$0")/../.github/labels.yml" | jq -c '.[]' | while read -r label; do
  gh label create "$(jq -r .name <<<"$label")" --repo "$REPO" \
    --color "$(jq -r .color <<<"$label")" \
    --description "$(jq -r .description <<<"$label")" \
    --force
done

if [[ "$(gh api "repos/$REPO" --jq .permissions.admin)" != "true" ]]; then
  echo "› $(gh api user --jq .login) is not admin on $REPO: rulesets and security settings skipped."
  echo "  The owner imports .github/rulesets/dev-swift.json (and legacy-master.json if wanted) from"
  echo "  Settings → Rules → Rulesets → New ruleset → Import a ruleset, or runs this script."
  exit 0
fi

echo "› Ruleset on dev-swift"
# Scoped to dev-swift rather than repository-wide merge settings, so the legacy master keeps its own rules.
# Check names must match the job names in .github/workflows (update the JSON if a job is renamed).
apply_ruleset "$RULESETS/dev-swift.json"

if $GUARD_MASTER; then
  echo "› Ruleset on the default branch"
  # Only repository admins (the owner) may update master; GitHub apps (Claude, CodeRabbit, Dependabot) may not.
  apply_ruleset "$RULESETS/legacy-master.json"
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

echo "✓ Done."
