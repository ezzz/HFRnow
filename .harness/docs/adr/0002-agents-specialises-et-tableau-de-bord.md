# 0002 — Agents spécialisés vendorisés, service de revue et tableau de bord du flux

**Statut :** Proposé — 2026-11-07 (le mainteneur décide)

## Contexte
Le volume de commits agentiques dépasse de loin celui d'un humain ; les cycles de revue et de CI deviennent le coût
principal (CI-BUDGET.md §5). Les projets ont besoin de relecteurs de conformité (RGPD, AI Act, NIS2, ISO 27001, SOC 2,
TISAX, PCI, HDS) lancés seulement quand le diff les concerne, de rôles d'entretien (issues, docs, flux) et d'un état
lisible par des non-techniciens. Le cadre 0.1.0 décrivait la revue adversariale en prose, sans agent réutilisable, et
n'avait aucune mesure du flux. OpenHarness (HKUDS, MIT) montre une machine d'états de tâches persistée dans le dépôt,
une boucle de réparation bornée et un tableau de bord exporté ([`src/openharness/autopilot/service.py`](https://github.com/HKUDS/OpenHarness/blob/main/src/openharness/autopilot/service.py), branche `main` lue le 2026-11-07, dernier commit du 2026-06-04).

## Options
1. **Prose seulement** : chaque projet écrit ses prompts. Gratuit, mais divergent et non testable.
2. **Agents Claude Code vendorisés** (`.claude/agents/*.md`) + workflows réutilisables + script de mesure en
   bibliothèque standard. Fonctionne en cloud et en local, versionné avec le cadre, contrôlé par la CI.
3. **Service externe** (CodeRabbit, outil de conformité, tableau de bord SaaS) : moins de code, mais comptes tiers,
   coût par siège, et nos règles (leçons, conventions) non appliquées.

## Décision
Option 2 :
- agents `adversarial-reviewer`, `issue-steward`, `doc-steward`, `flow-monitor`, `compliance-<id>` dans
  `plugins/harness/agents/`, vendorisés en `.claude/agents/` (manifeste, mode `tree`) ; conformité activée par
  `.harness/config.json` → `compliance` ;
- convention de nommage des agents `<projet>.<orchestrateur>.<rôle>.<cible>` (ORCHESTRATION.md §7), vérifiée en CI ;
- service de revue `ai-review.yml` (claude-code-action épinglée), jamais contrôle requis ;
- pipeline `security.yml` (Semgrep, Trivy, gitleaks) ; tableau de bord `flow-metrics.py` + `flow-report.yml` ;
- boucles bornées : 3 cycles de revue, 6 pushes testés par la CI par PR (FINOPS.md §3).

## Conséquences
- Plus facile : ajouter un référentiel = un fichier d'agent + une ligne de catalogue ; rapport d'état automatique.
- Plus difficile : les agents de conformité vieillissent avec les textes ; une revue annuelle par référentiel est
  nécessaire, et leurs identifiants « (à vérifier) » doivent être confirmés sur les textes officiels.
- À surveiller : coût de la revue IA par PR, pertinence de ses constats face à CodeRabbit (comparaison sur 10 PR).
