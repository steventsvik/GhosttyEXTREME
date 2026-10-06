# Changelog

What changed in each GhosttyEXTREME release. Work in progress collects under
**Unreleased**; at release time that heading becomes the version number, and
`./release.sh` uses the section as the release notes.

## Unreleased

**Set up in a minute**
- A welcome window on first launch finds Claude Code, Codex and the tools the hooks need, connects your agents in one click, lets you pick features, and runs a live test. It only appears when something needs setting up; open it any time from the GhosttyEXTREME menu.
- The agent hooks now come inside the app. Setting up copies them to `~/.ghostty-extreme`, adds GhosttyEXTREME's entries to `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.zshrc` (each backed up first, your own hooks untouched), and a rebuilt app keeps installed hooks up to date. No more separate hooks download or `install.sh`.
- **Check Setup** (GhosttyEXTREME menu or ⌘P) checks the hooks, each agent's config, jq, the shell integration, notifications and recent hook errors, with a fix button on each problem. **Copy report** gives a plain-text report for GitHub issues.
- `ghostty-extreme doctor` runs the same checks in a terminal and sends a test event through the real hooks.
- The sidebar shows a warning when agent status needs fixing, and a confirmation when a live test arrives.

**Settings**
- **GhosttyEXTREME Settings** (⌃⌘,) turns each feature on or off: code editor, Visual Fix, Mission Control, races, localhost sessions, review, undo, command history, activity, Background and the usage meter. A feature that's off has no menu item, shortcut, button or palette entry, and does no background work. Presets: Everything, Agent essentials, Just the sidebar.
- Animation (Full or Status only), aurora, compact rows and sidebar width, plus removing the hooks again.

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
