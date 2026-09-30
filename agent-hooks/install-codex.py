#!/usr/bin/env python3
"""Install only the Codex adapter and registrations, preserving other hooks and trust."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import time
import os


def install(home):
    source = Path(__file__).resolve().parent
    current = home / ".ghostty-extreme/agent-hooks"
    legacy = home / ".ghostty-custom/agent-hooks"
    directories = [current] + ([legacy] if legacy.is_dir() else [])
    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)
        for name in ("agent-hook.sh", "codex-hook.py", "ghostty-extreme.zsh"):
            shutil.copy2(source / name, directory / name)
        (directory / "agent-hook.sh").chmod(0o755)
    config = home / ".codex/hooks.json"
    config.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(config.read_text()) if config.exists() else {}
    hooks = data.setdefault("hooks", {})
    # Keep the previously approved command path whenever it was the legacy installation.
    script = current / "agent-hook.sh"
    for group in hooks.get("SessionStart", []):
        for handler in group.get("hooks", []):
            if handler.get("command") == str(legacy / "agent-hook.sh") + " codex session_start":
                script = legacy / "agent-hook.sh"
    events = {"SessionStart": "session_start", "UserPromptSubmit": "prompt_submit",
              "PreToolUse": "pre_tool_use", "PermissionRequest": "permission_request",
              "PostToolUse": "tool_complete", "Stop": "stop", "SessionEnd": "session_end",
              "SubagentStart": "subagent_start", "SubagentStop": "subagent_stop", "Interrupt": "interrupt"}
    changed = False
    for event, argument in events.items():
        command = str(script) + " codex " + argument
        groups = hooks.setdefault(event, [])
        if any(handler.get("command") == command for group in groups for handler in group.get("hooks", [])):
            continue
        group = {"hooks": [{"type": "command", "command": command, "timeout": 3}]}
        if event in ("PreToolUse", "PostToolUse"):
            group["matcher"] = "*"
        groups.append(group)
        changed = True
    if changed:
        if config.exists():
            shutil.copy2(config, config.with_name("hooks.json.ghostty-extreme-backup-" + str(time.time_ns())))
        descriptor, temporary = tempfile.mkstemp(dir=config.parent)
        with os.fdopen(descriptor, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, config)
    # No trust hashes are changed. Codex performs its own review for new registrations.
    return script


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    args = parser.parse_args()
    print("Installed Codex tracking:", install(args.home))
