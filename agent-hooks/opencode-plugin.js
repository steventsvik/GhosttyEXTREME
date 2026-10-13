// Tellurion: live status for OpenCode in the sidebar. Installed by Tellurion as
// ~/.config/opencode/plugins/ghostty-extreme.js; does nothing outside Tellurion.
//
// OpenCode has no command hooks, so this plugin listens to its events and writes the
// same OSC 777 notification the other agents' hooks send to the terminal. It only
// observes: it never answers a permission, changes a tool's input, or edits a message.
import { openSync, writeSync, closeSync } from "node:fs"

const ACTIVE = process.env.GHOSTTY_EXTREME_AGENT_EVENTS === "1"
const TOKEN = process.env.GHOSTTY_EXTREME_EVENT_TOKEN || ""

function clip(text) {
  return String(text || "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 48)
}

function send(event, detail) {
  if (!ACTIVE) return
  let text = clip(detail)
  let body = JSON.stringify({ agent: "opencode", event, detail: text, t: TOKEN })
  // The terminal caps notification bodies at 255 bytes; emoji take four each.
  while (Buffer.byteLength(body) > 250 && text) {
    text = Array.from(text).slice(0, -1).join("")
    body = JSON.stringify({ agent: "opencode", event, detail: text, t: TOKEN })
  }
  for (const path of [process.env.GHOSTTY_EXTREME_AGENT_TTY, "/dev/tty"]) {
    if (!path) continue
    try {
      const fd = openSync(path, "a")
      writeSync(fd, `\x1b]777;notify;ghostty-extreme://agent;${body}\x07`)
      closeSync(fd)
      return
    } catch {}
  }
}

function toolDetail(tool, args) {
  const a = args || {}
  const arg = a.command || a.filePath || a.file_path || a.path || a.url || a.pattern || ""
  return arg ? `${tool}: ${arg}` : tool
}

export const GhosttyExtreme = async () => {
  if (!ACTIVE) return {}
  send("session_start", "")
  return {
    event: async ({ event }) => {
      const p = event.properties || {}
      switch (event.type) {
        case "session.idle":
          send("stop", "")
          break
        case "session.status":
          if (p.status && p.status.type === "busy") send("tool_complete", "")
          break
        case "session.error":
          send("stop_failure", (p.error && (p.error.message || p.error.name)) || "")
          break
        case "permission.asked":
        case "permission.updated":
          send("permission_request", p.title || p.permission || p.type || "")
          break
        case "question.asked":
          send("input_needed", "Waiting for your answer")
          break
      }
    },
    "chat.message": async (input, output) => {
      const parts = (output && output.parts) || []
      const text = parts.filter((part) => part.type === "text" && !part.synthetic).map((part) => part.text).join(" ")
      if (text) send("prompt_submit", text)
    },
    "tool.execute.after": async (input) => {
      send("tool_complete", toolDetail(input.tool, input.args))
    },
  }
}
