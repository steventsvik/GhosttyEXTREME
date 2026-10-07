#!/bin/bash
# Installs or updates GhosttyEXTREME from the latest release on GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/steventsvik/GhosttyEXTREME/custom/install.sh | bash
#
# Downloads the app, checks it against the release's SHA-256 checksum, and puts it in
# /Applications (keeping the old copy until the new one is in place). Downloaded this way,
# macOS doesn't quarantine it, so there's no "can't be opened" step. Nothing else on the
# Mac is changed: the app's welcome window sets up agent status when it first opens.

set -euo pipefail

REPO=steventsvik/GhosttyEXTREME
DEST=${GHOSTTY_EXTREME_INSTALL_TO:-/Applications}/GhosttyEXTREME.app

say() { printf '%s\n' "$*"; }
die() { printf 'GhosttyEXTREME: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "this is a macOS app."
[ "$(uname -m)" = arm64 ] || die "only Apple silicon Macs are supported for now (https://github.com/$REPO/issues/7)."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || die "macOS 13 or newer is needed (this Mac has $(sw_vers -productVersion))."

if pgrep -qf "$DEST/Contents/MacOS/"; then
  die "GhosttyEXTREME is running. Quit it (⌘Q), then run this again."
fi

work=$(mktemp -d /tmp/ghostty-extreme-install.XXXXXX)
trap 'rm -rf "$work"' EXIT

say "Finding the latest release…"
curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest" -o "$work/release.json" \
  || die "couldn't reach GitHub."
json() { plutil -extract "$1" raw -o - "$work/release.json" 2>/dev/null; }
tag=$(json tag_name) || die "no published release found."
version=${tag#extreme-}

zip_url=""; zip_name=""; sums_url=""
i=0
while name=$(json "assets.$i.name"); do
  url=$(json "assets.$i.browser_download_url")
  case "$name" in
    *-macos-arm64.zip) zip_url=$url; zip_name=$name ;;
    SHA256SUMS) sums_url=$url ;;
  esac
  i=$((i + 1))
done
[ -n "$zip_url" ] || die "release $tag has no app download."

say "Downloading GhosttyEXTREME ${version}…"
curl -fL --progress-bar "$zip_url" -o "$work/$zip_name" || die "download failed."

# The checksum comes from the release's SHA256SUMS file, or its notes for older releases.
if [ -n "$sums_url" ]; then
  curl -fsSL "$sums_url" -o "$work/SHA256SUMS" || die "couldn't download the checksums."
  expected=$(awk -v f="$zip_name" '$2 == f || $2 == "*" f {print $1}' "$work/SHA256SUMS")
else
  expected=$(json body | grep -F "$zip_name" | grep -oE '[0-9a-f]{64}' | head -1 || true)
fi
[ -n "$expected" ] || die "release $tag doesn't list a checksum for $zip_name; not installing it."
actual=$(shasum -a 256 "$work/$zip_name" | awk '{print $1}')
[ "$actual" = "$expected" ] || die "the download doesn't match its checksum; not installing it."
say "Checksum verified."

ditto -x -k "$work/$zip_name" "$work/unpacked" || die "couldn't unpack the download."
[ -d "$work/unpacked/GhosttyEXTREME.app" ] || die "the download doesn't contain GhosttyEXTREME.app."
xattr -dr com.apple.quarantine "$work/unpacked/GhosttyEXTREME.app" 2>/dev/null || true

# Swap in the new copy; put the old one back if that fails.
if [ -d "$DEST" ]; then
  mv "$DEST" "$work/previous.app" || die "couldn't move the old copy aside (is /Applications writable?)."
fi
if ! mv "$work/unpacked/GhosttyEXTREME.app" "$DEST"; then
  [ -d "$work/previous.app" ] && mv "$work/previous.app" "$DEST"
  die "couldn't put the app in /Applications."
fi

say "Installed GhosttyEXTREME ${version} in /Applications."
say "Opening it: the welcome window connects Claude Code and Codex. Later versions arrive"
say "through GhosttyEXTREME > Check for Updates…"
[ -n "${GHOSTTY_EXTREME_INSTALL_TO:-}" ] || open "$DEST"
