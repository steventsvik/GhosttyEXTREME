# GhosttyEXTREME: tells the vertical tabs sidebar which coding agent a pane is running,
# the way Warp recognizes agents from the command line. Starting `claude`, `codex`, etc.
# marks the pane with that agent immediately; the mark clears when the command exits,
# even if the agent crashed. The agents' own hooks (agent-hook.sh) add live status.
#
# Sourced from ~/.zshrc. Does nothing outside GhosttyEXTREME.

# The pre-rebrand "Ghostty Custom" build is still served until it's replaced.
if [[ "${GHOSTTY_EXTREME_AGENT_EVENTS:-}" == 1 ]]; then
  typeset -g _gc_namespace=ghostty-extreme
elif [[ "${GHOSTTY_CUSTOM_AGENT_EVENTS:-}" == 1 ]]; then
  typeset -g _gc_namespace=ghostty-custom
else
  return 0
fi

typeset -g _gc_running_agent=""

# Command name -> agent id (see VerticalTabAgentKind).
typeset -gA _gc_agent_commands=(
  claude claude
  codex codex
  gemini gemini
  opencode opencode
  amp amp
  copilot copilot
  cursor-agent cursor
  droid droid
  goose goose
  hermes hermes
)

_gc_agent_event() {
  printf '\e]777;notify;%s://agent;{"agent":"%s","event":"%s"}\a' "$_gc_namespace" "$1" "$2" 2>/dev/null >/dev/tty
}

_gc_agent_preexec() {
  # $3 is the command line with aliases expanded. Skip env assignments and wrappers
  # to find the program actually being run.
  local word
  for word in ${(z)3}; do
    [[ $word == *=* || $word == (command|exec|env|noglob|nocorrect|time|nohup) ]] && continue
    break
  done
  local agent=${_gc_agent_commands[${word:t}]}
  [[ -n $agent ]] || return 0
  _gc_running_agent=$agent
  _gc_agent_event "$agent" session_start
}

_gc_agent_precmd() {
  [[ -n $_gc_running_agent ]] || return 0
  _gc_agent_event "$_gc_running_agent" session_end
  _gc_running_agent=""
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _gc_agent_preexec
add-zsh-hook precmd _gc_agent_precmd
