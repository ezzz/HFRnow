#!/usr/bin/env python3
"""Publish raw captures as the anonymized corpus (docs/FIXTURES.md).

    publish.py --config local.json --raw ~/agent-work/<task>/captures-raw --dest <corpus dir> [ID ...]

For every capture of the manifest (default `corpus.json` next to this script): the page is anonymized
to `<id>-<slug>.<ext>` (`--private` when the manifest says so) and its metadata to `<id>.meta.json`:
the kept fields of the raw meta, `request_body` (anonymized POST body, from `<raw>.request.txt`),
`file` and `private`. Page and meta share one alias table, so a pseudo in `final_url` or in the
request body gets the same `userN` as in the page. Member names seen in any capture of the manifest
are also replaced in the free text of every other one. Nothing is written for a capture that still
leaks (the `check` findings are printed as file:line:col and reason, never values). Prints file names and counts only.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _ui  # noqa: E402
import anonymize as A  # noqa: E402

DEFAULT_MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus.json")
META_KEYS = ("account", "method", "url_template", "url", "final_url", "status", "content_type", "date",
             "redirects", "set_cookie_names", "request_fields", "note")


def load_manifest(path):
    """[{raw, id, slug, ext, private}] from a manifest file, validated."""
    with open(path, encoding="utf-8") as fh:
        entries = json.load(fh)["captures"]
    for e in entries:
        missing = {"raw", "id", "slug", "ext", "private"} - set(e)
        if missing:
            raise ValueError("manifest entry %r lacks %s" % (e.get("raw"), ", ".join(sorted(missing))))
    return entries


def request_body(raw_dir, raw_id):
    """URL-encoded body recorded by flows.py (second block of <id>.request.txt), or None."""
    path = os.path.join(raw_dir, raw_id + ".request.txt")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read().split("\n\n")[1].strip()


def publish_one(anon, raw_dir, dest, entry):
    """Anonymize one capture; return the list of findings (empty = written)."""
    raw_id = entry["raw"]
    with open(os.path.join(raw_dir, raw_id + ".meta.json"), encoding="utf-8") as fh:
        raw_meta = json.load(fh)
    page = enc = None
    if entry["ext"]:
        text, enc = A.read_text(os.path.join(raw_dir, raw_id + ".html"))
        page = anon.anonymize(text, private=entry["private"])
    else:
        anon._reset()
    meta = {"id": entry["id"]}
    meta.update(anon.anonymize_meta({k: raw_meta[k] for k in META_KEYS if k in raw_meta}))
    body = request_body(raw_dir, raw_id)
    if body is not None:
        meta["request_body"] = anon.redact_text(body)
    name = None
    if page is not None:
        name = "%s-%s.%s" % (entry["id"], entry["slug"], entry["ext"])
        meta["file"] = name
    meta["private"] = entry["private"]
    mtext = json.dumps(meta, indent=2, ensure_ascii=False) + "\n"
    leaks = [(entry["id"] + ".meta.json",) + f for f in anon.findings(mtext)]
    if page is not None:
        leaks += [(name,) + f for f in anon.findings(page, private=entry["private"])]
    if leaks:
        return leaks
    if page is not None:
        with open(os.path.join(dest, name), "w", encoding=enc, newline="") as fh:
            fh.write(page)
    with open(os.path.join(dest, entry["id"] + ".meta.json"), "w", encoding="utf-8") as fh:
        fh.write(mtext)
    return []


def main(argv=None):
    """Entry point."""
    p = argparse.ArgumentParser(description="Anonymize raw captures into the fixture corpus.")
    p.add_argument("--config", required=True, help="local JSON config (git-ignored)")
    p.add_argument("--raw", required=True, help="raw capture folder (outside the repository)")
    p.add_argument("--dest", required=True, help="corpus folder")
    p.add_argument("--manifest", default=DEFAULT_MANIFEST)
    p.add_argument("ids", nargs="*", help="raw ids to publish (default: all)")
    args = p.parse_args(argv)
    try:
        entries = load_manifest(args.manifest)
        cfg = A.Config.load(args.config)
    except (OSError, ValueError) as exc:
        _ui.ko(str(exc))
        return 2
    unknown = set(args.ids) - {e["raw"] for e in entries}
    if unknown:
        _ui.ko("not in the manifest: %s" % ", ".join(sorted(unknown)))
        return 2
    texts = [A.read_text(os.path.join(args.raw, e["raw"] + ".html"))[0] for e in entries if e["ext"]]
    with _ui.Spinner("collecting member names"):
        known = A.known_member_names(texts)
    anon = A.Anonymizer(cfg, known_names=known)
    os.makedirs(args.dest, exist_ok=True)
    bad = 0
    for entry in entries:
        if args.ids and entry["raw"] not in args.ids:
            continue
        try:
            leaks = publish_one(anon, args.raw, args.dest, entry)
        except A.AnonymizeError as exc:
            leaks = [(entry["id"], 0, 0, str(exc))]
        if leaks:
            bad += 1
            for where, line, col, reason in leaks:
                _ui.ko("%s:%d:%d: %s" % (where, line, col, reason))
            _ui.ko("%s: NOT written" % entry["id"])
        else:
            _ui.ok("%s %s" % (entry["id"], "%s-%s.%s" % (entry["id"], entry["slug"], entry["ext"])
                              if entry["ext"] else "(meta only)"))
    (_ui.ko if bad else _ui.ok)("%d captures published, %d refused" % (
        sum(1 for e in entries if not args.ids or e["raw"] in args.ids) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
