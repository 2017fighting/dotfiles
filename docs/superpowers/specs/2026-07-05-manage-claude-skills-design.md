# Design: Manage Claude skills with chezmoi

- **Date:** 2026-07-05
- **Status:** Approved
- **Upstream:** https://github.com/backnotprop/plannotator (currently installed `0.21.3`, commit `1eee3eb`)
- **Scope:** chezmoi source repo at `~/.local/share/chezmoi`

## Context

`~/.claude/skills/` is populated by **two unrelated mechanisms**, which makes
"manage Claude skills with chezmoi" ambiguous and is why a naive approach breaks:

1. **Self-authored / hand-placed skills** — flat directories under
   `~/.claude/skills/<name>/SKILL.md`. Currently only the empty `learned/` dir;
   this is a future capability, not a migration. Examples of historical flat-copy
   residue also live here (`agents-sdk`, `cloudflare`, `grill-me`, …) from prior
   flat-install layouts — out of scope for this change.

2. **Third-party Claude Code plugins** — registered via the plugin system
   (`~/.claude/plugins/installed_plugins.json`), declaring skills/commands/hooks
   through the plugin manifest. **plannotator** is the hard case:

   - **plugin layer** — marketplace `plannotator@plannotator` (GitHub source
     `backnotprop/plannotator`), clone at `~/.claude/plugins/marketplaces/plannotator`,
     version `0.21.3` recorded in `installed_plugins.json`. Provides the
     `plannotator-{annotate,last,review}` skill dirs (real directories, copied by
     the installer — not present in the plugin cache's `skills/`).
   - **binary layer** — `scripts/install.sh` downloads a **151 MB `plannotator`
     binary** to `~/.local/bin`, optionally installs the `sem` sidecar
     (`Ataraxy-Labs/sem`), runs SLSA build-provenance verification, and a guided
     extras/model-invocable configurator. The plugin's `bin/plannotator.js`
     launches a hook server via `bun`, so `bun` is a runtime dependency.

The repo already manages **ecc** through the same shape of problem (plugin +
own installer). ecc's pattern — `.chezmoiexternals` clone pinned to a tag, a
`run_onchange_after_*` script that re-registers the plugin — is the proven
template. This design extends it to plannotator and codifies the rule for
self-authored skills.

`claude plugin install` has **no `--version` flag** (only `--scope`/`--config`),
so version-locking a plugin can only be done by pinning the marketplace's
git ref — exactly what the ecc pattern does via a directory-source marketplace
pointing at a pinned local clone.

## Decision

Two independent tracks, neither touching the other:

### Track 1 — Third-party plugin reproducibility (reuse the ecc pattern)

For each third-party plugin: a `.chezmoiexternals/<name>.yaml.tmpl` clones the
repo to `~/.local/share/<name>` pinned to a tag, and a
`run_onchange_after_7X-<name>-install.sh.tmpl` re-registers it with the Claude
Code plugin system. The script embeds the version string in a comment so
bumping it in `.chezmoidata.yaml` changes the script's content hash and triggers
`run_onchange` to re-run.

plannotator's binary layer is added to the **same** script: when
`~/.local/bin/plannotator` is missing (or its `--version` doesn't match the
pinned tag), the script runs the upstream `install.sh` non-interactively.

### Track 2 — Self-authored skills

Self-authored skills live as chezmoi source under `dot_claude/skills/<name>/`
and deploy flat to `~/.claude/skills/<name>/`. They use a clear prefix
(suggested `my-`) to avoid collisions with plugin-flat-copied skills. chezmoi
**never** vendors third-party skill output into the source tree — the lesson
already encoded in the ecc script (`Personal content belongs in chezmoi
source, not these dirs`).

### Boundary — `~/.claude/settings.json` is NOT managed by chezmoi

Claude Code writes this file frequently (theme, `enabledPlugins`,
`permissions`, …). Managing it from chezmoi would make every `chezmoi diff`
dirty and risk clobbering per-machine state. Instead the `run_onchange` scripts
idempotently write `enabledPlugins` / `extraKnownMarketplaces` via
`claude plugin marketplace add` + `claude plugin install`. Cross-machine sync
covers **plugin set + pinned versions only**, not theme/permissions/env.

### Why this approach (vs alternatives considered)

- **Follow upstream latest** (no pin) — *rejected:* violates the core
  reproducibility requirement; upstream drift changes the environment silently.
- **chezmoi fully declarative for the binary layer** (lock plannotator+sem
  versions, download+SHA256 ourselves, bun via mise) — *rejected:* most
  controllable but duplicates upstream's installer logic and must track every
  upstream change (attestation rules, sidecar versions, install-prefs format).
  Re-running upstream's own `install.sh` is strictly less work and stays correct.
- **settings.json-driven reconcile** (template settings.json, script reads
  `enabledPlugins`) — *rejected:* settings.json is the file Claude Code writes
  most; managing it causes continuous `chezmoi diff` noise and merge pain.
- **External clone + upstream installer + plugin marketplace add** *(chosen)* —
  mirrors the verified ecc pattern; real reproducibility via pinned refs;
  zero settings.json conflict; self-authored skills isolated by namespace.

## Detailed design

### `.chezmoidata.yaml` additions

```yaml
# Claude Code third-party plugins — managed by chezmoi.
# Each plugin has a matching .chezmoiexternals/<name>.yaml.tmpl and a
# run_onchange_after_7X-<name>-install.sh.tmpl. Bump version/ref to upgrade.
plugins:
  plannotator:
    version: "0.21.3"     # passed to install.sh --version
    ref: "v0.21.3"        # git tag/commit the external clone checks out (--branch)
    skipSem: true         # PLANNOTATOR_SKIP_SEM_INSTALL=1 (sem sidecar not currently installed)
```

### `.chezmoiexternals/plannotator.yaml.tmpl`

Clones `backnotprop/plannotator` to `~/.local/share/plannotator` pinned to
`{{ .plugins.plannotator.ref }}`. `refreshPeriod: 0` — same reason as ecc: a
periodic refresh would `git pull` on a detached HEAD and abort, breaking
`chezmoi apply`. Upgrades flow through the `run_onchange` script (its content
hash changes when `ref` bumps).

### `.chezmoiscripts/run_onchange_after_71-plannotator-install.sh.tmpl`

`after_71` so it runs strictly after the ecc installer (`after_70`). Structure
mirrors the ecc script:

1. Skip gracefully (`exit 0`) if `claude`, `node`, or `bun` are absent — this
   machine mise-manages them and lifecycle scripts must tolerate partial
   failure (no `set -e` brittle exits on missing tooling).
2. Self-clone if `~/.local/share/plannotator/.git` is missing (correct regardless
   of apply ordering), then `git fetch --tags && git checkout --force <ref>`.
3. Register the plugin with a **directory-source** marketplace (so the pin
   sticks): `claude plugin marketplace remove plannotator 2>/dev/null || true`
   then `claude plugin marketplace add ~/.local/share/plannotator --scope user`
   then `claude plugin install plannotator@plannotator --scope user`. The
   `remove`-then-`add` handles the github→directory source-type change
   idempotently (R1 fallback).
4. Binary layer: if `~/.local/bin/plannotator` is missing **or** reports a
   version ≠ `{{ .plugins.plannotator.version }}`, run
   `PLANNOTATOR_SKIP_SEM_INSTALL=<1|0> scripts/install.sh --version <tag>
   --non-interactive --no-extras --model-invocable none --skip-attestation`.
   Wrapped in a timeout; on failure print a warning and continue (do **not**
   block the rest of `chezmoi apply`).

Default install.sh flags align with the **current** machine state (no extras,
no model-invocable skills, no sem sidecar, attestation off). To enable any of
those later, edit the flag in the script.

### Self-authored skills

- Source path: `dot_claude/skills/<name>/SKILL.md` → `~/.claude/skills/<name>/SKILL.md`.
- Suggested name prefix `my-` to avoid colliding with plugin-flat-copied skills
  (non-binding convention; user decides per skill).
- A `dot_claude/skills/.keep` placeholder establishes the directory in chezmoi
  source so future skills drop in cleanly.
- **Out of scope:** cleaning up the existing flat-copy residue (`cloudflare`,
  `grill-me`, etc.). That is a separate task if desired.

## Risks / open questions to verify at implementation time

- **R1 (critical):** plannotator's current marketplace entry in settings.json
  is a GitHub source; the script re-adds it as a directory source. Whether
  `claude plugin marketplace add` is idempotent across source types is
  **unverified**. Mitigation: `marketplace remove || true` before `add`. Verify
  by running `chezmoi apply --dry-run` and a real apply, then check
  `installed_plugins.json` shows the directory source.
- **R2:** plannotator's release tag naming (`v0.21.3` vs `0.21.3`) must match
  what `git clone --branch` accepts. Verify with
  `git ls-remote --tags https://github.com/backnotprop/plannotator` and set
  `ref` accordingly. install.sh's `--version` accepts both `vX.Y.Z` and `X.Y.Z`.
- **R3:** install.sh downloads 151 MB and may invoke `gh` / GitHub API. On a
  slow/off network it must not block `chezmoi apply`. The script wraps the call
  in `timeout` and continues on failure with a visible warning.
- **R4:** the existing flat-copied skills under `~/.claude/skills/`
  (`cloudflare`, `grill-me`, `agents-sdk`, …) are not touched by this change.
  They are a separate cleanup if the user wants it.
- **R5:** `claude plugin marketplace remove` / `add` exit codes when the
  marketplace is/already-is present are tolerated with `set +e` around that
  block (matching the ecc script's tolerance).

## File plan

New:
- `.chezmoiexternals/plannotator.yaml.tmpl`
- `.chezmoiscripts/run_onchange_after_71-plannotator-install.sh.tmpl`
- `dot_claude/skills/.keep`
- `docs/superpowers/specs/2026-07-05-manage-claude-skills-design.md` (this doc)

Modified:
- `.chezmoidata.yaml` (add `plugins.plannotator.{version,ref,skipSem}`)

Unchanged:
- `~/.claude/settings.json`, `dot_claude/CLAUDE.md`, all ecc files.

A new machine reproduces plannotator (plugin + binary layer) and any
self-authored skill with a single `chezmoi apply`.
