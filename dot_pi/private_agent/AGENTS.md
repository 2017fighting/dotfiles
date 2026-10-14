# Global instructions

## Asking the user

Ask through the `ask_user_question` tool, never as prose. A grilling round is a single call: one numbered question per open decision, your recommended answer as the first option, at most four questions, then wait for the answers before the next round.

## Skills

`~/.agents/skills/` holds the mattpocock skill set. When it is unclear which one fits, read `~/.agents/skills/ask-matt/SKILL.md` — it maps situations to skills (grill → spec → tickets → implement, closed by retro). Read a skill's `SKILL.md` before acting on it or describing what it does.

## Environment

- **mise** (`~/.config/mise/mise.toml`) owns global tools: add one with `mise use -g`, never a brew or npm global install.
- **chezmoi** (`~/.local/share/chezmoi`) owns dotfiles and is their source of truth: edit it, then `chezmoi apply` (`just` wraps the usual commands).
- The network is proxied and always reachable, so a failed fetch is a real failure — retry once, then report it.
