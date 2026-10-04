<p align="center">
  <img src="images/readme/banner.png" alt="GhosttyEXTREME: the macOS terminal built for coding agents" width="100%">
</p>

<p align="center">
  <a href="https://github.com/steventsvik/GhosttyEXTREME/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/steventsvik/GhosttyEXTREME?style=flat-square&color=deb86e&labelColor=17140f&label=release"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-deb86e?style=flat-square&labelColor=17140f&logo=apple&logoColor=deb86e">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-arm64-deb86e?style=flat-square&labelColor=17140f">
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-deb86e?style=flat-square&labelColor=17140f"></a>
  <a href="https://ghostty.org"><img alt="Based on Ghostty 1.3.1" src="https://img.shields.io/badge/based%20on-Ghostty%201.3.1-78dceb?style=flat-square&labelColor=17140f"></a>
</p>

<p align="center">
  <b><a href="https://github.com/steventsvik/GhosttyEXTREME/releases/latest">Download</a></b> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#keyboard-shortcuts">Shortcuts</a> ·
  <a href="#security-and-privacy">Security</a>
</p>

**GhosttyEXTREME** is [Ghostty](https://ghostty.org), the fast native macOS terminal, rebuilt
for working with coding agents like **Claude Code** and **Codex**. Every agent shows up
live in a vertical sidebar. A code editor follows what it reads and changes, a map shows
where it's been in your project, and a backend view shows what your app runs on. When it
finishes, its changes wait for you in a review inbox.

Everything Ghostty does still works. This fork tracks official Ghostty releases and adds
its features on top.

> [!NOTE]
> Unofficial fork. Not affiliated with or endorsed by the Ghostty project.

<br>

## Features

### Every agent, at a glance

A vertical sidebar shows every tab and the agent running in it: Claude Code, Codex,
Gemini CLI, Copilot, Cursor, Amp, opencode, Goose, Droid or Hermes.

- **Live status** for each agent: working, waiting for permission, waiting for input,
  done or failed, with how long it's been at it and its last action.
- **Agents act out their mood.** Their sprite reads, types, runs commands, thinks, hops
  when it needs you and sparkles when it's done. The sigil at the top orbits once per
  working agent.
- **Project groups.** Tabs with agents in the same repository are bracketed together,
  with a live summary ("2 working · 1 waiting") and a warning when two agents touch the
  same file.
- **Mission Control** (⌃⌘M) shows every agent in every window. Agents waiting on you come
  first in the **command palette** (⌘P), and a notification and Dock badge tell you when one
  needs you.
- **Usage meters** for your Claude and ChatGPT plans sit at the bottom of the sidebar.

### A code editor that follows the agent

<p align="center">
  <img src="images/readme/code-map.png" alt="The code map: the project as a star map, with the agent's path and a file's blast radius" width="100%">
</p>

A VS Code–style editor (Monaco) opens beside any tab (⌃⌘E), on that tab's folder and in
your terminal theme. As the agent works, it opens the files it reads and animates its
edits in. With several sub-agents, it splits into a pane per agent.

**Code map.** Your project as a star map. Folders are tinted by what they are: frontend,
API, database, tests, config. Files light up as the agent reads (cyan) and edits (orange)
them, and the agent flies between them as a comet.

- **Zoom levels:** the **Overview** shows the project's areas and how much the agent did
  in each. **Files** shows every file. **Symbols** shows the functions and classes inside,
  with the ones changed this turn lit.
- **Details for anything you click:** what the agent did there, this turn's diff, its
  symbols, what imports it (drawn on the map as its blast radius, with a warning when
  no test covers it), and the backend pieces it uses.

### See your backend

<p align="center">
  <img src="images/readme/backend.png" alt="The Backend tab: frontend, compute, data and services, with live deploy status" width="100%">
</p>

The **Backend** tab shows what your project runs on, worked out from its own files
(`package.json`, `wrangler.jsonc`, `supabase/`, `.vercel/`, Prisma, env variable names).
It works offline and without logins.

- **Architecture:** frontend → compute → data → services, with a line only where your
  code really connects two pieces.
  - **Cloudflare Workers** show their environments, domains, cron schedules and every
    binding: D1, Hyperdrive, KV, R2, Queues, Durable Objects, service bindings, Workers AI
    and more.
  - **Supabase, Vercel, Prisma, Firebase,** and services like Stripe, OpenAI and Resend,
    show up too.
- **Live status** comes from each provider's own CLI (`wrangler`, `supabase`, `vercel`),
  using the logins you already have and only read-only commands. It shows deploys per
  environment, project health, migrations not applied yet, and commits newer than the
  last deploy.
- **Agent awareness:** when the agent edits something that belongs to a piece of your
  backend, that piece lights up.

<p align="center">
  <img src="images/readme/database.png" alt="The Database view: tables, columns and relations" width="100%">
</p>

The **Database** view draws your schema: tables, columns and relations for Supabase,
Cloudflare D1, Postgres behind Hyperdrive (read from your migrations) and Prisma.
Row-level security is checked on every Postgres table, and large schemas can be searched.

### Point at your app and have the agent change it

**Visual Fix** (⌃⌘V) previews your running dev server beside the terminal, at desktop,
tablet or phone size.

- **Pick an element:** hover and click any element, then say what should change.
- **What the agent gets:** the element's HTML and CSS selector, the component and source
  file that render it (React, Vue and Svelte), its computed styles, and a screenshot.
- **Where it goes:** the request goes to the agent working in that project. When the change
  lands, the preview reloads where you were.

### Clean up what's left running

**Background** (⌃⌘K) finds everything left running: dev servers, Colima VMs and
containers, agent sessions, browser automation, databases, watchers, log followers and
login services.

- **When it was last really used:** the last typing or output in its terminal, its agent
  transcript being written, a live connection to its port, or a busy container.
- **A staleness rating** (Active, Idle, Stale or Ready to close), with the reasons.
- **One-click cleanup** that always asks first. Login services are never marked ready to
  close.

### And more

| | |
|---|---|
| **Localhost sessions** (⌃⌘L) | Dev servers an agent starts (`npm run dev`, `vite`, `rails s`, …) open in their own tab and keep running after it's done; the agent is told the URL and how to read the logs. Each gets a live card with its URL, framework, CPU, memory, restart and stop. |
| **Review changes** (⌃⌘I) | When an agent finishes, its diff lands in an inbox. Comment on lines and send them back as its next prompt, approve or undo files, commit or open a pull request. |
| **Agent races** (⌃⌘R) | Run the same task with several agents in separate git worktrees, compare their diffs and keep the best one. |
| **Command history** (⌃⌘B) | Every command becomes a block with its output, exit code and duration. A failed one offers **Fix with Claude** or **Fix with Codex**. |
| **Agent activity** (⌃⌘A) | Active time, prompts, files and lines changed, tests and tokens, per day, agent and project. Flip **API value** to see what it would cost at API prices. |
| **Isolated sessions** | Ubuntu, Python, Node and sandboxed Claude Code or Codex in Docker. Only the project folder is shared. |
| **Handoff** | Pass a pane's context to a fresh Claude Code session in a split. |
| **AI POV** | Replay the agent's session as if you were at its keyboard: files opening, code typed, commands run. |

<br>

## Light on your Mac

All of the sidebar's animations run in Core Animation, so the app does almost no work per
frame. Anything you can't see pauses: background tabs, hidden and minimized windows. With six
agents working at once, GhosttyEXTREME uses about **1–3% CPU**.

## Security and privacy

- **Nothing leaves your Mac.** There's no account, telemetry or server. Agent tracking
  reads the session files Claude Code and Codex already write.
- **Only your own hooks can talk to it.** Agent status arrives as terminal escape
  sequences, which any printed text could imitate. Each launch creates a secret that only
  its own terminals and hooks know, and events without it are ignored.
- **The Backend view never stores credentials.** It runs your providers' own CLIs with
  their existing logins, read-only commands only. It reads only the *names* of your env
  variables, never their values.
- **The editor stays local.** It can only show its own pages, and Visual Fix only talks
  to your local dev server.

<br>

## Install

Apple silicon Macs, macOS 13 or newer.

1. Download `GhosttyEXTREME-<version>-macos-arm64.zip` from the
   [latest release](https://github.com/steventsvik/GhosttyEXTREME/releases/latest), unzip
   it, and move **GhosttyEXTREME.app** to `/Applications`.
2. The app isn't notarized, so clear the download quarantine once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/GhosttyEXTREME.app
   ```
3. For agent status and everything built on it, install the hooks from
   `GhosttyEXTREME-<version>-agent-hooks.zip`:
   ```sh
   ./GhosttyEXTREME-agent-hooks/install.sh
   python3 ./GhosttyEXTREME-agent-hooks/install-codex.py   # if you use Codex
   ```
   Then connect Claude Code as described in [Agent status setup](#agent-status-setup).

Your existing Ghostty configuration (`~/.config/ghostty/config`) works as-is.

## Keyboard shortcuts

| Shortcut | |
|---|---|
| ⌘P | Command palette: agents waiting on you, new sessions, every tool |
| ⌃⌘S | Show or hide the sidebar |
| ⌃⌘E | Code editor |
| ⌃⌘V | Visual Fix |
| ⌃⌘M | Mission Control |
| ⌃⌘K | Background |
| ⌃⌘L | Localhost sessions |
| ⌃⌘I | Review changes |
| ⌃⌘R | Race agents |
| ⌃⌘B | Command history |
| ⌃⌘A | Agent activity |

<br>

## Agent status setup

<details>
<summary><b>Connect Claude Code, Codex and your shell</b></summary>

<br>

GhosttyEXTREME sets `GHOSTTY_EXTREME_AGENT_EVENTS=1` in its terminals. The hook
scripts in `agent-hooks/` do nothing anywhere else.

First install them outside the repo:

```sh
./agent-hooks/install.sh
```

This copies the hooks to `~/.ghostty-extreme/agent-hooks/` and the `localhost` command
to `~/.ghostty-extreme/bin/`. Point your agents there rather than at the repo: macOS
privacy protection can block terminal processes from reading `~/Desktop` or
`~/Documents`, which silently breaks the hooks. Rerun it after updating.

**Shell detection** (shows the agent's logo as soon as you start it). Add to `~/.zshrc`:

```sh
[[ -n "$GHOSTTY_EXTREME_AGENT_EVENTS" ]] && source ~/.ghostty-extreme/agent-hooks/ghostty-extreme.zsh
```

**Claude Code status.** In `~/.claude/settings.json`, run
`~/.ghostty-extreme/agent-hooks/agent-hook.sh claude <event>` for these hooks:

| Hook | Event |
|---|---|
| `SessionStart` | `session_start` |
| `UserPromptSubmit` | `prompt_submit` |
| `PostToolUse` | `tool_complete` |
| `PermissionRequest` | `permission_request` |
| `Notification` | `notification` |
| `Stop` | `stop` |
| `StopFailure` | `stop_failure` |
| `SessionEnd` | `session_end` |
| `PreToolUse` (matcher `Bash`) | `pre_tool_use` (moves dev servers into localhost sessions) |

```json
{ "type": "command", "command": "~/.ghostty-extreme/agent-hooks/agent-hook.sh claude stop" }
```

**Codex status.** Run `python3 agent-hooks/install-codex.py` to install Codex tracking
and register its hooks without changing Claude's settings or any saved hook approvals.
It keeps existing hook handlers, backs up the config when adding registrations, and
retains the legacy command path when already configured. Restart Codex afterwards and
approve the new registrations through its normal hook review.

Open a new terminal pane after installation. The GhosttyEXTREME zsh integration
launches interactive Codex with `--no-daemon` and this pane's TTY, so local hooks reach
the correct pane. Codex tracking uses session IDs, live tool hooks and native rollout
records for reads, commands, multi-file patches, failures, messages and reasoning
summaries; child agents appear in their own editor lanes. Private tracking journals
live in `~/.ghostty-extreme/codex-tracking/`.

**Claude usage meter** (optional). Have your Claude Code status line script save
`rate_limits` to `~/.claude/ghostty-extreme/claude-usage.json` as
`{"updated": <unix time>, "rate_limits": <rate_limits>}`.

</details>

## Build from source

<details>
<summary><b>Requirements and build steps</b></summary>

<br>

- macOS 13 or newer (developed and tested on macOS 26, Apple silicon)
- Xcode 26 or newer
- Zig 0.15 from Homebrew: `brew install zig@0.15` (the ziglang.org build fails to link
  against the macOS 26.4+ SDKs)
- `jq` for the agent hooks: `brew install jq`

```sh
git clone https://github.com/steventsvik/GhosttyEXTREME.git
cd GhosttyEXTREME
/opt/homebrew/opt/zig@0.15/bin/zig build -Doptimize=ReleaseFast -Dxcframework-target=native
ditto macos/build/ReleaseLocal/Ghostty.app /Applications/GhosttyEXTREME.app
```

If the repo is in an iCloud-synced folder (like Desktop or Documents), codesign fails on
iCloud's extended attributes. Point `macos/build` at a folder outside iCloud first;
`update-ghostty.sh` does this for you.

**Staying up to date:** `./update-ghostty.sh` rebases this fork onto the newest official
Ghostty release, rebuilds and installs it. `./update-ghostty.sh --check` only reports
whether a new release exists. It needs an `upstream` remote pointing at
`ghostty-org/ghostty`.

</details>

<br>

## License

AGPL-3.0, see [LICENSE](LICENSE). Ghostty's own code is MIT
([LICENSE-GHOSTTY](LICENSE-GHOSTTY)). Parts of the sidebar are derived from
[Warp](https://github.com/warpdotdev/warp) (AGPL-3.0). Full credits and trademark notes
are in [NOTICE.md](NOTICE.md).

For Ghostty itself (configuration, themes, keybindings), see the
[Ghostty documentation](https://ghostty.org/docs).
