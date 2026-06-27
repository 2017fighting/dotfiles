# Design: Manage ecc with chezmoi

- **Date:** 2026-06-27
- **Status:** Approved
- **Upstream:** https://github.com/affaan-m/ecc (latest tag `v2.0.0`; was installed at `2.0.0-rc.1`)
- **Scope:** chezmoi source repo at `~/.local/share/chezmoi`

## Context

ecc ("Everything Claude Code") was installed **two** ways on this machine:

1. **Claude Code plugin** — a 153 MB clone at `~/.claude/plugins/marketplaces/ecc`
   (registry: `ecc@ecc` in `~/.claude/plugins/installed_plugins.json`), providing the
   `ecc:`-namespaced agents/skills/commands.
2. **ecc's own `install.sh`** — copied the plain-named set into `~/.claude/agents`
   (58 files), `~/.claude/commands`, `~/.claude/rules/ecc`, `~/.claude/skills/ecc`,
   with state at `~/.claude/ecc/install-state.json`.

ecc's own README (lines 179 & 254) calls this "stacked" configuration the **#1 broken
setup** — it produces duplicate skills and duplicate runtime behavior. The duplicates
are observable in this session's skill list: `code-review` **and** `ecc:code-review`,
`tdd-guide` **and** `ecc:tdd-guide`, `pr` **and** `ecc:pr`, etc.

## Decision

**Consolidate to chezmoi-only.** Remove the plugin install. chezmoi becomes the single
source of truth for ecc: it owns the repo (declarative external clone) and triggers the
installer; the installer owns its output files under `~/.claude`. A new machine gets ecc
with just `chezmoi apply`.

### Why this approach (vs alternatives considered)

- **Vendor output files into `dot_claude/`** — rejected: no auto-update, duplicates
  upstream, large diff noise.
- **Clone only, no installer** — rejected: chezmoi wouldn't actually reproduce the
  `~/.claude` surface; user would install manually.
- **External clone + installer** *(chosen)* — mirrors the user's existing
  `.chezmoiexternals` pattern (oh-my-zsh, oh-my-tmux, nvim), auto-updates, respects
  ecc's own installer as the source of truth for file layout.

## Installer verification (done during design)

- `install.sh` is a 32-line wrapper → `npm install` → `exec node scripts/install-apply.js`.
- The Node installer is **fully non-interactive** (flags only; no TTY prompts). Flags:
  `--target`, `--profile`, `--with/--without`, `--modules`, `--skills`, `--dry-run`, `--json`.
- Profiles: `minimal | core | developer | security | research | full`. Current state ≈ `full`.
- `node`/`npm` available (mise, v24.17.0).

## Files added to chezmoi source

1. **`.chezmoidata.yaml`** — single source of truth for version + profile:
   ```yaml
   ecc:
     version: "v2.0.0"
     profile: "full"
   ```
2. **`.chezmoiexternals/ecc.yaml.tmpl`** — declarative clone (mirrors oh-my-zsh/nvim
   pattern), pinned to the version tag, weekly refresh:
   ```yaml
   .local/share/ecc:
     type: git-repo
     url: https://github.com/affaan-m/ecc.git
     clone:
       args: ["--branch", "{{ .ecc.version }}"]
     refreshPeriod: 168h
   ```
3. **`.chezmoiscripts/run_onchange_after_70-ecc-install.sh.tmpl`** — runs the installer
   after the clone is refreshed. Embeds the version so bumping `.chezmoidata.yaml`
   re-triggers it. Idempotent; guards on node presence + clone presence.
4. **`.chezmoiignore`** (append) — exclude installer-owned paths from chezmoi's tracking
   so they don't show as drift, and exclude this `docs/` tree from deployment:
   ```
   .claude/rules/ecc
   .claude/skills/ecc
   .claude/ecc
   docs
   ```

## One-time migration (not part of recurring `chezmoi apply`)

1. `claude plugin uninstall ecc -y --scope user` — removes plugin cache entry.
2. `claude plugin marketplace remove ecc` — removes the marketplace + its 153 MB clone.
3. The first `chezmoi apply` clones ecc `v2.0.0` to `~/.local/share/ecc` and runs the
   installer, upgrading the rc.1 output in place (no manual wipe — eliminates risk to
   any user files; the installer manages its own file set).

## Verification

- `chezmoi diff` (review), then `chezmoi apply`.
- `~/.local/share/ecc/.git` exists and is at tag `v2.0.0`.
- `~/.claude/ecc/install-state.json` reflects `repoVersion: 2.0.0`.
- `~/.claude/plugins/marketplaces/ecc` is gone (153 MB reclaimed).
- `du -sh ~/.local/share/ecc` reasonable; no `ecc:`-prefixed duplicates expected in a
  fresh session (plain names only).

## Updating ecc later

Bump `ecc.version` in `.chezmoidata.yaml` (e.g. `v2.1.0`) and run `chezmoi apply`. The
external re-clones the tag and the `run_onchange` script re-renders (new version in its
body) and re-runs the installer.

## Out of scope

- Vendoring ecc files into `dot_claude/`.
- Managing ecc via the plugin marketplace going forward.
- Following `main` instead of tags (chose stability; one-line change to switch).
- Any encryption (no secrets involved).
