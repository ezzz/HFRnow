#!/usr/bin/env bash
# Run the legacy-app oracle exporter (LOT-002, LOT-003, LOT-004, LOT-005): apply hfrnow.patch to the legacy checkout, build it,
# run the real Objective-C list parsers, topic-page pipeline, write-flow form/response logic and storage formats
# on saved HTML/JSON inputs and write <case>.oracle.json files.
# macOS + Xcode 27 only. Nothing is ever committed or pushed in the legacy checkout.
#
# Usage: run-oracle.sh [-i INPUT_DIR] [-o OUTPUT_DIR]
#   INPUT_DIR   *.html pages and *.json specs, plus oracle-map.json   (default: ./samples next to this script)
#   OUTPUT_DIR  receives <case>.oracle.json, errors.json (default: ./out next to this script). Only the cases
#               exported by this run are replaced, and only once the export completed; other files are kept.
# Environment:
#   HFRNOW            legacy checkout            (default: $HOME/Git/hfrnow)
#   HFR_ORACLE_WORK   DerivedData and step logs  (default: ./.work next to this script)
#   NO_COLOR          disable colors (also off when stdout is not a terminal)
set -u
set -o pipefail

LEGACY_COMMIT=2440d79
SIM_NAME=agent-m1-iphone
SIM_DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro
SIM_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0

HERE=$(cd "$(dirname "$0")" && pwd)
HFRNOW=${HFRNOW:-$HOME/Git/hfrnow}
WORK=${HFR_ORACLE_WORK:-$HERE/.work}
IN_DIR=$HERE/samples
OUT_DIR=$HERE/out

while getopts "i:o:h" opt; do
  case $opt in
    i) IN_DIR=$OPTARG ;;
    o) OUT_DIR=$OPTARG ;;
    *) awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; exit 2 ;;
  esac
done

# --- output helpers: green ok, yellow warn, red ko; no color without a TTY or with NO_COLOR ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$(printf '\033[32m'); C_WARN=$(printf '\033[33m'); C_KO=$(printf '\033[31m'); C_OFF=$(printf '\033[0m')
  IS_TTY=1
else
  C_OK=; C_WARN=; C_KO=; C_OFF=
  IS_TTY=0
fi
ok()   { printf '%s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
ko()   { printf '%s[ko]%s   %s\n' "$C_KO" "$C_OFF" "$*" >&2; }
die()  { ko "$*"; exit 1; }

SPIN_PID=
on_signal() {
  if [ -n "$SPIN_PID" ]; then
    kill "$SPIN_PID" 2>/dev/null
    [ "$IS_TTY" = 1 ] && printf '\r\033[K'
  fi
  exit 130
}
trap on_signal INT TERM

# spin DIR LABEL LOGFILE CMD...: run CMD in DIR, in the background with a spinner; output goes to LOGFILE.
# Called from the main shell (not a subshell) so the signal trap sees SPIN_PID; the background job ignores
# SIGINT (non-interactive shell), so the trap stops it with SIGTERM.
spin() {
  local dir=$1 label=$2 log=$3 i=0 rc frames='|/-\'
  shift 3
  (cd "$dir" && exec "$@") >"$log" 2>&1 &
  SPIN_PID=$!
  if [ "$IS_TTY" = 1 ]; then
    while kill -0 "$SPIN_PID" 2>/dev/null; do
      printf '\r%s %s' "${frames:i%4:1}" "$label"
      i=$((i + 1))
      sleep 0.2
    done
    printf '\r\033[K'
  fi
  wait "$SPIN_PID"
  rc=$?
  SPIN_PID=
  if [ "$rc" -eq 0 ]; then
    ok "$label"
  else
    ko "$label (exit $rc), last lines of $log:"
    tail -n 25 "$log" >&2
  fi
  return "$rc"
}

# --- preflight ---
[ "$(uname -s)" = Darwin ] || die "macOS with Xcode 27 is required"
for tool in git xcodebuild xcrun carthage; do
  command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
done
[ -d "$HFRNOW/.git" ] || die "legacy checkout not found at $HFRNOW (set HFRNOW)"
[ -f "$IN_DIR/oracle-map.json" ] || die "no oracle-map.json in $IN_DIR"
mkdir -p "$WORK" "$OUT_DIR" || die "cannot create $WORK or $OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
IN_DIR=$(cd "$IN_DIR" && pwd)

# --- 1. legacy checkout at the expected commit ---
head=$(git -C "$HFRNOW" rev-parse HEAD) || die "cannot read $HFRNOW HEAD"
case $head in
  "$LEGACY_COMMIT"*) ok "hfrnow is at $LEGACY_COMMIT" ;;
  *) die "hfrnow is at ${head%"${head#???????}"}, expected $LEGACY_COMMIT (the oracle is pinned to it)" ;;
esac

# --- 2. patch ---
# Edits outside the patch's files (a leftover experiment, another patch) would silently change the oracle.
patch_paths=$(sed -n 's|^diff --git a/\(.*\) b/.*|\1|p' "$HERE/hfrnow.patch")
extra=$(git -C "$HFRNOW" status --porcelain | cut -c4- | grep -vxF -e "${patch_paths:-/}")
if [ -n "$extra" ]; then
  warn "hfrnow has local changes outside hfrnow.patch (they are part of this oracle run):"
  printf '%s\n' "$extra" | sed 's/^/         /'
fi
if git -C "$HFRNOW" apply --reverse --check "$HERE/hfrnow.patch" >/dev/null 2>&1; then
  ok "hfrnow.patch already applied"
elif git -C "$HFRNOW" apply --check "$HERE/hfrnow.patch" >/dev/null 2>&1; then
  git -C "$HFRNOW" apply "$HERE/hfrnow.patch" || die "git apply failed"
  ok "applied hfrnow.patch (local, uncommitted)"
else
  die "hfrnow.patch neither applied nor applicable: $HFRNOW has conflicting local changes"
fi

# --- 3. Carthage (Xcode 27 needs the xcconfig, see README) ---
spin "$HFRNOW" "carthage bootstrap (cached after the first run)" "$WORK/carthage.log" \
  env XCODE_XCCONFIG_FILE="$HERE/carthage-xcode27.xcconfig" \
  carthage bootstrap --platform iOS --use-xcframeworks --cache-builds || exit 1

# --- 4. simulator ---
udid=$(xcrun simctl list devices 2>/dev/null | sed -n "s/^ *$SIM_NAME (\([0-9A-F-]*\)).*/\1/p" | head -n 1)
if [ -n "$udid" ]; then
  ok "simulator $SIM_NAME reused ($udid)"
else
  udid=$(xcrun simctl create "$SIM_NAME" "$SIM_DEVICE_TYPE" "$SIM_RUNTIME") \
    || die "cannot create simulator (is the iOS 27.0 runtime installed?)"
  ok "simulator $SIM_NAME created ($udid)"
fi

# --- 5. export ---
# The exporter writes to a staging folder; OUT_DIR is only touched once the export completed (errors.json written),
# so a failed build or test run never removes oracles, and oracles of cases outside this run are kept.
STAGE=$WORK/export
rm -rf "$STAGE" && mkdir -p "$STAGE" || die "cannot create $STAGE"
status=0
spin "$HFRNOW" "xcodebuild test (OracleExport)" "$WORK/xcodebuild.log" \
  env TEST_RUNNER_HFR_ORACLE_IN="$IN_DIR" TEST_RUNNER_HFR_ORACLE_OUT="$STAGE" \
      TEST_RUNNER_HFR_ORACLE_LEGACY_COMMIT="$LEGACY_COMMIT" \
  xcodebuild test -project SuperHFRplus.xcodeproj -scheme HFRswift -destination "id=$udid" \
    -derivedDataPath "$WORK/build" CODE_SIGNING_ALLOWED=NO -only-testing:HFRswiftTests/OracleExport || status=1

# --- 6. publish and report ---
written=0
errors=0
if [ -f "$STAGE/errors.json" ]; then
  for f in "$STAGE"/*.oracle.json; do
    [ -e "$f" ] || continue
    mv -f "$f" "$OUT_DIR/" || die "cannot move $f to $OUT_DIR"
    written=$((written + 1))
  done
  errors=$(grep -c '"error"' "$STAGE/errors.json")
  mv -f "$STAGE/errors.json" "$OUT_DIR/" || die "cannot move errors.json to $OUT_DIR"
  if [ "$written" -gt 0 ]; then ok "$written oracle file(s) in $OUT_DIR"; else ko "no oracle file written"; status=1; fi
  if [ "$errors" -gt 0 ]; then ko "$errors case(s) in errors.json"; status=1; else ok "no error in errors.json"; fi
else
  ko "errors.json missing: the export did not complete, $OUT_DIR left unchanged"
  status=1
fi
exit "$status"
