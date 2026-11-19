"""Aliasing of an MPStorage JSON document (the first post of the storage thread and its form copies).

Used by anonymize.py (redactor side only: `check` has its own verifier and never imports this module,
docs/agents/LESSONS.md 33-34). The document is rewritten **in place**, token by token, so everything
that is not a member's or another client's data keeps its exact bytes (spacing, escapes, key order).

Positions known from the legacy app (`Classes/MPStorage.m:230-390, 440-490, 737-746` @ 87fe0d1c) and from the
Swift models (`MPStorageMPFlag`, `MPStorageBookmark`, `MPStorageBlocklistEntry`, `MPStorageTombstone`):

* blacklist item `username`: member alias (the page's own table, `userN`);
* bookmark item `author`: member alias; `label`: `textN`; `post`, `numreponse`: fake ids (9100NN);
* mpFlag item `post`: fake id; `p`, `href`, `uri`: `textN`;
* tombstone `id`: `textN` (string) or fake id (number);
* a `sourceName` other than `iOS`: `clientN`;
* any key of the root, of the `0.1` entry or of a section that is not part of the format: another client's
  namespace, key `nsN`; everything inside it is generic: keys `keyN`, strings `textN`, numbers fake ids.

Timestamps (`lastUpdate`, `createDate`, `deleteDate`), small page numbers and category ids, booleans and
null keep their value. A string that held a U+00A0 or a character outside the BMP keeps that property in its
alias (`textN` + U+00A0 / U+1F600), since those are what LOT-038 / LOT-062 need to see.
"""
import json
import json.decoder
import re

FAKE_ID_OTHER = 910001
TIME_KEYS = ("lastUpdate", "createDate", "deleteDate")
TIMESTAMP_RE = re.compile(r"\d{13}\Z")  # milliseconds since the epoch, 2001 to 2286
FAKE_TIME = 1700000000000
NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?")
WHITESPACE = " \t\r\n\u00a0"  # U+00A0: legacy removes it before parsing (`MPStorage.m`, HFR-PROTOCOL 3.3)


class DocumentError(ValueError):
    """The text is not a JSON document the aliaser can walk (malformed, duplicate key, wrong shape)."""


class Node:
    """A JSON value with its offsets in the text; `items` holds (key node, value node) pairs or a list."""
    __slots__ = ("kind", "start", "end", "value", "items")

    def __init__(self, kind, start, end, value=None, items=None):
        self.kind, self.start, self.end, self.value, self.items = kind, start, end, value, items


def scan_json(text):
    """Parse text into a tree of Node, refusing duplicate keys (json.loads would drop the first value unchecked)."""
    pos = 0
    n = len(text)

    def ws():
        nonlocal pos
        while pos < n and text[pos] in WHITESPACE:
            pos += 1

    def expect(ch):
        nonlocal pos
        if text[pos:pos + 1] != ch:
            raise DocumentError("expected %r at %d" % (ch, pos))
        pos += 1

    def string():
        nonlocal pos
        if text[pos:pos + 1] != '"':
            raise DocumentError("expected a string at %d" % pos)
        start = pos
        try:
            value, pos = json.decoder.scanstring(text, pos + 1)
        except json.JSONDecodeError as e:
            raise DocumentError(str(e)) from e
        return Node("str", start, pos, value)

    def value(depth=0):
        nonlocal pos
        if depth > 200:
            raise DocumentError("nested too deep")
        ws()
        c = text[pos:pos + 1]
        start = pos
        if c == "{":
            pos += 1
            items, seen = [], set()
            ws()
            if text[pos:pos + 1] == "}":
                pos += 1
                return Node("obj", start, pos, items=items)
            while True:
                ws()
                key = string()
                if key.value in seen:
                    raise DocumentError("duplicate key")
                seen.add(key.value)
                ws()
                expect(":")
                items.append((key, value(depth + 1)))
                ws()
                if text[pos:pos + 1] == ",":
                    pos += 1
                    continue
                expect("}")
                return Node("obj", start, pos, items=items)
        if c == "[":
            pos += 1
            items = []
            ws()
            if text[pos:pos + 1] == "]":
                pos += 1
                return Node("arr", start, pos, items=items)
            while True:
                items.append(value(depth + 1))
                ws()
                if text[pos:pos + 1] == ",":
                    pos += 1
                    continue
                expect("]")
                return Node("arr", start, pos, items=items)
        if c == '"':
            return string()
        for word, val in (("true", True), ("false", False), ("null", None)):
            if text.startswith(word, pos):
                pos += len(word)
                return Node("lit", start, pos, val)
        m = NUMBER_RE.match(text, pos)
        if not m:
            raise DocumentError("unexpected character at %d" % pos)
        pos = m.end()
        return Node("num", start, pos, m.group(0))

    root = value()
    ws()
    if pos != n:
        raise DocumentError("trailing text at %d" % pos)
    return root


class Aliaser:
    """Collects the replacements of one document; name_alias(name) -> `userN` or None (not a member)."""

    def __init__(self, name_alias):
        self.name_alias = name_alias
        self.edits = []
        self._tables = {}

    # -- alias tables (one per kind, per document) ------------------------------------------------------
    def _number(self, kind, real):
        table = self._tables.setdefault(kind, {})
        return table.setdefault(real, len(table) + 1)

    # No value is ever kept because it looks like an alias (`user77`, an id in 9100NN): a real value can look like
    # one. Everything not structural goes through the tables, so an aliased document is re-aliased, not trusted.
    def text(self, s):
        marks = ("\u00a0" if "\u00a0" in s else "") + ("\U0001F600" if any(ord(c) > 0xFFFF for c in s) else "")
        return "text%d%s" % (self._number("text", s), marks)

    def member(self, s):
        return self.name_alias(s) or self.text(s)

    def client(self, s):
        return "client%d" % self._number("client", s)

    def key(self, s, prefix):
        if s in TIME_KEYS:
            return s
        return "%s%d" % (prefix, self._number(prefix, s))

    def fake_id(self, real):
        return str(FAKE_ID_OTHER + self._number("id", real) - 1)

    # -- edits -----------------------------------------------------------------------------------------
    def _set(self, node, new):
        if node.kind == "str" and new != node.value:
            # U+00A0 as an escape: the page parser removes every raw one before reading the JSON (MPStorage.m:883).
            self.edits.append((node.start, node.end, json.dumps(new, ensure_ascii=False).replace("\u00a0", "\\u00a0")))

    def _set_number(self, node, new):
        if node.value != new:
            self.edits.append((node.start, node.end, new))

    def _key(self, knode, prefix):
        self._set(knode, self.key(knode.value, prefix))

    # -- walkers ---------------------------------------------------------------------------------------
    def generic(self, node, key=None):
        """Content of another client's namespace (or of a position with an unexpected type)."""
        if node.kind == "obj":
            for k, v in node.items:
                self._key(k, "key")
                self.generic(v, k.value)
        elif node.kind == "arr":
            for v in node.items:
                self.generic(v, key)
        elif node.kind == "str":
            self._set(node, self.text(node.value))
        elif node.kind == "num":
            self.timestamp(node) if key in TIME_KEYS else self._set_number(node, self.fake_id(node.value))

    def namespace(self, knode, vnode):
        self._key(knode, "ns")
        self.generic(vnode)

    def source(self, v):
        if v.kind == "str":
            if v.value != "iOS":
                self._set(v, self.client(v.value))
        else:
            self.generic(v)

    def version(self, v):
        if v.kind == "str":
            if v.value != "0.1":
                self._set(v, self.text(v.value))
        else:
            self.generic(v)

    def id_value(self, v):
        if v.kind == "str":
            self._set(v, self.fake_id(v.value))
        elif v.kind == "num":
            self._set_number(v, self.fake_id(v.value))
        else:
            self.generic(v)

    def text_value(self, v):
        if v.kind == "str":
            self._set(v, self.text(v.value))
        else:
            self.generic(v)

    def member_value(self, v):
        if v.kind == "str":
            self._set(v, self.member(v.value))
        else:
            self.generic(v)

    def category(self, v):
        keep = (v.kind == "str" and re.fullmatch(r"\d{1,3}", v.value)) or (
            v.kind == "num" and re.fullmatch(r"\d{1,3}", v.value))
        if not keep:
            self.id_value(v)

    def page(self, v):
        if not (v.kind == "num" and re.fullmatch(r"\d{1,5}", v.value)):
            self.generic(v, "page")

    def timestamp(self, node):
        """A plausible timestamp keeps its value; anything else (an id, a small number) becomes a fixed fake one."""
        if not TIMESTAMP_RE.match(node.value):
            self._set_number(node, str(FAKE_TIME + self._number("time", node.value)))

    def time(self, v):
        self.generic(v, "lastUpdate")

    FIELDS = {
        "blacklist": {"username": "member_value", "createDate": "time"},
        "bookmarks": {"author": "member_value", "label": "text_value", "post": "id_value",
                      "numreponse": "id_value", "cat": "category", "createDate": "time"},
        "mpFlags": {"post": "id_value", "p": "text_value", "href": "text_value", "uri": "text_value",
                    "page": "page"},
    }

    def item(self, e, section):
        if e.kind != "obj":  # a bare value in a list: a pseudo in a blacklist, anything else is text or an id
            if e.kind == "str":
                self._set(e, self.member(e.value) if section == "blacklist" else self.text(e.value))
            else:
                self.generic(e)
            return
        fields = self.FIELDS[section]
        for k, v in e.items:
            handler = fields.get(k.value)
            if handler:
                getattr(self, handler)(v)
            else:
                self._key(k, "key")
                self.generic(v, k.value)

    def tombstone_id(self, val, section):
        """A tombstone id is its item's storageKey (MPStorageItem.swift): alias it the way the item is aliased."""
        if val.kind == "num":
            self.id_value(val)
        elif val.kind != "str":
            self.generic(val)
        elif section == "blacklist":
            self._set(val, self.member(val.value).lower())
        elif section == "mpFlags" and val.value.isdigit():
            self._set(val, self.fake_id(val.value))
        elif section == "bookmarks" and re.fullmatch(r"\d+-\d+-\d+", val.value):
            cat, post, numreponse = val.value.split("-")
            self._set(val, "-".join((cat if len(cat) <= 3 else self.fake_id(cat), self.fake_id(post),
                                     self.fake_id(numreponse))))
        else:
            self._set(val, self.text(val.value))

    def tombstones(self, v, section=None):
        if v.kind != "arr":
            self.generic(v)
            return
        for e in v.items:
            if e.kind != "obj":
                self.generic(e)
                continue
            for k, val in e.items:
                if k.value == "id":
                    self.tombstone_id(val, section)
                elif k.value == "deleteDate":
                    self.time(val)
                else:
                    self._key(k, "key")
                    self.generic(val, k.value)

    def section(self, v, name):
        if v.kind != "obj":
            self.generic(v)
            return
        for k, val in v.items:
            if k.value == "list" and val.kind == "arr":
                for e in val.items:
                    self.item(e, name)
            elif k.value == "sourceName":
                self.source(val)
            elif k.value == "lastUpdate":
                self.time(val)
            elif k.value == "tombstones":
                self.tombstones(val, name)
            else:
                self.namespace(k, val)

    def entry(self, e):
        if e.kind != "obj":
            self.generic(e)
            return
        for k, v in e.items:
            if k.value == "version":
                self.version(v)
            elif k.value in self.FIELDS:
                self.section(v, k.value)
            elif k.value == "sourceName":
                self.source(v)
            elif k.value == "lastUpdate":
                self.time(v)
            elif k.value == "tombstones":
                self.tombstones(v)
            else:
                self.namespace(k, v)

    def root(self, node):
        if node.kind != "obj":
            raise DocumentError("the document is not a JSON object")
        for k, v in node.items:
            if k.value == "data" and v.kind == "arr":
                for e in v.items:
                    self.entry(e)
            elif k.value == "sourceName":
                self.source(v)
            elif k.value == "lastUpdate":
                self.time(v)
            else:
                self.namespace(k, v)


def alias_document(text, name_alias):
    """The document text with every position holding member or other-client data aliased (see module doc).

    Raises DocumentError for a malformed document, a duplicate key or a root that is not an object."""
    tree = scan_json(text)
    aliaser = Aliaser(name_alias)
    aliaser.root(tree)
    out = text
    for start, end, new in sorted(aliaser.edits, reverse=True):
        out = out[:start] + new + out[end:]
    return out
