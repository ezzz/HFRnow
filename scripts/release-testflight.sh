#!/usr/bin/env bash
# Archive, export and (optionally) upload a SwiftHFR build to TestFlight (LOT-161, docs/lots/LOT-161-release-pipeline.md).
#
#   scripts/release-testflight.sh --version 5.0 --build 1 --dry-run [--unsigned]   # stops before the upload
#   scripts/release-testflight.sh --version 5.0 --build 1 --upload                 # operator only: asks for confirmation
#
# Credentials (App Store Connect API key) and signing choices come from environment variables or from a local file
# outside the repository (default ~/.config/swifthfr/release.env, see scripts/release.env.example). Nothing secret is
# ever read from or written to the repository. Runs with the macOS bash 3.2: no associative arrays, no mapfile.
set -euo pipefail

# Highest legacy version found for the bundle id hfrplus.red.super (legacy SuperHFRplus.xcodeproj/project.pbxproj,
# target HFRswift, MARKETING_VERSION 4.0.3 / CURRENT_PROJECT_VERSION 36 on ezzz/HFRnow master @ 21173e77, lines 6056-6173). A SwiftHFR
# version must be strictly greater. The operator's decision on #251 sets the first upload; see the spec.
LEGACY_FLOOR_VERSION="4.0.3"
MIN_XCODE_MAJOR=27
SCHEME="SwiftHFR"
CONFIGURATION="Release"
INTEGRATION_BRANCH="dev-swift"

# ---------------------------------------------------------------- output helpers
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_KO=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_KO=""; C_DIM=""; C_OFF=""
fi
ok()   { printf '%s[ok]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
ko()   { printf '%s[ko]%s %s\n' "$C_KO" "$C_OFF" "$*" >&2; }
info() { printf '%s[..]%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
die()  { ko "$*"; exit 1; }

BG_PID=""
cleanup() { if [ -n "$BG_PID" ]; then kill "$BG_PID" 2>/dev/null || true; fi; }
trap cleanup EXIT
trap 'cleanup; ko "Interrupted."; exit 130' INT TERM

# Runs "$@" in the background with its output in a log file, showing a spinner on a TTY.
# Returns the command's exit status; prints the error lines of the log on failure.
run_step() {
  local label="$1" log="$2" rc=0 i=0 frames='|/-+'
  shift 2
  "$@" >"$log" 2>&1 &
  BG_PID=$!
  if [ -t 1 ]; then
    while kill -0 "$BG_PID" 2>/dev/null; do
      printf '\r%s[%s]%s %s' "$C_DIM" "${frames:i++%4:1}" "$C_OFF" "$label"
      sleep 0.2
    done
    printf '\r\033[K'
  else
    info "$label"
  fi
  wait "$BG_PID" || rc=$?
  BG_PID=""
  if [ "$rc" -ne 0 ]; then
    ko "$label failed (exit $rc). Log: $log"
    grep -E 'error:|\*\* [A-Z ]+ FAILED \*\*' "$log" | head -20 >&2 || true
    return "$rc"
  fi
  ok "$label"
}

usage() {
  cat <<'EOF'
Usage: scripts/release-testflight.sh --version X.Y[.Z] --build N (--dry-run | --upload) [options]

Required:
  --version X.Y[.Z]   CFBundleShortVersionString (MARKETING_VERSION); must exceed the legacy floor
  --build N[.N[.N]]   CFBundleVersion (CURRENT_PROJECT_VERSION); no default, chosen by the operator
  --dry-run           archive, check, export (if signed), write release notes, then stop before the upload
  --upload            same, then upload to App Store Connect after an interactive confirmation (operator only)

Options:
  --unsigned          archive with CODE_SIGNING_ALLOWED=NO and skip the export (dry run only)
  --since REF         first commit (exclusive) of the release notes' change list (default: last swifthfr-* tag)
  --output DIR        output folder (default: <repo>/build/release/<version>-<build>, git-ignored)
  --config FILE       local settings file (default: ${XDG_CONFIG_HOME:-~/.config}/swifthfr/release.env)
  -h, --help          this help

Settings (environment variables win over the config file; see scripts/release.env.example):
  HFR_ASC_KEY_ID, HFR_ASC_ISSUER_ID, HFR_ASC_KEY_PATH   App Store Connect API key (upload; path outside the repo)
  HFR_SIGNING_STYLE (manual|automatic), HFR_PROFILE_NAME, HFR_TEAM_ID                export signing
  HFR_ALLOW_PROVISIONING_UPDATES (0|1)  operator opt-in for automatic export signing; agents and CI never set it
  HFR_INTERNAL_ONLY (0|1)               mark the build "TestFlight internal testing only"
EOF
}

# ---------------------------------------------------------------- arguments
VERSION=""; BUILD=""; MODE=""; UNSIGNED=0; SINCE=""; OUTPUT=""
CONFIG="${HFR_RELEASE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/swifthfr/release.env}"
# Value of an option that takes one; fails clearly instead of a silent `shift 2` error under set -e.
need_value() { [ "$#" -ge 2 ] && [ -n "$2" ] || die "$1 needs a value."; }
while [ $# -gt 0 ]; do
  case "$1" in
    --version) need_value "$@"; VERSION="$2"; shift 2 ;;
    --build) need_value "$@"; BUILD="$2"; shift 2 ;;
    --dry-run) [ -z "$MODE" ] || [ "$MODE" = dry-run ] || die "--dry-run and --upload are exclusive."; MODE="dry-run"; shift ;;
    --upload) [ -z "$MODE" ] || [ "$MODE" = upload ] || die "--dry-run and --upload are exclusive."; MODE="upload"; shift ;;
    --unsigned) UNSIGNED=1; shift ;;
    --since) need_value "$@"; SINCE="$2"; shift 2 ;;
    --output) need_value "$@"; OUTPUT="$2"; shift 2 ;;
    --config) need_value "$@"; CONFIG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown argument: $1" ;;
  esac
done
[ -n "$MODE" ] || { usage >&2; die "Choose --dry-run or --upload."; }
[ -n "$VERSION" ] || die "--version is required (no default: the operator chooses it on #251)."
[ -n "$BUILD" ] || die "--build is required (no default: the operator chooses it on #251)."
[ "$MODE" = dry-run ] || [ "$UNSIGNED" -eq 0 ] || die "--unsigned is for --dry-run only: an unsigned archive cannot be uploaded."

# ---------------------------------------------------------------- version rules
is_version() { printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; }
# Succeeds when version $1 > version $2 (numeric, missing components count as 0).
version_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"
  IFS=. read -r b1 b2 b3 <<<"$2"
  a1=$((10#${a1:-0})); a2=$((10#${a2:-0})); a3=$((10#${a3:-0}))
  b1=$((10#${b1:-0})); b2=$((10#${b2:-0})); b3=$((10#${b3:-0}))
  [ "$a1" -ne "$b1" ] && { [ "$a1" -gt "$b1" ]; return; }
  [ "$a2" -ne "$b2" ] && { [ "$a2" -gt "$b2" ]; return; }
  [ "$a3" -gt "$b3" ]
}
is_version "$VERSION" || die "--version must look like 5 or 5.0 or 5.0.1 (got '$VERSION')."
is_version "$BUILD" || die "--build must be one to three dot-separated integers (got '$BUILD')."
version_gt "$VERSION" "$LEGACY_FLOOR_VERSION" \
  || die "Version $VERSION does not exceed the legacy floor $LEGACY_FLOOR_VERSION (App Store Connect refuses a lower version)."
ok "Version $VERSION ($BUILD) exceeds the legacy floor $LEGACY_FLOOR_VERSION"

# ---------------------------------------------------------------- local settings (outside the repo)
# Reads KEY=VALUE lines for known keys only; the file is never sourced, so it cannot run code.
load_config() {
  local file="$1" line key val
  [ -f "$file" ] || { info "No local settings file at $file (environment variables only)."; return 0; }
  if [ -n "$(find "$file" \( -perm -040 -o -perm -004 \) 2>/dev/null)" ]; then
    warn "$file is readable by group or others: chmod 600 it."
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    case "$key" in
      HFR_ASC_KEY_ID|HFR_ASC_ISSUER_ID|HFR_ASC_KEY_PATH|HFR_SIGNING_STYLE|HFR_PROFILE_NAME|HFR_TEAM_ID|HFR_ALLOW_PROVISIONING_UPDATES|HFR_INTERNAL_ONLY)
        if [ -z "${!key:-}" ]; then printf -v "$key" '%s' "$val"; fi ;;
      *) warn "Ignoring unknown key '$key' in $file." ;;
    esac
  done <"$file"
  ok "Loaded local settings from $file"
}
load_config "$CONFIG"
HFR_ASC_KEY_ID="${HFR_ASC_KEY_ID:-}"; HFR_ASC_ISSUER_ID="${HFR_ASC_ISSUER_ID:-}"; HFR_ASC_KEY_PATH="${HFR_ASC_KEY_PATH:-}"
HFR_SIGNING_STYLE="${HFR_SIGNING_STYLE:-manual}"; HFR_PROFILE_NAME="${HFR_PROFILE_NAME:-}"; HFR_TEAM_ID="${HFR_TEAM_ID:-}"
HFR_ALLOW_PROVISIONING_UPDATES="${HFR_ALLOW_PROVISIONING_UPDATES:-0}"; HFR_INTERNAL_ONLY="${HFR_INTERNAL_ONLY:-0}"
# A literal "~/" from the config file (the file is not sourced, so the shell did not expand it).
# shellcheck disable=SC2088
case "$HFR_ASC_KEY_PATH" in "~/"*) HFR_ASC_KEY_PATH="$HOME/${HFR_ASC_KEY_PATH#\~/}" ;; esac
case "$HFR_SIGNING_STYLE" in manual|automatic) ;; *) die "HFR_SIGNING_STYLE must be manual or automatic." ;; esac
case "$HFR_ALLOW_PROVISIONING_UPDATES" in 0|1) ;; *) die "HFR_ALLOW_PROVISIONING_UPDATES must be 0 or 1." ;; esac
case "$HFR_INTERNAL_ONLY" in 0|1) ;; *) die "HFR_INTERNAL_ONLY must be 0 or 1." ;; esac

# ---------------------------------------------------------------- preflight
command -v xcodebuild >/dev/null || die "xcodebuild not found: run on the maintainer's Mac with Xcode installed."
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run from inside the SwiftHFR repository."
cd "$REPO_ROOT"
[ -d App/SwiftHFR.xcodeproj ] || die "App/SwiftHFR.xcodeproj not found: is this the dev-swift tree?"

XCODE_VERSION="$(xcodebuild -version | awk 'NR==1 {print $2}')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
[ "${XCODE_MAJOR:-0}" -ge "$MIN_XCODE_MAJOR" ] 2>/dev/null \
  || die "Xcode $XCODE_VERSION found; the iOS 27 target needs Xcode $MIN_XCODE_MAJOR or later."
ok "Xcode $XCODE_VERSION ($(xcode-select -p))"

# Release preconditions: hard failures before an upload, warnings in a dry run.
precondition() {
  if [ "$MODE" = upload ]; then die "$1"; else warn "$1 (allowed in a dry run, refused with --upload)"; fi
}
BRANCH="$(git branch --show-current)"
if [ "$BRANCH" = "$INTEGRATION_BRANCH" ]; then
  ok "On $INTEGRATION_BRANCH"
else
  precondition "On branch '${BRANCH:-detached}', not $INTEGRATION_BRANCH."
fi
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  precondition "Working tree not clean (git status shows changes): a release builds committed code only."
else
  ok "Working tree clean"
fi
if git fetch -q origin "$INTEGRATION_BRANCH" 2>/dev/null; then
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$INTEGRATION_BRANCH")" ]; then
    ok "HEAD is origin/$INTEGRATION_BRANCH ($(git rev-parse --short HEAD))"
  else
    precondition "HEAD $(git rev-parse --short HEAD) is not origin/$INTEGRATION_BRANCH $(git rev-parse --short "origin/$INTEGRATION_BRANCH")."
  fi
else
  precondition "Could not fetch origin/$INTEGRATION_BRANCH to compare with HEAD."
fi
COMMIT="$(git rev-parse --short HEAD)"

# Upload credentials: required for --upload, reported in a dry run.
inside_repo() {
  local dir
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  case "$dir/" in "$REPO_ROOT/"*) return 0 ;; *) return 1 ;; esac
}
CREDS_OK=1
[ -n "$HFR_ASC_KEY_ID" ] || { CREDS_OK=0; precondition "HFR_ASC_KEY_ID is not set."; }
[ -n "$HFR_ASC_ISSUER_ID" ] || { CREDS_OK=0; precondition "HFR_ASC_ISSUER_ID is not set."; }
if [ -z "$HFR_ASC_KEY_PATH" ]; then
  CREDS_OK=0; precondition "HFR_ASC_KEY_PATH is not set."
elif [ ! -f "$HFR_ASC_KEY_PATH" ]; then
  CREDS_OK=0; precondition "API key file not found at HFR_ASC_KEY_PATH."
elif inside_repo "$HFR_ASC_KEY_PATH"; then
  die "The API key file is inside the repository: move it outside (ADR 0007, AGENTS.md ground rule 4)."
fi
if [ "$CREDS_OK" -eq 1 ]; then ok "App Store Connect API key settings present (key file outside the repository)"; fi
if [ "$HFR_SIGNING_STYLE" = manual ] && [ -z "$HFR_PROFILE_NAME" ] && [ "$UNSIGNED" -eq 0 ]; then
  precondition "HFR_SIGNING_STYLE=manual needs HFR_PROFILE_NAME (the App Store provisioning profile for the app)."
fi

OUTPUT="${OUTPUT:-$REPO_ROOT/build/release/$VERSION-$BUILD}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd -P)"
ARCHIVE="$OUTPUT/SwiftHFR-$VERSION-$BUILD.xcarchive"
EXPORT_DIR="$OUTPUT/export"
EXPORT_PLIST="$OUTPUT/ExportOptions.plist"
NOTES="$OUTPUT/release-notes-$VERSION-$BUILD.md"
[ ! -e "$ARCHIVE" ] || die "$ARCHIVE already exists: remove it or pick another --output."
info "Output: $OUTPUT"

# xcodebuild arguments for the operator's opt-in automatic signing (never used by agents or CI).
AUTH_ARGS=()
if [ "$HFR_ALLOW_PROVISIONING_UPDATES" = 1 ]; then
  [ "$CREDS_OK" -eq 1 ] || die "HFR_ALLOW_PROVISIONING_UPDATES=1 needs the App Store Connect API key settings."
  AUTH_ARGS=(-allowProvisioningUpdates -authenticationKeyPath "$HFR_ASC_KEY_PATH"
    -authenticationKeyID "$HFR_ASC_KEY_ID" -authenticationKeyIssuerID "$HFR_ASC_ISSUER_ID")
  warn "Provisioning updates allowed (operator opt-in): xcodebuild may create or update profiles."
fi

# ---------------------------------------------------------------- archive
ARCHIVE_ARGS=(xcodebuild archive -project App/SwiftHFR.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION"
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUTPUT/DerivedData"
  "MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD")
if [ "$UNSIGNED" -eq 1 ]; then
  ARCHIVE_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  warn "Unsigned archive: validates the build and the archive layout, cannot be exported or uploaded."
else
  ARCHIVE_ARGS+=("${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}")
fi
run_step "Archive $SCHEME $VERSION ($BUILD), $CONFIGURATION, generic iOS" "$OUTPUT/archive.log" "${ARCHIVE_ARGS[@]}"

APP_PATH="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP_PATH" ] || die "No .app in $ARCHIVE/Products/Applications."
plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
GOT_VERSION="$(plist_get "$APP_PATH/Info.plist" CFBundleShortVersionString)"
GOT_BUILD="$(plist_get "$APP_PATH/Info.plist" CFBundleVersion)"
BUNDLE_ID="$(plist_get "$APP_PATH/Info.plist" CFBundleIdentifier)"
[ "$GOT_VERSION" = "$VERSION" ] && [ "$GOT_BUILD" = "$BUILD" ] \
  || die "Archived app says $GOT_VERSION ($GOT_BUILD), expected $VERSION ($BUILD)."
ok "Archived Info.plist: $BUNDLE_ID $GOT_VERSION ($GOT_BUILD)"
if [ "$(plist_get "$APP_PATH/Info.plist" ITSAppUsesNonExemptEncryption)" = "false" ]; then
  ok "ITSAppUsesNonExemptEncryption = NO (LOT-160)"
else
  warn "ITSAppUsesNonExemptEncryption missing or not NO: App Store Connect will ask the export question."
fi
[ -f "$APP_PATH/PrivacyInfo.xcprivacy" ] || die "PrivacyInfo.xcprivacy missing from the archived app."
ok "PrivacyInfo.xcprivacy in the bundle (LOT-160)"
if [ "$UNSIGNED" -eq 0 ]; then
  if codesign --verify --strict "$APP_PATH" 2>/dev/null; then ok "Archive signature verifies"; else die "codesign cannot verify $APP_PATH."; fi
fi

# ---------------------------------------------------------------- export options
plutil -create xml1 "$EXPORT_PLIST"
plutil -insert method -string app-store-connect "$EXPORT_PLIST"
plutil -insert destination -string export "$EXPORT_PLIST"
plutil -insert manageAppVersionAndBuildNumber -bool NO "$EXPORT_PLIST"
plutil -insert uploadSymbols -bool YES "$EXPORT_PLIST"
plutil -insert signingStyle -string "$HFR_SIGNING_STYLE" "$EXPORT_PLIST"
if [ "$HFR_INTERNAL_ONLY" = 1 ]; then plutil -insert testFlightInternalTestingOnly -bool YES "$EXPORT_PLIST"; fi
if [ -n "$HFR_TEAM_ID" ]; then plutil -insert teamID -string "$HFR_TEAM_ID" "$EXPORT_PLIST"; fi
if [ "$HFR_SIGNING_STYLE" = manual ] && [ -n "$HFR_PROFILE_NAME" ]; then
  plutil -insert signingCertificate -string "Apple Distribution" "$EXPORT_PLIST"
  plutil -insert provisioningProfiles -dictionary "$EXPORT_PLIST"
  plutil -insert "provisioningProfiles.${BUNDLE_ID//./\\.}" -string "$HFR_PROFILE_NAME" "$EXPORT_PLIST"
fi
plutil -lint -s "$EXPORT_PLIST"
ok "ExportOptions.plist (app-store-connect, $HFR_SIGNING_STYLE signing): $EXPORT_PLIST"

# ---------------------------------------------------------------- export
IPA=""
if [ "$UNSIGNED" -eq 1 ]; then
  warn "Export skipped (unsigned archive)."
else
  run_step "Export for App Store Connect" "$OUTPUT/export.log" \
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" -exportOptionsPlist "$EXPORT_PLIST" \
    "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}"
  IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print -quit)"
  [ -n "$IPA" ] || die "No .ipa in $EXPORT_DIR."
  ok "IPA: $IPA ($(du -h "$IPA" | awk '{print $1}'))"
fi

# ---------------------------------------------------------------- release notes
if [ -z "$SINCE" ]; then
  SINCE="$(git describe --tags --abbrev=0 --match 'swifthfr-*' 2>/dev/null || true)"
fi
TEMPLATE="$REPO_ROOT/scripts/release-notes.template.md"
[ -f "$TEMPLATE" ] || die "Release notes template not found: $TEMPLATE"
{
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "{{CHANGES}}" ]; then
      if [ -n "$SINCE" ]; then
        git log --no-merges --format='- %s (%h)' "$SINCE..HEAD"
      else
        echo "- (first SwiftHFR build: no previous swifthfr-* tag; pass --since <ref> to list changes)"
      fi
      continue
    fi
    line="${line//\{\{VERSION\}\}/$VERSION}"
    line="${line//\{\{BUILD\}\}/$BUILD}"
    line="${line//\{\{COMMIT\}\}/$COMMIT}"
    line="${line//\{\{SINCE\}\}/${SINCE:-none}}"
    printf '%s\n' "$line"
  done <"$TEMPLATE"
} >"$NOTES"
ok "Release notes draft: $NOTES (edit the French sections before pasting them in TestFlight)"

# ---------------------------------------------------------------- upload (operator only)
TAG="swifthfr-$VERSION-$BUILD"
if [ "$MODE" = dry-run ]; then
  ok "Dry run complete: stopped before the upload. Nothing was sent to Apple."
  exit 0
fi

[ -n "$IPA" ] || die "No IPA to upload."
[ -r /dev/tty ] || die "The upload needs an interactive terminal for its confirmation."
printf '\n%sAbout to upload%s %s %s (%s), commit %s, to App Store Connect.\n' "$C_WARN" "$C_OFF" "$BUNDLE_ID" "$VERSION" "$BUILD" "$COMMIT"
printf 'A build number can be uploaded only once. Type "upload %s (%s)" to confirm: ' "$VERSION" "$BUILD"
read -r answer </dev/tty
[ "$answer" = "upload $VERSION ($BUILD)" ] || die "Not confirmed: nothing uploaded."

run_step "Upload to App Store Connect" "$OUTPUT/upload.log" \
  xcrun altool --upload-package "$IPA" --api-key "$HFR_ASC_KEY_ID" --api-issuer "$HFR_ASC_ISSUER_ID" \
  --p8-file-path "$HFR_ASC_KEY_PATH" --output-format normal
grep -iE 'delivery|uuid|success' "$OUTPUT/upload.log" | head -5 || true
ok "Uploaded $VERSION ($BUILD). Next (by hand): record the build on the LOT-161 PR or issue, paste the release notes"
ok "in TestFlight, and tag the commit: git tag $TAG $COMMIT && git push origin $TAG (operator-confirmed)."
