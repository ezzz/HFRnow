"""Tests for capture.py. No request ever leaves the machine: only a loopback server is used."""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import capture as C  # noqa: E402

JAR_SAMPLE = "jar-sample-one"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n).decode()
        ok = "pseudo=fakeuser" in body and "action=send" in body and "login=Se+connecter" in body
        self.send_response(200)
        if ok:
            self.send_header("Set-Cookie", "md_user=%s; path=/" % JAR_SAMPLE)
        self.end_headers()
        self.wfile.write(b"<a href='login_redirection.php'>go</a>" if ok else b"nope")

    def do_GET(self):
        code = 429 if self.path == "/limited" else 200
        self.send_response(code)
        self.send_header("Set-Cookie", "md_pass=%s" % JAR_SAMPLE)
        self.end_headers()
        self.wfile.write(b"page " + self.path.encode())


class CaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def session(self):
        s = C.Session(self.base, C.Throttle(0))
        self.addCleanup(s.opener.close)
        return s

    def test_login_success_and_failure(self):
        self.session().login({"pseudo": "fakeuser", "password": "fakepw"})
        with self.assertRaises(C.CaptureError):
            self.session().login({"pseudo": "other", "password": "x"})

    def test_stops_on_429(self):
        with self.assertRaises(C.CaptureError):
            self.session().request("/limited")

    def test_headers_strip_cookie_values(self):
        s = self.session()
        status, headers, _b = s.request("/p")
        text = C.format_headers(status, headers)
        self.assertNotIn(JAR_SAMPLE, text)
        self.assertIn("Set-Cookie: md_pass=REDACTED", text)

    def test_full_run_writes_files_and_never_prints_secrets(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory() as d:
            creds = os.path.join(d, "c.json")
            man = os.path.join(d, "m.json")
            with open(creds, "w") as fh:
                json.dump({"accounts": [{"pseudo": "fakeuser", "password": "fakepw"}]}, fh)
            with open(man, "w") as fh:
                json.dump({"pages": [{"id": "a", "url": "/a", "account": "anon"},
                                     {"id": "b", "url": "/b", "account": "user1"}]}, fh)
            out = os.path.join(d, "raw")
            args = C.argparse.Namespace(delay=3.0, out=out, manifest=man, credentials=creds, only=None,
                                        dry_run=False, base_url=self.base)
            # Skip the real 3 s politeness wait: the delay rule itself is tested separately.
            orig = C.Throttle
            C.Throttle = lambda delay: orig(0)
            buf_o, buf_e = io.StringIO(), io.StringIO()
            try:
                with contextlib.redirect_stdout(buf_o), contextlib.redirect_stderr(buf_e):
                    self.assertEqual(C.run(args), 0)
            finally:
                C.Throttle = orig
            with open(os.path.join(out, "b.html"), "rb") as fh:
                self.assertEqual(fh.read(), b"page /b")
            with open(os.path.join(out, "b.headers.txt")) as fh:
                self.assertNotIn(JAR_SAMPLE, fh.read())
            for text in (buf_o.getvalue(), buf_e.getvalue()):
                for secret in (JAR_SAMPLE, "fakepw"):
                    self.assertNotIn(secret, text)
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o700)


class InputTests(unittest.TestCase):
    def test_delay_below_minimum_refused(self):
        args = C.argparse.Namespace(delay=1.0, out="/nonexistent-x", manifest="m", credentials=None,
                                    only=None, dry_run=True, base_url="")
        with self.assertRaises(C.CaptureError):
            C.run(args)

    def test_output_inside_git_work_tree_refused(self):
        if not shutil.which("git"):
            self.skipTest("git not installed")
        with tempfile.TemporaryDirectory() as repo:
            subprocess.run(["git", "init", "-q", repo], check=True)
            self.assertTrue(C.inside_git_work_tree(os.path.join(repo, "does", "not", "exist")))
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse(C.inside_git_work_tree(os.path.join(d, "raw")))

    def test_throttle_enforces_delay(self):
        now, slept = [100.0], []
        t = C.Throttle(3.0, clock=lambda: now[0], sleep=lambda s: (slept.append(s), now.__setitem__(0, now[0] + s)))
        t.wait()
        now[0] += 1.0
        t.wait()
        self.assertEqual(slept, [2.0])

    def test_manifest_validation(self):
        def load(obj):
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
                json.dump(obj, fh)
            try:
                return C.load_manifest(fh.name)
            finally:
                os.unlink(fh.name)
        good = {"id": "x", "url": "/y", "account": "anon"}
        self.assertEqual(len(load([good])), 1)
        for bad in ({**good, "method": "POST"}, {**good, "account": "root"}, {**good, "url": "http://evil/"},
                    {**good, "id": "../x"}, {"id": "x"}):
            with self.assertRaises(C.CaptureError, msg=str(bad)):
                load([bad])
        with self.assertRaises(C.CaptureError):
            load([good, good])

    def test_credentials_format(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write("pseudo password plain text")
        try:
            with self.assertRaises(C.CaptureError):
                C.load_credentials(fh.name)
        finally:
            os.unlink(fh.name)


if __name__ == "__main__":
    unittest.main()
