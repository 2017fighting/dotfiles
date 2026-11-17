# Global instructions

## Asking the user

Ask through the `ask_user_question` tool, never as prose. A grilling round is a single call: one numbered question per open decision, your recommended answer as the first option, at most four questions, then wait for the answers before the next round.

## Skills

`~/.agents/skills/` holds the mattpocock skill set. When it is unclear which one fits, read `~/.agents/skills/ask-matt/SKILL.md` — it maps situations to skills (grill → spec → tickets → implement, closed by retro). Read a skill's `SKILL.md` before acting on it or describing what it does.

## Searching

`rg` searches content and `fd` searches file names, both rooted at an explicit directory: `.` in the repo at hand, a parent, or `~`. Widen one level at a time while a scoped search comes up empty — a whole-filesystem sweep walks `/` for minutes and returns noise.

## Environment

- **mise** (`~/.config/mise/mise.toml`) owns global tools: add one with `mise use -g`, never a brew or npm global install.
- **chezmoi** (`~/.local/share/chezmoi`) owns dotfiles and is their source of truth: edit it, then `chezmoi apply` (`just` wraps the usual commands).
- The network is proxied and always reachable, so a failed fetch is a real failure — retry once, then report it.

## Concurrent sessions

A git checkout holds ONE branch. When a second session may share a checkout — the user starts another agent, a background job lands, or the repo is already busy — start in a worktree: `mise run wt <name>` creates one and prints the path to cd into. Otherwise another session's `git checkout` moves the branch under a commit and it lands somewhere you did not mean; on 2026-11-17 exactly that put a feature commit on `main`.
