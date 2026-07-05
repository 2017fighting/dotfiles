# CLAUDE.md

This repository is a **chezmoi dotfiles** repo, not an application. It manages
config files for macOS and Linux: shell (sh/bash/zsh), Go templates (`.tmpl`),
TOML, YAML, and Lua. There is **no build step and no test suite.**

> **Read [`AGENTS.md`](./AGENTS.md) for the full guide.** It is the source of
> truth for code style, chezmoi prefixes, naming conventions, and workflows.
> This file is a quick reference only.

## Commands

| Task | Command |
| --- | --- |
| Preview pending changes (REQUIRED before apply) | `chezmoi diff` |
| Dry-run validate | `chezmoi apply --dry-run --verbose` |
| Deploy to `$HOME` | `chezmoi apply` |
| Re-sync a target file back into the source | `chezmoi re-add <file>` |
| Resolve conflicts | `chezmoi merge-all` |
| Task-runner shortcuts | `just` (then `just diff` / `just apply` / `just dump` / `just re-add`) |
| Refresh Brewfile | `just dump` (= `brew bundle dump --force ...`) |
| Lint shell | `shellcheck <file>` |
| Format shell | `shfmt -i 2 -ci -bn -w <file>` |
| Lint YAML / markdown | `yamllint <file>` / `markdownlint <file>` |

`just dump` regenerates `dot_config/homebrew/Brewfile` and re-adds it to chezmoi.

## Critical constraints

- **Always run `chezmoi diff` before `chezmoi apply`.** Apply writes to `$HOME`.
- **No `set -e` in `.chezmoiscripts/` lifecycle scripts** — they run on every
  machine and must tolerate partial failure. Guard critical steps explicitly:
  `if [ -f "$FILE" ]; then ...`.
- **Never commit unencrypted secrets.** Secrets use **age** encryption
  (`encrypted_*.age`); key lives at `~/.config/chezmoi/key.txt`. SSH keys are
  loaded into the OS-native ssh-agent by `bw-ssh-add` (unlocks Bitwarden via
  the `bw` CLI, then `ssh-add`).
- **This source dir deploys to `$HOME`.** Files here are not deployed unless they
  carry a chezmoi prefix — so a plain `CLAUDE.md`/`README.md` at root stays
  repo-only.

## Chezmoi prefix cheat sheet

- `dot_` → hidden target (`.zshrc`), `private_` → sensitive, `executable_`,
  `symlink_`, `encrypted_` (with `.age`).
- Scripts: `run_` (every apply), `run_once_` (once per machine),
  `run_onchange_` (when content hash changes).
- Third-party Claude plugins (plannotator, ecc): `.chezmoiexternals/<name>.yaml.tmpl`
  clones pin a tag; `run_onchange_after_7X-<name>-install.sh.tmpl` re-registers the
  plugin + runs upstream installer. Bump `plugins.<name>.{version,ref}` in
  `.chezmoidata.yaml` to upgrade. Self-authored skills go in `dot_claude/skills/`.
- Timing/order: `before_` / `after_`, numeric prefix controls order (`10-`, `20-`, …).

## Go template essentials

Use `{{ .chezmoi.os }}`, `{{ .chezmoi.homeDir }}`, `{{ .is_darwin }}` (from
`.chezmoidata.yaml`). Trim whitespace with `{{-` / `-}}` and gate OS-specific
blocks with `{{ if .is_darwin }}...{{ end }}`. Hash for change detection:
`{{ include $file | sha256sum }}`.

## Working rules for agents

- Edit in the source dir here, then `chezmoi apply`; verify with `chezmoi diff`.
- Prefer POSIX shell unless a bash/zsh feature is genuinely needed; indent
  **2 spaces**, always quote variables.
- Keep scripts **idempotent** — they may run repeatedly across machines.
- Comments may be Chinese or English; the codebase uses both.
