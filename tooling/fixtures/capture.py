#!/usr/bin/env python3
"""Capture raw HFR pages listed in a manifest, politely, for later anonymization.

    capture.py --credentials creds.json --manifest manifest.json --out ~/agent-work/<task>/raw

Credentials file (JSON, never inside the repo):
    {"accounts": [{"pseudo": "...", "password": "..."}, {"pseudo": "...", "password": "..."}]}
Account `user1` is the first entry, `user2` the second.

Manifest (JSON): {"pages": [{"id": "topic-p1", "url": "/forum2.php?...", "account": "anon|user1|user2",
"method": "GET"}]} (a bare list of pages is accepted too). Only GET is supported.

Output (outside any git work tree): `<id>.html` (raw body) and `<id>.headers.txt` (status + headers,
Set-Cookie values removed). Raw captures must be deleted once anonymized and committed.
"""
import argparse
import http.cookiejar
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _ui  # noqa: E402

DEFAULT_BASE = "https://forum.hardware.fr"
MIN_DELAY = 3.0
USER_AGENT = "SwiftHFR-fixture-capture/1 (operator-run, 1 request per 3 s)"
ACCOUNTS = ("anon", "user1", "user2")
# HFR-PROTOCOL.md §5 (LoginService.swift:48-129)
LOGIN_PATH = "/login_validation.php?config=hfr.inc"
LOGIN_SUCCESS_MARKER = "login_redirection.php"


class CaptureError(Exception):
    """A condition that must stop the whole run (bad input, login failure, throttling by the server)."""


def inside_git_work_tree(path):
    """True when path (or its nearest existing ancestor) is inside any git work tree."""
    probe = os.path.realpath(path)
    while not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            break
        probe = parent
    try:
        r = subprocess.run(["git", "-C", probe, "rev-parse", "--is-inside-work-tree"],
                           capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return False
    return r.returncode == 0 and r.stdout.strip() == "true"


def load_credentials(path):
    """Return the list of {"pseudo", "password"} dicts; raises CaptureError on a bad file."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        accounts = data["accounts"]
        for a in accounts:
            if not a["pseudo"] or not a["password"]:
                raise ValueError
    except (OSError, ValueError, KeyError, TypeError):
        raise CaptureError("credentials file must be JSON: "
                           '{"accounts": [{"pseudo": "...", "password": "..."}]}') from None
    return accounts


def load_manifest(path):
    """Return the validated list of pages; raises CaptureError on a bad manifest."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise CaptureError("cannot read manifest: %s" % exc) from None
    pages = data["pages"] if isinstance(data, dict) and "pages" in data else data
    if not isinstance(pages, list) or not pages:
        raise CaptureError("manifest has no pages")
    seen = set()
    for p in pages:
        if not isinstance(p, dict) or not all(k in p for k in ("id", "url", "account")):
            raise CaptureError("each page needs id, url, account")
        if not all(c.isalnum() or c in "-_." for c in p["id"]) or p["id"].startswith("."):
            raise CaptureError("page id %r must be alphanumeric, '-', '_' or '.'" % p["id"])
        if p["id"] in seen:
            raise CaptureError("duplicate page id %r" % p["id"])
        seen.add(p["id"])
        if p["account"] not in ACCOUNTS:
            raise CaptureError("page %s: account must be one of %s" % (p["id"], "|".join(ACCOUNTS)))
        if p.get("method", "GET").upper() != "GET":
            raise CaptureError("page %s: only GET is supported" % p["id"])
        if not p["url"].startswith("/"):
            raise CaptureError("page %s: url must be a path starting with '/'" % p["id"])
    return pages


def format_headers(status, headers):
    """Render status and headers as text, replacing every Set-Cookie value."""
    lines = ["HTTP %s" % status]
    for name, value in headers:
        if name.lower() == "set-cookie":
            cookie_name = value.split("=", 1)[0].strip()
            value = "%s=REDACTED" % cookie_name
        lines.append("%s: %s" % (name, value))
    return "\n".join(lines) + "\n"


class Throttle:
    """Guarantees a minimum delay between two requests."""

    def __init__(self, delay, clock=time.monotonic, sleep=time.sleep):
        self.delay, self._clock, self._sleep = delay, clock, sleep
        self._last = None

    def wait(self):
        """Block until the delay since the previous request has elapsed."""
        if self._last is not None:
            remaining = self.delay - (self._clock() - self._last)
            if remaining > 0:
                with _ui.Spinner("waiting %.0fs (politeness delay)" % remaining):
                    self._sleep(remaining)
        self._last = self._clock()


class Session:
    """One cookie jar per account."""

    def __init__(self, base, throttle):
        self.base, self.throttle = base, throttle
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        self.opener.addheaders = [("User-Agent", USER_AGENT)]

    def request(self, path, data=None):
        """Perform one throttled request; returns (status, headers, body). Stops on 429/5xx."""
        self.throttle.wait()
        body = urllib.parse.urlencode(data, encoding="utf-8").encode("ascii") if data else None
        req = urllib.request.Request(self.base + path, data=body)
        try:
            with self.opener.open(req, timeout=30) as resp:
                return resp.status, resp.getheaders(), resp.read()
        except urllib.error.HTTPError as exc:
            with exc:
                if exc.code == 429 or exc.code >= 500:
                    raise CaptureError("server answered HTTP %d: stopping" % exc.code) from None
                return exc.code, list(exc.headers.items()), exc.read()
        except urllib.error.URLError as exc:
            raise CaptureError("network error: %s" % exc.reason) from None

    def login(self, account):
        """Log in; success means the body contains login_redirection.php (HFR-PROTOCOL §5)."""
        status, _h, body = self.request(LOGIN_PATH, {
            "pseudo": account["pseudo"], "password": account["password"],
            "action": "send", "login": "Se connecter"})
        text = body.decode("utf-8", "replace")
        if LOGIN_SUCCESS_MARKER not in text:
            raise CaptureError("login failed (HTTP %s, marker %s absent)" % (status, LOGIN_SUCCESS_MARKER))


def run(args):
    """Execute a capture run."""
    if args.delay < MIN_DELAY:
        raise CaptureError("--delay must be at least %.0f seconds" % MIN_DELAY)
    out = os.path.abspath(os.path.expanduser(args.out))
    if inside_git_work_tree(out):
        raise CaptureError("output directory is inside a git work tree; raw captures must stay outside")
    pages = load_manifest(args.manifest)
    if args.only:
        pages = [p for p in pages if p["id"] in args.only]
        if not pages:
            raise CaptureError("--only matched no page")
    needed = {p["account"] for p in pages}
    accounts = {}
    if needed - {"anon"}:
        creds = load_credentials(args.credentials) if args.credentials else None
        if creds is None:
            raise CaptureError("--credentials is required for pages that need an account")
        for label in sorted(needed - {"anon"}):
            idx = ACCOUNTS.index(label) - 1
            if idx >= len(creds):
                raise CaptureError("manifest uses %s but the credentials file has %d account(s)"
                                   % (label, len(creds)))
            accounts[label] = creds[idx]
    if args.dry_run:
        for p in pages:
            _ui.ok("would GET %s as %s -> %s.html" % (p["url"], p["account"], p["id"]))
        return 0
    os.makedirs(out, mode=0o700, exist_ok=True)
    os.chmod(out, 0o700)
    throttle = Throttle(args.delay)
    sessions = {}
    for p in pages:
        label = p["account"]
        if label not in sessions:
            sessions[label] = Session(args.base_url.rstrip("/"), throttle)
            if label != "anon":
                sessions[label].login(accounts[label])
                _ui.ok("logged in as %s" % label)
        status, headers, body = sessions[label].request(p["url"])
        with open(os.path.join(out, p["id"] + ".html"), "wb") as fh:
            fh.write(body)
        with open(os.path.join(out, p["id"] + ".headers.txt"), "w", encoding="utf-8") as fh:
            fh.write(format_headers(status, headers))
        _ui.ok("%s: HTTP %s, %d bytes" % (p["id"], status, len(body)))
    _ui.warn("raw captures in %s: anonymize them, commit only the output, then delete this directory" % out)
    return 0


def main(argv=None):
    """Entry point."""
    ap = argparse.ArgumentParser(description="Politely capture raw HFR pages listed in a manifest.")
    ap.add_argument("--credentials", help="JSON file with the accounts (outside the repo)")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True, help="output directory, outside any git work tree")
    ap.add_argument("--delay", type=float, default=MIN_DELAY, help="seconds between requests (min 3)")
    ap.add_argument("--base-url", default=DEFAULT_BASE)
    ap.add_argument("--only", nargs="*", help="capture only these page ids")
    ap.add_argument("--dry-run", action="store_true", help="validate inputs and list the plan, no network")
    try:
        return run(ap.parse_args(argv))
    except CaptureError as exc:
        _ui.ko(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
