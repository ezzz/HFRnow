#!/usr/bin/env bash
# Hook SessionStart du cadre agentic-harness : quelques lignes de contexte ajoutées au début de chaque session.
# Usage : session-start.sh plugin|vendored
#   plugin    lancé par le plugin Claude Code (version dans ${CLAUDE_PLUGIN_ROOT}) ;
#   vendored  lancé par la copie vendorisée dans .harness/hooks/ (déclarée dans .claude/settings.json).
# Si le projet a les deux, seule la copie vendorisée parle (pas de doublon).
# Ne fait que lire ; ne bloque jamais la session (toujours exit 0).
set -u
MODE="${1:-vendored}"
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
VENDORED=""
[ -f "$PROJECT/.harness/VERSION" ] && VENDORED="$(head -1 "$PROJECT/.harness/VERSION")"

if [ "$MODE" = plugin ] && [ -n "$VENDORED" ] \
  && grep -q 'harness/hooks/session-start.sh' "$PROJECT/.claude/settings.json" 2>/dev/null; then
  exit 0
fi

PLUGIN=""
if [ "$MODE" = plugin ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
fi
BRANCH="$(git -C "$PROJECT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

echo "## Cadre agentic-harness"
if [ -n "$VENDORED" ]; then
  echo "- Version vendorisée : ${VENDORED} (.harness/VERSION)${PLUGIN:+ ; plugin : ${PLUGIN}}. Règles : .harness/docs/ESSENTIEL.md."
  if [ -n "$PLUGIN" ] && [ "$PLUGIN" != "$VENDORED" ]; then
    echo "- 🟠 Plugin et copie vendorisée diffèrent : la copie du dépôt fait foi (mise à jour : skill harness-update)."
  fi
else
  echo "- Plugin ${PLUGIN:-?} ; ce dépôt n'a pas adopté le cadre (.harness/ absent) : voir docs/ADOPTION.md du cadre."
fi
echo "- Branche courante : ${BRANCH}. Travail = une issue prise en charge, branche claude/<lot> depuis la branche d'intégration à jour, PR en brouillon."
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  echo "- Session cloud (Linux) : pas de build Xcode ici ; relire le code app avec une rigueur de compilateur, reprise sur Mac (MAC-HANDOFF.md)."
fi
echo "- Avant la PR : auto-relecture contre LESSONS.md, revue par un autre modèle, un seul push par lot."
exit 0
