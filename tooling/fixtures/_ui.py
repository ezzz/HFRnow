"""Tiny terminal helpers: colored ok/warn/ko and a spinner (TTY only, NO_COLOR aware)."""
import itertools
import os
import sys
import threading
import time

_COLORS = {"ok": "32", "warn": "33", "ko": "31"}


def _tty(stream):
    return hasattr(stream, "isatty") and stream.isatty()


def _color_on(stream):
    return _tty(stream) and "NO_COLOR" not in os.environ


def _say(kind, msg, stream):
    tag = kind
    if _color_on(stream):
        tag = "\033[%sm%s\033[0m" % (_COLORS[kind], kind)
    print("%s %s" % (tag, msg), file=stream)


def ok(msg):
    """Print a green `ok` line."""
    _say("ok", msg, sys.stdout)


def warn(msg):
    """Print a yellow `warn` line (stderr)."""
    _say("warn", msg, sys.stderr)


def ko(msg):
    """Print a red `ko` line (stderr)."""
    _say("ko", msg, sys.stderr)


class Spinner:
    """Context manager showing a spinner on stderr while waiting; silent without a TTY."""

    def __init__(self, label):
        self.label = label
        self._stop = threading.Event()
        self._thread = None

    def _run(self):
        for ch in itertools.cycle("|/-\\"):
            if self._stop.is_set():
                break
            sys.stderr.write("\r%s %s" % (ch, self.label))
            sys.stderr.flush()
            time.sleep(0.1)
        sys.stderr.write("\r" + " " * (len(self.label) + 2) + "\r")
        sys.stderr.flush()

    def __enter__(self):
        if _tty(sys.stderr):
            self._thread = threading.Thread(target=self._run, daemon=True)
            self._thread.start()
        return self

    def __exit__(self, *exc):
        self._stop.set()
        if self._thread:
            self._thread.join()
        return False
