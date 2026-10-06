# Changelog

What changed in each GhosttyEXTREME release. Work in progress collects under
**Unreleased**; at release time that heading becomes the version number, and
`./release.sh` uses the section as the release notes.

## Unreleased

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
