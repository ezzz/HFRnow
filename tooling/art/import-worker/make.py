#!/usr/bin/env python3
"""Draws the construction worker of the first-launch import screen (#754), original work, style 1 « digital sketching »
(docs/THEMES.md §6): flat colour areas, one dark contour, no gradient and no worked shading.

Three SVG layers on one 128 x 128 canvas, so SwiftUI can stack them and move two of them:
  body   : ground, post and nail, boots, legs, torso, back arm, head, helmet  (static)
  arm    : the hammer arm, drawn raised; SwiftUI turns it around the shoulder (SHOULDER)
  spark  : the little flash at the nail (pulses at the impact)
Each layer exists in a light and a dark palette. Output goes to the asset catalogue (imagesets) when run with --assets.

    python3 tooling/art/import-worker/make.py --assets App/SwiftHFR/Assets.xcassets --preview tooling/art/import-worker/layers

Pure standard library; every shape is hand-placed below, no tracing, no downloaded asset.
"""
import argparse
import json
import os

SHOULDER = (72, 62)   # pivot of the arm layer; mirrored in LegacyImportProgressView.shoulder
IMPACT_ANGLE = 58     # degrees clockwise from the raised pose to the nail; mirrored in LegacyImportProgressView.impactAngle

LIGHT = dict(line="#3B2F2A", skin="#F0BE96", helmet="#F6B92B", helmet_shade="#E39A12", vest="#F36F2E", stripe="#EEF1F3",
             pants="#46659A", boot="#5E4837", wood="#B98150", wood_dark="#9A6638", metal="#8F99A5", glove="#DCD3C6",
             ground="#00000018", spark="#FFD84A", nail="#6F7782")
DARK = dict(line="#120E0C", skin="#E7B48C", helmet="#F2B52F", helmet_shade="#D9921A", vest="#F2783A", stripe="#D5DADF",
            pants="#6A89BF", boot="#8A6C54", wood="#C99063", wood_dark="#A9773F", metal="#A9B3BF", glove="#CFC6B8",
            ground="#FFFFFF1F", spark="#FFE066", nail="#9AA3AD")


def svg(inner):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">'
            f'{inner}</svg>\n')


def sk(fill, c, w=2.4):
    return f'fill="{fill}" stroke="{c["line"]}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"'


def body(c):
    return svg(
        # ground and the post the hammer works on
        f'<ellipse cx="62" cy="117" rx="46" ry="4.5" fill="{c["ground"]}"/>'
        f'<rect x="108" y="58" width="12" height="58" rx="2" {sk(c["wood"], c)}/>'
        f'<rect x="108" y="58" width="5" height="58" rx="2" fill="{c["wood_dark"]}"/>'
        f'<rect x="112" y="49" width="4" height="10" rx="1.5" {sk(c["nail"], c, 1.8)}/>'
        # back arm (rests along the body), behind the torso
        f'<rect x="28" y="62" width="12" height="28" rx="6" {sk(c["vest"], c)}/>'
        f'<circle cx="34" cy="92" r="6" {sk(c["glove"], c)}/>'
        # legs and boots
        f'<rect x="38" y="88" width="14" height="24" rx="4" {sk(c["pants"], c)}/>'
        f'<rect x="56" y="88" width="14" height="24" rx="4" {sk(c["pants"], c)}/>'
        f'<path d="M35 112h19a3 3 0 0 1 3 3v2H35z" {sk(c["boot"], c)}/>'
        f'<path d="M53 112h19a3 3 0 0 1 3 3v2H53z" {sk(c["boot"], c)}/>'
        # torso, reflective stripe, zip
        f'<rect x="34" y="56" width="44" height="40" rx="11" {sk(c["vest"], c)}/>'
        f'<rect x="34.5" y="74" width="43" height="7" fill="{c["stripe"]}"/>'
        f'<path d="M34 74h44M34 81h44" stroke="{c["line"]}" stroke-width="1.6" fill="none"/>'
        f'<path d="M56 57v38" stroke="{c["line"]}" stroke-width="1.6" fill="none"/>'
        # head (turned to the right), face
        f'<circle cx="56" cy="38" r="16" {sk(c["skin"], c)}/>'
        f'<circle cx="62.5" cy="39" r="1.9" fill="{c["line"]}"/><circle cx="71" cy="39" r="1.9" fill="{c["line"]}"/>'
        f'<path d="M62 46.5q4 3.2 8.5 0" stroke="{c["line"]}" stroke-width="2" fill="none" stroke-linecap="round"/>'
        # helmet: dome, brim, ridge
        f'<path d="M39 35a17 17 0 0 1 34 0z" {sk(c["helmet"], c)}/>'
        f'<rect x="54" y="19" width="6" height="16" fill="{c["helmet_shade"]}" stroke="{c["line"]}" stroke-width="1.8"/>'
        f'<rect x="36" y="33" width="46" height="6" rx="3" {sk(c["helmet"], c)}/>')


def arm(c):
    sx, sy = SHOULDER
    hx, hy = sx + 15, sy - 19      # hand
    tx, ty = sx + 21, sy - 36      # top of the handle
    return svg(
        # sleeve (outline stroke under a colour stroke), glove, handle, hammer head; drawn raised, rotated by SwiftUI
        f'<path d="M{sx} {sy} L{hx} {hy}" stroke="{c["line"]}" stroke-width="15" stroke-linecap="round"/>'
        f'<path d="M{sx} {sy} L{hx} {hy}" stroke="{c["vest"]}" stroke-width="10.4" stroke-linecap="round"/>'
        f'<path d="M{hx} {hy} L{tx} {ty}" stroke="{c["line"]}" stroke-width="8" stroke-linecap="round"/>'
        f'<path d="M{hx} {hy} L{tx} {ty}" stroke="{c["wood"]}" stroke-width="4" stroke-linecap="round"/>'
        f'<circle cx="{hx}" cy="{hy}" r="6" {sk(c["glove"], c)}/>'
        f'<g transform="rotate(-8 {tx} {ty})">'
        f'<rect x="{tx - 12}" y="{ty - 6}" width="24" height="11" rx="2.5" {sk(c["metal"], c)}/></g>')


def spark(c):
    cx, cy = 112, 55
    rays = "".join(
        f'<path d="M{cx} {cy} L{cx + dx} {cy + dy}" stroke="{c["line"]}" stroke-width="5" stroke-linecap="round"/>'
        for dx, dy in [(-9, -12), (3, -15), (-15, -3)]
    ) + "".join(
        f'<path d="M{cx} {cy} L{cx + dx} {cy + dy}" stroke="{c["spark"]}" stroke-width="2.4" stroke-linecap="round"/>'
        for dx, dy in [(-9, -12), (3, -15), (-15, -3)]
    )
    return svg(rays)


LAYERS = {"body": body, "arm": arm, "spark": spark}


def imageset(layer):
    return {
        "images": [
            {"filename": f"{layer}.svg", "idiom": "universal"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": f"{layer}-dark.svg", "idiom": "universal"},
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", help="asset catalogue to write the three imagesets into")
    ap.add_argument("--preview", help="folder for loose light/dark SVG layers (used by the preview renderer)")
    a = ap.parse_args()
    for layer, fn in LAYERS.items():
        if a.assets:
            name = "ImportWorker" + layer.capitalize() + ".imageset"
            d = os.path.join(a.assets, name)
            write(os.path.join(d, f"{layer}.svg"), fn(LIGHT))
            write(os.path.join(d, f"{layer}-dark.svg"), fn(DARK))
            write(os.path.join(d, "Contents.json"), json.dumps(imageset(layer), indent=2) + "\n")
        if a.preview:
            write(os.path.join(a.preview, f"{layer}-light.svg"), fn(LIGHT))
            write(os.path.join(a.preview, f"{layer}-dark.svg"), fn(DARK))


if __name__ == "__main__":
    main()
