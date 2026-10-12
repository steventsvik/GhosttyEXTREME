#!/usr/bin/env python3
"""Live status from more coding agents, for GhosttyEXTREME's sidebar.

Usage (from an agent's hooks): agent-event.py <agent> <hook event>
  agent: copilot | droid | kiro | gemini | antigravity | cursor | qwen | goose

Reads the hook's JSON from stdin, turns the agent's own event into one of the sidebar's
(session_start, prompt_submit, tool_complete, permission_request, input_needed, stop,
stop_failure, session_end), and writes it to the agent's terminal as an OSC 777
notification titled "ghostty-extreme://agent". It only observes: it never approves,
denies or changes anything, prints only what each agent needs to carry on ("{}" for the
ones that parse JSON), and always exits 0.
"""
import json
import os
import re
import subprocess
import sys

# Agents that parse the hook's stdout as JSON; the rest get nothing.
JSON_REPLY = {"gemini", "antigravity", "cursor", "qwen"}


def text(value):
    return value if isinstance(value, str) else ""


def tool_detail(name, arguments):
    if isinstance(arguments, str):
        try:
            arguments = json.loads(arguments)
        except ValueError:
            arguments = {}
    if not isinstance(arguments, dict):
        arguments = {}
    argument = next((arguments[k] for k in ("command", "cmd", "file_path", "filePath", "path", "url", "pattern")
                     if isinstance(arguments.get(k), str) and arguments.get(k)), "")
    name = text(name)
    return f"{name}: {argument}" if argument else name


def prompt_text(prompt):
    """What the user asked, without image placeholders and paste wrappers."""
    prompt = re.sub(r"\[Image #\d+\]|</?pasted_content[^>]*>", "", text(prompt))
    change = re.search(r"\nChange: ([^\n]*)", prompt)
    if change and re.search(r"(^|\n)Visual fix #\d+:", prompt):
        return "Visual fix: " + change.group(1)
    return prompt


def translate(agent, event, p):
    """(sidebar event, detail) for this agent's hook event, or None to ignore it."""
    tool = tool_detail(p.get("tool_name") or p.get("toolName") or (p.get("toolCall") or {}).get("name"),
                       p.get("tool_input") or p.get("toolArgs") or p.get("toolInput") or (p.get("toolCall") or {}).get("args"))
    kind = text(p.get("notification_type")) or text(p.get("notificationType"))
    prompt = prompt_text(p.get("prompt") or os.environ.get("USER_PROMPT", ""))
    common = {
        "session_start": ("session_start", ""), "sessionStart": ("session_start", ""), "SessionStart": ("session_start", ""),
        "session_end": ("session_end", ""), "sessionEnd": ("session_end", ""), "SessionEnd": ("session_end", ""),
        "UserPromptSubmit": ("prompt_submit", prompt), "userPromptSubmitted": ("prompt_submit", prompt),
        "BeforeAgent": ("prompt_submit", prompt), "PreInvocation": ("prompt_submit", prompt),
        "beforeSubmitPrompt": ("prompt_submit", prompt),
        "PostToolUse": ("tool_complete", tool), "postToolUse": ("tool_complete", tool), "AfterTool": ("tool_complete", tool),
        "afterShellExecution": ("tool_complete", tool_detail("Shell", {"command": p.get("command")})),
        "afterFileEdit": ("tool_complete", tool_detail("Edit", {"file_path": p.get("file_path")})),
        "Stop": ("stop", ""), "agentStop": ("stop", ""), "AfterAgent": ("stop", ""),
    }
    if event == "stop" and agent == "cursor":
        return ("stop_failure" if p.get("status") == "error" else "stop"), ""
    if event in ("Notification", "notification"):
        if kind in ("permission_prompt", "ToolPermission"):
            return "permission_request", text(p.get("message")) or tool
        if kind == "elicitation_dialog":
            return "input_needed", text(p.get("message"))
        # Droid reports a cancelled turn as idle instead of stopping.
        if kind == "idle_prompt" and agent == "droid":
            return "stop", ""
        return None
    if event == "errorOccurred":
        return None if p.get("recoverable") else ("stop_failure", text((p.get("error") or {}).get("message")))
    if event == "stop" and agent != "cursor":
        return "stop", ""
    return common.get(event)


def clip(detail):
    # One line of printable text: control characters would show up in the sidebar.
    text = "".join(c if c.isprintable() else " " for c in str(detail))
    return " ".join(text.split())[:48]


def tty_path():
    """The agent's terminal. Hooks often run without one, so try the pane the shell
    integration recorded, then the first ancestor process that has a terminal."""
    try:
        descriptor = os.open("/dev/tty", os.O_WRONLY | os.O_NOCTTY)
        os.close(descriptor)
        return "/dev/tty"
    except OSError:
        pass
    bound = os.environ.get("GHOSTTY_EXTREME_AGENT_TTY", "")
    if re.fullmatch(r"/dev/ttys[0-9]+", bound):
        return bound
    pid = os.getppid()
    for _ in range(32):
        if pid <= 1:
            break
        try:
            row = subprocess.check_output(["/bin/ps", "-o", "ppid=,tty=", "-p", str(pid)], text=True,
                                          stderr=subprocess.DEVNULL, timeout=0.2).split()
            if len(row) != 2:
                break
            pid = int(row[0])
            if row[1] not in ("??", "?"):
                return "/dev/" + row[1]
        except (OSError, ValueError, subprocess.SubprocessError):
            break
    return None


def main():
    agent = sys.argv[1] if len(sys.argv) > 1 else ""
    event = sys.argv[2] if len(sys.argv) > 2 else ""
    try:
        if os.environ.get("GHOSTTY_EXTREME_AGENT_EVENTS") != "1":
            return
        try:
            payload = json.load(sys.stdin)
        except ValueError:
            payload = {}
        if not isinstance(payload, dict):
            payload = {}
        mapped = translate(agent, event, payload)
        if not mapped:
            return
        name, detail = mapped
        status = {"agent": agent, "event": name, "detail": clip(detail),
                  "t": os.environ.get("GHOSTTY_EXTREME_EVENT_TOKEN", "")}
        # The terminal caps notification bodies at 255 bytes.
        while len(json.dumps(status, ensure_ascii=True, separators=(",", ":")).encode()) > 250 and status["detail"]:
            status["detail"] = status["detail"][:-1]
        sequence = "\x1b]777;notify;ghostty-extreme://agent;" + json.dumps(status, ensure_ascii=True, separators=(",", ":")) + "\x07"
        tty = tty_path()
        if tty:
            # Never as a controlling terminal: the hook isn't the terminal's process.
            descriptor = os.open(tty, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
            try:
                os.write(descriptor, sequence.encode())
            finally:
                os.close(descriptor)
    except Exception:  # noqa: BLE001 - observing must never break the agent
        pass
    finally:
        if agent in JSON_REPLY:
            print("{}")


if __name__ == "__main__":
    main()
