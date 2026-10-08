#!/usr/bin/env python3
"""Codex telemetry for GhosttyEXTREME. Never decides PermissionRequest hooks.

Keep rich tool data in private local JSONL; OSC notifications carry only identity and
status, safely below the terminal's 255-byte body limit. Claude's adapter is independent.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import tempfile


def identifier(value):
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,100}", value) else None


def transcript_metadata(path):
    try:
        with open(path, encoding="utf-8") as stream:
            record = json.loads(stream.readline(65536))
        return record.get("payload", {}) if record.get("type") == "session_meta" else {}
    except (OSError, ValueError, TypeError):
        return {}


def tty_path():
    bound = os.environ.get("GHOSTTY_EXTREME_CODEX_TTY", "")
    if re.fullmatch(r"/dev/ttys[0-9]+", bound):
        return bound
    try:
        descriptor = os.open("/dev/tty", os.O_WRONLY | os.O_NOCTTY)
        os.close(descriptor)
        return "/dev/tty"
    except OSError:
        pid = os.getppid()
        for _ in range(32):
            if pid <= 1:
                break
            try:
                row = subprocess.check_output(
                    ["/bin/ps", "-o", "ppid=,tty=", "-p", str(pid)], text=True,
                    stderr=subprocess.DEVNULL, timeout=0.2).split()
                if len(row) != 2:
                    break
                pid = int(row[0])
                if row[1] not in ("??", "?"):
                    return "/dev/" + row[1]
            except (OSError, ValueError, subprocess.SubprocessError):
                break
    return None


def prompt_text(prompt):
    """What the user asked: without image placeholders and paste wrappers, and for a
    Visual Fix request, the change they described."""
    text = re.sub(r"\[Image #\d+\]|</?pasted_content[^>]*>", "", str(prompt or ""))
    change = re.search(r"\nChange: ([^\n]*)", text)
    if change and re.search(r"(^|\n)Visual fix #\d+:", text):
        return "Visual fix: " + change.group(1)
    return text


def compact_detail(payload, event):
    tool = payload.get("tool_name", "")
    arguments = payload.get("tool_input") or {}
    if not isinstance(arguments, dict):
        arguments = {}
    if event == "prompt_submit":
        detail = prompt_text(payload.get("prompt", ""))
    elif event in ("pre_tool_use", "tool_complete", "permission_request"):
        argument = arguments.get("command", arguments.get("cmd", arguments.get("file_path", "")))
        detail = f"{tool}: {argument}" if argument else tool
    else:
        detail = ""
    # ASCII encoding makes the byte limit independent of non-ASCII prompt text.
    return " ".join(str(detail).split())[:48]


def codex_background_session(payload, home):
    """Codex's own memory-writing agent runs as a separate session in its memories folder,
    from the same terminal. It isn't the pane's agent, so it must not show as its task."""
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        return False
    codex_home = Path(os.environ.get("CODEX_HOME") or home / ".codex")
    try:
        return Path(cwd).resolve().is_relative_to((codex_home / "memories").resolve())
    except (OSError, ValueError):
        return False


def record_event(payload, event, home):
    session = identifier(payload.get("session_id"))
    if not session or codex_background_session(payload, home):
        return None
    transcript = payload.get("transcript_path")
    meta = transcript_metadata(transcript) if isinstance(transcript, str) else {}
    actual = identifier(meta.get("id")) or session
    child = identifier(payload.get("agent_id")) if event.startswith("subagent_") else None
    directory = home / ".ghostty-extreme" / "codex-tracking"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    record = {"event": event, "timestamp": time.time(), "session": actual,
              "parent": session if actual != session else None,
              "child": child, "payload": payload}
    # Lock across parallel tool hooks; one complete JSON record per append.
    path = directory / f"{actual}.jsonl"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        stream.write(json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n")
    if isinstance(transcript, str) and meta.get("id") == actual:
        descriptor, temporary = tempfile.mkstemp(dir=directory)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump({"id": actual, "transcript": transcript}, stream)
        os.replace(temporary, directory / f"{actual}.json")
    if actual != session or child:
        # A child finishing never marks its parent Done or clears its parent pane.
        return None
    mapped = {"pre_tool_use": "tool_start", "interrupt": "input_needed"}.get(event, event)
    detail = compact_detail(payload, event)
    if event == "pre_tool_use" and payload.get("tool_name", "").split(".")[-1] in (
            "request_user_input", "request_user_input_async"):
        mapped = "input_needed"
        detail = "Waiting for your answer"
    result = {"agent": "codex", "event": mapped, "session": session, "detail": detail}
    while len(json.dumps(result, ensure_ascii=True, separators=(",", ":")).encode()) > 250:
        detail = detail[:-1]
        result["detail"] = detail
    return result


def localhost_context(payload, event, home):
    if event != "pre_tool_use" or os.environ.get("GHOSTTY_EXTREME_AGENT_EVENTS") != "1":
        return None
    if payload.get("tool_name") not in ("Bash", "exec_command", "shell", "local_shell"):
        return None
    arguments = payload.get("tool_input") or {}
    if not isinstance(arguments, dict):
        return None
    command = arguments.get("command", arguments.get("cmd"))
    launcher = home / ".ghostty-extreme" / "bin" / "localhost"
    if not isinstance(command, str) or not launcher.is_file():
        return None
    try:
        cwd_arg = arguments.get("workdir", payload.get("cwd"))
        extra = ["--cwd", cwd_arg] if isinstance(cwd_arg, str) and cwd_arg else []
        rewritten = subprocess.check_output([str(launcher), "rewrite", command, *extra],
                                            text=True, stderr=subprocess.DEVNULL, timeout=1).strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if not rewritten:
        return None
    cwd = arguments.get("workdir", payload.get("cwd"))
    if isinstance(cwd, str):
        import shlex
        rewritten = f"cd {shlex.quote(cwd)} && {rewritten}"
    rewritten = rewritten.replace("/bin/localhost start ", "/bin/localhost start --agent codex ", 1)
    updated = dict(arguments)
    updated["command" if "command" in arguments else "cmd"] = rewritten
    # Codex requires 'allow' on PreToolUse to accept updatedInput. This allows the
    # rewrite, not a PermissionRequest: retain all tool sandbox/escalation arguments.
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
        "updatedInput": updated, "additionalContext":
        "The dev server command now opens a GhosttyEXTREME localhost session: a separate "
        "terminal tab that keeps running after you finish. The command prints the URL and "
        "log commands. Do not start another copy. The usual tool approval flow still applies."}}


def shared_memory(payload):
    """What Claude Code remembers about the project, for a new Codex session."""
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        return None
    try:
        # No __pycache__ in the user's hooks folder.
        sys.dont_write_bytecode = True
        from memory_context import context
        text = context("codex", cwd)
    except Exception:  # noqa: BLE001 - never fail a session start
        return None
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}} if text else None


def main():
    if os.environ.get("GHOSTTY_EXTREME_AGENT_EVENTS") != "1" and os.environ.get("GHOSTTY_CUSTOM_AGENT_EVENTS") != "1":
        return
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            return
        home = Path.home()
        status = record_event(payload, event, home)
        if status:
            namespace = "ghostty-extreme" if os.environ.get("GHOSTTY_EXTREME_AGENT_EVENTS") == "1" else "ghostty-custom"
            # This launch's secret, so the app can tell real events from printed text.
            status["t"] = os.environ.get("GHOSTTY_EXTREME_EVENT_TOKEN", "")
            sequence = f"\x1b]777;notify;{namespace}://agent;{json.dumps(status, ensure_ascii=True, separators=(',', ':'))}\x07"
            tty = tty_path()
            if tty:
                try:
                    with open(tty, "w", encoding="utf-8") as stream:
                        stream.write(sequence)
                except OSError:
                    pass
        context = localhost_context(payload, event, home)
        if event == "session_start" and os.environ.get("GHOSTTY_EXTREME_AGENT_EVENTS") == "1":
            context = shared_memory(payload)
        if context:
            print(json.dumps(context))
    except (OSError, ValueError, TypeError):
        # Observability must never fail a tool, delay an exit, or block a turn.
        pass


if __name__ == "__main__":
    main()
