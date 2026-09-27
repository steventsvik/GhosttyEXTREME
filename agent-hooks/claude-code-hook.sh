#!/bin/bash
# Reports Claude Code activity to Ghostty Custom's vertical tabs sidebar.
#
# Usage (from a Claude Code hook): claude-code-hook.sh <event>
#   event: session_start | prompt_submit | tool_complete | permission_request |
#          notification | stop | stop_failure | session_end
#
# Emits an OSC 777 notification titled "ghostty-custom://agent" with a compact JSON
# body. Ghostty Custom consumes it silently; it is never shown as a notification.
# Output uses Claude Code's `terminalSequence` hook field, so Claude Code writes the
# sequence to its own terminal. The script only ever prints that field: it never
# approves, denies, or otherwise changes what Claude Code does.

# Only inside Ghostty Custom; anywhere else (including official Ghostty) do nothing.
[ "${GHOSTTY_CUSTOM_AGENT_EVENTS:-}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

event="${1:-}"
input=$(cat)

# Ghostty caps notification bodies at 255 bytes, so keep details short.
jq -c --arg event "$event" '
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
  | {agent: "claude"} + .
  | {terminalSequence: "\u001b]777;notify;ghostty-custom://agent;\(tojson)\u0007"}
' <<<"$input" 2>/dev/null

exit 0
