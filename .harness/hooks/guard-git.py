#!/usr/bin/env python3
"""Garde-fou git (hook PreToolUse sur Bash) du cadre agentic-harness.

Refuse, avant exécution, les commandes qui cassent les règles communes (docs/BRANCHING-RELEASE.md, docs/ESSENTIEL.md) :
  - un `git push` forcé (`--force`, `-f`, `--force-with-lease`, refspec `+…`) ;
  - un `git push` vers une branche protégée (liste dans `.harness/config.json`, clé `protected_branches`) ;
  - `--no-verify` sur `git commit` ou `git push` (contourne gitleaks et les hooks pre-commit).
Une commande refusée sort en code 2 : Claude Code bloque l'appel et montre le message à l'agent.
L'opérateur reste libre de lancer la commande lui-même s'il le décide.
Bibliothèque standard uniquement ; toute erreur interne laisse passer la commande (le hook ne doit jamais bloquer
le travail par sa propre faute).
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

DEFAULT_PROTECTED = ["main", "master", "develop", "beta"]
SEPARATORS = re.compile(r"&&|\|\||;|\||\n")
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}


def protected_branches(project_dir: str) -> list[str]:
    """Branches protégées : `.harness/config.json` du projet, sinon la liste par défaut."""
    try:
        with open(os.path.join(project_dir, ".harness", "config.json"), encoding="utf-8") as handle:
            value = json.load(handle).get("protected_branches")
        if isinstance(value, list) and all(isinstance(item, str) for item in value):
            return value
    except (OSError, ValueError, AttributeError):
        pass
    return DEFAULT_PROTECTED


def git_subcommand(tokens: list[str]) -> tuple[str | None, list[str], str | None]:
    """(sous-commande, arguments, dossier -C) d'une commande `git …`, ou (None, [], None)."""
    if not tokens or os.path.basename(tokens[0]) != "git":
        return None, [], None
    index, workdir = 1, None
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        if option in GIT_GLOBAL_WITH_VALUE and index + 1 < len(tokens):
            if option == "-C":
                workdir = tokens[index + 1]
            index += 2
        else:
            index += 1
    if index >= len(tokens):
        return None, [], workdir
    return tokens[index], tokens[index + 1:], workdir


def current_branch(cwd: str) -> str | None:
    """Branche courante de `cwd`, ou None si elle ne se lit pas."""
    try:
        out = subprocess.run(["git", "-C", cwd, "symbolic-ref", "--short", "-q", "HEAD"],
                             capture_output=True, text=True, timeout=5, check=False)
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def check_push(args: list[str], protected: list[str], cwd: str) -> str | None:
    """Motif de refus d'un `git push`, ou None."""
    positional = []
    for arg in args:
        if arg in ("--force", "-f", "--force-if-includes") or arg.startswith("--force-with-lease"):
            return "push forcé interdit (jamais de force-push sur une branche partagée)"
        if arg == "--no-verify":
            return "`--no-verify` interdit (gitleaks et les hooks pre-commit doivent tourner)"
        if arg in ("--mirror", "--all"):
            return f"`git push {arg}` interdit (pousse aussi les branches protégées)"
        if not arg.startswith("-"):
            positional.append(arg)
    refspecs = positional[1:]
    for refspec in refspecs:
        if refspec.startswith("+"):
            return f"refspec forcée `{refspec}` interdite"
        destination = refspec.split(":", 1)[-1]
        destination = destination.removeprefix("refs/heads/")
        if destination in protected:
            return f"push direct vers la branche protégée `{destination}` interdit : passer par une PR"
    if not refspecs:
        branch = current_branch(cwd)
        if branch in protected:
            return f"push depuis la branche protégée `{branch}` interdit : créer une branche `claude/<lot>` et une PR"
    return None


def reason_for(command: str, protected: list[str], cwd: str) -> str | None:
    """Motif de refus de la première sous-commande fautive de `command`, ou None."""
    for part in SEPARATORS.split(command):
        try:
            tokens = shlex.split(part, comments=True)
        except ValueError:
            continue
        while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
            tokens = tokens[1:]  # affectations VAR=… en tête
        sub, args, workdir = git_subcommand(tokens)
        where = os.path.join(cwd, workdir) if workdir else cwd
        if sub == "push":
            reason = check_push(args, protected, where)
            if reason:
                return reason
        elif sub == "commit" and ("--no-verify" in args or "-n" in args):
            return "`git commit --no-verify` interdit (gitleaks et les hooks pre-commit doivent tourner)"
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
        cwd = payload.get("cwd") or os.getcwd()
        project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
        if not isinstance(command, str) or "git" not in command:
            return 0
        reason = reason_for(command, protected_branches(project_dir), cwd)
    except Exception:  # noqa: BLE001 — un hook en panne ne bloque jamais le travail
        return 0
    if reason:
        print(f"agentic-harness : {reason}. Si c'est vraiment voulu, l'opérateur lance la commande lui-même "
              "(docs/BRANCHING-RELEASE.md).", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
