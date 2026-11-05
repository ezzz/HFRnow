#!/usr/bin/env bash
# Setup script for Claude Code cloud environments (Ubuntu 24.04, x86_64 or aarch64).
# Installs the Swift toolchain and SwiftLint used by the Linux CI so agents can run `swift test` and lint locally.
# Paste into the environment settings → Setup script. Needs download.swift.org, www.swift.org, github.com and
# release-assets.githubusercontent.com in Allowed domains.
set -euo pipefail

SWIFT_VERSION="6.2.4"
SWIFTLINT_VERSION="0.65.1"  # the version CI runs (ci.yml, ghcr.io/realm/swiftlint)

# SwiftLint, so agents lint before pushing (needs github.com and release-assets.githubusercontent.com).
if ! swiftlint version 2>/dev/null | grep -qx "${SWIFTLINT_VERSION}"; then
  case "$(uname -m)" in x86_64) SL_ARCH="amd64" ;; aarch64) SL_ARCH="arm64" ;; *) SL_ARCH="" ;; esac
  if [ -n "${SL_ARCH}" ]; then
    SL_TMP="$(mktemp -d)"
    curl -fsSL "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_${SL_ARCH}.zip" -o "${SL_TMP}/sl.zip"
    unzip -o -q "${SL_TMP}/sl.zip" swiftlint -d "${SL_TMP}"
    install -m 755 "${SL_TMP}/swiftlint" /usr/local/bin/swiftlint
    rm -rf "${SL_TMP}"
  fi
fi

if command -v swift >/dev/null 2>&1 && swift --version 2>/dev/null | grep -q "Swift version ${SWIFT_VERSION}"; then
  echo "Swift ${SWIFT_VERSION} already installed"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  binutils ca-certificates curl git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config \
  tzdata unzip zlib1g-dev

case "$(uname -m)" in
  x86_64) PLATFORM="ubuntu2404"; SUFFIX="ubuntu24.04" ;;
  aarch64) PLATFORM="ubuntu2404-aarch64"; SUFFIX="ubuntu24.04-aarch64" ;;
  *) echo "Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

NAME="swift-${SWIFT_VERSION}-RELEASE-${SUFFIX}"
BASE="https://download.swift.org/swift-${SWIFT_VERSION}-release/${PLATFORM}/swift-${SWIFT_VERSION}-RELEASE/${NAME}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "${BASE}.tar.gz" -o "${WORK}/swift.tar.gz"
curl -fsSL "${BASE}.tar.gz.sig" -o "${WORK}/swift.tar.gz.sig"

# Verify the toolchain signature with swift.org's published release keys.
export GNUPGHOME="${WORK}/gnupg"
mkdir -m 700 "$GNUPGHOME"
curl -fsSL https://www.swift.org/keys/all-keys.asc -o "${WORK}/keys.asc"
# swift.org may serve the key file gzip-compressed without saying so: unpack it when it is.
if gzip -t "${WORK}/keys.asc" 2>/dev/null; then gunzip -c "${WORK}/keys.asc" > "${WORK}/keys.txt" && mv "${WORK}/keys.txt" "${WORK}/keys.asc"; fi
# gpg 2.4 rejects the whole concatenated file because some old blocks do not import:
# import block by block, then require a valid signature anyway.
awk -v dir="${WORK}" '/BEGIN PGP PUBLIC KEY BLOCK/ { n++ } { print > (dir "/key-" n ".asc") }' "${WORK}/keys.asc"
for key in "${WORK}"/key-*.asc; do
  gpg --batch --quiet --import "$key" 2>/dev/null || true
done
gpg --batch --verify "${WORK}/swift.tar.gz.sig" "${WORK}/swift.tar.gz"

rm -rf "/opt/${NAME}"
tar -xzf "${WORK}/swift.tar.gz" -C /opt
ln -sf "/opt/${NAME}/usr/bin/"* /usr/local/bin/

swift --version
