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
zig_bin="$HOME/.local/zig/zig-aarch64-macos-$zig_version/zig"
if [[ ! -x "$zig_bin" ]]; then
  echo "$latest needs Zig $zig_version, which isn't installed at $zig_bin." >&2
  exit 1
fi

"$zig_bin" build -Doptimize=ReleaseFast
git push --force-with-lease origin custom
echo "Updated to $latest and rebuilt."
