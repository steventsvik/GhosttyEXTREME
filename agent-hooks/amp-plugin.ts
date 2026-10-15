// Tellurion: live status for Amp in the sidebar. Installed by Tellurion as
// ~/.config/amp/plugins/tellurion.ts; does nothing outside Tellurion.
//
// Amp has no command hooks, so this plugin listens to its events and writes the same
// OSC 777 notification the other agents' hooks send to the terminal. It only observes:
// it never allows, rejects or changes a tool call.
import { closeSync, openSync, writeSync } from "node:fs"

const ACTIVE = process.env.GHOSTTY_EXTREME_AGENT_EVENTS === "1"
const TOKEN = process.env.GHOSTTY_EXTREME_EVENT_TOKEN || ""

function clip(text: unknown): string {
  return String(text || "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 48)
}

function send(event: string, detail: unknown) {
  if (!ACTIVE) return
  let text = clip(detail)
  let body = JSON.stringify({ agent: "amp", event, detail: text, t: TOKEN })
  // The terminal caps notification bodies at 255 bytes; emoji take four each.
  while (Buffer.byteLength(body) > 250 && text) {
    text = Array.from(text).slice(0, -1).join("")
    body = JSON.stringify({ agent: "amp", event, detail: text, t: TOKEN })
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

function toolDetail(tool: unknown, input: any): string {
  const a = input && typeof input === "object" ? input : {}
  const arg = a.command || a.cmd || a.filePath || a.file_path || a.path || a.url || a.pattern || ""
  const name = typeof tool === "string" ? tool : (tool as any)?.name || ""
  return arg ? `${name}: ${arg}` : name
}

function promptText(message: any): string {
  if (typeof message === "string") return message
  const content = message?.content
  if (typeof content === "string") return content
  if (Array.isArray(content)) return content.filter((p: any) => p?.type === "text").map((p: any) => p.text).join(" ")
  return ""
}

export default (amp: any) => {
  if (!ACTIVE) return
  // Observers only: nothing here returns a decision.
  amp.on("session.start", async () => { send("session_start", "") })
  amp.on("agent.start", async (e: any) => { send("prompt_submit", promptText(e?.message)) })
  amp.on("tool.result", async (e: any) => { send("tool_complete", toolDetail(e?.tool, e?.input)) })
  amp.on("agent.end", async (e: any) => { send(e?.status === "error" ? "stop_failure" : "stop", "") })
}
