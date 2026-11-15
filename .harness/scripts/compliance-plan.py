#!/usr/bin/env python3
"""Résout la clé `compliance` de .harness/config.json en relecteurs de conformité à lancer (COMPLIANCE.md §2).

Trois façons de brancher un référentiel, au choix de l'entreprise :
  "gdpr"                                         agent intégré du cadre (.claude/agents/compliance-gdpr.md)
  {"id": "pci", "agent": "<chemin .md>"}         agent de l'entreprise, qui remplace l'intégré ou ajoute un référentiel
  {"id": "dora", "spec": "<chemin .md>"}         spec seule : le relecteur générique `compliance-reviewer` l'applique
Options communes : "paths" (globs) et "keywords" (mots du diff) décident du périmètre sans lancer d'agent ;
"enabled": false désactive une entrée ; "confirme" nomme qui tranche (DPO, RSSI, QSA…).

Usage : compliance-plan.py [--root .] [--files f1 f2 … | --base origin/develop] [--diff-file diff.txt]
Sortie JSON {"reviewers": [...], "errors": [...]} ; code 1 si une entrée est invalide. Bibliothèque standard seulement.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

AGENTS_DIR = ".claude/agents"
GENERIC = "compliance-reviewer"
SPEC_SECTIONS = ("## Quand intervenir", "## Ce que je vérifie", "## Preuves attendues", "## Sources")
SPEC_KEYS = ("id", "référentiel", "confirme")


def _frontmatter(text):
    if not text.startswith("---\n") or text.find("\n---", 4) < 0:
        return None
    meta = {}
    for line in text[4:text.find("\n---", 4)].splitlines():
        if ":" in line and not line.startswith(" "):
            key, value = line.split(":", 1)
            meta[key.strip()] = value.strip()
    return meta


def check_spec(path):
    """Écarts d'un fichier de spec de conformité (frontmatter et sections obligatoires)."""
    path = pathlib.Path(path)
    if not path.is_file():
        return [f"spec introuvable : {path}"]
    text = path.read_text(encoding="utf-8")
    meta = _frontmatter(text) or {}
    errors = [f"{path} : clé `{k}` manquante dans l'en-tête" for k in SPEC_KEYS if not meta.get(k)]
    errors += [f"{path} : section « {s} » manquante" for s in SPEC_SECTIONS if s not in text]
    return errors


def glob_match(path, pattern):
    """Glob de chemin : `*` et `?` restent dans un dossier, `**/` couvre zéro ou plusieurs dossiers, `/**` tout le dessous."""
    rx, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            rx, i = rx + "(?:.*/)?", i + 3
        elif pattern.startswith("**", i):
            rx, i = rx + ".*", i + 2
        elif pattern[i] == "*":
            rx, i = rx + "[^/]*", i + 1
        elif pattern[i] == "?":
            rx, i = rx + "[^/]", i + 1
        else:
            rx, i = rx + re.escape(pattern[i]), i + 1
    return re.fullmatch(rx, path) is not None


def _inside(root, rel):
    """Le chemin reste dans le dépôt (ni absolu hors racine, ni `..` qui en sort)."""
    base = pathlib.Path(root).resolve()
    target = (base / rel).resolve()
    return target == base or base in target.parents


def _in_scope(entry, files, diff):
    paths, keywords = entry.get("paths") or [], entry.get("keywords") or []
    if not paths and not keywords:
        return "à évaluer", "périmètre jugé par l'agent (section « Quand intervenir »)"
    for f in files:
        for g in paths:
            if glob_match(f, g):
                return "dans le périmètre", f"{f} correspond à {g}"
    # Lignes ajoutées ou retirées seulement (pas les en-têtes +++/--- qui portent des chemins), mot entier
    changed = "\n".join(line[1:] for line in diff.splitlines()
                        if line.startswith(("+", "-")) and not line.startswith(("+++", "---")))
    for k in keywords:
        if re.search(rf"(?<!\w){re.escape(k)}(?!\w)", changed, re.IGNORECASE):
            return "dans le périmètre", f"mot-clé « {k} » dans le diff"
    return "hors périmètre", "aucun chemin ni mot-clé configuré n'est touché"


def plan(config, root, files=(), diff=""):
    root = pathlib.Path(root)
    reviewers, errors, seen = [], [], set()
    entries = config.get("compliance", [])
    if not isinstance(entries, list):
        return {"reviewers": [], "errors": ["`compliance` doit être une liste (ex. [\"gdpr\"])"]}
    for raw in entries:
        if not isinstance(raw, (str, dict)):
            errors.append(f"entrée invalide (texte ou objet attendu) : {raw!r}")
            continue
        entry = {"id": raw} if isinstance(raw, str) else dict(raw)
        cid = entry.get("id")
        if not isinstance(cid, str) or not cid.strip():
            errors.append(f"entrée sans `id` texte : {raw!r}")
            continue
        cid = cid.strip()
        if re.search(r"[/\\]|\.\.", cid):  # l'id entre dans un nom de fichier : ni dossier, ni remontée
            errors.append(f"{cid!r} : `id` invalide (ni `/`, ni `\\`, ni `..`)")
            continue
        bad = [k for k in ("agent", "spec") if entry.get(k) is not None and not isinstance(entry[k], str)]
        if bad:
            errors.append(f"{cid} : `{bad[0]}` doit être un chemin (texte)")
            continue
        outside = [k for k in ("agent", "spec") if entry.get(k) and not _inside(root, entry[k])]
        if outside:
            errors.append(f"{cid} : `{outside[0]}` pointe hors du dépôt, refusé")
            continue
        if cid in seen:
            errors.append(f"{cid} : déclaré deux fois")
            continue
        seen.add(cid)
        if entry.get("enabled", True) is False:
            continue
        if entry.get("agent") and entry.get("spec"):
            errors.append(f"{cid} : `agent` ou `spec`, pas les deux")
            continue
        if entry.get("agent"):
            path = root / entry["agent"]
            meta = _frontmatter(path.read_text(encoding="utf-8")) if path.is_file() else None
            if not path.is_file():
                errors.append(f"{cid} : agent introuvable {entry['agent']}")
                continue
            if not meta or not meta.get("name"):
                errors.append(f"{cid} : {entry['agent']} sans `name` dans son en-tête")
                continue
            mode, agent, file = "agent du projet", meta["name"], entry["agent"]
        elif entry.get("spec"):
            spec_errors = check_spec(root / entry["spec"])
            if spec_errors:
                errors += [f"{cid} : {e}" for e in spec_errors]
                continue
            if not (root / AGENTS_DIR / f"{GENERIC}.md").is_file():
                errors.append(f"{cid} : relecteur générique {AGENTS_DIR}/{GENERIC}.md absent (exclu de la synchro ?)")
                continue
            mode, agent, file = "spec", GENERIC, entry["spec"]
        else:
            file = f"{AGENTS_DIR}/compliance-{cid}.md"
            if not (root / file).is_file():
                errors.append(f"{cid} : pas d'agent intégré {file} ; fournir `agent` ou `spec`")
                continue
            mode, agent = "intégré", f"compliance-{cid}"
        scope, reason = _in_scope(entry, files, diff)
        reviewer = {"id": cid, "mode": mode, "agent": agent, "file": file, "scope": scope, "reason": reason}
        if entry.get("confirme"):
            reviewer["confirme"] = entry["confirme"]
        reviewers.append(reviewer)
    return {"reviewers": reviewers, "errors": errors}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--files", nargs="*", default=None)
    ap.add_argument("--base", help="calcule fichiers et diff avec git diff <base>...HEAD")
    ap.add_argument("--diff-file")
    a = ap.parse_args()
    root = pathlib.Path(a.root)
    cfg_path = root / ".harness/config.json"
    config = json.loads(cfg_path.read_text(encoding="utf-8")) if cfg_path.is_file() else {}
    files, diff = a.files or [], ""
    if a.base:
        git = ["git", "-C", str(root), "diff", f"{a.base}...HEAD"]
        names = subprocess.run(git + ["--name-only"], capture_output=True, text=True)
        if names.returncode != 0:
            print(f"✘ git diff {a.base}...HEAD : {names.stderr.strip()}", file=sys.stderr)
            return 1
        files = names.stdout.split()
        diff = subprocess.run(git, capture_output=True, text=True).stdout
    if a.diff_file:
        diff = pathlib.Path(a.diff_file).read_text(encoding="utf-8")
    result = plan(config, root, files, diff)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    for e in result["errors"]:
        print(f"✘ {e}", file=sys.stderr)
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
