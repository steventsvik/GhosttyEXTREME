#!/bin/bash
# Installs the agent hooks and localhost-session scripts outside the repo:
#   ~/.ghostty-extreme/agent-hooks/  what ~/.claude/settings.json, ~/.codex/hooks.json and
#                                    ~/.zshrc point at
#   ~/.ghostty-extreme/bin/          `localhost` and its runner
# The repo may live in ~/Desktop or ~/Documents, which macOS privacy protection (TCC) can
# block for the terminal's processes ("Operation not permitted"), silently breaking agent
# status. Rerun after editing any of these files.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
hooks="$HOME/.ghostty-extreme/agent-hooks"
bin="$HOME/.ghostty-extreme/bin"
mkdir -p "$hooks" "$bin"
cp "$here/agent-hook.sh" "$here/ghostty-extreme.zsh" "$here/codex-hook.py" "$hooks/"
cp "$here/localhost" "$here/localhost-run" "$bin/"
chmod +x "$hooks/agent-hook.sh" "$bin/localhost" "$bin/localhost-run"
# Before the rebrand the hooks lived in ~/.ghostty-custom; agents may still point there
# (Codex ties its hook approvals to the exact command), so keep that copy current too.
legacy="$HOME/.ghostty-custom/agent-hooks"
if [ -d "$legacy" ]; then
  cp "$here/agent-hook.sh" "$here/ghostty-extreme.zsh" "$here/codex-hook.py" "$legacy/"
  chmod +x "$legacy/agent-hook.sh"
fi
echo "Installed agent hooks to $hooks and localhost scripts to $bin"
