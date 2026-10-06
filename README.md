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
  <a href="#watch-your-agents-work-live">Live agents</a> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#keyboard-shortcuts">Shortcuts</a> ·
  <a href="#security-and-privacy">Security</a>
</p>

<p align="center">
  <img src="images/readme/main-window.png" alt="GhosttyEXTREME with a live Claude Code agent: the agent sidebar, the terminal, the code editor typing in the agent's edit, and the code map tracing its path" width="100%">
</p>

<p align="center"><sub>One window, one live agent: the sidebar, the agent in the terminal, the editor typing in its
edit as it happens, and the code map tracing every file it has read and changed.</sub></p>

**GhosttyEXTREME** is [Ghostty](https://ghostty.org), the fast native macOS terminal, rebuilt
for working with AI coding agents like **Claude Code** and **Codex**. You see every agent
work, live: what it's doing in each tab, the code it's writing as it writes it, where it is
in your project and what part of your backend it touches. When it finishes, its changes wait
for you in a review inbox.

Everything Ghostty does still works. This fork tracks official Ghostty releases and adds
its features on top.

> [!NOTE]
> Unofficial fork. Not affiliated with or endorsed by the Ghostty project.

<br>

## Watch your agents work, live

Run Claude Code, Codex, Gemini CLI or another agent in a tab, the way you already do.
GhosttyEXTREME follows each one as it works, with nothing to set up beyond its hooks.

| As the agent… | …you see |
|---|---|
| **starts a task** | Its card in the sidebar shows the task, a working spinner and a timer. Its sprite starts typing and the terminal's frame lights up cyan. |
| **reads a file** | The editor opens that file at the lines it read; the file lights up cyan on the code map, and a comet flies there. |
| **edits a file** | The change types itself into the editor with the lines highlighted, the file turns orange on the map, and the turn's diff count goes up. |
| **thinks or replies** | The agent panel shows its thinking, messages and every tool call as a timeline, sub-agents included. |
| **touches your backend** | The Worker, database or bucket that code belongs to lights up in the Backend view. |
| **needs you** | Its card turns amber and jumps to the top of the command palette and Mission Control; you get a notification and a Dock badge. |
| **finishes** | Its sprite sparkles, the sigil flares gold, and its changes land in Review with the full diff. |

Several agents at once? Each tab follows its own, tabs in the same repository are grouped,
and you're warned when two agents edit the same file.

<br>

## Features

<table>
<tr>
<td width="33%" valign="top"><b><a href="#every-agent-at-a-glance">Agent sidebar</a></b><br><sub>Live status for every agent in every tab</sub></td>
<td width="33%" valign="top"><b><a href="#a-code-editor-that-follows-the-agent">Code editor</a></b><br><sub>Opens what the agent reads and animates its edits</sub></td>
<td width="33%" valign="top"><b><a href="#code-map">Code map</a></b><br><sub>Your project as a star map of what the agent touched</sub></td>
</tr>
<tr>
<td valign="top"><b><a href="#see-your-backend">Backend view</a></b><br><sub>Cloudflare, Supabase, Vercel and more, with live status</sub></td>
<td valign="top"><b><a href="#database">Database view</a></b><br><sub>Tables, columns and relations from your schema</sub></td>
<td valign="top"><b><a href="#visual-fix">Visual Fix</a></b><br><sub>Click an element in your app, say what to change</sub></td>
</tr>
<tr>
<td valign="top"><b><a href="#review-changes">Review changes</a></b><br><sub>An inbox for each agent's diff, with line comments</sub></td>
<td valign="top"><b><a href="#agent-races">Agent races</a></b><br><sub>Several agents, one task, keep the best result</sub></td>
<td valign="top"><b><a href="#localhost-sessions">Localhost sessions</a></b><br><sub>Dev servers that outlive the agent that started them</sub></td>
</tr>
<tr>
<td valign="top"><b><a href="#background-processes">Background processes</a></b><br><sub>Find and close what's been left running</sub></td>
<td valign="top"><b><a href="#command-history">Command history</a></b><br><sub>Every command as a block, with one-click fixes</sub></td>
<td valign="top"><b><a href="#agent-activity">Agent activity</a></b><br><sub>Time, prompts, changes and tokens per day and project</sub></td>
</tr>
<tr>
<td valign="top"><b><a href="#mission-control">Mission Control</a></b><br><sub>Every agent in every window on one screen</sub></td>
<td valign="top"><b><a href="#sessions">Sessions</a></b><br><sub>Agents, Docker sandboxes, Hermes and cloud sessions</sub></td>
<td valign="top"><b><a href="#handoff">Handoff</a></b><br><sub>Pass a pane's work to Claude or Codex</sub></td>
</tr>
</table>

<br>

### Every agent, at a glance

A Warp-style vertical sidebar (⌃⌘S) lists every tab with its folder, git branch and
uncommitted changes. Tabs can be pinned, colored and renamed, and hovering one shows a card
with more detail.

- **It recognizes the agent in each tab:** Claude Code, Codex, Gemini CLI, Copilot, Cursor,
  Amp, opencode, Goose, Droid and Hermes, each with its own logo.
- **Live status:** working, waiting for permission, waiting for input, done or failed. Each
  card shows the task, how long the agent has been at it and its last action.
- **Agents act out their mood.** Their sprite reads, types, runs commands and thinks, hops
  when it needs you and sparkles when it's done.
- **The sigil comes alive.** One cyan pixel orbits the sidebar's sigil per working agent;
  it glows amber while one waits and flares gold when one finishes.
- **The terminal's frame lights up too.** A cyan light travels around the edge while the
  tab's agent works, and the corners blink amber when it needs you.
- **Project groups:** tabs whose agents share a repository are bracketed together, with a
  live summary ("2 working · 1 waiting") and a warning when two agents edit the same file.
- **Alerts:** when an agent waits on you in a pane you aren't looking at, you get a
  notification (click it to jump there) and a count on the Dock icon.
- **Usage meters** for your Claude and ChatGPT plans (5-hour and weekly windows), with
  graphs.

### Mission Control

⌃⌘M shows every agent (or every pane) in every window as a live card: status, task, last
action, time in that state and the last lines of its terminal. Agents waiting on you come
first. Click a card to jump to it.

The **command palette** (⌘P) puts waiting agents at the top too, so you can answer one in
two keystrokes. It also starts new sessions and opens every tool.

<br>

### A code editor that follows the agent

<p align="center">
  <img src="images/readme/code-map.png" alt="The code map: the project as a star map, with the agent's path and a file's blast radius" width="100%">
</p>

Each tab has its own VS Code–style editor (Monaco, ⌃⌘E) on that tab's folder, in your
terminal theme.

- **Follow mode:** the editor opens each file the agent reads and animates its edits in as
  they happen. It follows even while closed, so opening it mid-task shows where the agent
  is right away.
- **Agent panel:** a timeline of the session: prompts, thinking, messages, tool calls and
  results, sub-agents included. With several sub-agents, the editor splits into a pane for
  each.
- **AI POV:** replay a session as if you were at the agent's keyboard: files opening, code
  being typed, commands running.

#### Code map

Your project as a star map. Folders are tinted by what they are: frontend, API, database,
tests, config. Files light up as the agent reads (cyan) and edits (orange) them, and the
agent flies between them as a comet.

- **Zoom levels:** **Overview** shows the project's areas and how much the agent did in
  each. **Files** shows every file. **Symbols** shows the functions and classes inside, with
  the ones changed this turn lit.
- **Details for anything you click:** what the agent did there, this turn's diff, the
  file's symbols, what imports it, and the backend pieces it uses.
- **Blast radius:** what imports the file is drawn on the map, with a warning when no
  test covers the change.

<br>

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
- **Code links:** click any piece to see every file that uses it, and open the provider's
  dashboard or your live site.
- **Agent awareness:** when the agent edits something that belongs to a piece of your
  backend, that piece lights up.

#### Database

<p align="center">
  <img src="images/readme/database.png" alt="The Database view: tables, columns and relations" width="100%">
</p>

The **Database** view draws your schema: tables, columns and relations for Supabase,
Cloudflare D1, Postgres behind Hyperdrive (read from your migrations) and Prisma.

- **Click a table** to see its columns, what references it and where your code queries it.
- **Row-level security** is checked on every Postgres table.
- **Large schemas** can be searched, and unrelated tables fade back.

<br>

### Visual Fix

<p align="center">
  <img src="images/readme/visual-fix.png" alt="Visual Fix: your running app beside the terminal, ready to pick an element" width="100%">
</p>

⌃⌘V previews your running dev server beside the terminal, at desktop, tablet or phone size.

- **Pick an element:** hover any element and click it, then say what should change.
- **What the agent gets:** the element's HTML and CSS selector, the component and source
  file that render it (React, Vue and Svelte), its computed styles, and a screenshot.
- **Where it goes:** the request goes to the agent working in that project, pinned to the
  element. When the change lands, the preview reloads where you were.

### Review changes

When an agent finishes working in a git repository, its changes land in an inbox (⌃⌘I).

- **Read the diff** file by file.
- **Comment on lines** and send the comments back as the agent's next prompt.
- **Finish up:** approve or undo files, commit, or open a pull request.

### Agent races

⌃⌘R gives the same task to several agents at once (Claude Code and Codex, or several of
one), each in its own git worktree so they can't touch each other's work or yours. Compare
their diffs side by side and apply the one you want.

### Handoff

Pass a pane's work to another Claude Code or Codex session: a new one in a split beside it,
or one that's already running. The message carries the task, the recent conversation,
exactly what the first agent changed (since its first prompt) and failed commands, and you
can edit it first. **Continue** picks up where the last agent stopped, **Review** checks
the work without editing anything, and **Second opinion** weighs in on the approach. A
failed command can go straight to the agent already working on the project.

<br>

### Review loops

Pair an agent with a reviewer: each time the writer finishes a turn, the reviewer gets its
changes and answers APPROVED or CHANGES NEEDED, and its findings go back to the writer,
until it approves or a round limit. Every message waits for your Send unless you turn on
Send automatically, and nothing is ever typed into an agent mid-turn or over your own
typing.

### Localhost sessions

When an agent starts a dev server (`npm run dev`, `vite`, `rails s`,
`python -m http.server`, …), it opens in its own tab instead, so it keeps running after
the agent is done. The agent is told the URL and how to read the logs.

- **Sidebar cards:** each server gets a card with live status, its `localhost` URL,
  framework, uptime, restart and stop.
- **The Localhost manager** (⌃⌘L) groups servers by project and shows their CPU and memory.
  It previews pages in a built-in browser and finds dev servers running elsewhere on your
  Mac, with **Keep alive** to move one into its own tab.
- **Start one yourself** from **New → Localhost Server…**, which offers your
  `package.json` scripts.

### Background processes

<p align="center">
  <img src="images/readme/background.png" alt="The Background window: leftover VMs, containers, agent sessions and browsers with staleness ratings" width="85%">
</p>

⌃⌘K finds everything left running: dev servers, Colima VMs and containers, agent sessions,
browser automation, databases, watchers, log followers and login services.

- **Last really used:** the last typing or output in its terminal, its agent transcript
  being written, a live connection to its port, or a busy container.
- **A staleness rating** (Active, Idle, Stale or Ready to close), with the reasons.
- **Cleanup in one click,** always with a confirmation first. Login services are never
  marked ready to close.

### Ports

The sidebar lists what's listening, which project it belongs to and what started it.
Open it in the browser or Visual Fix, jump to its tab, or stop it. When a command fails
because its port is taken, the sidebar says what holds the port and offers to stop it.

### Git panel

Click a tab's branch for its pull request and every check (from the GitHub CLI), branch
switching, stashes and recent commits. Tabs show commits to push and pull and the pull
request's state beside the branch.

### Command history

Every command becomes a block with its output, exit code and duration (⌃⌘B). When one
fails, a chip offers **Fix with Claude** or **Fix with Codex**, which opens the agent in a
split with the command and its output.

### Agent activity

⌃⌘A shows active time, prompts, files and lines changed, commands, test runs and tokens,
per day, hour, agent and project. It reads the session history Claude Code and Codex
already keep.

- **Resume** any recent session in a new tab.
- **API value** shows what your usage would cost at API prices.

### Sessions

**+ New** in the sidebar opens a terminal, Claude Code, Codex, a Claude Code cloud
session, Hermes, or a localhost server.

- **Isolated sessions** run Ubuntu, Python, Node, or sandboxed Claude Code or Codex in a
  throwaway Docker container. Only the project folder is shared (never your home
  folder), and the container is deleted when you exit.
- **Hermes tabs** open Hermes's own app (chat, sessions, skills, models and cron) right in
  the tab.

### Everything Ghostty already does

GPU-accelerated rendering, native tabs and splits, the quick terminal, hundreds of themes,
ligatures, shell integration, AppleScript and Shortcuts. Your Ghostty config works as-is.

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
3. Open it. The welcome window finds Claude Code and Codex, connects them in one click
   (backing up each file it changes) and runs a live test. Come back to it, or to
   **Check Setup**, from the GhosttyEXTREME menu; `ghostty-extreme doctor` runs the same
   checks in a terminal.

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
| ⌃⌘/ | Every shortcut (or hold ⌃⌘ for a moment) |
| ⌃⌘, | GhosttyEXTREME Settings: turn features on or off |

<br>

## Agent status setup

<details>
<summary><b>Connect Claude Code, Codex and your shell</b></summary>

<br>

The welcome window and **Check Setup** do all of this for you. The steps below are what
they do, for doing it by hand.

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
