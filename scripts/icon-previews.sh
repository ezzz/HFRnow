#!/usr/bin/env bash
# Renders the picker's preview of every alternate icon from its Icon Composer file (Mac only, Xcode's `ictool`).
#
# The system has no API to read an alternate icon's image at runtime, so the picker (#730) shows previews kept in the app's
# asset catalogue: App/SwiftHFR/Assets.xcassets/IconPreviews/IconPreview-<bundle>.imageset, one per App/SwiftHFR/Icon-*.icon, with
# a Default (any appearance) and a Dark image so the grid follows light and dark. They come from the same .icon as the Home Screen
# icon, so a redrawn icon only needs this script run again; the AppIconPackTests test fails when an option has no preview.
#
# Usage: scripts/icon-previews.sh            render every icon
#        scripts/icon-previews.sh Icon-X     render only the named .icon bundle(s)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/App/SwiftHFR"
OUT="${APP}/Assets.xcassets/IconPreviews"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
SIZE=360 # px: 120 pt at @3x, the grid shows 76 pt

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then GREEN=$'\033[32m'; RED=$'\033[31m'; OFF=$'\033[0m'; else GREEN=""; RED=""; OFF=""; fi
ok() { printf '%sok%s   %s\n' "${GREEN}" "${OFF}" "$*"; }
ko() { printf '%sko%s   %s\n' "${RED}" "${OFF}" "$*" >&2; }

[ -x "${ICTOOL}" ] || { ko "ictool not found at ${ICTOOL} (needs Xcode with Icon Composer)"; exit 1; }

if [ "$#" -gt 0 ]; then names=("$@"); else names=(); for f in "${APP}"/Icon-*.icon; do names+=("$(basename "${f}" .icon)"); done; fi

mkdir -p "${OUT}"
[ -f "${OUT}/Contents.json" ] || printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' > "${OUT}/Contents.json"

for name in "${names[@]}"; do
  src="${APP}/${name}.icon"
  [ -d "${src}" ] || { ko "${name}: no such .icon in ${APP}"; exit 1; }
  set_dir="${OUT}/IconPreview-${name}.imageset"
  mkdir -p "${set_dir}"
  for rendition in Default Dark; do
    file="$(printf '%s' "${rendition}" | tr '[:upper:]' '[:lower:]').png"
    "${ICTOOL}" "${src}" --export-image --output-file "${set_dir}/${file}" --platform iOS --rendition "${rendition}" \
      --width "${SIZE}" --height "${SIZE}" --scale 1 > /dev/null
  done
  # Most icons have no Dark layer: their Dark rendition is the Default one, so only a different one gets its own entry.
  if cmp -s "${set_dir}/default.png" "${set_dir}/dark.png"; then
    rm -f "${set_dir}/dark.png"
    dark_entry=""
  else
    dark_entry=',
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "dark.png", "idiom" : "universal" }'
  fi
  cat > "${set_dir}/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "default.png", "idiom" : "universal" }${dark_entry}
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  ok "${name}"
done
