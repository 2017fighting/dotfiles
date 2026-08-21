# Design: Pinned-tool installers own their clones

- **Date:** 2026-08-21
- **Status:** Approved
- **Supersedes in part:** `2026-06-27-manage-ecc-with-chezmoi-design.md` and
  `2026-07-05-manage-claude-skills-design.md` (their `.chezmoiexternals` +
  installer pairing; everything else in those docs stands)
- **Scope:** chezmoi source repo at `~/.local/share/chezmoi`

## Context

ecc and plannotator are Claude Code tools pinned to exact git tags. Both were
managed as a **pair**: a `.chezmoiexternals/<name>.yaml.tmpl` cloning at
`--branch <tag>` plus a `run_onchange_after_7X` installer script that then
self-cloned (fallback) and force-checked out the same ref. The pairing mirrors
the oh-my-zsh/nvim pattern recorded in the two prior design docs.

Two facts made that pairing wrong for **pinned** refs:

1. **The external is a live footgun.** chezmoi's external refresh runs
   `git pull`; on a tag-pinned (detached-HEAD) working tree that aborts with
   "You are not currently on a branch" and breaks `chezmoi apply`. Both tools
   needed `refreshPeriod: 0` surgery (commit `7701437` for ecc) plus ~15 lines
   of apology comments per external to neutralize it. oh-my-zsh/nvim don't hit
   this because they track HEAD.
2. **The script was already authoritative.** Both installers self-clone when
   the repo is missing (correct regardless of apply ordering and under
   `--exclude=externals`) and force-checkout the pinned ref. The external's
   clone — the only thing it contributed — was redundant; two sources of truth
   for one pin.

A third problem surfaced while folding: the plannotator installer `exit 0`'d on
clone failure (lifecycle tolerance), so chezmoi recorded its hash and **never
retried** — recovery required the manual `chezmoi state delete --bucket=entryState`
ritual documented in its header.

## Decision

**Delete both externals; the installer scripts own their clones.**

- `.chezmoiexternals/ecc.yaml.tmpl` and `.chezmoiexternals/plannotator.yaml.tmpl`
  are removed. `.chezmoiexternals` remains for HEAD-tracking clones only
  (oh-my-zsh, nvim, tmux plugins, catppuccin files).
- Each tool's entry in `.chezmoidata.yaml` gains an explicit **`clonePath`**
  (home-relative) — one fact consumed by the installer script and `just doctor`
  (which derives a "pinned tools" presence check from it) instead of three
  hardcoded copies.
- **Error philosophy, uniform across both installers:**
  - **Loud clone** — clone/fetch/checkout failures `exit 1`. Verified: chezmoi
    does not record state for failing scripts, so the next `chezmoi apply`
    retries automatically (replacing the state-delete ritual). Tradeoff: a
    failing script blocks later scripts (`80-hapi`, `81-ssh-agent`) for that
    one apply run — acceptable; the clone is a hard prerequisite and the
    retry is automatic.
  - **clone-present hash line** — each installer embeds
    `# clone-present={{ if stat <clonePath>/.git }}…` (the pacman script's
    target-stat trick). run_onchange keys on rendered content, so a clone
    deleted *after* a successful run re-triggers the installer on the next
    apply — restoring the always-reclone property the external used to
    provide. (Found the hard way: content-hash alone ignores target state.)
  - **Tolerant tail** — npm install, plugin marketplace registration, symlinks
    warn and continue. ecc drops `set -euo pipefail` for this; plannotator
    drops its exit-0 clone branch.

### Alternatives considered

- **Keep the pairing, keep `refreshPeriod: 0`** — status quo ante; the trap is
  documented rather than deleted, and every future pinned tool copies the
  apology comments.
- **Externals on HEAD + script pins the ref** — clone lands at HEAD, script
  force-checks out the tag; works, but the external's refresh still runs
  pointlessly and the pin has two homes.
- **Vendor the tools into chezmoi source** — huge diff noise, no clean
  upgrades; rejected for the same reasons as in the ecc design.

## Consequences

- Adding a pinned tool = one data entry (with `clonePath`) + one installer
  script; no external, no refresh traps.
- First-clone network failure now fails the apply loudly and self-heals on the
  next apply (previously: silent skip + manual state surgery).
- Deleting a pinned clone post-install also self-heals (clone-present hash
  line re-triggers the installer; verified live by removing the plannotator
  clone and re-applying).
- `just doctor` still asserts both clones exist — derived from `clonePath`
  entries instead of the externals dir. Its fail() now appends to a file so
  checks running in pipeline subshells still fail the recipe (found while
  testing: `awk | while` loops were silently discarding failures).
