#!/usr/bin/env python3
"""Archive the SwiftHFR tracker of ezzz/HFRnow into a directory (ADR 0010 mirror).

Copies every issue and every pull request whose base is `dev-swift`, with their
comments, reviews and review comments, as JSON (the full API payload) and as a
readable Markdown file. Runs in francoisgn/ios-app_SwiftHFR, so the project keeps
its history if the source repository goes away.

Incremental: `<out>/state.json` keeps the time of the last run; only items
updated since then are fetched again. Standard library only.

Usage: GH_TOKEN=… python3 scripts/archive_tracker.py --repo ezzz/HFRnow --out archive
Prints the archived pull request numbers (one per line) to `<out>/pulls.txt`, so
the workflow can fetch and keep their head commits.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.github.com"
BASE_BRANCH = "dev-swift"


def request(url: str, token: str | None) -> tuple[object, str | None]:
    """GET one page; returns (json, next page url). Retries on rate limits and 5xx."""
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
               "User-Agent": "swifthfr-archive"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as resp:
                return json.load(resp), next_link(resp.headers.get("Link"))
        except urllib.error.HTTPError as err:
            if err.code in (403, 429) and err.headers.get("X-RateLimit-Remaining") == "0":
                reset = int(err.headers.get("X-RateLimit-Reset", time.time() + 60))
                time.sleep(max(1, min(900, reset - time.time() + 1)))
            elif err.code >= 500 and attempt < 4:
                time.sleep(2 ** attempt)
            else:
                raise
    raise RuntimeError(f"giving up on {url}")


def next_link(header: str | None) -> str | None:
    """The `rel="next"` URL of a GitHub `Link` header, if any."""
    for part in (header or "").split(","):
        if 'rel="next"' in part:
            return part[part.index("<") + 1:part.index(">")]
    return None


def paginate(path: str, token: str | None, **params: str) -> list:
    url: str | None = f"{API}{path}?{urllib.parse.urlencode({'per_page': '100', **params})}"
    repo_prefix = "/".join(path.split("/")[:4])  # /repos/<owner>/<name>
    items: list = []
    while url:
        page, url = request(url, token)
        items.extend(page)  # type: ignore[arg-type]
        if url:
            url = owner_path(url, repo_prefix)
    return items


def owner_path(url: str, repo_prefix: str) -> str:
    """GitHub's next links may use /repositories/<id>/; some proxies only allow /repos/<owner>/<name>/."""
    return re.sub(r"^https://api\.github\.com/repositories/\d+(?=/)", f"{API}{repo_prefix}", url)


def render(item: dict, comments: list, reviews: list, review_comments: list) -> str:
    """One issue or pull request as Markdown, events in time order."""
    kind = "PR" if "base" in item else "Issue"
    head = [f"# {kind} #{item['number']}: {item['title']}", "",
            f"- State: {item['state']}" + (" (merged)" if item.get("merged_at") else ""),
            f"- Author: {item['user']['login']} · created {item['created_at']} · updated {item['updated_at']}",
            f"- Labels: {', '.join(label['name'] for label in item.get('labels', [])) or '—'}",
            f"- Source: {item['html_url']}"]
    if kind == "PR":
        head.append(f"- Branch: {item['head']['label']} → {item['base']['ref']} · head {item['head']['sha']}")
        if item.get("merge_commit_sha") and item.get("merged_at"):
            head.append(f"- Merged as {item['merge_commit_sha']} on {item['merged_at']}")
    events = [(c["created_at"], f"## {c['user']['login']} · {c['created_at']}", c.get("body") or "")
              for c in comments]
    events += [(r.get("submitted_at") or "", f"## Review {r['state']} by {r['user']['login']} · "
                f"{r.get('submitted_at')} · on {r.get('commit_id', '')[:7]}", r.get("body") or "")
               for r in reviews]
    events += [(c["created_at"], f"## Review comment by {c['user']['login']} · {c['created_at']} · "
                f"`{c.get('path')}`:{c.get('line') or c.get('original_line')}", c.get("body") or "")
               for c in review_comments]
    parts = ["\n".join(head), item.get("body") or ""]
    parts += [f"{title}\n\n{body}" for _, title, body in sorted(events, key=lambda e: e[0])]
    return "\n\n".join(parts).rstrip() + "\n"


def group(items: list, key: str) -> dict[int, list]:
    """Comments grouped by the issue or PR number found at the end of `item[key]`."""
    out: dict[int, list] = {}
    for c in items:
        out.setdefault(int(c[key].rstrip("/").rsplit("/", 1)[1]), []).append(c)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default="ezzz/HFRnow")
    parser.add_argument("--out", type=Path, default=Path("archive"))
    args = parser.parse_args()
    token = os.environ.get("GH_TOKEN")
    repo = f"/repos/{args.repo}"
    state_file = args.out / "state.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    since = state.get("since")
    started = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    window = {"since": since} if since else {}

    pulls = {p["number"]: p for p in paginate(f"{repo}/pulls", token, state="all", base=BASE_BRANCH)}
    issues = [i for i in paginate(f"{repo}/issues", token, state="all", **window)]
    comments = group(paginate(f"{repo}/issues/comments", token, **window), "issue_url")
    review_comments = group(paginate(f"{repo}/pulls/comments", token, **window), "pull_request_url")

    touched = {i["number"] for i in issues} | set(comments) | set(review_comments)
    if since:
        touched |= {n for n, p in pulls.items() if p["updated_at"] >= since}
    else:
        touched |= set(pulls)
    issue_by_number = {i["number"]: i for i in issues}
    written = 0
    for number in sorted(touched):
        if number in pulls:
            item, folder = pulls[number], args.out / "pulls"
            reviews = paginate(f"{repo}/pulls/{number}/reviews", token)
        elif number in issue_by_number and "pull_request" not in issue_by_number[number]:
            item, folder, reviews = issue_by_number[number], args.out / "issues", []
        else:
            continue  # a PR on another base (the legacy app), or unknown: out of scope
        folder.mkdir(parents=True, exist_ok=True)
        stem = folder / f"{number:04d}"
        old = json.loads(stem.with_suffix(".json").read_text()) if stem.with_suffix(".json").exists() else {}
        merged = {
            "item": item,
            "comments": merge_by_id(old.get("comments", []), comments.get(number, [])),
            "reviews": reviews or old.get("reviews", []),
            "review_comments": merge_by_id(old.get("review_comments", []), review_comments.get(number, [])),
        }
        stem.with_suffix(".json").write_text(json.dumps(merged, indent=1, ensure_ascii=False) + "\n")
        stem.with_suffix(".md").write_text(render(item, merged["comments"], merged["reviews"],
                                                  merged["review_comments"]))
        written += 1

    (args.out / "pulls.txt").write_text("".join(f"{n}\n" for n in sorted(pulls)))
    state_file.write_text(json.dumps({"since": started, "source": args.repo}, indent=1) + "\n")
    print(f"archived {written} items; {len(pulls)} PRs on {BASE_BRANCH}", file=sys.stderr)
    return 0


def merge_by_id(old: list, new: list) -> list:
    """Old entries updated by new ones (same id), in creation order. Deleted comments are kept."""
    by_id = {c["id"]: c for c in old}
    by_id.update({c["id"]: c for c in new})
    return sorted(by_id.values(), key=lambda c: c["created_at"])


if __name__ == "__main__":
    sys.exit(main())
