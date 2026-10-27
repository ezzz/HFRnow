#!/usr/bin/env python3
"""Issue claims and the PR link check (AGENTS.md §5, §8).

Break-glass: a PR whose body has a line `Direct-PR: <reason>` (or that carries the `direct-pr` label) skips the issue and
claim rule; the check then labels it `direct-pr` so such PRs can be counted later. Dependabot is exempt.

A session claims an issue with a comment whose first line is `/claim <session-id>` and gives it back with `/release`.
The first claim wins; another session's `/claim` is refused until the holder releases. Only comments from repository
members count (author association OWNER, MEMBER or COLLABORATOR), so outsiders cannot take or drop a claim on a public repo.

Commands (run by the workflows, standard library only, GitHub REST through GITHUB_TOKEN):
    issue_claims.py check-pr      PR event: the body links an open issue and states the claim that holds it.
    issue_claims.py sync-issue    Issue comment event: labels the issue and answers a refused claim.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

SESSION_ID = re.compile(r"^[a-z]+/[A-Za-z0-9._-]{1,64}$")
COMMAND = re.compile(r"^/(claim|release)(?:[ \t]+(\S+))?[ \t]*$")
MEMBERS = {"OWNER", "MEMBER", "COLLABORATOR"}
ISSUE_LINK = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)\s+#(\d+)\b", re.IGNORECASE)
CLAIM_LINE = re.compile(r"^Claim:[ \t]*(\S+)[ \t]*$", re.MULTILINE)
EXEMPT_AUTHORS = {"dependabot[bot]"}
HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
DIRECT_PR_LINE = re.compile(r"^Direct-PR:[ \t]*(.*?)[ \t]*$", re.MULTILINE | re.IGNORECASE)
DIRECT_PR_LABEL = "direct-pr"
CLAIMED_LABEL = "status: claimed"
READY_LABEL = "status: ready"


@dataclass
class ClaimState:
    """Result of replaying an issue's comments in order."""

    holder: str | None = None
    refused: list[tuple[str, str]] = field(default_factory=list)  # (session that asked, holder at that time)
    invalid: list[str] = field(default_factory=list)  # malformed session ids


def parse_command(body: str) -> tuple[str, str | None] | None:
    """`("claim", id)` or `("release", id or None)` from the first non-empty line of a comment, else None."""
    for line in (body or "").splitlines():
        if line.strip():
            match = COMMAND.match(line.strip())
            return (match.group(1), match.group(2)) if match else None
    return None


def replay(comments: list[dict]) -> ClaimState:
    """Claim state after `comments` (GitHub REST issue comments, oldest first)."""
    state = ClaimState()
    for comment in comments:
        if comment.get("author_association") not in MEMBERS:
            continue
        command = parse_command(comment.get("body", ""))
        if command is None:
            continue
        verb, session = command
        if verb == "claim":
            if session is None or not SESSION_ID.match(session):
                state.invalid.append(session or "")
            elif state.holder is None:
                state.holder = session
            elif state.holder != session:
                state.refused.append((session, state.holder))
        elif session is None or session == state.holder:
            # `/release` alone frees the issue; `/release <id>` only when it names the holder.
            state.holder = None
    return state


def direct_pr_reason(body: str) -> str | None:
    """The break-glass reason of a `Direct-PR:` line ("" when the line is there but empty), None without the line."""
    match = DIRECT_PR_LINE.search(normalized(body))
    return match.group(1) if match else None


def break_glass(body: str, author: str, labels: frozenset[str]) -> tuple[bool, list[str]]:
    """`(skips the issue rule, errors)`: Dependabot, the `direct-pr` label, or a `Direct-PR:` line of two words or more."""
    if author in EXEMPT_AUTHORS or DIRECT_PR_LABEL in labels:
        return True, []
    reason = direct_pr_reason(body)
    if reason is None:
        return False, []
    if len(reason.split()) < 2:
        return True, ["`Direct-PR:` needs a short reason (two words or more) on the same line, e.g. `Direct-PR: fix CI badge`."]
    return True, []


def pr_errors(body: str, author: str, issues: dict[int, dict], claims: dict[int, ClaimState],
              labels: frozenset[str] = frozenset()) -> list[str]:
    """Reasons the PR fails the check; empty when it passes. `issues`/`claims` are keyed by the linked numbers."""
    skipped, errors = break_glass(body, author, labels)
    if skipped:
        return errors
    body = normalized(body)
    errors = []
    numbers = linked_issues(body)
    if not numbers:
        errors.append("The PR body must link its issue in this repository: `Closes #N` (or `Refs #N` for partial work), "
                      "or, as a break-glass, state `Direct-PR: <reason>` on its own line.")
    claim_match = CLAIM_LINE.search(body)
    claimant = claim_match.group(1) if claim_match else None
    if claimant is None:
        errors.append("The PR body must state the claim it works under: a line `Claim: <session-id>`.")
    for number in numbers:
        issue = issues.get(number)
        if issue is None:
            errors.append(f"#{number} does not exist.")
            continue
        if "pull_request" in issue:
            errors.append(f"#{number} is a pull request, not an issue.")
            continue
        if issue.get("state") != "open":
            errors.append(f"#{number} is closed.")
            continue
        holder = claims[number].holder
        if holder is None:
            errors.append(f"#{number} is not claimed: comment `/claim {claimant or '<session-id>'}` on it first.")
        elif claimant is not None and holder != claimant:
            errors.append(f"#{number} is claimed by `{holder}`, not by `{claimant}`.")
    return errors


def normalized(body: str | None) -> str:
    """PR body without CR (the web editor sends CRLF) and without HTML comments (template hints are not links)."""
    return HTML_COMMENT.sub("", (body or "").replace("\r\n", "\n").replace("\r", "\n"))


def linked_issues(body: str) -> list[int]:
    """Issue numbers linked with a closing keyword or `Refs`, in order, without duplicates."""
    return list(dict.fromkeys(int(n) for n in ISSUE_LINK.findall(normalized(body))))


# MARK: - GitHub REST

def api(path: str, method: str = "GET", payload: dict | None = None):
    """JSON from the GitHub REST API (`path` relative to the repository), or None on 404."""
    url = f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            text = response.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def all_comments(number: int) -> list[dict]:
    comments, page = [], 1
    while True:
        batch = api(f"issues/{number}/comments?per_page=100&page={page}") or []
        comments += batch
        if len(batch) < 100:
            return comments
        page += 1


def event() -> dict:
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as handle:
        return json.load(handle)


def check_pr() -> int:
    number = event()["pull_request"]["number"]
    # Current state, not the event's snapshot: an older run must not act on a body or labels that changed since.
    pull = api(f"pulls/{number}")
    body, author = pull.get("body") or "", pull["user"]["login"]
    labels = frozenset(label["name"] for label in pull.get("labels", []))
    skipped, errors = break_glass(body, author, labels)
    if skipped and not errors and author not in EXEMPT_AUTHORS:
        if DIRECT_PR_LABEL not in labels:
            api(f"issues/{pull['number']}/labels", "POST", {"labels": [DIRECT_PR_LABEL]})
        print(f"::notice title=Issue and claim::Direct PR (break-glass): {direct_pr_reason(body) or 'label set by a maintainer'}")
    if skipped:
        for error in errors:
            print(f"::error title=Issue and claim::{error}")
        return 1 if errors else 0
    numbers = linked_issues(body)
    issues = {n: issue for n in numbers if (issue := api(f"issues/{n}")) is not None}
    claims = {n: replay(all_comments(n)) for n in issues}
    errors = pr_errors(body, author, issues, claims, labels)
    for error in errors:
        print(f"::error title=Issue and claim::{error}")
    if not errors:
        linked = ", ".join(f"#{n} ({claims[n].holder})" for n in numbers) or "exempt author"
        print(f"Issue and claim OK: {linked}")
    return 1 if errors else 0


def sync_issue() -> int:
    """Replays the whole history (a comment may have been edited or deleted), then fixes the labels."""
    payload = event()
    issue, comment = payload["issue"], payload["comment"]
    if "pull_request" in issue:
        return 0
    number = issue["number"]
    state = replay(all_comments(number))
    labels = {label["name"] for label in issue.get("labels", [])}
    if issue.get("state") == "open":
        # Only `status: claimed` moves; `status: ready` is left as triage set it (picking work excludes claimed issues).
        if state.holder and CLAIMED_LABEL not in labels:
            api(f"issues/{number}/labels", "POST", {"labels": [CLAIMED_LABEL]})
        elif state.holder is None and CLAIMED_LABEL in labels:
            api(f"issues/{number}/labels/{urllib.parse.quote(CLAIMED_LABEL)}", "DELETE")
    command = parse_command(comment.get("body", "")) if payload.get("action") == "created" else None
    reply = None
    if command and command[0] == "claim":
        if issue.get("state") != "open":
            reply = "Claim refused: this issue is closed."
        elif command[1] is None or not SESSION_ID.match(command[1]):
            reply = "Claim refused: the session id must look like `cloud/c12-sonnet`, `mac/M1` or `human/<login>`."
        elif state.holder != command[1]:
            reply = f"Claim refused: this issue is claimed by `{state.holder}`. Ask it to `/release`, or the maintainer."
        elif "status: blocked" in labels:
            reply = "Claimed, but note: this issue is `status: blocked`. Check its dependencies before writing code."
    if reply:
        api(f"issues/{number}/comments", "POST", {"body": reply})
    rerun_pr_checks(number)
    print(f"#{number}: holder={state.holder}")
    return 0


def rerun_pr_checks(number: int) -> None:
    """Re-runs the latest `Issue and claim` run of every open PR linking #number, so its result follows the claim.

    The re-run executes the base-branch workflow again, and `check_pr` re-reads the PR, so it sees the current claim.
    A run still in progress is waited for (it may have read the claim before this change), then re-run. A failure on
    one PR is reported and does not stop the others; the fallback is a PR edit (AGENTS.md §8).
    """
    pulls, page = [], 1
    while True:
        batch = api(f"pulls?state=open&per_page=100&page={page}") or []
        pulls += batch
        if len(batch) < 100:
            break
        page += 1
    deadline = time.monotonic() + 300  # one shared ~5-minute budget for waiting on running checks
    for pull in pulls:
        if number not in linked_issues(pull.get("body") or ""):
            continue
        try:
            run = latest_check_run(pull)
            while run is not None and run.get("status") != "completed" and time.monotonic() < deadline:
                time.sleep(15)
                run = api(f"actions/runs/{run['id']}")
            if run is None:
                print(f"::warning::no Issue and claim run found for PR #{pull['number']}; edit the PR to re-run it")
                continue
            api(f"actions/runs/{run['id']}/rerun", "POST", {})
            print(f"re-ran Issue and claim on PR #{pull['number']}")
        except (urllib.error.URLError, KeyError, TypeError) as error:
            print(f"::warning::could not re-run Issue and claim on PR #{pull['number']} ({error}); edit the PR to re-run it")


def latest_check_run(pull: dict) -> dict | None:
    """Newest `pr-issue.yml` run for this PR: matched by the run's pull request number, else by the PR head commit."""
    for page in range(1, 6):  # newest first, up to 500 runs
        runs = (api(f"actions/workflows/pr-issue.yml/runs?event=pull_request_target&per_page=100&page={page}") or {})
        batch = runs.get("workflow_runs", [])
        for run in batch:
            numbers = {entry.get("number") for entry in run.get("pull_requests") or []}
            if pull["number"] in numbers or run.get("head_sha") == pull["head"]["sha"]:
                return run
        if len(batch) < 100:
            break
    return None

if __name__ == "__main__":
    commands = {"check-pr": check_pr, "sync-issue": sync_issue}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(f"usage: {sys.argv[0]} {{{'|'.join(commands)}}}")
    sys.exit(commands[sys.argv[1]]())
