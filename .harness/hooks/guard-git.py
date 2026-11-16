#!/usr/bin/env python3
"""Garde-fou git (hook PreToolUse sur Bash) du cadre agentic-harness.

Refuse, avant exécution, les commandes qui cassent les règles communes (BRANCHING-RELEASE.md, ESSENTIEL.md) :
  - un `git push` forcé : `--force`, `-f` (aussi groupé : `-fu`, `-uf`), `--force-with-lease`, refspec `+…` ;
  - `git push --mirror`, `--all` ou `--branches` (poussent aussi les branches protégées) ;
  - un `git push` vers une branche protégée (`protected_branches` de `.harness/config.json`), y compris `HEAD`, un
    `git push` nu ou `git push origin` quand la branche courante est protégée, et la suppression d'une branche
    protégée (`--delete`, `-d`, refspec `:branche`) ;
  - `--no-verify` sur `git commit` (aussi `-n`, groupé ou non) ou `git push` (contourne gitleaks et les hooks).
La commande est découpée comme le ferait le shell : séparateurs `;` `&&` `||` `|` `&` et retours à la ligne,
sous-shells `( … )`, groupes `{ …; }`, substitutions `$( … )` et `` `…` ``, here-documents, redirections,
enveloppes `env`, `command`, `exec`, `nohup`, `time`, `nice`, `timeout`, `sudo`, `xargs`, `eval`, `bash -c` /
`sh -c`, options globales `git -C <dir>` et `git -c k=v`, `cd <dir>` qui précède. Si la commande ne se découpe pas
(guillemet non fermé…), une expression régulière prudente lit le texte brut au lieu de laisser passer.
Ne sont pas refusés : `git push --dry-run` (`-n`), `--force-if-includes` seul, un push vers une branche non protégée.

Une commande refusée sort en code 2 : Claude Code bloque l'appel et montre le message à l'agent. L'opérateur reste
libre de lancer la commande lui-même s'il le décide.
La branche courante est celle du dépôt, ou celle qu'une commande précédente de la même ligne vient de choisir
(`git switch [-c] <b>`, `git checkout [-b] <b>`). Une refspec à joker (`refs/heads/*`) qui couvre une branche protégée
est refusée.
Limites assumées : un hook côté agent se contourne (alias git, script intermédiaire, script passé sur l'entrée
standard d'un shell (`… | sh`, `bash <<EOF`), variable non résolue, push par l'API) ; la vraie protection reste le ruleset côté serveur (BRANCHING-RELEASE.md §Règles communes).
Bibliothèque standard uniquement ; une entrée de hook illisible ou une erreur interne laisse passer la commande (le
hook ne bloque jamais le travail par sa propre faute), comme l'absence de python3.
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
import subprocess
import sys

DEFAULT_PROTECTED = ["main", "master", "develop", "beta"]
DEFAULT_BRANCH_TYPES = ["lot", "fix", "feat", "chore", "docs"]
MAX_DEPTH = 6
OPERATORS = ("&&", "||", ";;", ";", "|&", "|", "&", "(", ")", "\n")
SHELL_KEYWORDS = {"{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "time"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*", re.S)
CURRENT_BRANCH_EXPR = re.compile(r"^\$\(\s*git\s+(branch\s+--show-current|rev-parse\s+--abbrev-ref\s+HEAD|"
                                 r"symbolic-ref\s+--short\s+HEAD)\s*\)$")
# Options globales de git suivies d'une valeur séparée
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env",
                         "--super-prefix", "--list-cmds"}
# Options de `git push` suivies d'une valeur séparée
PUSH_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
# Options courtes de `git commit` dont la valeur suit (collée ou séparée) ; -u et -S n'acceptent qu'une valeur collée
COMMIT_SHORT_VALUE = {"m", "F", "c", "C", "t"}
COMMIT_SHORT_ATTACHED = {"u", "S"}


class ParseError(ValueError):
    """La commande ne se découpe pas (guillemet ou parenthèse non fermés)."""


# --- Découpage shell ------------------------------------------------------------------------------------------------

def _heredoc_delimiter(text: str, i: int) -> tuple[str, bool, int]:
    """(délimiteur, tabulations retirées, index après le mot) d'un here-document ; `i` pointe après `<<`."""
    strip = text.startswith("-", i)
    i += 1 if strip else 0
    while i < len(text) and text[i] in " \t":
        i += 1
    start = i
    while i < len(text) and text[i] not in " \t\n;&|<>()":
        i += 1
    return re.sub(r"['\"\\]", "", text[start:i]), strip, i


def _skip_heredocs(text: str, i: int, pending: list[tuple[str, bool]]) -> int:
    """Index après les corps des here-documents en attente ; `i` pointe juste après le retour à la ligne."""
    for delimiter, strip in pending:
        while i < len(text):
            end = text.find("\n", i)
            line = text[i:] if end < 0 else text[i:end]
            i = len(text) if end < 0 else end + 1
            if (line.lstrip("\t") if strip else line) == delimiter:
                break
    pending.clear()
    return i


def _substitution_end(text: str, start: int) -> int:
    """Index juste après la `)` qui ferme la substitution `$(` ouverte avant `start` (qui pointe après `$(`)."""
    depth, i, quote = 1, start, None
    pending: list[tuple[str, bool]] = []
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in "'\"`":
            quote = c
        elif c == "\\":
            i += 1
        elif text.startswith("<<", i) and not text.startswith("<<<", i):
            delimiter, strip, i = _heredoc_delimiter(text, i + 2)
            pending.append((delimiter, strip))
            continue
        elif c == "\n" and pending:
            i = _skip_heredocs(text, i + 1, pending)
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ParseError("substitution non fermée")


def tokenize(text: str) -> tuple[list[str], list[str]]:
    """(jetons, scripts des substitutions) : mots sans guillemets et opérateurs, comme les découpe le shell.

    Les redirections (`>f`, `2>&1`, `<<EOF` et le corps du here-document) sont retirées."""
    tokens: list[str] = []
    nested: list[str] = []
    word: list[str] = []
    in_word = False
    drop_next = False
    pending: list[tuple[str, bool]] = []
    i = 0

    def flush() -> None:
        nonlocal word, in_word, drop_next
        if in_word:
            if drop_next:
                drop_next = False
            else:
                tokens.append("".join(word))
        word, in_word = [], False

    def substitution(at: int) -> int:
        end = _substitution_end(text, at + 2)
        nested.append(text[at + 2:end - 1])
        word.append(text[at:end])
        return end

    def backquote(at: int) -> int:
        end = text.find("`", at + 1)
        if end < 0:
            raise ParseError("accent grave non fermé")
        nested.append(text[at + 1:end])
        word.append(text[at:end + 1])
        return end + 1

    while i < len(text):
        c = text[i]
        if c == "\\":
            if text.startswith("\n", i + 1):
                i += 2
                continue
            if i + 1 < len(text):
                word.append(text[i + 1])
            in_word = True
            i += 2
            continue
        if c == "'":
            end = text.find("'", i + 1)
            if end < 0:
                raise ParseError("apostrophe non fermée")
            word.append(text[i + 1:end])
            in_word, i = True, end + 1
            continue
        if c == '"':
            i += 1
            in_word = True
            while True:
                if i >= len(text):
                    raise ParseError("guillemet non fermé")
                d = text[i]
                if d == '"':
                    i += 1
                    break
                if d == "\\" and i + 1 < len(text) and text[i + 1] in '"\\$`\n':
                    word.append(text[i + 1])
                    i += 2
                elif text.startswith("$(", i):
                    i = substitution(i)
                elif d == "`":
                    i = backquote(i)
                else:
                    word.append(d)
                    i += 1
            continue
        if text.startswith("$(", i):
            in_word = True
            i = substitution(i)
            continue
        if c == "`":
            in_word = True
            i = backquote(i)
            continue
        if c == "#" and not in_word:
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
            continue
        if c in "<>":
            if in_word and "".join(word).isdigit():
                word, in_word = [], False  # descripteur (`2>`)
            flush()
            if text.startswith("<<", i) and not text.startswith("<<<", i):
                delimiter, strip, i = _heredoc_delimiter(text, i + 2)
                pending.append((delimiter, strip))
                continue
            while i < len(text) and text[i] in "<>&|":
                i += 1
            if i < len(text) and (text[i].isdigit() or text[i] == "-") and text[i - 1] == "&":
                while i < len(text) and (text[i].isdigit() or text[i] == "-"):
                    i += 1  # `>&1`, `>&-` : pas de mot cible
            else:
                drop_next = True
            continue
        operator = next((op for op in OPERATORS if text.startswith(op, i)), None)
        if operator:
            flush()
            tokens.append(";" if operator == "\n" else operator)
            i += len(operator)
            if operator == "\n" and pending:
                i = _skip_heredocs(text, i, pending)
            continue
        if c in " \t\r":
            flush()
            i += 1
            continue
        word.append(c)
        in_word = True
        i += 1
    flush()
    return tokens, nested


def simple_commands(tokens: list[str]) -> list[list[str]]:
    """Commandes simples (listes de mots) séparées par les opérateurs ; mots-clés du shell en tête retirés."""
    commands, current = [], []
    for token in tokens:
        if token in OPERATORS:
            if current:
                commands.append(current)
            current = []
        else:
            current.append(token)
    if current:
        commands.append(current)
    cleaned = []
    for words in commands:
        while words and words[0] in SHELL_KEYWORDS:
            words = words[1:]
        while words and words[-1] == "}":
            words = words[:-1]
        if words:
            cleaned.append(words)
    return cleaned


# --- Enveloppes -----------------------------------------------------------------------------------------------------

def _skip_options(words: list[str], with_value: set[str]) -> list[str]:
    i = 0
    while i < len(words) and words[i].startswith("-") and words[i] != "-":
        if words[i] == "--":
            return words[i + 1:]
        i += 2 if words[i] in with_value else 1
    return words[i:]


def unwrap(words: list[str]) -> tuple[list[str], str | None]:
    """(commande réelle, script à analyser) après les affectations et enveloppes ; script pour `eval`, `bash -c`."""
    for _ in range(MAX_DEPTH * 2):
        while words and ASSIGNMENT.fullmatch(words[0]):
            words = words[1:]
        if not words:
            return [], None
        head = os.path.basename(words[0])
        rest = words[1:]
        if head == "env":
            words = _skip_options(rest, {"-u", "--unset", "-C", "--chdir"})
        elif head == "command":
            if rest[:1] and rest[0] in ("-v", "-V"):
                return [], None  # simple recherche, rien n'est lancé
            words = _skip_options(rest, set())
        elif head in ("exec", "nohup", "builtin"):
            words = _skip_options(rest, {"-a"})
        elif head == "time":
            words = _skip_options(rest, {"-f", "-o"})
        elif head == "nice":
            words = _skip_options(rest, {"-n"})
        elif head == "timeout":
            words = _skip_options(rest, {"-s", "--signal", "-k", "--kill-after"})[1:]  # puis la durée
        elif head == "sudo":
            words = _skip_options(rest, {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U"})
        elif head == "xargs":
            words = _skip_options(rest, {"-I", "-L", "-n", "-P", "-d", "-a", "-E", "-s", "--arg-file",
                                         "--delimiter", "--max-args", "--max-procs", "--max-lines"})
        elif head == "eval":
            return [], " ".join(rest)
        elif head in SHELLS:
            for index, arg in enumerate(rest):
                if not arg.startswith("-"):
                    break
                if not arg.startswith("--") and "c" in arg[1:]:
                    return [], rest[index + 1] if index + 1 < len(rest) else None
            return [], None
        else:
            return words, None
    return words, None


# --- git ------------------------------------------------------------------------------------------------------------

def git_subcommand(words: list[str]) -> tuple[str | None, list[str], list[str]]:
    """(sous-commande, arguments, dossiers -C) d'une commande `git …`, ou (None, [], [])."""
    if not words or os.path.basename(words[0]) != "git":
        return None, [], []
    index, dirs = 1, []
    while index < len(words) and words[index].startswith("-"):
        option = words[index]
        if option in GIT_GLOBAL_WITH_VALUE and index + 1 < len(words):
            if option == "-C":
                dirs.append(words[index + 1])
            index += 2
        else:
            index += 1
    if index >= len(words):
        return None, [], dirs
    return words[index], words[index + 1:], dirs


def _long(arg: str, full: str, minimum: int) -> bool:
    """`arg` désigne l'option longue `full` (git accepte un préfixe non ambigu ; `minimum` le rend non ambigu)."""
    name = arg.split("=", 1)[0]
    return len(name) >= minimum and full.startswith(name)


def current_branch(cwd: str) -> str | None:
    """Branche courante de `cwd` (`git rev-parse --abbrev-ref HEAD`, ou `symbolic-ref` pour une branche encore sans
    commit), ou None si elle ne se lit pas (HEAD détachée, pas un dépôt, git absent)."""
    for args in (["rev-parse", "--abbrev-ref", "HEAD"], ["symbolic-ref", "--short", "-q", "HEAD"]):
        try:
            out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5, check=False)
        except (OSError, subprocess.SubprocessError, ValueError):
            return None
        branch = out.stdout.strip()
        if out.returncode == 0 and branch and branch != "HEAD":
            return branch
    return None


def _branch_of(ref: str, current) -> str | None:
    """Branche que désigne `ref` ; `HEAD`, `@` et `$(git branch --show-current)` : la branche courante (`current()`)."""
    if ref in ("HEAD", "@") or CURRENT_BRANCH_EXPR.match(ref):
        return current()
    return ref.removeprefix("refs/heads/")


def _protected_match(branch: str | None, protected: list[str]) -> str | None:
    """La branche protégée que désigne `branch` (nom exact, ou motif à joker qui la couvre), sinon None."""
    if branch is None:
        return None
    if branch in protected:
        return branch
    if "*" in branch:
        return next((name for name in protected if fnmatch.fnmatchcase(name, branch)), None)
    return None


def check_push(args: list[str], protected: list[str], cwd: str, advice: str, head: str | None = None) -> str | None:
    """Motif de refus d'un `git push`, ou None. `head` : branche courante déjà connue par la ligne de commande (une
    chaîne vide pour une HEAD détachée) ; None : la lire dans `cwd`."""
    def current() -> str | None:
        return (head or None) if head is not None else current_branch(cwd)
    positional: list[str] = []
    force = no_verify = dry_run = delete = repo_option = tags = False
    wide = None
    index = 0
    while index < len(args):
        arg = args[index]
        index += 1
        if arg == "--":
            positional += args[index:]
            break
        if arg.startswith("--"):
            name = arg.split("=", 1)[0]
            if name in PUSH_WITH_VALUE:
                repo_option = repo_option or name == "--repo"
                index += 0 if "=" in arg else 1
            elif arg == "--force" or _long(arg, "--force-with-lease", 9):
                force = True
            elif _long(arg, "--no-verify", 9):
                no_verify = True
            elif _long(arg, "--dry-run", 4):
                dry_run = True
            elif _long(arg, "--no-dry-run", 7):
                dry_run = False
            elif arg == "--tags":
                tags = True
            elif _long(arg, "--delete", 4):
                delete = True
            elif _long(arg, "--mirror", 3):
                wide = "--mirror"
            elif _long(arg, "--all", 4) or _long(arg, "--branches", 4):
                wide = "--all" if name.startswith("--a") else "--branches"
            continue
        if arg.startswith("-") and len(arg) > 1:
            letters = arg[1:]
            for position, letter in enumerate(letters):
                if letter == "f":
                    force = True
                elif letter == "n":
                    dry_run = True
                elif letter == "d":
                    delete = True
                elif letter == "o":
                    if position == len(letters) - 1:
                        index += 1  # valeur séparée
                    break
            continue
        positional.append(arg)

    if dry_run:
        return None
    if force:
        return "push forcé interdit (jamais de force-push sur une branche partagée)"
    if no_verify:
        return "`git push --no-verify` interdit (gitleaks et les hooks pre-commit doivent tourner)"
    if wide:
        return f"`git push {wide}` interdit (pousse aussi les branches protégées)"

    refspecs = positional if repo_option else positional[1:]
    for refspec in refspecs:
        if refspec.startswith("+"):
            return f"refspec forcée `{refspec}` interdite"
        if delete or refspec.startswith(":"):
            branch = _protected_match(_branch_of(refspec.lstrip(":"), current), protected)
            if branch:
                return f"suppression de la branche protégée `{branch}` interdite"
            continue
        source, _, destination = refspec.partition(":")
        branch = _protected_match(_branch_of(destination or source, current), protected)
        if branch:
            return f"push direct vers la branche protégée `{branch}` interdit : {advice}"
    if not refspecs and not delete and not tags:  # `--tags` seul ne pousse que les tags
        branch = current()
        if branch in protected:
            return f"push depuis la branche protégée `{branch}` interdit : {advice}"
    return None


def local_branch_exists(cwd: str, name: str) -> bool:
    try:
        out = subprocess.run(["git", "-C", cwd, "rev-parse", "--verify", "--quiet", f"refs/heads/{name}"],
                             capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError, ValueError):
        return False
    return out.returncode == 0


def switched_branch(sub: str, args: list[str]) -> str | None:
    """Branche que `git switch|checkout <args>` rend courante ("" pour une HEAD détachée), ou None si on ne sait pas."""
    create = {"-c", "-C", "--create", "--force-create"} if sub == "switch" else {"-b", "-B", "--orphan"}
    positional: list[str] = []
    for index, arg in enumerate(args):
        if arg == "--":
            return None if sub == "checkout" else (args[index + 1] if index + 1 < len(args) else None)
        if arg in create:
            return args[index + 1] if index + 1 < len(args) else None
        if arg.split("=", 1)[0] in ("--create", "--force-create", "--orphan") and "=" in arg:
            return arg.split("=", 1)[1]
        if arg in ("--detach", "-d") and sub == "switch" or arg == "--detach":
            return ""
        if not arg.startswith("-"):
            positional.append(arg)
    if sub == "checkout" and len(positional) != 1:
        return None  # `checkout <commit> <fichiers>` ne change pas de branche
    return positional[0] if positional else None


def check_commit(args: list[str]) -> str | None:
    """Motif de refus d'un `git commit`, ou None."""
    message = "`git commit --no-verify` (`-n`) interdit (gitleaks et les hooks pre-commit doivent tourner)"
    index = 0
    while index < len(args):
        arg = args[index]
        index += 1
        if arg == "--":
            break
        if arg.startswith("--"):
            if _long(arg, "--no-verify", 9):
                return message
            continue
        if arg.startswith("-") and len(arg) > 1:
            letters = arg[1:]
            for position, letter in enumerate(letters):
                if letter == "n":
                    return message
                if letter in COMMIT_SHORT_ATTACHED:
                    break
                if letter in COMMIT_SHORT_VALUE:
                    if position == len(letters) - 1:
                        index += 1  # valeur séparée : dans `-m -n`, `-n` est le message
                    break
    return None


# --- Analyse --------------------------------------------------------------------------------------------------------

RAW_PUSH = re.compile(r"\bgit\b[^;&|\n]*?\bpush\b(?P<args>[^;&|\n]*)")
RAW_COMMIT = re.compile(r"\bgit\b[^;&|\n]*?\bcommit\b(?P<args>[^;&|\n]*)")


def raw_reason(command: str, protected: list[str], cwd: str, advice: str) -> str | None:
    """Lecture prudente du texte brut quand la commande ne se découpe pas (préfère refuser à tort)."""
    for match in RAW_PUSH.finditer(command):
        args = match.group("args")
        if re.search(r"(^|\s)(--dry-run|-[A-Za-z]*n[A-Za-z]*)(\s|$)", args):
            continue
        if re.search(r"(^|\s)(--force(?!-if-includes)|-[A-Za-z]*f[A-Za-z]*\b)|(^|\s)['\"]?\+\S", args):
            return "push forcé interdit (jamais de force-push sur une branche partagée)"
        if re.search(r"--no-verify|--mirror|(^|\s)--(all|branches)\b", args):
            return "push interdit (`--no-verify`, `--mirror`, `--all` ou `--branches`)"
        for branch in protected:
            if re.search(r"(^|[\s:'\"/])" + re.escape(branch) + r"(['\"]?(\s|$))", args):
                return f"push direct vers la branche protégée `{branch}` interdit : {advice}"
        if re.fullmatch(r"\s*(\S+\s*)?(HEAD\s*)?['\"]?\s*", args):
            branch = current_branch(cwd)
            if branch in protected:
                return f"push depuis la branche protégée `{branch}` interdit : {advice}"
    for match in RAW_COMMIT.finditer(command):
        if re.search(r"--no-verify|(^|\s)-[A-Za-z]*n", match.group("args")):
            return "`git commit --no-verify` (`-n`) interdit (gitleaks et les hooks pre-commit doivent tourner)"
    return None


def reason_for(command: str, protected: list[str], cwd: str, advice: str = "passer par une branche et une PR",
               depth: int = 0) -> str | None:
    """Motif de refus de la première commande fautive de `command`, ou None."""
    if depth > MAX_DEPTH or "git" not in re.sub(r"['\"\\]", "", command):
        return None
    try:
        tokens, nested = tokenize(command)
    except ParseError:
        return raw_reason(command, protected, cwd, advice)
    for script in nested:
        reason = reason_for(script, protected, cwd, advice, depth + 1)
        if reason:
            return reason
    base = cwd
    heads: dict[str, str] = {}  # dossier → branche choisie plus tôt dans la ligne ("" : HEAD détachée)
    for words in simple_commands(tokens):
        words, script = unwrap(words)
        if script is not None:
            reason = reason_for(script, protected, base, advice, depth + 1)
            if reason:
                return reason
            continue
        if words[:1] == ["cd"] and len(words) == 2 and not words[1].startswith("-"):
            base = os.path.join(base, os.path.expanduser(words[1]))
            continue
        sub, args, dirs = git_subcommand(words)
        where = base
        for directory in dirs:
            where = os.path.join(where, os.path.expanduser(directory))
        if sub in ("switch", "checkout"):
            switched = switched_branch(sub, args)
            if sub == "checkout" and switched and not any(a in ("-b", "-B", "--orphan") or a.startswith("--orphan=")
                                                          for a in args):
                # `checkout <nom>` change de branche seulement si <nom> en est une (sinon c'est un fichier)
                switched = switched if switched in protected or local_branch_exists(where, switched) else None
            if switched is not None:
                heads[os.path.normpath(where)] = switched
            continue
        if sub == "push":
            reason = check_push(args, protected, where, advice, heads.get(os.path.normpath(where)))
        elif sub == "commit":
            reason = check_commit(args)
        else:
            reason = None
        if reason:
            return reason
    return None


# --- Hook -----------------------------------------------------------------------------------------------------------

def load_config(project_dir: str) -> dict:
    """`.harness/config.json` du projet, ou {} s'il manque ou ne se lit pas."""
    try:
        with open(os.path.join(project_dir, ".harness", "config.json"), encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def _string_list(value: object, default: list[str]) -> list[str]:
    if isinstance(value, list) and value and all(isinstance(item, str) for item in value):
        return value
    return default


def doc_path(project_dir: str) -> str:
    """BRANCHING-RELEASE.md tel que l'agent le trouve : la copie vendorisée, sinon celle du cadre."""
    if os.path.isfile(os.path.join(project_dir, ".harness", "docs", "BRANCHING-RELEASE.md")):
        return ".harness/docs/BRANCHING-RELEASE.md"
    return "docs/BRANCHING-RELEASE.md du cadre agentic-harness"


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = payload.get("tool_input", {}).get("command", "")
        cwd = payload.get("cwd") or os.getcwd()
        project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
        if not isinstance(command, str) or "git" not in re.sub(r"['\"\\]", "", command):
            return 0
        config = load_config(project_dir)
        protected = _string_list(config.get("protected_branches"), DEFAULT_PROTECTED)
        types = _string_list(config.get("branch_types"), DEFAULT_BRANCH_TYPES)
        advice = f"créer une branche `<type>/<nom-court>` (types : {', '.join(types)}) et une PR"
        reason = reason_for(command, protected, cwd, advice)
        doc = doc_path(project_dir)
    except Exception:  # noqa: BLE001 — un hook en panne ne bloque jamais le travail
        return 0
    if reason:
        print(f"agentic-harness : {reason}. Si c'est vraiment voulu, l'opérateur lance la commande lui-même "
              f"({doc}).", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
