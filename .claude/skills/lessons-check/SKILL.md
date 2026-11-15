---
name: lessons-check
description: Auto-relecture du diff courant contre le tableau des leçons du cadre agentic-harness (et celui du projet) avant une PR ou un correctif de revue ; rend un verdict par leçon applicable. À utiliser avant de pousser ou de passer une PR en revue.
argument-hint: "[base, défaut : branche d'intégration]"
---

# Auto-relecture contre les leçons

1. Diff : `git diff origin/<base>...HEAD`, où `<base>` est « $ARGUMENTS » s'il est donné, sinon la branche
   d'intégration (`.harness/config.json` → `integration_branch`).
2. Tableaux : `.harness/docs/LESSONS.md` (sinon `${CLAUDE_PLUGIN_ROOT}/docs/LESSONS.md`) **et** les leçons propres au
   projet s'il en a (ex. `docs/agents/LESSONS.md`). Garder les portées utiles : `général`, `docs`, `ci` toujours ;
   `swift`, `ios`, `linux-cloud` selon le projet et l'environnement.
3. Pour **chaque** leçon applicable au diff, une ligne : `L.. — ✅ respectée | ⚠️ à vérifier | ❌ enfreinte — où
   (fichier:ligne) et pourquoi`. Ne pas lister les leçons sans rapport.
4. Vérifications concrètes, pas d'impression : lancer les tests annoncés, montrer qu'un nouveau test échoue sans le
   changement (L01), chercher l'appelant d'une fonction « appelée au lancement » (L82), relire les tableaux Markdown
   modifiés (L07), vérifier la compatibilité des sauvegardes si un type persisté change (L80).
5. Corriger les ❌ avant de pousser ; les ⚠️ non résolus vont dans « Points de vigilance » de la PR.
