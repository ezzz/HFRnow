#!/usr/bin/env python3
"""Tableau de bord du flux d'un dépôt : avancement, goulots, travaux en panne, boucles, coût CI (docs/FINOPS.md §4).

Lit les issues, PR et passages de CI d'un dépôt GitHub (via `gh api`, jeton du workflow ou de la session) ou un fichier
JSON (`--input`, pour les tests et le rejeu), puis écrit un rapport Markdown lisible par un non-technicien, ou du JSON.
Ne fait que lire ; publier le rapport (issue « Tableau de bord ») est le travail du workflow flow-report.yml.

Usage :
  flow-metrics.py --repo owner/nom [--format md|json] [--stall-hours 24] [--draft-stall-hours 120]
                  [--max-ci-runs 6] [--max-review-rounds 3] [--window-days 14] [--json-out f]
  flow-metrics.py --input donnees.json --now 2026-11-07T12:00:00Z
Bibliothèque standard seulement (Python ≥ 3.9).
"""
import argparse
import calendar
import json
import math
import re
import statistics
import subprocess
import sys
import time

# PR d'agent : `Claim: <id>` d'un agent (un humain prend avec `human/<login>`, CONVENTIONS.md §PR), pied de génération,
# ou ancienne branche `claude/…` (convention d'avant 0.3.0, gardée pour l'historique).
AGENT_PREFIXES = ("claude/",)
AGENT_BODY_RE = re.compile(r"^Claim:[ \t]*(?!human/)\S+|Generated with \[Claude Code\]", re.M)
LABELS_CLAIMED = ("pris en charge", "status: claimed")
BOTTLENECK_LABELS = ("bloqué", "à clarifier")
P1_PREFIX = "P1"


VERDICT_RE = re.compile(r"\*\*Revue (adversariale|IA|conformité)[^*\n]*?:\s*"
                        r"(APPROUVÉ|CHANGEMENTS DEMANDÉS|CONFORME|ÉCARTS|HORS PÉRIMÈTRE)")
VERDICT_SOURCE = {"adversariale": "adversariale", "IA": "ia", "conformité": "conformité"}
ACTIONABLE_RE = re.compile(r"Actionable comments posted:\s*(\d+)")
MIN_QUALITY_SAMPLE = 3


def review_events(pull):
    """Verdicts tracés sur une PR, dans l'ordre (revues GitHub, puis commentaires) : [{source, problem, at}].

    Sources : verdicts du cadre (« **Revue adversariale|IA|conformité (…) : VERDICT** », REVIEW-ROUNDS.md §Traçabilité),
    CodeRabbit (« Actionable comments posted: N »), humains (APPROVED / CHANGES_REQUESTED). Le reste est ignoré.
    """
    events = []
    items = [(rv.get("body") or "", rv.get("state"), (rv.get("user") or {}).get("login", ""), rv.get("submitted_at"))
             for rv in pull.get("reviews", [])]
    items += [(c.get("body") or "", None, (c.get("user") or {}).get("login", ""), c.get("created_at"))
              for c in pull.get("comments", [])]
    for body, state, login, at in items:
        # Verdicts en début de ligne seulement : une citation (`>`) ou une ligne de tableau (`|`) ne compte pas ;
        # un corps peut en porter plusieurs (consolidation de /compliance-review).
        verdicts = [m for line in body.splitlines() if not line.lstrip().startswith((">", "|"))
                    for m in [VERDICT_RE.match(re.sub(r"^(?:[-*]|\d+[.)])\s+", "", line.strip()))] if m]
        if verdicts:
            events += [{"source": VERDICT_SOURCE[m.group(1)], "at": at,
                        "problem": m.group(2) in ("CHANGEMENTS DEMANDÉS", "ÉCARTS")}
                       for m in verdicts if m.group(2) != "HORS PÉRIMÈTRE"]
            continue
        if login.startswith("coderabbitai"):
            n = ACTIONABLE_RE.search(body)
            if n:
                events.append({"source": "coderabbit", "at": at, "problem": int(n.group(1)) > 0})
            elif state == "CHANGES_REQUESTED":
                events.append({"source": "coderabbit", "at": at, "problem": True})
        elif state in ("APPROVED", "CHANGES_REQUESTED"):
            events.append({"source": "bot" if login.endswith("[bot]") else "humain", "at": at,
                           "problem": state == "CHANGES_REQUESTED"})
    return events


def quality(merged):
    """Qualité au premier passage et effort de correction sur les PR mergées (FINOPS.md §4)."""
    q = {"reviewed": 0, "problem": 0, "untraced": 0, "by_source": {},
         "agent": {"reviewed": 0, "problem": 0}, "human": {"reviewed": 0, "problem": 0}}
    fix_commits, fix_hours = [], []
    for p in merged:
        merged_at = parse_time(p["merged_at"])
        # Un verdict posté après le merge ne dit rien de la qualité au premier passage
        events = [e for e in review_events(p) if not e.get("at") or parse_time(e["at"]) <= merged_at]
        if not events:
            q["untraced"] += 1
            continue
        side = q["agent"] if is_agent(p) else q["human"]
        q["reviewed"] += 1
        side["reviewed"] += 1
        problems = [e for e in events if e["problem"]]
        if not problems:
            continue
        q["problem"] += 1
        side["problem"] += 1
        for src in sorted({e["source"] for e in problems}):
            q["by_source"][src] = q["by_source"].get(src, 0) + 1
        dated = [parse_time(e["at"]) for e in problems if e.get("at")]
        if not dated:
            continue
        first = min(dated)
        commits = [c["commit"]["committer"]["date"] for c in p.get("commits", [])]
        fix_commits.append(sum(1 for d in commits if parse_time(d) > first))
        fix_hours.append(_hours(parse_time(p["merged_at"]) - first))
    q["by_source"] = dict(sorted(q["by_source"].items()))
    q["problem_ratio"] = round(100 * q["problem"] / q["reviewed"]) if q["reviewed"] else None
    q["fix_commits_mean"] = round(sum(fix_commits) / len(fix_commits), 1) if fix_commits else None
    q["fix_hours_median"] = round(statistics.median(fix_hours), 1) if fix_hours else None
    return q


def is_agent(pull):
    """PR écrite par un agent (AGENT_BODY_RE), plutôt que par un humain."""
    return pull["head"]["ref"].startswith(AGENT_PREFIXES) or bool(AGENT_BODY_RE.search(pull.get("body") or ""))


def parse_time(value):
    """ISO 8601 UTC (`2026-11-07T12:00:00Z`) → secondes epoch."""
    return calendar.timegm(time.strptime(value.replace("Z", "")[:19], "%Y-%m-%dT%H:%M:%S"))


def format_time(seconds):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(seconds))


def _labels(item):
    return [label["name"] if isinstance(label, dict) else label for label in item.get("labels", [])]


def _hours(seconds):
    return seconds / 3600


def analyse(data, now, stall_hours=24, draft_stall_hours=120, max_ci_runs=6, max_review_rounds=3, window_days=14,
            max_problem_ratio=50):
    """Calcule le rapport à partir de {"issues", "pulls", "runs"} (formes de l'API REST GitHub)."""
    issues = [i for i in data.get("issues", []) if "pull_request" not in i]
    pulls = data.get("pulls", [])
    runs = data.get("runs", [])
    open_issues = [i for i in issues if i["state"] == "open"]
    open_pulls = [p for p in pulls if p["state"] == "open"]

    stalled = []
    for i in open_issues:
        idle = _hours(now - parse_time(i["updated_at"]))
        if any(lb in LABELS_CLAIMED for lb in _labels(i)) and idle > stall_hours:
            stalled.append({"kind": "issue", "number": i["number"], "title": i["title"], "idle_hours": round(idle),
                            "p1": any(lb.startswith(P1_PREFIX) for lb in _labels(i)), "url": i.get("html_url")})
    for p in open_pulls:
        idle = _hours(now - parse_time(p["updated_at"]))
        if idle > (draft_stall_hours if p.get("draft") else stall_hours):
            stalled.append({"kind": "PR", "number": p["number"], "title": p["title"], "idle_hours": round(idle),
                            "p1": False, "url": p.get("html_url")})

    # Un passage de CI = un push testé sur la PR : SHA distincts des runs `pull_request` de sa branche. Ni le nombre de
    # workflows par push, ni les runs push/schedule d'une branche de promotion (develop) ne comptent, ni les runs
    # entièrement sautés ou annulés : pousser souvent sur un brouillon ne coûte rien et n'est pas une boucle (CI-BUDGET §2).
    pushes_by_branch = {}
    for r in runs:
        if r.get("event") == "pull_request" and r.get("conclusion") not in ("skipped", "cancelled"):
            pushes_by_branch.setdefault(r.get("head_branch"), set()).add(r.get("head_sha"))
    loops = []
    for p in open_pulls:
        n_runs = len(pushes_by_branch.get(p["head"]["ref"], ()))
        if n_runs > max_ci_runs:
            loops.append({"kind": "ci", "number": p["number"], "title": p["title"], "count": n_runs,
                          "url": p.get("html_url")})
        if p.get("review_count", 0) > max_review_rounds:
            loops.append({"kind": "revue", "number": p["number"], "title": p["title"], "count": p["review_count"],
                          "url": p.get("html_url")})

    bottlenecks = {}
    bottleneck_items = [{"number": i["number"], "title": i["title"], "labels": [lb for lb in _labels(i) if lb in BOTTLENECK_LABELS]}
                        for i in sorted(open_issues, key=lambda i: i["number"])
                        if any(lb in BOTTLENECK_LABELS for lb in _labels(i))]
    for label in BOTTLENECK_LABELS:
        numbers = sorted(i["number"] for i in open_issues if label in _labels(i))
        if numbers:
            bottlenecks[label] = numbers

    milestones = {}
    for i in ([] if data.get("milestones") else issues):
        if i.get("milestone"):
            m = milestones.setdefault(i["milestone"]["title"], {"closed": 0, "total": 0})
            m["total"] += 1
            m["closed"] += i["state"] == "closed"
    milestone_list = [{"title": t, "closed": m["closed"], "total": m["total"],
                       "percent": round(100 * m["closed"] / m["total"])} for t, m in sorted(milestones.items())]
    if data.get("milestones"):  # source exacte : compteurs de l'API, issues anciennes comprises
        milestone_list = []
        for m in sorted(data["milestones"], key=lambda m: m["title"]):
            total = m["open_issues"] + m["closed_issues"]
            if total:
                milestone_list.append({"title": m["title"], "closed": m["closed_issues"], "total": total,
                                       "percent": round(100 * m["closed_issues"] / total),
                                       "due_on": (m.get("due_on") or "")[:10] or None})

    window_start = now - window_days * 86400
    merged = [p for p in pulls if p.get("merged_at") and parse_time(p["merged_at"]) >= window_start]
    agent = [p for p in merged if is_agent(p)]
    leads = [_hours(parse_time(p["merged_at"]) - parse_time(p["created_at"])) for p in merged]

    durations = []
    for r in runs:
        start = r.get("run_started_at") or r.get("created_at")
        if start and r.get("updated_at") and r.get("conclusion") != "skipped":  # un run sauté ne facture rien
            durations.append(max(0.0, (parse_time(r["updated_at"]) - parse_time(start)) / 60))
    # Annulés (cancel-in-progress) et sautés (brouillon) ne disent rien de la qualité : hors du dénominateur.
    finished = [r for r in runs if r.get("conclusion") in ("success", "failure")]
    failures = [r for r in finished if r["conclusion"] == "failure"]

    by_type = {}
    for i in open_issues:
        for lb in _labels(i):
            by_type[lb] = by_type.get(lb, 0) + 1

    q = quality(merged)
    high_problem = (q["problem_ratio"] is not None and q["reviewed"] >= MIN_QUALITY_SAMPLE
                    and q["problem_ratio"] > max_problem_ratio)

    if any(s["p1"] for s in stalled) or loops:
        status = "🔴"
    elif stalled or bottlenecks or high_problem:
        status = "🟠"
    else:
        status = "🟢"

    return {
        "status": status,
        "generated_at": format_time(now),
        "open": {"issues": len(open_issues), "pulls": len(open_pulls),
                 "drafts": sum(1 for p in open_pulls if p.get("draft"))},
        "labels": dict(sorted(by_type.items(), key=lambda kv: (-kv[1], kv[0]))),
        "milestones": milestone_list,
        "stalled": sorted(stalled, key=lambda s: -s["idle_hours"]),
        "loops": loops,
        "bottlenecks": bottlenecks,
        "bottleneck_items": bottleneck_items,
        "merged": {"total": len(merged), "agent": len(agent), "human": len(merged) - len(agent),
                   "median_lead_hours": round(statistics.median(leads), 1) if leads else None},
        "quality": q,
        "ci": {"runs": len(runs),
               # Chaque job est arrondi à la minute (CI-BUDGET.md §1) : sans le détail des jobs, borne basse par passage.
               "billed_minutes_min": sum(max(1, math.ceil(d)) for d in durations),
               "failure_rate": round(100 * len(failures) / len(finished)) if finished else 0},
        "thresholds": {"stall_hours": stall_hours, "draft_stall_hours": draft_stall_hours,
                       "max_ci_runs": max_ci_runs, "max_review_rounds": max_review_rounds, "window_days": window_days,
                       "max_problem_ratio": max_problem_ratio},
    }


def _cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def render_markdown(r, repo):
    verdict = {"🟢": "OK : le flux avance", "🟠": "Vigilance : des éléments attendent",
               "🔴": "Critique : panne ou boucle à traiter"}[r["status"]]
    out = [f"# Tableau de bord — {repo}", "",
           f"**{r['status']} {verdict}** · généré le {r['generated_at']} (UTC)", "",
           "| Indicateur | Valeur |", "|---|---|",
           f"| Issues ouvertes | {r['open']['issues']} |",
           f"| PR ouvertes (dont brouillons) | {r['open']['pulls']} ({r['open']['drafts']}) |",
           f"| PR mergées sur {r['thresholds']['window_days']} j (agents / humains) | "
           f"{r['merged']['total']} ({r['merged']['agent']} / {r['merged']['human']}) |",
           f"| Délai médian ouverture → merge | "
           f"{'—' if r['merged']['median_lead_hours'] is None else str(r['merged']['median_lead_hours']) + ' h'} |",
           f"| Passages de CI (minutes facturées, borne basse) | {r['ci']['runs']} ({r['ci']['billed_minutes_min']} min) |",
           f"| Taux d'échec CI | {r['ci']['failure_rate']} % |", ""]
    if r["milestones"]:
        out += ["## Jalons", "", "| Jalon | Avancement | Fermées / total | Échéance |", "|---|---|---|---|"]
        for m in r["milestones"]:
            bar = "█" * (m["percent"] // 10) + "░" * (10 - m["percent"] // 10)
            out.append(f"| {_cell(m['title'])} | `{bar}` {m['percent']} % | {m['closed']} / {m['total']} | "
                       f"{m.get('due_on') or '—'} |")
        out.append("")
    out += ["## Goulots", ""]
    if r["bottleneck_items"]:
        out += ["| Issue | Titre | Statut |", "|---|---|---|"]
        out += [f"| #{b['number']} | {_cell(b['title'])} | {', '.join(b['labels'])} |" for b in r["bottleneck_items"]]
    else:
        out.append("- Aucun élément `bloqué` ni `à clarifier`.")
    out += ["", "## En panne (sans activité)", ""]
    if r["stalled"]:
        out += ["| Élément | Titre | Inactif depuis |", "|---|---|---|"]
        out += [f"| {s['kind']} #{s['number']}{' 🔴' if s['p1'] else ''} | {_cell(s['title'])} | {s['idle_hours']} h |"
                for s in r["stalled"]]
    else:
        out.append("- Rien.")
    out += ["", "## Boucles (CI ou revue qui tournent en rond)", ""]
    if r["loops"]:
        out += ["| PR | Titre | Type | Nombre |", "|---|---|---|---|"]
        out += [f"| #{lp['number']} | {_cell(lp['title'])} | {lp['kind']} | {lp['count']} |" for lp in r["loops"]]
    else:
        out.append("- Rien.")
    q = r["quality"]
    out += ["", "## Qualité au premier passage", ""]
    if q["reviewed"]:
        def ratio(side):
            return f"{round(100 * side['problem'] / side['reviewed'])} % ({side['problem']}/{side['reviewed']})" \
                if side["reviewed"] else "—"
        out += ["| Indicateur | Valeur |", "|---|---|",
                f"| PR à problème (au moins un constat en revue) | {q['problem_ratio']} % ({q['problem']}/{q['reviewed']}) |",
                f"| … écrites par des agents / des humains | {ratio(q['agent'])} / {ratio(q['human'])} |",
                "| Constats par source (PR concernées) | "
                + (", ".join(f"{k} {v}" for k, v in q["by_source"].items()) or "—") + " |",
                f"| Effort de correction : commits après le 1er constat (moyenne) | "
                f"{'—' if q['fix_commits_mean'] is None else q['fix_commits_mean']} |",
                f"| Délai 1er constat → merge (médiane) | "
                f"{'—' if q['fix_hours_median'] is None else str(q['fix_hours_median']) + ' h'} |"]
    else:
        out.append("- Aucune PR mergée avec une revue tracée sur la période.")
    if q["untraced"]:
        out.append(f"\n🟠 {q['untraced']} PR mergée(s) sans aucun verdict tracé : la mesure les ignore "
                   "(REVIEW-ROUNDS.md §Traçabilité).")
    if r["labels"]:
        out += ["", "## Issues ouvertes par label", "", "| Label | Nombre |", "|---|---|"]
        out += [f"| {_cell(k)} | {v} |" for k, v in r["labels"].items()]
    t = r["thresholds"]
    out += ["", f"_Seuils : inactivité {t['stall_hours']} h (brouillon {t['draft_stall_hours']} h), "
                f"boucle CI > {t['max_ci_runs']} pushes testés, boucle de revue > {t['max_review_rounds']} revues, "
                f"PR à problème > {t['max_problem_ratio']} % (dès {MIN_QUALITY_SAMPLE} PR relues). "
                "Lecture : FINOPS.md §4 du cadre agentic-harness._", ""]
    return "\n".join(out)


def _gh(path):
    out = subprocess.run(["gh", "api", "--paginate", "--slurp", path], capture_output=True, text=True, check=True).stdout
    pages = json.loads(out)
    items = []
    for page in pages:
        items.extend(page.get("workflow_runs", []) if isinstance(page, dict) else page)
    return items


def collect(repo, window_days):
    since = format_time(time.time() - max(window_days, 30) * 86400)
    # Ouvertes : toutes, sans `since` (une prise en charge inactive depuis longtemps est la panne la plus grave) ;
    # fermées : la fenêtre seulement. Jalons : compteurs de l'API, exacts quelle que soit l'ancienneté des issues.
    issues = _gh(f"repos/{repo}/issues?state=open&per_page=100")
    issues += _gh(f"repos/{repo}/issues?state=closed&per_page=100&since={since}")
    milestones = _gh(f"repos/{repo}/milestones?state=open&per_page=100")
    pulls = _gh(f"repos/{repo}/pulls?state=all&per_page=100&sort=updated&direction=desc")
    pulls = [p for p in pulls if p["state"] == "open" or (p.get("updated_at") or "") >= since]
    for p in pulls:
        if p["state"] == "open":
            p["review_count"] = len(_gh(f"repos/{repo}/pulls/{p['number']}/reviews?per_page=100"))
        elif p.get("merged_at") and p["merged_at"] >= since:
            # Qualité au premier passage : verdicts (revues, commentaires) et commits de correction
            p["reviews"] = _gh(f"repos/{repo}/pulls/{p['number']}/reviews?per_page=100")
            p["comments"] = _gh(f"repos/{repo}/issues/{p['number']}/comments?per_page=100")
            p["commits"] = _gh(f"repos/{repo}/pulls/{p['number']}/commits?per_page=100")
    runs = _gh(f"repos/{repo}/actions/runs?per_page=100&created=>={since[:10]}")
    return {"issues": issues, "pulls": pulls, "runs": runs, "milestones": milestones}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--repo")
    src.add_argument("--input")
    ap.add_argument("--now", help="horloge fixée (tests, rejeu)")
    ap.add_argument("--format", choices=("md", "json"), default="md")
    ap.add_argument("--json-out", help="écrit aussi le rapport JSON dans ce fichier (une seule collecte)")
    ap.add_argument("--stall-hours", type=float, default=24)
    ap.add_argument("--draft-stall-hours", type=float, default=120)
    ap.add_argument("--max-ci-runs", type=int, default=6)
    ap.add_argument("--max-review-rounds", type=int, default=3)
    ap.add_argument("--window-days", type=int, default=14)
    ap.add_argument("--max-problem-ratio", type=int, default=50, help="%% de PR à problème au-delà duquel le statut passe 🟠")
    a = ap.parse_args(argv)
    if a.input:
        with open(a.input, encoding="utf-8") as f:
            data = json.load(f)
    else:
        data = collect(a.repo, a.window_days)
    now = parse_time(a.now) if a.now else time.time()
    report = analyse(data, now, a.stall_hours, a.draft_stall_hours, a.max_ci_runs, a.max_review_rounds, a.window_days,
                     a.max_problem_ratio)
    if a.json_out:
        with open(a.json_out, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
    if a.format == "json":
        json.dump(report, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(render_markdown(report, a.repo or a.input))
    return 0


if __name__ == "__main__":
    sys.exit(main())
