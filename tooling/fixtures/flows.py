#!/usr/bin/env python3
"""Capture HFR pages and write flows one step at a time, for the LOT-001 capture checklist.

    flows.py --work DIR [--credentials creds.json] login --account user1 --id W01
    flows.py --work DIR get   --account anon  --id R01 --url /
    flows.py --work DIR post  --account user1 --id R52 --url /transsearch.php --field word=x ... --no-redirect
    flows.py --work DIR form  --account user1 --id W10 --form-url /message.php?... --set sujet=...
    flows.py --work DIR peek  R01 --forms --links 'addflag'

Each invocation performs a few requests and stops; state lives in DIR (outside any git work tree):
`cookies/<account>.txt` (persistent jars, 0600), `captures-raw/<id>.*` (raw body, headers, meta,
request body), `state.json` (time of the last request and request count, shared by every run so the
politeness delay and the request budget hold across invocations).

Write flows follow docs/HFR-PROTOCOL.md §3.1: GET the form page, copy its fields (checkbox
semantics `legacy` = "1"/"0" like ReplyService.swift:311-338, or `browser` = unchecked fields not
sent), override, POST to the form action resolved against the form URL. Field order is the DOM
order. Saved request bodies have `hash_check` and `password` replaced by REDACTED; saved headers
keep cookie names and attributes but never values. Output is passed through the anonymizer before
it is printed, so real pseudos and tokens never reach the terminal.
"""
import argparse
import html.parser
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _ui  # noqa: E402
import anonymize as A  # noqa: E402
import capture as C  # noqa: E402

DEFAULT_BUDGET = 120
REFUSED_LOGIN_WORD = "refused-login-sample"
SECRET_FIELDS = {"hash_check", "password"}
FORM_CONTENT_TYPE = "application/x-www-form-urlencoded; charset=utf-8"
# Pages HFR shows instead of content when it throttles or blocks a client: stop at once.
# The composer's JS always mentions `document.hop.codecaptcha`; only a rendered field counts.
STOP_MARKERS = re.compile(r"name=[\"']codecaptcha|g-recaptcha|cf-challenge|vous avez été banni|"
                          r"compte (?:a été )?bloqué|trop de tentatives|access denied", re.I)


# -- persistent state ------------------------------------------------------------------------------
class State:
    """Request count and last-request time shared by every invocation on one work directory."""

    def __init__(self, path, delay, budget, clock=time.time, sleep=time.sleep):
        self.path, self.delay, self.budget = path, delay, budget
        self._clock, self._sleep = clock, sleep
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            data = {}
        self.count = int(data.get("count", 0))
        self.last = data.get("last")

    def _save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump({"count": self.count, "last": self.last}, fh)
        os.replace(tmp, self.path)

    def before_request(self):
        """Enforce the budget and the politeness delay, then count the request."""
        if self.count >= self.budget:
            raise C.CaptureError("request budget of %d reached: stopping" % self.budget)
        if self.last is not None:
            remaining = self.delay - (self._clock() - self.last)
            if remaining > 0:
                with _ui.Spinner("waiting %.0fs (politeness delay)" % remaining):
                    self._sleep(remaining)
        self.last = self._clock()
        self.count += 1
        self._save()


class _Recorder(urllib.request.HTTPRedirectHandler):
    """Records every redirect hop; refuses to follow when follow is False."""

    def __init__(self):
        self.chain, self.follow = [], True

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.chain.append({"status": code, "location": headers.get("Location", "")})
        if not self.follow:
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class Client:
    """One account: a cookie jar persisted in the work directory (none for `anon`)."""

    def __init__(self, base, state, jar_path=None):
        self.base, self.state, self.jar_path = base.rstrip("/"), state, jar_path
        self.jar = http.cookiejar.MozillaCookieJar(jar_path) if jar_path else http.cookiejar.CookieJar()
        if jar_path and os.path.exists(jar_path):
            self.jar.load(ignore_discard=True, ignore_expires=True)
        self.recorder = _Recorder()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar), self.recorder)
        self.opener.addheaders = [("User-Agent", C.USER_AGENT)]

    def save_jar(self):
        """Persist the jar (session cookies included), readable by the owner only."""
        if not self.jar_path:
            return
        fd = os.open(self.jar_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.close(fd)
        self.jar.save(ignore_discard=True, ignore_expires=True)
        os.chmod(self.jar_path, 0o600)

    def set_temp_cookie(self, name, value):
        """Add a cookie for the forum domain (multi-quote, HFR-PROTOCOL §4); see drop_cookie."""
        host = urllib.parse.urlsplit(self.base).hostname or ""
        if re.fullmatch(r"[\d.]+", host) or host.count(".") < 2:
            domain = host
        else:
            domain = "." + host.split(".", 1)[1]
        self.jar.set_cookie(http.cookiejar.Cookie(
            0, name, value, None, False, domain, True, domain.startswith("."), "/", True,
            False, None, False, None, None, {}))
        return domain

    def drop_cookie(self, name, domain):
        """Remove a cookie added by set_temp_cookie."""
        try:
            self.jar.clear(domain, "/", name)
        except KeyError:
            pass

    def request(self, path_or_url, fields=None, follow=True):
        """One throttled request; fields (list of pairs) make it a POST. Returns a Response."""
        self.state.before_request()
        url = urllib.parse.urljoin(self.base + "/", path_or_url)
        body = None
        headers = {}
        if fields is not None:
            body = urllib.parse.urlencode(fields, encoding="utf-8").encode("ascii")
            headers["Content-Type"] = FORM_CONTENT_TYPE
        req = urllib.request.Request(url, data=body, headers=headers)
        self.recorder.chain, self.recorder.follow = [], follow
        try:
            with self.opener.open(req, timeout=30) as resp:
                res = Response(url, resp.geturl(), resp.status, resp.getheaders(), resp.read(),
                               list(self.recorder.chain), fields)
        except urllib.error.HTTPError as exc:
            with exc:
                if exc.code == 429 or exc.code >= 500:
                    raise C.CaptureError("server answered HTTP %d: stopping" % exc.code) from None
                res = Response(url, exc.geturl() or url, exc.code, list(exc.headers.items()),
                               exc.read(), list(self.recorder.chain), fields)
        except urllib.error.URLError as exc:
            raise C.CaptureError("network error: %s" % exc.reason) from None
        self.save_jar()
        return res


class Response:
    """A captured exchange."""

    def __init__(self, url, final_url, status, headers, body, chain, fields):
        self.url, self.final_url, self.status = url, final_url, status
        self.headers, self.body, self.chain, self.fields = headers, body, chain, fields

    def header(self, name):
        """First value of a header, or None."""
        for k, v in self.headers:
            if k.lower() == name.lower():
                return v
        return None

    def text(self):
        """Body decoded as UTF-8 (lenient)."""
        return self.body.decode("utf-8", "replace")


# -- forms -----------------------------------------------------------------------------------------
class _FormParser(html.parser.HTMLParser):
    """Collects forms and their fields in document order (attribute entities are decoded)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.forms, self._form, self._textarea, self._select, self._option = [], None, None, None, None

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v if v is not None else "") for k, v in attrs}
        if tag == "form":
            self._form = {"attrs": a, "fields": []}
            self.forms.append(self._form)
        elif self._form is None:
            return
        elif tag == "input":
            self._form["fields"].append({"tag": "input", "name": a.get("name"), "type": a.get("type", "text").lower(),
                                         "value": a.get("value"), "checked": "checked" in a})
        elif tag == "textarea":
            self._textarea = {"tag": "textarea", "name": a.get("name"), "type": "textarea", "value": ""}
            self._form["fields"].append(self._textarea)
        elif tag == "select":
            self._select = {"tag": "select", "name": a.get("name"), "type": "select", "options": []}
            self._form["fields"].append(self._select)
        elif tag == "option" and self._select is not None:
            self._option = {"value": a.get("value"), "selected": "selected" in a, "text": ""}
            self._select["options"].append(self._option)

    def handle_endtag(self, tag):
        if tag == "form":
            self._form = None
        elif tag == "textarea":
            self._textarea = None
        elif tag == "select":
            self._select, self._option = None, None
        elif tag == "option":
            self._option = None

    def handle_data(self, data):
        if self._textarea is not None:
            self._textarea["value"] += data
        elif self._option is not None:
            self._option["text"] += data


def parse_forms(text):
    """Return [{"attrs": {...}, "fields": [...]}] for every form in the page."""
    p = _FormParser()
    p.feed(text)
    p.close()
    return p.forms


def pick_form(forms, name=None, index=None, action_contains=None):
    """Select one form by name, index or action substring; raises CaptureError when none matches."""
    if index is not None:
        if index < len(forms):
            return forms[index]
    else:
        for f in forms:
            if name is not None and f["attrs"].get("name") != name:
                continue
            if action_contains is not None and action_contains not in f["attrs"].get("action", ""):
                continue
            return f
    raise C.CaptureError("no matching form on the page (%d forms)" % len(forms))


def form_fields(form, mode="legacy"):
    """Fields to submit, as an ordered list of pairs.

    legacy: checkbox -> "1"/"0", every named input sent (ReplyService.swift:311-338).
    browser: unchecked checkbox/radio not sent, checked checkbox sends its value ("on" by default),
    only the first named submit button is sent (the one a user would click).
    """
    if mode not in ("legacy", "browser"):
        raise ValueError("mode must be legacy or browser")
    out, submit_seen = [], False
    for f in form["fields"]:
        name = f["name"]
        if not name:
            continue
        typ = f["type"]
        if f["tag"] == "select":
            opts = f["options"]
            chosen = next((o for o in opts if o["selected"]), opts[0] if opts else None)
            if chosen is not None:
                out.append((name, chosen["value"] if chosen["value"] is not None else chosen["text"].strip()))
            continue
        if typ == "checkbox":
            if mode == "legacy":
                out.append((name, "1" if f["checked"] else "0"))
            elif f["checked"]:
                out.append((name, f["value"] if f["value"] is not None else "on"))
            continue
        if typ == "radio":
            if f["checked"]:
                out.append((name, f["value"] or ""))
            continue
        if typ in ("submit", "button", "image", "reset") and mode == "browser":
            if typ == "submit" and not submit_seen:
                submit_seen = True
                out.append((name, f["value"] or ""))
            continue
        out.append((name, f["value"] or ""))
    return out


def apply_overrides(fields, sets=(), drops=()):
    """Replace (first occurrence, others removed) or append fields; drop names."""
    fields = [(k, v) for k, v in fields if k not in set(drops)]
    for k, v in sets:
        idx = [i for i, (n, _v) in enumerate(fields) if n == k]
        if idx:
            fields[idx[0]] = (k, v)
            fields = [f for i, f in enumerate(fields) if i not in idx[1:]]
        else:
            fields.append((k, v))
    return fields


def redact_fields(fields):
    """Copy of fields with secret values replaced."""
    return [(k, A.REDACTED if k in SECRET_FIELDS and v else v) for k, v in fields]


def first_hash_check(text):
    """Value of the first hash_check hidden input in a page, or None."""
    for f in parse_forms(text):
        for fld in f["fields"]:
            if fld["name"] == "hash_check" and fld.get("value"):
                return fld["value"]
    m = re.search(r"name=[\"']hash_check[\"'][^>]*value=[\"']([^\"']+)", text)
    return m.group(1) if m else None


# -- recording -------------------------------------------------------------------------------------
def format_headers(status, headers):
    """Status and headers; Set-Cookie keeps the name and attributes, never the value."""
    lines = ["HTTP %s" % status]
    for name, value in headers:
        if name.lower() == "set-cookie":
            first, _sep, attrs = value.partition(";")
            cookie_name, _eq, cookie_value = first.partition("=")
            shown = "deleted" if cookie_value.strip() == "deleted" else (
                "" if not cookie_value.strip() else A.REDACTED)
            value = "%s=%s%s" % (cookie_name.strip(), shown, (";" + attrs) if attrs else "")
        lines.append("%s: %s" % (name, value))
    return "\n".join(lines) + "\n"


def record(raw_dir, cid, res, account, method, template=None, note=None):
    """Write <id>.html, .headers.txt, .meta.json and (for POST) .request.txt in raw_dir."""
    os.makedirs(raw_dir, mode=0o700, exist_ok=True)
    base = os.path.join(raw_dir, cid)
    with open(base + ".html", "wb") as fh:
        fh.write(res.body)
    with open(base + ".headers.txt", "w", encoding="utf-8") as fh:
        fh.write(format_headers(res.status, res.headers))
    meta = {"id": cid, "account": account, "method": method,
            "url_template": template or urllib.parse.urlsplit(res.url)._replace(scheme="", netloc="").geturl(),
            "url": res.url, "final_url": res.final_url, "status": res.status,
            "content_type": res.header("Content-Type"), "date": res.header("Date"),
            "redirects": res.chain,
            "set_cookie_names": [v.split("=", 1)[0].strip() for k, v in res.headers if k.lower() == "set-cookie"]}
    if note:
        meta["note"] = note
    if res.fields is not None:
        red = redact_fields(res.fields)
        meta["request_fields"] = [k for k, _v in red]
        with open(base + ".request.txt", "w", encoding="utf-8", newline="") as fh:
            fh.write("POST %s\nContent-Type: %s\n\n" % (res.url, FORM_CONTENT_TYPE))
            fh.write(urllib.parse.urlencode(red, encoding="utf-8") + "\n\n")
            for k, v in red:
                fh.write("%s=%s\n" % (k, json.dumps(v, ensure_ascii=False)))
    with open(base + ".meta.json", "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    return meta


# -- CLI -------------------------------------------------------------------------------------------
class Ctx:
    """Shared objects for one invocation."""

    def __init__(self, args):
        self.args = args
        self.work = os.path.abspath(os.path.expanduser(args.work))
        if C.inside_git_work_tree(self.work):
            raise C.CaptureError("work directory is inside a git work tree; raw captures must stay outside")
        os.makedirs(self.work, mode=0o700, exist_ok=True)
        self.raw = os.path.join(self.work, "captures-raw")
        self.cookies = os.path.join(self.work, "cookies")
        for d in (self.raw, self.cookies):
            os.makedirs(d, mode=0o700, exist_ok=True)
            os.chmod(d, 0o700)
        if args.delay < C.MIN_DELAY:
            raise C.CaptureError("--delay must be at least %.0f seconds" % C.MIN_DELAY)
        self.state = State(os.path.join(self.work, "state.json"), args.delay, args.budget)
        cfg = args.anon_config
        self.anon = A.Anonymizer(A.Config.load(cfg) if cfg else A.Config())

    def safe(self, s):
        """Text safe to print: anonymized (pseudos, tokens, ids)."""
        self.anon._reset()  # loads the operator pseudos; redact_text alone knows none
        return self.anon.redact_text(str(s))

    def client(self, account):
        """Client for an account label."""
        if account not in C.ACCOUNTS:
            raise C.CaptureError("account must be one of %s" % "|".join(C.ACCOUNTS))
        jar = None if account == "anon" else os.path.join(self.cookies, account + ".txt")
        return Client(self.args.base_url, self.state, jar)

    def check_id(self, cid):
        """Refuse an id that is not a safe file name, or one already captured (unless --overwrite)."""
        if not cid or not all(c.isalnum() or c in "-_." for c in cid) or cid.startswith("."):
            raise C.CaptureError("id %r must be alphanumeric, '-', '_' or '.'" % cid)
        if os.path.exists(os.path.join(self.raw, cid + ".html")) and not self.args.overwrite:
            raise C.CaptureError("%s already captured (use --overwrite)" % cid)

    def done(self, cid, res, account, method, template=None, note=None):
        """Record a capture, print its anonymized summary, stop on a block or captcha page."""
        meta = record(self.raw, cid, res, account, method, template, note)
        text = res.text()
        chain = " ".join("%s->%s" % (h["status"], self.safe(h["location"])) for h in res.chain)
        _ui.ok("%s: HTTP %s, %d bytes%s, final %s [requests %d/%d]" % (
            cid, res.status, len(res.body), (" via " + chain) if chain else "",
            self.safe(res.final_url), self.state.count, self.state.budget))
        if STOP_MARKERS.search(text):
            raise C.CaptureError("%s: page looks like a block/captcha page: stopping" % cid)
        return meta


def _pairs(items):
    out = []
    for it in items or ():
        if "=" not in it:
            raise C.CaptureError("expected name=value, got %r" % it)
        k, v = it.split("=", 1)
        out.append((k, v))
    return out


def _json_pairs(items):
    out = []
    for k, v in _pairs(items):
        try:
            val = json.loads(v)
        except ValueError:
            raise C.CaptureError("--set-json %s: value must be a JSON string" % k) from None
        if not isinstance(val, str):
            raise C.CaptureError("--set-json %s: value must be a JSON string" % k)
        out.append((k, val))
    return out


def _account_creds(args, label):
    creds = C.load_credentials(args.credentials) if args.credentials else None
    if creds is None:
        raise C.CaptureError("--credentials is required to log in")
    idx = C.ACCOUNTS.index(label) - 1
    if idx < 0 or idx >= len(creds):
        raise C.CaptureError("no credentials for %s" % label)
    return creds[idx]


def cmd_login(ctx, a):
    """POST the login form; the jar is kept only when the login succeeds (staging jar)."""
    ctx.check_id(a.id)
    acct = _account_creds(ctx.args, a.account)
    staging = Client(ctx.args.base_url, ctx.state, None)
    fields = [("pseudo", acct["pseudo"]),
              ("password", REFUSED_LOGIN_WORD if a.wrong_password else acct["password"]),
              ("action", "send"), ("login", "Se connecter")]
    res = staging.request(C.LOGIN_PATH, fields, follow=not a.no_redirect)
    ctx.done(a.id, res, a.account, "POST", template=C.LOGIN_PATH,
             note="wrong password on purpose" if a.wrong_password else None)
    ok = C.LOGIN_SUCCESS_MARKER in res.text()
    names = sorted({c.name for c in staging.jar})
    _ui.ok("login marker %s; cookies set: %s" % ("present" if ok else "absent", ", ".join(names) or "none"))
    if ok and not a.wrong_password:
        target = ctx.client(a.account)
        for c in staging.jar:
            target.jar.set_cookie(c)
        target.save_jar()
        _ui.ok("jar saved for %s" % a.account)
    elif not a.wrong_password:
        raise C.CaptureError("login failed for %s" % a.account)
    return 0


def cmd_get(ctx, a):
    """GET one URL with the account's jar."""
    ctx.check_id(a.id)
    cl = ctx.client(a.account)
    temp = []
    for k, v in _pairs(a.cookie):
        temp.append((k, cl.set_temp_cookie(k, v)))
    try:
        res = cl.request(a.url, follow=not a.no_redirect)
    finally:
        for k, dom in temp:
            cl.drop_cookie(k, dom)
        cl.save_jar()
    note = a.note
    if temp:
        note = ((note + "; ") if note else "") + "extra cookies: " + ", ".join(k for k, _d in temp)
    ctx.done(a.id, res, a.account, "GET", a.template, note)
    return 0


def _resolve_hash(ctx, fields, hash_from):
    if not any(v == "@HASH" for _k, v in fields):
        return fields
    if not hash_from:
        raise C.CaptureError("@HASH used without --hash-from")
    with open(os.path.join(ctx.raw, hash_from + ".html"), "rb") as fh:
        h = first_hash_check(fh.read().decode("utf-8", "replace"))
    if not h:
        raise C.CaptureError("no hash_check in %s" % hash_from)
    return [(k, h if v == "@HASH" else v) for k, v in fields]


def cmd_post(ctx, a):
    """POST explicit fields (order kept); '@HASH' takes hash_check from a captured page."""
    ctx.check_id(a.id)
    fields = _resolve_hash(ctx, _pairs(a.field) + _json_pairs(a.field_json), a.hash_from)
    res = ctx.client(a.account).request(a.url, fields, follow=not a.no_redirect)
    ctx.done(a.id, res, a.account, "POST", a.template, a.note)
    return 0


def cmd_form(ctx, a):
    """GET a form page (or reuse a captured one), copy its fields, override, POST to its action."""
    ctx.check_id(a.id)
    cl = ctx.client(a.account)
    if a.form_from:
        with open(os.path.join(ctx.raw, a.form_from + ".html"), "rb") as fh:
            page = fh.read().decode("utf-8", "replace")
        with open(os.path.join(ctx.raw, a.form_from + ".meta.json"), encoding="utf-8") as fh:
            page_url = json.load(fh)["final_url"]
    else:
        if not a.form_url:
            raise C.CaptureError("--form-url or --form-from is required")
        ctx.check_id(a.id + ".form")
        res = cl.request(a.form_url)
        ctx.done(a.id + ".form", res, a.account, "GET", a.form_template)
        page, page_url = res.text(), res.final_url
    form = pick_form(parse_forms(page), a.form_name, a.form_index, a.form_action)
    action = form["attrs"].get("action") or "/bddpost.php?config=hfr.inc"
    target = urllib.parse.urljoin(page_url, action)
    fields = apply_overrides(form_fields(form, a.mode), _pairs(a.set) + _json_pairs(a.set_json), a.drop or ())
    if a.dry_run:
        for k, v in redact_fields(fields):
            print("%s=%s" % (k, ctx.safe(json.dumps(v, ensure_ascii=False))[:120]))
        _ui.ok("would POST %d fields to %s" % (len(fields), ctx.safe(target)))
        return 0
    poster = ctx.client(a.post_account) if a.post_account else cl
    res = poster.request(target, fields, follow=not a.no_redirect)
    ctx.done(a.id, res, a.post_account or a.account, "POST", a.template, a.note)
    return 0


def _visible(text):
    t = re.sub(r"(?is)<(script|style)\b.*?</\1>", " ", text)
    t = re.sub(r"(?s)<[^>]+>", " ", t)
    return re.sub(r"\s+", " ", A.html.unescape(t)).strip()


def cmd_peek(ctx, a):
    """Print an anonymized summary of a raw capture (never the raw bytes)."""
    with open(os.path.join(ctx.raw, a.id + ".html"), "rb") as fh:
        raw = fh.read().decode("utf-8", "replace")
    text = ctx.anon.anonymize(raw, private=a.private)
    title = re.search(r"(?is)<title>(.*?)</title>", text)
    print("title:", _visible(title.group(1)) if title else None, "| bytes:", len(raw))
    for m in re.finditer(r"(?is)<meta[^>]+refresh[^>]*>", text):
        print("refresh:", m.group(0)[:300])
    for m in re.finditer(r"(?is)<div[^>]*class=[\"']hop[\"'][^>]*>(.*?)</div>", text):
        print("hop:", _visible(m.group(1))[:300])
    if a.forms:
        for i, f in enumerate(parse_forms(text)):
            print("form[%d] %s" % (i, {k: v for k, v in f["attrs"].items() if k in ("name", "action", "method", "id")}))
            for fld in f["fields"]:
                val = fld.get("value")
                if fld["tag"] == "select":
                    sel = [o for o in fld["options"] if o["selected"]]
                    val = "select(%d opts, selected=%s)" % (len(fld["options"]), sel[0]["value"] if sel else None)
                elif fld["type"] in ("hidden", "password") and fld["name"] not in ("cat", "post", "subcat", "config", "page", "p", "numreponse", "verifrequet", "sondage", "owntopic", "new", "numrep", "ref", "cache", "wysiwyg", "sond"):
                    val = (val[:3] + "..(%d)" % len(val)) if val and val != A.REDACTED else val
                print("   %s %s=%r%s" % (fld["type"], fld["name"], (val or "")[:160] if isinstance(val, str) else val,
                                       " checked" if fld.get("checked") else ""))
    if a.links:
        seen = set()
        for m in re.finditer(r"(?is)href=[\"']([^\"']+)[\"']", text):
            if re.search(a.links, m.group(1)) and m.group(1) not in seen:
                seen.add(m.group(1))
                print("link:", m.group(1)[:200])
                if len(seen) >= a.max:
                    break
    if a.grep:
        n = 0
        for m in re.finditer(a.grep, text):
            s = max(0, m.start() - a.context)
            print("grep:", text[s:m.end() + a.context].replace("\n", "\\n")[:600])
            n += 1
            if n >= a.max:
                break
    if a.text:
        print("text:", _visible(text)[:a.text])
    return 0


def cmd_budget(ctx, _a):
    """Print the request count."""
    _ui.ok("requests %d/%d" % (ctx.state.count, ctx.state.budget))
    return 0


def build_parser():
    """Argument parser."""
    ap = argparse.ArgumentParser(description="Capture HFR pages and write flows one step at a time.")
    ap.add_argument("--work", required=True, help="work directory, outside any git work tree")
    ap.add_argument("--credentials")
    ap.add_argument("--anon-config", help="anonymizer config used to mask printed output")
    ap.add_argument("--base-url", default=C.DEFAULT_BASE)
    ap.add_argument("--delay", type=float, default=C.MIN_DELAY)
    ap.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    ap.add_argument("--overwrite", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("login")
    p.add_argument("--account", required=True, choices=["user1", "user2"])
    p.add_argument("--id", required=True)
    p.add_argument("--wrong-password", action="store_true")
    p.add_argument("--no-redirect", action="store_true")
    p.set_defaults(func=cmd_login)

    p = sub.add_parser("get")
    p.add_argument("--account", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--template")
    p.add_argument("--note")
    p.add_argument("--cookie", action="append", help="extra cookie name=value for this request only")
    p.add_argument("--no-redirect", action="store_true")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("post")
    p.add_argument("--account", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--template")
    p.add_argument("--note")
    p.add_argument("--field", action="append", help="name=value, in order; value @HASH = hash_check")
    p.add_argument("--field-json", action="append", help="name=<JSON string>")
    p.add_argument("--hash-from", help="captured id whose hash_check replaces @HASH")
    p.add_argument("--no-redirect", action="store_true")
    p.set_defaults(func=cmd_post)

    p = sub.add_parser("form")
    p.add_argument("--account", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--form-url")
    p.add_argument("--form-from", help="reuse this captured page as the form page")
    p.add_argument("--form-template")
    p.add_argument("--form-name", default="hop")
    p.add_argument("--form-index", type=int)
    p.add_argument("--form-action")
    p.add_argument("--mode", default="legacy", choices=["legacy", "browser"])
    p.add_argument("--set", action="append")
    p.add_argument("--set-json", action="append", help="name=<JSON string> (controls \\r\\n exactly)")
    p.add_argument("--drop", action="append")
    p.add_argument("--post-account", help="send the POST with another account's jar (anon = logged out)")
    p.add_argument("--template")
    p.add_argument("--note")
    p.add_argument("--no-redirect", action="store_true")
    p.add_argument("--dry-run", action="store_true", help="print the fields (masked) without posting")
    p.set_defaults(func=cmd_form)

    p = sub.add_parser("peek")
    p.add_argument("id")
    p.add_argument("--private", action="store_true")
    p.add_argument("--forms", action="store_true")
    p.add_argument("--links")
    p.add_argument("--grep")
    p.add_argument("--context", type=int, default=80)
    p.add_argument("--max", type=int, default=30)
    p.add_argument("--text", type=int, default=0)
    p.set_defaults(func=cmd_peek)

    p = sub.add_parser("budget")
    p.set_defaults(func=cmd_budget)
    return ap


def main(argv=None):
    """Entry point."""
    args = build_parser().parse_args(argv)
    try:
        return args.func(Ctx(args), args)
    except C.CaptureError as exc:
        _ui.ko(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
