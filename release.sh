#!/bin/zsh
# Builds a GhosttyEXTREME release, checks it, and creates a draft release on GitHub.
#
#   ./release.sh check 1.5.0    build and check everything; nothing leaves this Mac
#   ./release.sh draft 1.5.0    the same, then a *draft* release (nobody is notified)
#   ./release.sh keys           one-time: the update-signing key and the code-signing
#                               certificate, both kept in your login keychain
#
# Every release publishes appcast.xml, the feed the app's updater reads (signed with the
# update key, so only your builds are ever offered), and SHA256SUMS, which install.sh checks.
#
# Publish the draft from GitHub once you've looked at it. The notes come from the
# "## 1.5.0" section of CHANGELOG.md. `draft` only runs on `custom`, clean and pushed,
# so a release always matches what's on GitHub.
set -u
setopt pipefail

MODE=${1:-}
VERSION=${2:-}
REPO=steventsvik/GhosttyEXTREME
# The update key's name in the keychain, and the code-signing certificate's.
KEY_ACCOUNT=GhosttyEXTREME
SIGN_ID="GhosttyEXTREME Release"
# Ghostty's own update key: an app that still trusts it would accept official Ghostty builds.
GHOSTTY_ED_KEY="wsNcGf5hirwtdXMVnYoxRIX/SqZQLMOsYlD3q3imeok="
sparkle_tool() {
  find ~/Library/Developer/Xcode/DerivedData -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$1" -type f 2>/dev/null | head -1
}
TAG="extreme-$VERSION"
ROOT=${0:A:h}
OUT=/private/tmp/ghostty-extreme-release/$VERSION
ZIG=/opt/homebrew/opt/zig@0.15/bin/zig

step() { print -P "\n%F{yellow}▸ $1%f"; }
pass() { print -P "  %F{green}✓%f $1"; }
fail() { print -P "  %F{red}✗ $1%f"; exit 1; }

cd $ROOT

# ── One-time setup ──────────────────────────────────────────────────────
if [[ $MODE == keys ]]; then
  GENERATE=$(sparkle_tool generate_keys)
  [[ -n $GENERATE ]] || fail "Sparkle's tools aren't built yet; build the app once in Xcode first"
  step "Update-signing key"
  # Creates the key in the login keychain the first time; prints the public key either way.
  $GENERATE --account $KEY_ACCOUNT >/dev/null || fail "couldn't create the update key"
  PUBLIC=$($GENERATE --account $KEY_ACCOUNT -p) || fail "couldn't read the update key"
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC" macos/Ghostty-Info.plist
  pass "key \"$KEY_ACCOUNT\" in your keychain; its public half is now in Ghostty-Info.plist (commit that)"
  print "  Back the private key up: $GENERATE --account $KEY_ACCOUNT -x ~/ghostty-extreme-update-key.txt"
  print "  (keep that file somewhere safe and offline; without the key, installed copies can't update)"
  step "Code-signing certificate"
  if security find-identity -v -p codesigning | grep -q "\"$SIGN_ID\""; then
    pass "\"$SIGN_ID\" already exists"
  else
    TMP=$(mktemp -d)
    cat > $TMP/cert.cnf <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_ID
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config $TMP/cert.cnf \
      -keyout $TMP/key.pem -out $TMP/cert.pem 2>/dev/null || fail "couldn't create the certificate"
    PASS=$(openssl rand -hex 16)
    openssl pkcs12 -export -legacy -inkey $TMP/key.pem -in $TMP/cert.pem -name "$SIGN_ID" \
      -out $TMP/cert.p12 -passout pass:$PASS 2>/dev/null \
      || openssl pkcs12 -export -inkey $TMP/key.pem -in $TMP/cert.pem -name "$SIGN_ID" -out $TMP/cert.p12 -passout pass:$PASS
    security import $TMP/cert.p12 -k ~/Library/Keychains/login.keychain-db -P $PASS -T /usr/bin/codesign >/dev/null \
      || fail "couldn't add the certificate to your keychain"
    print "  macOS now asks for your password to trust it for code signing:"
    security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db $TMP/cert.pem \
      || fail "the certificate wasn't trusted"
    rm -rf $TMP
    security find-identity -v -p codesigning | grep -q "\"$SIGN_ID\"" || fail "the certificate isn't usable for signing"
    pass "\"$SIGN_ID\" created (self-signed, 10 years): releases signed with it keep users' macOS permissions across updates"
  fi
  exit 0
fi

if [[ ( $MODE != check && $MODE != draft ) || ! $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "usage: ./release.sh check|draft <version>   e.g. ./release.sh check 1.5.0"
  echo "       ./release.sh keys                    (once, before the first release with updates)"
  exit 2
fi

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
rm -rf $APP $OUT/GhosttyEXTREME-agent-hooks $OUT/*.zip(N)
ditto macos/build/ReleaseLocal/Ghostty.app $APP
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" $APP/Contents/Info.plist
# Only release builds check for updates by themselves (see AppDelegate).
/usr/libexec/PlistBuddy -c "Delete :GhosttyExtremeRelease" $APP/Contents/Info.plist 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :GhosttyExtremeRelease bool true" $APP/Contents/Info.plist
# The menu bar shows CFBundleName, which Xcode sets from the target name ("Ghostty").
/usr/libexec/PlistBuddy -c "Set :CFBundleName GhosttyEXTREME" $APP/Contents/Info.plist
# Debug info carries the build machine's paths; the release doesn't need it.
find $APP -type f -perm +111 -exec sh -c 'file "$1" | grep -q Mach-O && strip -S -x "$1" 2>/dev/null; true' _ {} \;
LEAKS=$(LC_ALL=C grep -rl -a "/Users/$USER" $APP | wc -l | xargs)
[[ $LEAKS == 0 ]] || { LC_ALL=C grep -rl -a "/Users/$USER" $APP | head -5; fail "$LEAKS files in the app contain your home path"; }
pass "no home-folder paths in the app"
# The same certificate every release, so macOS keeps users' permissions (notifications,
# folders) across updates; ad hoc only for a local check without it.
if security find-identity -v -p codesigning | grep -q "\"$SIGN_ID\""; then
  codesign --force --deep --sign "$SIGN_ID" $APP 2>/dev/null && codesign --verify --deep --strict $APP || fail "signing failed"
  pass "signed with \"$SIGN_ID\" and verified"
else
  [[ $MODE == draft ]] && fail "no \"$SIGN_ID\" certificate; run ./release.sh keys first"
  codesign --force --deep --sign - $APP 2>/dev/null && codesign --verify --deep --strict $APP || fail "signing failed"
  pass "signed ad hoc and verified (run ./release.sh keys to sign releases with your certificate)"
fi
# The updater must trust this project's key, never Ghostty's.
APP_ED_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" $APP/Contents/Info.plist)
[[ $APP_ED_KEY != $GHOSTTY_ED_KEY ]] || fail "the app still trusts Ghostty's update key; run ./release.sh keys and commit Ghostty-Info.plist"
SIGN_UPDATE=$(sparkle_tool sign_update)
GENERATE=$(sparkle_tool generate_keys)
[[ -n $SIGN_UPDATE && -n $GENERATE ]] || fail "Sparkle's sign_update / generate_keys not found (build the app in Xcode once)"
[[ $($GENERATE --account $KEY_ACCOUNT -p 2>/dev/null) == $APP_ED_KEY ]] \
  || fail "the app's SUPublicEDKey isn't the key in your keychain (\"$KEY_ACCOUNT\"); updates would be rejected"
pass "updates signed with your key ($KEY_ACCOUNT) will be accepted"
[[ $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $APP/Contents/Info.plist) == $VERSION ]] || fail "version not set"
pass "version $VERSION"

HOOKS=$OUT/GhosttyEXTREME-agent-hooks
mkdir -p $HOOKS
for f in agent-hook.sh ghostty-extreme.zsh ghostty-extreme install.sh localhost localhost-run codex-hook.py install-codex.py; do
  git show HEAD:agent-hooks/$f > $HOOKS/$f || fail "agent-hooks/$f missing"
done
chmod +x $HOOKS/{agent-hook.sh,ghostty-extreme,install.sh,localhost,localhost-run,codex-hook.py,install-codex.py}
grep -rqE "/Users/|$USER" $HOOKS && fail "the hooks contain a personal path or name"
for f in $HOOKS/*.sh $HOOKS/localhost $HOOKS/localhost-run $HOOKS/ghostty-extreme; do bash -n $f || fail "$f has a syntax error"; done
# The app installs these itself (welcome window, Check Setup).
for f in agent-hook.sh ghostty-extreme.zsh ghostty-extreme codex-hook.py localhost localhost-run; do
  cmp -s $HOOKS/$f $APP/Contents/Resources/agent-hooks/$f || fail "the app's bundled agent-hooks/$f doesn't match the repo"
done
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
pass "launched and stayed up (idle CPU ${CPU}%%), no crash report"

# ── Archives and notes ──────────────────────────────────────────────────
step "Archives"
APPZIP=GhosttyEXTREME-$VERSION-macos-arm64.zip
HOOKZIP=GhosttyEXTREME-$VERSION-agent-hooks.zip
(cd $OUT && ditto -c -k --keepParent GhosttyEXTREME.app $APPZIP && ditto -c -k --keepParent GhosttyEXTREME-agent-hooks $HOOKZIP)
APPSHA=$(shasum -a 256 $OUT/$APPZIP | cut -d' ' -f1)
HOOKSHA=$(shasum -a 256 $OUT/$HOOKZIP | cut -d' ' -f1)
(cd $OUT && shasum -a 256 $APPZIP $HOOKZIP > SHA256SUMS)
pass "SHA256SUMS (install.sh checks downloads against it)"
# The update feed: one item, this release, its zip signed with the update key.
SIGNATURE=$($SIGN_UPDATE --account $KEY_ACCOUNT $OUT/$APPZIP) || fail "couldn't sign the update"
[[ $SIGNATURE == *edSignature=* ]] || fail "sign_update returned no signature"
cat > $OUT/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GhosttyEXTREME</title>
    <link>https://github.com/$REPO/releases</link>
    <item>
      <title>GhosttyEXTREME $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$APPZIP" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
APPCAST
xmllint --noout $OUT/appcast.xml || fail "appcast.xml isn't valid XML"
pass "appcast.xml (the updater's feed, signed)"
UPSTREAM=$(git tag --merged HEAD --sort=-v:refname | grep -E '^v[0-9]' | head -1 | sed 's/^v//')
cat > $OUT/notes.md <<NOTES
$NOTES_BODY

## Install

Apple silicon Macs only, macOS 13 or newer. Based on **Ghostty $UPSTREAM**.

**Already on 1.5.0 or later?** GhosttyEXTREME → Check for Updates… installs it.

**New install, or updating from 1.4.x** (whose updater can't reach this release), in Terminal:

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/$REPO/custom/install.sh | bash
\`\`\`

It downloads \`$APPZIP\`, checks it against \`SHA256SUMS\`, and puts it in \`/Applications\`. Or by hand: download the zip, move \`GhosttyEXTREME.app\` to \`/Applications\`, and since the app isn't notarized, clear the download quarantine once with \`xattr -dr com.apple.quarantine /Applications/GhosttyEXTREME.app\`.

Then open it. The welcome window connects Claude Code and Codex and runs a live test (the hooks are inside the app). \`$HOOKZIP\` has the same hooks for setting up by hand; see the [README](https://github.com/$REPO#agent-status-setup).

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
  --notes-file $OUT/notes.md $OUT/$APPZIP $OUT/$HOOKZIP $OUT/SHA256SUMS $OUT/appcast.xml) || fail "couldn't create the draft"
pass "draft created (not visible to anyone else yet)"
print -P "\n%F{green}Review it here, then press Publish:%f\n  $URL"
