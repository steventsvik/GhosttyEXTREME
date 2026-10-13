# Changelog

What changed in each Tellurion (formerly GhosttyEXTREME) release. Work in progress collects under
**Unreleased**; at release time that heading becomes the version number, and
`./release.sh` uses the section as the release notes.

## Unreleased

- **GhosttyEXTREME is now Tellurion.** "Ghostty" and the ghost icon are trademarks of the Ghostty project, which asked this project not to use them, so the app has a new name and icon: a T sealed in the hexagon, with the same gold and cyan. Every feature, setting and shortcut stays the same, and so do your settings, permissions, paired phones and agent hooks. Menus, windows and alerts say Tellurion, and the command-line tool is now `tellurion` (`tellurion doctor`, `tellurion phone`); `ghostty-extreme` still works. Ghostty's alternate icons (`macos-icon = blueprint`, `xray` and the rest, and `custom-style`) are Ghostty's artwork, so they now show the Tellurion icon; `macos-icon = custom` with your own image still works. Tellurion is still built on Ghostty and still reads your Ghostty config.
- **Your terminal on your phone.** Open your Mac's address in your phone's browser and you get every terminal tab, grouped by project, with agents that need you (a permission prompt, a question) at the top. Tap one to see its screen live, in color, and type to it: a text box that sends with Return, a key row (Esc, Tab, Ctrl, arrows, Ctrl-C, Backspace, Return), and **1 / 2 / 3 / Esc** buttons while an agent is asking for permission. Typing arrives as keystrokes, so vim, shells and agents behave as if you typed on the Mac. **Fit** shows the whole width of the tab; **1:1** shows it at a readable size and follows the cursor. Moving around feels like an app: tabs slide in and out, Back (or the swipe-back gesture, which on the Home Screen comes from the left edge) returns to the list, a strip of tabs across the top jumps between them (or swipe the title for the next one), a banner says when another agent needs you, and each tab keeps what you'd started typing. Reloading keeps you in the tab you were in. Add it to your Home Screen to use it like an app. It works anywhere your phone has internet, over your own private Tailscale network: nothing goes through a server of ours, and GhosttyEXTREME never turns on Tailscale Funnel.
  - **Setting it up.** A small phone in the bottom-right corner of the terminal shows whether phone access is live: dim when it's off, gold while it waits for a phone, green with a phone connected. Hover it for the details (including which Tailscale step is missing); clicking it opens the Phone window: once Tailscale is set up it leads with whether phone access is live, the pairing code (already showing if no phone is paired yet) and your phones, with the finished checklist folded away at the bottom. Before that, it's a short checklist with one button per step (install with Homebrew, turn on and sign in, open Tailscale's DNS settings for HTTPS, a QR code to get Tailscale on your phone), which ticks itself off as you go. From a terminal, `ghostty-extreme phone` prints the same status in one line and `ghostty-extreme phone setup` walks through the steps, asking before each one.
  - **Pairing.** **Turn on phone access** gives this Mac a private HTTPS address on your tailnet, and **Pair a phone…** shows a QR code and a short code like `K7QM-2XRD` that works once, for 10 minutes. Scan it, or type it on the phone (the Home Screen app can't scan). Only devices signed in to your own Tailscale account can connect, each must be paired first, and five wrong codes withdraw the code. Paired phones are listed with when they were last used; remove one on the Mac, or **Unpair this phone** on the phone. The Phone switch in Settings hides all of this and turns phone access off.
- **Fixed:** a localhost session stayed **Live** after its dev server crashed when the process above it kept running (Next.js's `next dev` does), and its address moved to one of that process's internal ports. It now says **Not listening** after a few seconds, and an agent starting the same server again restarts that session in its tab instead of being told it's already running. Two starts at once no longer open a second tab: the later one waits for the first.
- **Fixed:** opening Visual Fix from a dev server's own tab (Fix on its card, or ⌃⌘V there) put the panel in the server's tab. It now opens in the tab of the agent working on that project.
- **Fixed:** Claude's **5h** usage row disappeared between 5-hour windows, when Claude Code leaves that window out of its report. The 5h and Week rows now stay, keeping the last numbers until they reset.

## 1.5.8

- **jj (Jujutsu) support.** In a jj repository the sidebar shows the change you're on (or its nearest bookmark), and the Git panel shows jj instead of branches and stashes: the working-copy change with Describe, Commit, New change and Squash; the changes around it (edit one, start a new change on top, abandon); bookmarks with Fetch and Push; and the operation log, where Undo last or Restore reverses any jj command, an agent's included. Undo a Turn remembers jj's state when each turn starts, so if the agent also ran jj commands, **Restore with jj** puts jj's history back along with the files. Works with jj repositories that keep a git repository beside them (the default) and ones that don't. Pull request status and Create… work from the bookmark.
- **GitButler.** When GitButler manages a repository, the sidebar names the branches it has applied (instead of gitbutler/workspace), and the Git panel shows them side by side with their commits, push state and pull requests, what's uncommitted, and GitButler's own Commit (to the branch you pick), New branch, Push and Undo, plus Open GitButler. Branch switching and stashes are hidden there, since they'd take the repository out of GitButler's workspace.
- **Graphite.** In a repository set up with `gt init`, the Git panel shows the stack your branch is in, from trunk to the top, with each branch's pull request and a "needs restack" marker. Restack, Submit (the whole stack) and Sync run Graphite in a new tab, so you see its questions and your login works.
- **Live status for more agents.** GhosttyEXTREME now connects to GitHub Copilot CLI, Droid, Kiro CLI, Gemini CLI, Antigravity CLI (agy), Cursor CLI and OpenCode, so their tabs show Working, Done and (where the agent reports it) Needs permission, with notifications, Mission Control and Undo a Turn, like Claude Code and Codex. Check Setup offers Connect for each one it finds on your Mac; it adds a small observer hook (OpenCode: a plugin) that never approves, blocks or changes anything, and backs up any settings file it touches. Copilot, Droid, Gemini and OpenCode report permission prompts; Kiro, Antigravity and Cursor don't have a way to, so they show Working and Done.
- **More agents recognized.** Antigravity (agy), Kiro, Aider, Crush, Qwen Code, Kimi and Mistral Vibe get their own logo and name in the sidebar when you start them, alongside the ones already recognized.
- **Environment window** (⌃⌘N, Environment in the command palette, or the sidebar's … menu). **This Folder** shows what the folder sets up: the tool versions it asks for (mise, asdf, .nvmrc, .python-version and friends), which aren't installed, when the terminal's own copy differs, and the environment variables mise and direnv add (names only; values are never read). Trust a mise config, install missing versions, and allow or block an .envrc (after seeing what it runs). **Containers** lists everything Docker runs (Docker Desktop, OrbStack or Colima), grouped by Compose project, with CPU, memory, published ports, and Start, Stop, Restart, Logs, a shell inside, and Remove. **Local Models** shows the models in Ollama and LM Studio, which are loaded and how much memory and GPU they take, with Unload, Run, Pull and Remove.
- **Fixed:** connecting Claude Code or Codex in Check Setup replaced a symlinked settings file (a dotfiles repo, say) with a plain copy. The link now stays, and the file it points to gets the hooks.

## 1.5.7

- **Skills.** A new Skills window (the puzzle-piece button at the top of the sidebar, ⌃⌘U, or Skills in the command palette) shows every skill your agents have, in one place: Claude Code, Codex, Cursor, Hermes, the shared `~/.agents/skills` folder, Claude Code plugins, Claude.ai's synced skills, and the current project's own. Skills installed with `npx skills` or cloned with git are checked against their source, with **Update** on each and **Update All**. **Discover** shows what's trending, hot and most installed on skills.sh, with search, install counts and security reviews; official company skills are hidden unless you want them. **Install** lets you pick which agents get it and whether it's for every project or just this one, shows the exact command, and runs it in a new tab.
- **The sidebar's tool buttons fit any width.** When the row of buttons at the top of the sidebar doesn't fit, Condense and Agent Activity (and in a very narrow sidebar, Skills) move into a … menu at the end instead of being cut off.

## 1.5.6

- **A proper update screen.** Clicking the gold update button in the corner (or "What's new" on the sidebar card) opens GhosttyEXTREME's own update window: the new version, its size and date, what's new in it, and **Update and restart** (or **Update when done** while agents are mid-turn), **Later** and **Skip this version**. After you click Update, the same window shows the progress: downloading with a percentage and size, preparing, then restarting. Check for Updates… opens it straight away when there's a new version.
- **Localhost folds away.** Click the LOCALHOST heading in the sidebar to collapse its cards to one line, and again to bring them back. It remembers which way you left it.
- **Notarized by Apple.** The app is now signed with a Developer ID certificate and notarized, so a downloaded zip opens with a double-click instead of macOS saying it can't check it for malicious software. No more clearing the quarantine by hand. Because the certificate changed, macOS may ask once more for permissions you'd already given (notifications, folders); updating from the app works as before.

- **GhosttyEXTREME has a website**: [steventsvik.github.io/GhosttyEXTREME](https://steventsvik.github.io/GhosttyEXTREME/). Every feature on an interactive select screen with live previews and full details, the agent turn and the rest of the story told as scroll-driven scenes, a comparison table, and a download button that always points at the latest release. It lives in `docs/` and is served by GitHub Pages.

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
