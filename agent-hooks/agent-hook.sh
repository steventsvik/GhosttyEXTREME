#!/bin/bash
# Reports coding-agent activity to Ghostty Custom's vertical tabs sidebar.
#
# Usage (from an agent's hooks): agent-hook.sh <agent> <event>
#   agent: claude | codex
#   event: session_start | prompt_submit | tool_complete | permission_request |
#          notification | stop | stop_failure | session_end
#
# Emits an OSC 777 notification titled "ghostty-custom://agent" with a compact JSON
# body. Ghostty Custom consumes it silently; it is never shown as a notification.
#   - Claude Code: printed as the `terminalSequence` hook field, so Claude Code
#     writes it to its own terminal.
#   - Others (Codex): written straight to the controlling terminal; nothing is
#     printed, so the agent sees an empty hook result.
# The script never approves, denies, or otherwise changes what the agent does.

# Only inside Ghostty Custom; anywhere else (including official Ghostty) do nothing.
[ "${GHOSTTY_CUSTOM_AGENT_EVENTS:-}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

agent="${1:-}"
event="${2:-}"
input=$(cat)

# Ghostty caps notification bodies at 255 bytes, so keep details short.
sequence=$(jq -r --arg agent "$agent" --arg event "$event" '
  def clip: gsub("[\\s]+"; " ") | ltrimstr(" ") | if length > 48 then .[0:47] + "…" else . end;
  def tool_detail:
    (.tool_name // "") as $tool
    | (.tool_input.command // .tool_input.file_path // .tool_input.url // "" | tostring) as $arg
    | if $arg == "" then $tool else "\($tool): \($arg)" end;

  (if $event == "notification" then
     (if .notification_type == "permission_prompt" then "permission_request"
      elif .notification_type == "elicitation_dialog" then "input_needed"
      else empty end)
   else $event end) as $e
  | {
      event: $e,
      detail: (
        if $e == "prompt_submit" then (.prompt // "")
        elif $e == "permission_request" or $e == "tool_complete" then tool_detail
        elif $e == "input_needed" then (.message // "")
        else "" end | clip)
    }
  | {agent: $agent} + .
  | "\u001b]777;notify;ghostty-custom://agent;\(tojson)\u0007"
' <<<"$input" 2>/dev/null) || exit 0
[ -n "$sequence" ] || exit 0

if [ "$agent" = "claude" ]; then
  jq -nc --arg seq "$sequence" '{terminalSequence: $seq}'
else
  printf '%s' "$sequence" > /dev/tty 2>/dev/null
fi

exit 0
