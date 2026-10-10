# Changelog

What changed in each GhosttyEXTREME release. Work in progress collects under
**Unreleased**; at release time that heading becomes the version number, and
`./release.sh` uses the section as the release notes.

## Unreleased

## 1.5.5.1

- **No more tab bar at the top of the window.** Tabs live in the sidebar, but macOS's own tab bar could still show up in the window's top corner (#23). It's now removed for good, including with `macos-titlebar-style = tabs`, which now gives the normal transparent titlebar. View → Show Tab Bar is gone too; ⌘1–9, ⌘P and the Window menu still switch tabs when the sidebar is hidden.

## 1.5.5

- **Updates show up on their own.** GhosttyEXTREME checks for a new release shortly after it starts and every hour, and an update card appears at the top of the sidebar with the new version, what's new, and **Update and restart**.
- **A progress bar while it updates:** downloading with a percentage, preparing, then restarting.
- **Everything comes back after an update.** Windows, tabs, splits and folders reopen, Claude Code and Codex sessions resume in their panes (`claude --resume`, `codex resume`), and localhost servers start again in their tabs. If an agent is mid-turn, **Update when done** waits for it to finish first.
- **Fixed:** automatic update checks could be switched off for good on Macs that had ever run a self-built copy, so updates only appeared through Check for Updates…. Release builds now always check unless `auto-update = off`.
- "What's new" for an update opens GhosttyEXTREME's release notes, not official Ghostty's.
- **Agent Activity covers any period.** Next to Today, 7 days and 30 days there are 90 days, This year, All (back to your first session) and Custom, which picks any from-and-to dates. Time, tokens and API value all follow the period, and long periods chart by week or by month.

## 1.5.4

- **Visual Fix requests read clearly on the agent's card.** The card, Mission Control and the notification showed `[Image #1] <pasted_content id=…>` as the task; they now show "Visual fix: " and the change you asked for. Image placeholders and paste markers are left out of every task.
- **Undoing a turn updates Review.** After you undo an agent's turn, its changes leave the review inbox (or it shows only what's left), instead of listing a diff that's no longer there.

## 1.5.3

- **Allow and Deny work with Claude Code 2.1.29x.** Its permission prompt now ends with a numbered "No" and "Esc to cancel" instead of "No, and tell Claude what to do differently", so GhosttyEXTREME didn't recognize it and showed no Allow or Deny on the card, in Mission Control or in the notification. Both forms work now.
- **Codex cards show the right task again.** Codex's own background memory agent ("Memory Writing Agent: Phase 2") runs from the same terminal; its prompt used to replace your task on the card, and its work kept the card on Working after Codex had finished. It's now ignored.

## 1.5.2

- **Project Memory** (⌃⌘Y, the tab's ⋮ menu, or the command palette): see what Claude Code and Codex remember about the tab's project, in one window. Claude Code's notes can be edited and deleted (a deleted note leaves `MEMORY.md` too); Codex's memories for the project are shown read-only, since Codex rewrites them itself; and the `CLAUDE.md`, `CLAUDE.local.md` and `AGENTS.md` files the agents load every session can be edited in place. It never overwrites a file an agent changed while you were editing.
- **Shared memory**: Claude Code and Codex now share what they've learned about a project. A new Codex session starts with Claude Code's notes for the project (and its `CLAUDE.md`), and a new Claude Code session with Codex's memories for it (and its `AGENTS.md`), labelled as notes that may be out of date. Nothing leaves your Mac. Turn it off with Shared memory in Settings or the Project Memory window. GhosttyEXTREME updates the installed hooks when it starts, so new sessions get it right away.
- **Hand Off and Review Loop carry project notes** to an agent that's already running: when Claude Code hands work to a running Codex (or the other way round), the message includes what the first agent remembers about the project, since a running session never gets them at its start. Shown as "Project notes" under Include in Hand Off.
- **Settings is ⌘,** (or whatever your config binds `open_config` to), from the terminal too, and the menu bar says GhosttyEXTREME. Ghostty's config file moved to GhosttyEXTREME → Edit Config File…; ⌃⌘, still opens Settings.
- **Localhost sessions** catch more of the servers Claude Code starts, so they open in their own tab instead of running hidden in the background: SSH tunnels (`ssh -L`, `gcloud compute ssh … -L`), `kubectl port-forward`, `ngrok` and `cloudflared`; project scripts and `make`/`just` targets it runs in the background whose names say what they are (`scripts/run.sh dashboard`, `make dev`); and any command that has run in a localhost session in that folder before.

## 1.5.1

- **Hand Off and Review Loop** always start from the pane you opened them from. A window still open from another pane used to come forward unchanged and hand off that pane's work ([#10](https://github.com/steventsvik/GhosttyEXTREME/issues/10)).
- **Allow notifications** in Check Setup now says what to do and opens System Settings → Notifications when macOS doesn't show its prompt (Focus modes can hide it), instead of seeming to do nothing ([#11](https://github.com/steventsvik/GhosttyEXTREME/issues/11)).
- **Ports, with VoiceOver**: pressing a port row now goes to its tab, like a click. It used to run the row's actions, which could open the browser and stop the server; Stop, Open in browser and Open in Visual Fix are separate named actions ([#12](https://github.com/steventsvik/GhosttyEXTREME/issues/12)).
- Builds you make yourself no longer check for updates automatically (they'd always see the latest release as newer); Check for Updates… still works.

## 1.5.0

**Set up in a minute**
- A welcome window on first launch finds Claude Code, Codex and the tools the hooks need, connects your agents in one click, lets you pick features, and runs a live test. It only appears when something needs setting up; open it any time from the GhosttyEXTREME menu.
- The agent hooks now come inside the app. Setting up copies them to `~/.ghostty-extreme`, adds GhosttyEXTREME's entries to `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.zshrc` (each backed up first, your own hooks untouched), and a rebuilt app keeps installed hooks up to date. No more separate hooks download or `install.sh`.
- **Check Setup** (GhosttyEXTREME menu or ⌘P) checks the hooks, each agent's config, jq, the shell integration, notifications and recent hook errors, with a fix button on each problem. **Copy report** gives a plain-text report for GitHub issues.
- `ghostty-extreme doctor` runs the same checks in a terminal and sends a test event through the real hooks.
- The sidebar shows a warning when agent status needs fixing, and a confirmation when a live test arrives.

**Settings**
- **GhosttyEXTREME Settings** (⌃⌘,) turns each feature on or off: code editor, Visual Fix, Mission Control, races, localhost sessions, review, undo, command history, activity, Background, the usage meter, Ports and the Git panel. A feature that's off has no menu item, shortcut, button or palette entry, and does no background work. Presets: Everything, Agent essentials, Just the sidebar.
- Animation (Full or Status only), aurora, compact rows and sidebar width, plus removing the hooks again.

**Ports**
- A Ports section in the sidebar lists what's listening and which project it belongs to (Next.js, Vite, Django and more get their own badge). Open it in the browser or Visual Fix, click it to go to its tab, or **Stop** it (click twice). Apps and container ports are one click away.
- When a command fails because its port is taken ("EADDRINUSE", "address already in use"), the sidebar names what holds the port and offers to stop it.
- The list reads sockets straight from macOS, so it costs a couple of milliseconds every few seconds, and nothing while GhosttyEXTREME is in the background.

**Git panel**
- Click a tab's branch in the sidebar for a panel with its pull request (title, review state and every check, failing ones first, each linked to its log), branches (switch, filter, create), stashes (stash, apply, pop, drop) and recent commits.
- Tabs show commits to push and pull (↑2 ↓1) and the branch's pull request with its checks (#123 ✓) beside the branch.
- Pull requests come from the GitHub CLI (`gh`) when it's installed and signed in, refreshed every minute and when an agent finishes a turn. Switching branches warns when an agent is working in the tab and offers to stash uncommitted changes first.

**Agents working together**
- **Hand Off…** (⋮ menu, Mission Control, ⌘P) passes a pane's work to another agent with what it needs: the task, the recent conversation, exactly what the first agent changed (a diff since its first prompt, from the undo snapshots) and failed commands. Review, continue, or ask for a second opinion; to a new Claude Code or Codex beside it, or to one that's already running. You can read and edit the message first.
- **Review loops**: pair an agent with a reviewer (⋮ → Start a review loop…). When the writer finishes a turn, the reviewer gets its changes and answers APPROVED or CHANGES NEEDED; its findings go back to the writer, round after round, until it approves or the round limit (3 by default). Each message waits for you to press Send on the agent's card, unless you turn on Send automatically.
- **Send a failed command to the agent already working on the project**: the failed-command chip offers it first, with the output and what's changed.
- Messages are only ever typed into an agent between turns, into an empty input box: never into a permission prompt, a menu or a dialog, and never over something you've started typing (greyed-out suggestions don't count). Until then they wait on the agent's card, where you can drop them.

**Install and update**
- **One-line install**: `curl -fsSL https://raw.githubusercontent.com/steventsvik/GhosttyEXTREME/custom/install.sh | bash` downloads the latest release, checks its checksum and puts it in /Applications, with no quarantine step.
- **Updates in the app**: GhosttyEXTREME now checks its own releases (GhosttyEXTREME → Check for Updates…, and automatically) and installs them. Updates are signed with this project's key and nothing else is accepted.
- **Fixed**: Check for Updates… used official Ghostty's feed, which could offer plain Ghostty and replace GhosttyEXTREME ([#13](https://github.com/steventsvik/GhosttyEXTREME/issues/13)). Coming from 1.4.x, install this version once with the line above; later versions update in the app.
- Releases are signed with the same certificate every time, so macOS keeps your permissions (notifications, folder access) across updates.

**Every shortcut at a glance**
- Hold ⌃⌘ for a moment to see every ⌃⌘ shortcut over the window, along with Ghostty's essentials; let go and it's gone. ⌃⌘/ keeps it open.

**Answer permission prompts from anywhere**
- **Allow** and **Deny** on an agent's permission prompt, from its sidebar card, Mission Control or the notification, without switching to its pane.
- Keys are only sent when the pane is showing Claude Code's or Codex's prompt with the first "Yes" selected, so a status that's a moment out of date can't send a stray Enter or Escape.

**Undo an agent's turn**
- Every agent turn starts with a snapshot of the project. Undo the last turn (or an earlier one) from the tab's ⋮ menu, or with **Restore to before this** on any prompt in the agent timeline.
- Restoring lists every file it will change and asks first; Return cancels. Your current files are saved before a restore, so you can undo the restore too.
- Snapshots are git objects written through a copy of the index: no commits, branches or stash entries, and your staged changes are untouched. Folders that aren't repositories work too.

**Lighter**
- Each tab's code editor is only created when you first open it, and freed when you close it and its agent has exited. Before, every tab with an agent kept a hidden editor (a separate WebKit process) in the background.

**Calmer terminal frame**
- The light racing around the terminal's edge is gone. The corners breathe while an agent works and pulse smoothly when one needs you.

## 1.4.1

- No more high CPU while a dev server runs: the pulsing dot on localhost server cards now plays in Core Animation.
- The sigil's glow pauses while its window is off screen.
- Code map: a file's "Imported by" list no longer comes up empty when clicked early.
- Database view: D1 tables no longer show a `public.` prefix.

## 1.4.0

Code map, Backend tab (Cloudflare, Supabase, Vercel), Background processes window,
API value in Agent activity, a refined interface, much lower CPU, and events that only
your own hooks can send. Full notes: [GhosttyEXTREME 1.4.0](https://github.com/steventsvik/GhosttyEXTREME/releases/tag/extreme-1.4.0).

Earlier releases: see [Releases](https://github.com/steventsvik/GhosttyEXTREME/releases).
