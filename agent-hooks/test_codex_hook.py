import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("codex_hook", Path(__file__).with_name("codex-hook.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class CodexHookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)

    def transcript(self, session, parent=None):
        file = self.home / (session + ".jsonl")
        file.write_text(json.dumps({"type": "session_meta", "payload": {"id": session, "parent_thread_id": parent}}) + "\n")
        return str(file)

    def test_session_binding_and_long_unicode_status(self):
        session = "01a00000-1111-2222-3333-444444444444"
        path = self.transcript(session)
        status = hook.record_event({"session_id": session, "transcript_path": path, "prompt": "🐋" * 100}, "prompt_submit", self.home)
        self.assertLessEqual(len(json.dumps(status, ensure_ascii=True, separators=(",", ":")).encode()), 250)
        self.assertEqual(status["session"], session)
        manifest = json.loads((self.home / ".ghostty-extreme/codex-tracking" / (session + ".json")).read_text())
        self.assertEqual(manifest["transcript"], path)

    def test_child_never_marks_parent_done(self):
        path = self.transcript("child", "parent")
        self.assertIsNone(hook.record_event({"session_id": "parent", "transcript_path": path}, "stop", self.home))
        self.assertIsNone(hook.record_event({"session_id": "parent", "agent_id": "child"}, "subagent_stop", self.home))
        records = (self.home / ".ghostty-extreme/codex-tracking/child.jsonl").read_text().splitlines()
        self.assertEqual(json.loads(records[0])["parent"], "parent")

    def test_memory_writing_agent_is_ignored(self):
        memories = str(self.home / ".codex/memories")
        with patch.dict(os.environ, {"CODEX_HOME": ""}):
            for event in ("session_start", "prompt_submit", "pre_tool_use", "stop"):
                payload = {"session_id": "memory-agent", "cwd": memories, "transcript_path": None,
                           "prompt": "## Memory Writing Agent: Phase 2 (Consolidation)"}
                self.assertIsNone(hook.record_event(payload, event, self.home))
            self.assertFalse((self.home / ".ghostty-extreme/codex-tracking/memory-agent.jsonl").exists())
            project = {"session_id": "project", "cwd": str(self.home / "project"), "prompt": "Fix the links"}
            self.assertIsNotNone(hook.record_event(project, "prompt_submit", self.home))

    def test_prompt_text_hides_paste_wrappers_and_names_visual_fixes(self):
        visual = '[Image #1]\n\n<pasted_content id="49c0">\nVisual fix #1: I pointed at an element.\nChange: Make it bigger\n</pasted_content id="49c0">\n'
        self.assertEqual(hook.prompt_text(visual), "Visual fix: Make it bigger")
        self.assertEqual(hook.prompt_text("Fix this [Image #2]").strip(), "Fix this")
        self.assertEqual(hook.prompt_text("Change: nothing special"), "Change: nothing special")

    def test_pretool_and_question_status(self):
        payload = {"session_id": "parent", "tool_name": "Bash", "tool_input": {"command": "cat src/app.ts"}}
        self.assertEqual(hook.record_event(payload, "pre_tool_use", self.home)["event"], "tool_start")
        payload["tool_name"] = "request_user_input"
        self.assertEqual(hook.record_event(payload, "pre_tool_use", self.home)["event"], "input_needed")

    def test_no_output_or_storage_outside_extreme(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(hook.sys, "stdin", io.StringIO('{"session_id":"parent"}')):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                hook.main()
            self.assertEqual(output.getvalue(), "")
            self.assertFalse((self.home / ".ghostty-extreme").exists())

    def test_no_path_traversal(self):
        self.assertIsNone(hook.record_event({"session_id": "../../escape"}, "session_start", self.home))
        self.assertFalse((self.home / ".ghostty-extreme").exists())

    def test_localhost_rewrite_preserves_permission_arguments(self):
        launcher = self.home / ".ghostty-extreme/bin/localhost"
        launcher.parent.mkdir(parents=True)
        launcher.touch()
        payload = {"session_id": "parent", "tool_name": "Bash", "cwd": "/tmp/a project",
                   "tool_input": {"command": "npm run dev", "sandbox_permissions": "require_escalated", "justification": "Start server"}}
        with patch.dict(os.environ, {"GHOSTTY_EXTREME_AGENT_EVENTS": "1"}), patch.object(hook.subprocess, "check_output", return_value="~/.ghostty-extreme/bin/localhost start -- 'npm run dev'\n"):
            result = hook.localhost_context(payload, "pre_tool_use", self.home)["hookSpecificOutput"]
        self.assertEqual(result["hookEventName"], "PreToolUse")
        self.assertEqual(result["updatedInput"]["sandbox_permissions"], "require_escalated")
        self.assertEqual(result["updatedInput"]["justification"], "Start server")
        self.assertIn("--agent codex", result["updatedInput"]["command"])
        self.assertIn("cd '/tmp/a project'", result["updatedInput"]["command"])
        self.assertIsNone(hook.localhost_context(payload, "permission_request", self.home))

    def test_non_server_is_not_rewritten(self):
        launcher = self.home / ".ghostty-extreme/bin/localhost"
        launcher.parent.mkdir(parents=True)
        launcher.touch()
        payload = {"tool_name": "Bash", "tool_input": {"command": "npm test"}}
        with patch.dict(os.environ, {"GHOSTTY_EXTREME_AGENT_EVENTS": "1"}), patch.object(hook.subprocess, "check_output", side_effect=hook.subprocess.CalledProcessError(1, "localhost")):
            self.assertIsNone(hook.localhost_context(payload, "pre_tool_use", self.home))

    def test_shell_wrapper_binds_pane_runtime_and_preserves_arguments(self):
        executable = self.home / "codex"
        executable.write_text('#!/bin/zsh\nprintf "%s\\n" "$GHOSTTY_EXTREME_CODEX_TTY" "$@"\n')
        executable.chmod(0o755)
        master, slave = os.openpty()
        environment = dict(os.environ, GHOSTTY_EXTREME_AGENT_EVENTS="1",
                           PATH=str(self.home) + ":" + os.environ.get("PATH", ""))
        try:
            result = subprocess.run(["/bin/zsh", "-f", "-c",
                'source "$1"; TTY=/dev/ttys123; codex resume saved-session --sandbox read-only "$2"',
                "zsh", str(Path(__file__).with_name("ghostty-extreme.zsh")), "a literal $prompt"],
                stdin=slave, stdout=slave, stderr=slave, env=environment, timeout=3)
            self.assertEqual(result.returncode, 0)
            arguments = os.read(master, 65536).decode().splitlines()
            self.assertEqual(arguments[:2], ["/dev/ttys123", "--no-daemon"])
            self.assertEqual(arguments[2:], ["resume", "saved-session", "--sandbox", "read-only", "a literal $prompt"])
        finally:
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    unittest.main()
