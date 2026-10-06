#!/bin/zsh
# Builds a GhosttyEXTREME release, checks it, and creates a draft release on GitHub.
#
#   ./release.sh check 1.5.0    build and check everything; nothing leaves this Mac
#   ./release.sh draft 1.5.0    the same, then a *draft* release (nobody is notified)
#
# Publish the draft from GitHub once you've looked at it. The notes come from the
# "## 1.5.0" section of CHANGELOG.md. `draft` only runs on `custom`, clean and pushed,
# so a release always matches what's on GitHub.
set -u
setopt pipefail

MODE=${1:-}
VERSION=${2:-}
REPO=steventsvik/GhosttyEXTREME
TAG="extreme-$VERSION"
ROOT=${0:A:h}
OUT=/private/tmp/ghostty-extreme-release/$VERSION
ZIG=/opt/homebrew/opt/zig@0.15/bin/zig

if [[ ( $MODE != check && $MODE != draft ) || ! $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "usage: ./release.sh check|draft <version>   e.g. ./release.sh check 1.5.0"; exit 2
fi

step() { print -P "\n%F{yellow}▸ $1%f"; }
pass() { print -P "  %F{green}✓%f $1"; }
fail() { print -P "  %F{red}✗ $1%f"; exit 1; }

cd $ROOT

# ── Source ──────────────────────────────────────────────────────────────
step "Source"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ -z $(git status --porcelain) ]] || fail "uncommitted changes; commit or stash them first"
pass "working tree clean ($BRANCH @ $(git rev-parse --short HEAD))"
git fetch -q origin --tags || fail "couldn't reach GitHub"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists"
pass "$TAG is a new version"
if [[ $MODE == draft ]]; then
  [[ $BRANCH == custom ]] || fail "drafts are made from custom (you're on $BRANCH); merge your work first"
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/custom) ]] || fail "custom isn't pushed (or is behind origin)"
  pass "custom is pushed"
fi
section() { awk -v v="## $1" '$0==v {on=1; next} on && /^## / {exit} on' CHANGELOG.md; }
NOTES_BODY=$(section $VERSION)
if [[ -z ${NOTES_BODY//[[:space:]]/} && $MODE == check ]]; then
  NOTES_BODY=$(section Unreleased)
  [[ -n ${NOTES_BODY//[[:space:]]/} ]] && pass "release notes: using \"## Unreleased\" (rename it to \"## $VERSION\" before drafting)"
fi
[[ -n ${NOTES_BODY//[[:space:]]/} ]] || fail "CHANGELOG.md has no \"## $VERSION\" section"
[[ $MODE == draft ]] && pass "release notes found in CHANGELOG.md"
PREV=$(git tag --sort=-v:refname | grep '^extreme-' | head -1)

# ── Secrets ─────────────────────────────────────────────────────────────
step "Secrets in changes since $PREV"
PATTERNS='(sk-(ant|proj)-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-[A-Za-z0-9-]{10,})'
if git diff "$PREV"..HEAD | grep -E '^\+' | grep -Eq "$PATTERNS"; then
  git diff "$PREV"..HEAD | grep -E '^\+' | grep -En "$PATTERNS" | cut -c1-120
  fail "something that looks like a key or token was added"
fi
pass "no keys or tokens added"
if git diff "$PREV"..HEAD | grep -E '^\+' | grep -v '^+++' | grep -q "/Users/$USER"; then
  git diff "$PREV"..HEAD | grep -E '^\+' | grep -v '^+++' | grep -n "/Users/$USER" | cut -c1-120
  fail "a path inside your home folder was added to the code"
fi
pass "no paths to your home folder added"

# ── Build ───────────────────────────────────────────────────────────────
step "Build (a few minutes)"
mkdir -p $OUT
ZIG_GLOBAL_CACHE_DIR=/private/tmp/gx-zig-global ZIG_LOCAL_CACHE_DIR=/private/tmp/gx-zig-local \
  $ZIG build -Doptimize=ReleaseFast -Dxcframework-target=native -Demit-macos-app=false > $OUT/zig.log 2>&1 \
  || { tail -20 $OUT/zig.log; fail "core build failed (log: $OUT/zig.log)"; }
pass "core library"
(cd macos && xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal \
  SYMROOT="$PWD/build" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > $OUT/xcode.log 2>&1) \
  || { grep -E "error:" $OUT/xcode.log | head -10; fail "app build failed (log: $OUT/xcode.log)"; }
pass "app"
LINT=$(cd macos && swiftlint lint --quiet 2>/dev/null | grep -c ' error: ')
[[ $LINT == 0 ]] || fail "SwiftLint: $LINT errors"
pass "SwiftLint: 0 errors"
for js in macos/EditorWeb/*.js; do node --check $js || fail "$js has a syntax error"; done
pass "editor scripts parse"

# ── Package ─────────────────────────────────────────────────────────────
step "Package"
APP=$OUT/GhosttyEXTREME.app
rm -rf $APP $OUT/*.zip $OUT/GhosttyEXTREME-agent-hooks
ditto macos/build/ReleaseLocal/Ghostty.app $APP
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" $APP/Contents/Info.plist
# Debug info carries the build machine's paths; the release doesn't need it.
find $APP -type f -perm +111 -exec sh -c 'file "$1" | grep -q Mach-O && strip -S -x "$1" 2>/dev/null; true' _ {} \;
LEAKS=$(LC_ALL=C grep -rl -a "/Users/$USER" $APP | wc -l | xargs)
[[ $LEAKS == 0 ]] || { LC_ALL=C grep -rl -a "/Users/$USER" $APP | head -5; fail "$LEAKS files in the app contain your home path"; }
pass "no home-folder paths in the app"
codesign --force --deep --sign - $APP 2>/dev/null && codesign --verify --deep --strict $APP || fail "signing failed"
pass "signed (ad hoc) and verified"
[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist) == $VERSION ]] || fail "version not set"
pass "version $VERSION"

HOOKS=$OUT/GhosttyEXTREME-agent-hooks
mkdir -p $HOOKS
for f in agent-hook.sh ghostty-extreme.zsh install.sh localhost localhost-run codex-hook.py install-codex.py; do
  git show HEAD:agent-hooks/$f > $HOOKS/$f || fail "agent-hooks/$f missing"
done
chmod +x $HOOKS/{agent-hook.sh,install.sh,localhost,localhost-run,codex-hook.py,install-codex.py}
grep -rqE "/Users/|$USER" $HOOKS && fail "the hooks contain a personal path or name"
for f in $HOOKS/*.sh $HOOKS/localhost $HOOKS/localhost-run; do bash -n $f || fail "$f has a syntax error"; done
for f in $HOOKS/*.py; do python3 -m py_compile $f || fail "$f has a syntax error"; done
pass "agent hooks (checked, no personal paths)"

# ── Launch test ─────────────────────────────────────────────────────────
step "Launch test"
TEST=$OUT/LaunchTest.app
rm -rf $TEST && ditto $APP $TEST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.steventsvik.ghostty-extreme.releasetest" $TEST/Contents/Info.plist
codesign --force --deep --sign - $TEST 2>/dev/null
CRASHES_BEFORE=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -ci ghostty)
# In the background: it starts without taking focus or opening a window in front of you.
env -i HOME=$HOME USER=$USER PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/open -gna $TEST --args --window-save-state=never
sleep 12
PID=$(pgrep -f "^$TEST/Contents/MacOS/ghostty" | head -1)
[[ -n $PID ]] || fail "the app quit or crashed on launch"
CPU=$(ps -o %cpu= -p $PID | xargs)
pkill -f "^$TEST/Contents/MacOS/ghostty"; sleep 1; rm -rf $TEST
[[ $(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -ci ghostty) == $CRASHES_BEFORE ]] || fail "a crash report appeared"
pass "launched and stayed up (idle CPU ${CPU}%), no crash report"

# ── Archives and notes ──────────────────────────────────────────────────
step "Archives"
APPZIP=GhosttyEXTREME-$VERSION-macos-arm64.zip
HOOKZIP=GhosttyEXTREME-$VERSION-agent-hooks.zip
(cd $OUT && ditto -c -k --keepParent GhosttyEXTREME.app $APPZIP && ditto -c -k --keepParent GhosttyEXTREME-agent-hooks $HOOKZIP)
APPSHA=$(shasum -a 256 $OUT/$APPZIP | cut -d' ' -f1)
HOOKSHA=$(shasum -a 256 $OUT/$HOOKZIP | cut -d' ' -f1)
UPSTREAM=$(git tag --merged HEAD --sort=-v:refname | grep -E '^v[0-9]' | head -1 | sed 's/^v//')
cat > $OUT/notes.md <<NOTES
$NOTES_BODY

## Install

Apple silicon Macs only, macOS 13 or newer. Based on **Ghostty $UPSTREAM**.

1. Download \`$APPZIP\`, unzip it, and move \`GhosttyEXTREME.app\` to \`/Applications\` (replacing an older version if you have one).
2. The app isn't signed with an Apple Developer ID or notarized, so macOS blocks the first launch. Clear the download quarantine once:
   \`\`\`sh
   xattr -dr com.apple.quarantine /Applications/GhosttyEXTREME.app
   \`\`\`
3. For agent status and everything built on it, download \`$HOOKZIP\`, unzip it, and run:
   \`\`\`sh
   ./GhosttyEXTREME-agent-hooks/install.sh
   python3 ./GhosttyEXTREME-agent-hooks/install-codex.py   # if you use Codex
   \`\`\`
   Connect Claude Code as described in the [README](https://github.com/$REPO#agent-status-setup).

Your existing Ghostty configuration (\`~/.config/ghostty/config\`) works as-is.

SHA-256:
- \`$APPZIP\`: \`$APPSHA\`
- \`$HOOKZIP\`: \`$HOOKSHA\`

---

Not affiliated with or endorsed by the Ghostty project. AGPL-3.0; Ghostty's code is MIT. See [NOTICE.md](https://github.com/$REPO/blob/custom/NOTICE.md) for credits.
NOTES
pass "$APPZIP ($(du -h $OUT/$APPZIP | cut -f1 | xargs))"
pass "$HOOKZIP"
pass "notes: $OUT/notes.md"

if [[ $MODE == check ]]; then
  print -P "\n%F{green}All checks passed.%f Nothing was published. Files are in $OUT"
  print "When it's merged into custom and pushed: ./release.sh draft $VERSION"
  exit 0
fi

# ── Draft ───────────────────────────────────────────────────────────────
step "Draft release"
URL=$(gh release create $TAG -R $REPO --draft --target $(git rev-parse HEAD) --title "GhosttyEXTREME $VERSION" \
  --notes-file $OUT/notes.md $OUT/$APPZIP $OUT/$HOOKZIP) || fail "couldn't create the draft"
pass "draft created (not visible to anyone else yet)"
print -P "\n%F{green}Review it here, then press Publish:%f\n  $URL"
