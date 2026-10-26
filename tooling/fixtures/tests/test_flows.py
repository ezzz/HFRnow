"""Tests for flows.py. No request ever leaves the machine: only a loopback server is used."""
import contextlib
import http.server
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import capture as C  # noqa: E402
import flows as F  # noqa: E402

JAR_SAMPLE = "jar-sample-two"
FORM_SAMPLE = "form-sample-value"
FORM_PAGE = """<html><body>
<form name="search" action="/search.php"><input name="q" value="x"></form>
<form name="hop" action="bddpost.php?config=hfr.inc" method="post">
<input type="hidden" name="hash_check" value="%s">
<input type="hidden" name="verifrequet" value="1100">
<input type="text" name="sujet" value="a &amp; b">
<input type="checkbox" name="signature" value="1" checked>
<input type="checkbox" name="emaill" value="1">
<input type="radio" name="MsgIcon" value="1">
<input type="radio" name="MsgIcon" value="2" checked>
<select name="subcat"><option value="0">none</option><option value="7" selected>seven</option></select>
<textarea name="content_form">old</textarea>
<input type="submit" name="submit" value="Valider">
<input type="submit" name="preview" value="Aper&ccedil;u">
</form></body></html>""" % FORM_SAMPLE


class Handler(http.server.BaseHTTPRequestHandler):
    posts = []

    def log_message(self, *a):
        pass

    def _send(self, code, body, headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path.startswith("/form"):
            self._send(200, FORM_PAGE)
        elif self.path.startswith("/redir"):
            self._send(301, "", [("Location", "/target_2.htm")])
        elif self.path == "/limited":
            self._send(503, "busy")
        elif self.path == "/captcha":
            self._send(200, "<form><input name=\"codecaptcha\"></form>")
        elif self.path == "/composer":
            self._send(200, "<script>if (document.hop.codecaptcha) {}</script>")
        else:
            self._send(200, "page %s cookie=%s" % (self.path, self.headers.get("Cookie", "")))

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n).decode()
        Handler.posts.append((self.path, self.headers.get("Content-Type"), body, self.headers.get("Cookie", "")))
        if self.path.startswith("/login_validation.php"):
            ok = "password=goodpw" in body
            hdr = [("Set-Cookie", "md_user=%s; expires=Wed, 01 Jan 2031 00:00:00 GMT; path=/" % JAR_SAMPLE)] if ok else []
            self._send(200, "<a href='login_redirection.php'>go</a>" if ok else "mot de passe invalide", hdr)
        else:
            self._send(200, "<meta http-equiv=\"refresh\" content=\"0; url=/x.htm#t1\">ok")


def git_repo(test):
    """A fresh git work tree in a temporary folder (tests must not depend on where they run)."""
    if not shutil.which("git"):
        test.skipTest("git not installed")
    d = tempfile.TemporaryDirectory()
    test.addCleanup(d.cleanup)
    subprocess.run(["git", "init", "-q", d.name], check=True)
    return d.name


class FlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        Handler.posts = []
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = os.path.join(self.tmp.name, "work")
        self.creds = os.path.join(self.tmp.name, "c.json")
        with open(self.creds, "w") as fh:
            json.dump({"accounts": [{"pseudo": "fakeuser", "password": "goodpw"},
                                    {"pseudo": "other", "password": "goodpw"}]}, fh)
        # Skip the real politeness wait; State's delay rule is tested on its own.
        orig = F.State.__init__
        F.State.__init__ = lambda s, path, delay, budget, **kw: orig(s, path, 0, budget, sleep=lambda x: None)
        self.addCleanup(setattr, F.State, "__init__", orig)

    def run_cli(self, *argv, budget=None):
        out, err = io.StringIO(), io.StringIO()
        base = ["--work", self.work, "--credentials", self.creds, "--base-url", self.base]
        if budget:
            base += ["--budget", str(budget)]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = F.main(base + list(argv))
        for secret in (JAR_SAMPLE, "goodpw", FORM_SAMPLE):
            self.assertNotIn(secret, out.getvalue() + err.getvalue())
        return rc, out.getvalue() + err.getvalue()

    def raw(self, name):
        with open(os.path.join(self.work, "captures-raw", name), encoding="utf-8") as fh:
            return fh.read()

    def test_login_keeps_jar_only_on_success(self):
        rc, _o = self.run_cli("login", "--account", "user1", "--id", "W02", "--wrong-password")
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(os.path.join(self.work, "cookies", "user1.txt")))
        self.assertIn("password=REDACTED", self.raw("W02.request.txt"))
        rc, _o = self.run_cli("login", "--account", "user1", "--id", "W01")
        self.assertEqual(rc, 0)
        jar = os.path.join(self.work, "cookies", "user1.txt")
        self.assertEqual(os.stat(jar).st_mode & 0o777, 0o600)
        headers = self.raw("W01.headers.txt")
        self.assertNotIn(JAR_SAMPLE, headers)
        self.assertIn("md_user=REDACTED; expires=Wed, 01 Jan 2031 00:00:00 GMT; path=/", headers)
        self.assertEqual(json.loads(self.raw("W01.meta.json"))["set_cookie_names"], ["md_user"])
        # The persisted jar is sent on the next run.
        self.run_cli("get", "--account", "user1", "--id", "R1", "--url", "/p")
        self.assertIn("md_user=" + JAR_SAMPLE, self.raw("R1.html"))

    def test_form_flow_legacy_mode_dom_order_and_redaction(self):
        rc, _o = self.run_cli("form", "--account", "anon", "--id", "W10", "--form-url", "/form/a",
                              "--set", "sujet=fixture-test-1", "--set-json", 'content_form="l1\\r\\nl2"')
        self.assertEqual(rc, 0)
        path, ctype, body, _c = Handler.posts[-1]
        self.assertEqual(path, "/form/bddpost.php?config=hfr.inc")  # resolved against the form URL
        self.assertEqual(ctype, F.FORM_CONTENT_TYPE)
        fields = urllib.parse.parse_qsl(body, keep_blank_values=True)
        self.assertEqual([k for k, _v in fields], ["hash_check", "verifrequet", "sujet", "signature", "emaill",
                                                   "MsgIcon", "subcat", "content_form", "submit", "preview"])
        d = dict(fields)
        self.assertEqual((d["signature"], d["emaill"], d["MsgIcon"], d["subcat"]), ("1", "0", "2", "7"))
        self.assertEqual(d["content_form"], "l1\r\nl2")
        self.assertEqual(d["hash_check"], FORM_SAMPLE)
        req = self.raw("W10.request.txt")
        self.assertNotIn(FORM_SAMPLE, req)
        self.assertIn("hash_check=REDACTED", req)
        self.assertIn("content_form=l1%0D%0Al2", req)
        self.assertTrue(os.path.exists(os.path.join(self.work, "captures-raw", "W10.form.html")))

    def test_form_browser_mode_and_reuse_of_captured_form(self):
        self.run_cli("get", "--account", "anon", "--id", "R45", "--url", "/form/b")
        n = len(Handler.posts)
        rc, _o = self.run_cli("form", "--account", "anon", "--id", "W13b", "--form-from", "R45",
                              "--mode", "browser", "--drop", "verifrequet")
        self.assertEqual(rc, 0)
        self.assertEqual(len(Handler.posts), n + 1)
        fields = urllib.parse.parse_qsl(Handler.posts[-1][2], keep_blank_values=True)
        names = [k for k, _v in fields]
        self.assertNotIn("emaill", names)
        self.assertNotIn("preview", names)
        self.assertNotIn("verifrequet", names)
        self.assertEqual(dict(fields)["signature"], "1")
        self.assertEqual(dict(fields)["sujet"], "a & b")  # entities decoded

    def test_printed_urls_are_anonymized(self):
        cfg = os.path.join(self.tmp.name, "anon.json")
        with open(cfg, "w") as fh:
            json.dump({"pseudos": ["RealPseudoX"]}, fh)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            F.main(["--work", self.work, "--anon-config", cfg, "--base-url", self.base,
                    "get", "--account", "anon", "--id", "U", "--url", "/m?dest=RealPseudoX"])
        self.assertNotIn("RealPseudoX", out.getvalue() + err.getvalue())
        self.assertIn("dest=user1", out.getvalue())

    def test_no_redirect_records_location(self):
        rc, _o = self.run_cli("get", "--account", "anon", "--id", "R24", "--url", "/redir", "--no-redirect")
        self.assertEqual(rc, 0)
        meta = json.loads(self.raw("R24.meta.json"))
        self.assertEqual(meta["status"], 301)
        self.assertEqual(meta["redirects"], [{"status": 301, "location": "/target_2.htm"}])
        self.run_cli("get", "--account", "anon", "--id", "R24f", "--url", "/redir")
        meta = json.loads(self.raw("R24f.meta.json"))
        self.assertEqual(meta["status"], 200)
        self.assertTrue(meta["final_url"].endswith("/target_2.htm"))

    def test_post_hash_from_captured_page(self):
        self.run_cli("get", "--account", "anon", "--id", "P", "--url", "/form/c")
        rc, _o = self.run_cli("post", "--account", "anon", "--id", "S", "--url", "/transsearch.php",
                              "--field", "hash_check=@HASH", "--field", "word=abc", "--hash-from", "P")
        self.assertEqual(rc, 0)
        self.assertEqual(urllib.parse.parse_qsl(Handler.posts[-1][2]), [("hash_check", FORM_SAMPLE), ("word", "abc")])

    def test_temp_cookie_sent_once_and_not_persisted(self):
        self.run_cli("login", "--account", "user1", "--id", "W01")
        self.run_cli("get", "--account", "user1", "--id", "Q1", "--url", "/q", "--cookie", "quotesx-1-2=|5|6")
        self.assertIn("quotesx-1-2=|5|6", self.raw("Q1.html"))
        self.run_cli("get", "--account", "user1", "--id", "Q2", "--url", "/q")
        self.assertNotIn("quotesx", self.raw("Q2.html"))

    def test_stops_on_5xx_budget_and_block_page(self):
        rc, _o = self.run_cli("get", "--account", "anon", "--id", "L", "--url", "/limited")
        self.assertEqual(rc, 1)
        rc, _o = self.run_cli("get", "--account", "anon", "--id", "K", "--url", "/captcha")
        self.assertEqual(rc, 1)
        rc, _o = self.run_cli("get", "--account", "anon", "--id", "J", "--url", "/composer")
        self.assertEqual(rc, 0)
        rc, out = self.run_cli("get", "--account", "anon", "--id", "B", "--url", "/b", budget=3)
        self.assertEqual(rc, 1)
        self.assertIn("budget", out)

    def test_refuses_overwrite_and_work_dir_in_git(self):
        self.run_cli("get", "--account", "anon", "--id", "D", "--url", "/d")
        rc, _o = self.run_cli("get", "--account", "anon", "--id", "D", "--url", "/d")
        self.assertEqual(rc, 1)
        repo = git_repo(self)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(F.main(["--work", os.path.join(repo, "w"), "budget"]), 1)
        self.assertFalse(os.path.exists(os.path.join(repo, "w")))

    def test_peek_prints_an_anonymized_summary(self):
        # Nit: cmd_peek had no test. It must never print a pseudo, a token or raw bytes.
        cfg = os.path.join(self.tmp.name, "anon.json")
        with open(cfg, "w") as fh:
            json.dump({"pseudos": ["fakeuser"]}, fh)
        self.run_cli("get", "--account", "anon", "--id", "PK", "--url", "/form/p")
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = F.main(["--work", self.work, "--anon-config", cfg, "peek", "PK", "--forms", "--grep", "hash_check"])
        self.assertEqual(rc, 0)
        text = out.getvalue()
        self.assertIn("form[1]", text)
        self.assertIn("hash_check", text)
        self.assertNotIn(FORM_SAMPLE, text)


class UnitTests(unittest.TestCase):
    def test_state_delay_and_count_persist(self):
        with tempfile.TemporaryDirectory() as d:
            now, slept = [100.0], []
            path = os.path.join(d, "s.json")
            s = F.State(path, 3.0, 10, clock=lambda: now[0], sleep=slept.append)
            s.before_request()
            now[0] += 1.0
            s2 = F.State(path, 3.0, 10, clock=lambda: now[0], sleep=slept.append)
            s2.before_request()
            self.assertEqual(slept, [2.0])
            self.assertEqual(F.State(path, 3.0, 10).count, 2)

    def test_overrides(self):
        f = [("a", "1"), ("b", "2"), ("a", "3")]
        self.assertEqual(F.apply_overrides(f, [("a", "x"), ("c", "y")], ["b"]), [("a", "x"), ("c", "y")])

    def test_pick_form(self):
        forms = F.parse_forms(FORM_PAGE)
        self.assertEqual(F.pick_form(forms, "hop")["attrs"]["action"], "bddpost.php?config=hfr.inc")
        self.assertEqual(F.pick_form(forms, None, action_contains="search")["attrs"]["name"], "search")
        with self.assertRaises(C.CaptureError):
            F.pick_form(forms, "nope")


if __name__ == "__main__":
    unittest.main()
