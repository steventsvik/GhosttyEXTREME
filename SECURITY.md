# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue: use
[Report a vulnerability](https://github.com/steventsvik/GhosttyEXTREME/security/advisories/new)
on the repository's Security tab. Include what you found, how to reproduce it, and which
version you're on (GhosttyEXTREME → About).

You'll get a reply within a few days. Fixes ship in a new release, and the advisory is
published once people have had a chance to update.

Problems in Ghostty itself (the terminal emulator, not GhosttyEXTREME's additions) should
go to the [Ghostty project](https://github.com/ghostty-org/ghostty/security).

## Supported versions

Only the latest release gets security fixes. GhosttyEXTREME updates itself through
**Check for Updates…**; downloads are checked against a signature built into the app.

## What GhosttyEXTREME does and doesn't do

- **Nothing leaves your Mac.** No account, telemetry or server. Agent tracking reads the
  session files Claude Code and Codex already write.
- **Only its own hooks can send it events.** Agent status arrives as terminal escape
  sequences; each launch creates a secret that only its own terminals and hooks know, and
  events without it are ignored.
- **The Backend view never reads credentials.** It runs your providers' own CLIs with their
  existing logins, read-only commands only, and reads only the names of env variables.
- **The code editor and Visual Fix stay local.** The editor only shows its own pages, and
  Visual Fix only talks to your local dev server.
- **Releases** are built and checked by `release.sh` (including a scan for keys, tokens and
  personal paths), and every release lists SHA-256 checksums.
