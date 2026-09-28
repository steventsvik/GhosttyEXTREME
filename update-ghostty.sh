#!/usr/bin/env bash
# Move the `custom` branch onto the newest official Ghostty release and rebuild.
# Usage: ./update-ghostty.sh          (check + update + build)
#        ./update-ghostty.sh --check  (only report whether an update exists)
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted changes present — commit or stash them first." >&2
  exit 1
fi

git fetch upstream --tags --quiet

current=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' custom)
latest=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)

echo "Your base: $current"
echo "Latest official release: $latest"

if [[ "$current" == "$latest" ]]; then
  echo "Already up to date."
  exit 0
fi
[[ "${1:-}" == "--check" ]] && exit 0

git switch --quiet custom
git branch --force "backup-before-$latest" custom
if ! git rebase --onto "$latest" "$current" custom; then
  echo
  echo "Your changes conflict with $latest. Resolve them, then run: git rebase --continue"
  echo "To give up and go back: git rebase --abort (backup branch: backup-before-$latest)"
  exit 1
fi

zig_version=$(grep -o 'minimum_zig_version = "[^"]*"' build.zig.zon | cut -d'"' -f2)
# Homebrew's Zig bottles carry patches for newer Xcode SDKs; the ziglang.org
# tarballs of 0.15.x fail to link against the macOS 26.4+ SDKs.
zig_bin=""
for candidate in "/opt/homebrew/opt/zig@${zig_version%.*}/bin/zig" /opt/homebrew/bin/zig; do
  if [[ -x "$candidate" && "$("$candidate" version)" == "$zig_version" ]]; then
    zig_bin="$candidate"
    break
  fi
done
if [[ -z "$zig_bin" ]]; then
  echo "$latest needs Zig $zig_version. Try: brew install zig@${zig_version%.*}" >&2
  exit 1
fi

# The repo lives under ~/Desktop, where iCloud's File Provider tags new files
# with xattrs that codesign rejects. Keep Xcode's build output outside it.
build_cache="$HOME/Library/Caches/ghostty-extreme/macos-build"
if [[ ! -L macos/build ]]; then
  rm -rf macos/build
  mkdir -p "$build_cache"
  ln -s "$build_cache" macos/build
fi

"$zig_bin" build -Doptimize=ReleaseFast -Dxcframework-target=native
ditto macos/build/ReleaseLocal/Ghostty.app "/Applications/GhosttyEXTREME.app"
git push --force-with-lease origin custom
echo "Updated to $latest and rebuilt."
