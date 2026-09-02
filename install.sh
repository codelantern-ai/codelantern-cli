#!/usr/bin/env bash
#
# public/install.sh — install the `codelantern` CLI on macOS/Linux from a GitHub
# Release, assuming the repository's releases are PUBLIC (no authentication).
#
# For the private repository, use ../install.sh instead, which authenticates via
# the GitHub CLI (`gh`). This variant uses plain `curl` against the public
# `/releases/latest/download/` (or `/releases/download/<tag>/`) URLs and needs no
# `gh` and no token. It will fail with a download error if the release is not
# public.
#
# Usage:
#   ./install.sh [version]
#   VERSION=v0.1.0 ./install.sh        # pin a version (default: latest release)
#   PREFIX=/opt/bin ./install.sh       # install dir (default: ~/.local/bin)
set -euo pipefail

REPO="${REPO:-codelantern-ai/codelantern-cli}"

die()  { printf 'install.sh: %s\n' "$1" >&2; exit 1; }
warn() { printf 'install.sh: %s\n' "$1" >&2; }

# normalize_os <uname-s> -> darwin|linux (dies on anything else).
normalize_os() {
  case "$1" in
    Linux)  echo linux ;;
    Darwin) echo darwin ;;
    *) die "unsupported OS '$1'. On Windows use scripts/public/install.ps1 in PowerShell." ;;
  esac
}

# normalize_arch <uname-m> -> amd64|arm64 (dies on anything else).
normalize_arch() {
  case "$1" in
    x86_64|amd64)   echo amd64 ;;
    arm64|aarch64)  echo arm64 ;;
    *) die "unsupported architecture '$1' (need amd64 or arm64)." ;;
  esac
}

# sha256_of <file> -> hex digest, using whichever tool is present.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "no sha256 tool found (need sha256sum or shasum)."; fi
}

# verify_checksum <archive> <checksums-file> -> 0 if the archive's digest matches
# its entry in checksums.txt, non-zero otherwise. Does not exit (caller decides).
verify_checksum() {
  local archive="$1" checksums="$2" base computed expected
  base="$(basename "$archive")"
  computed="$(sha256_of "$archive")"
  expected="$(awk -v f="$base" '$2 == f {print $1}' "$checksums")"
  [ -n "$expected" ] && [ "$computed" = "$expected" ]
}

# fetch <url> <out> -> download a URL to a path, failing on any HTTP error.
fetch() {
  curl -fsSL "$1" -o "$2"
}

main() {
  local version prefix os arch base archive
  version="${VERSION:-${1:-}}"
  prefix="${PREFIX:-$HOME/.local/bin}"

  command -v curl >/dev/null 2>&1 || die "curl not found. Install curl and retry."
  os="$(normalize_os "$(uname -s)")"
  arch="$(normalize_arch "$(uname -m)")"

  # tmp is intentionally global: the EXIT trap runs after main returns, so a
  # `local tmp` would be out of scope there (and unbound under `set -u`).
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  if [ -n "$version" ]; then
    base="https://github.com/$REPO/releases/download/$version"
  else
    base="https://github.com/$REPO/releases/latest/download"
  fi

  # checksums.txt has a version-independent URL under both bases, so fetch it
  # first, then read the real (version-stamped) archive name for this host from it.
  fetch "$base/checksums.txt" "$tmp/checksums.txt" \
    || die "could not download checksums.txt from $base (is the release public?)."

  archive="$(awk '{print $2}' "$tmp/checksums.txt" | grep -E "_${os}_${arch}\.tar\.gz$" | head -n1)"
  [ -n "$archive" ] || die "no release asset found for ${os}/${arch}."

  fetch "$base/$archive" "$tmp/$archive" \
    || die "could not download $archive from $base."

  verify_checksum "$tmp/$archive" "$tmp/checksums.txt" \
    || die "checksum verification failed for $archive — aborting, nothing installed."

  tar -xzf "$tmp/$archive" -C "$tmp"
  [ -f "$tmp/codelantern" ] || die "codelantern binary not found in $archive."

  mkdir -p "$prefix"
  cp "$tmp/codelantern" "$prefix/codelantern"
  chmod +x "$prefix/codelantern"

  case ":$PATH:" in
    *":$prefix:"*) ;;
    *) warn "$prefix is not on your PATH. Add it: export PATH=\"$prefix:\$PATH\"" ;;
  esac

  printf 'install.sh: installed to %s/codelantern\n' "$prefix"
  "$prefix/codelantern" --version
}

# Run when executed as a file OR piped into bash (the `... | bash` install path);
# skip when sourced, so tests can load the functions. `${BASH_SOURCE[0]:-$0}` is
# unset when piped via stdin — default it to $0 so the install path still runs,
# and stays set -u safe.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  main "$@"
fi
