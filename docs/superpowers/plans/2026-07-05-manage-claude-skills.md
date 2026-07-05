# Manage Claude Skills with chezmoi — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make plannotator (plugin + 151 MB binary layer) and any future self-authored skill reproducible across machines via `chezmoi apply`.

**Architecture:** Two independent tracks. (1) Third-party plugin track reuses the verified ecc pattern: a `.chezmoiexternals` clone pinned to a tag + a `run_onchange_after_*` script that re-registers the plugin with a directory-source marketplace and runs upstream `install.sh` for plannotator's binary layer. (2) Self-authored skill track drops plain `dot_claude/skills/<name>/SKILL.md` files into chezmoi source. `~/.claude/settings.json` is intentionally NOT managed (Claude Code writes it frequently).

**Tech Stack:** chezmoi (Go templates, YAML externals, `run_onchange` scripts), POSIX bash, the `claude` CLI's `plugin marketplace`/`plugin install` commands, plannotator's upstream `scripts/install.sh`.

## Global Constraints

(From the spec + repo conventions. Every task's requirements implicitly include these.)

- **No `set -e` in lifecycle scripts** — `.chezmoiscripts/run_*` run on every machine and must tolerate partial failure (missing tools, network errors). Guard each failure-prone step explicitly and always end with `exit 0`.
- **`chezmoi apply` uses `--exclude=externals`** — externals are declarative records only; the `run_onchange` installer scripts self-clone (mirrors the verified ecc pattern, and makes apply robust against external-clone failures since the script `exit 0`s on network error). Both ecc and plannotator externals use `refreshPeriod: 0`, so apply no longer aborts on detached HEAD (commit `c47b462` fixed ecc's refresh — the old `--exclude=externals` workaround is no longer strictly required), but `--exclude=externals` is kept for consistency with the self-clone pattern.
- **First-clone is the script's job, not external refresh's** — the `run_onchange` script self-clones plannotator if `~/.local/share/plannotator/.git` is missing (mirrors the ecc script), so the script is correct even when apply is run with `--exclude=externals`.
- **Shell style** — 2-space indent, always quote variables, idempotent (re-runs are no-ops or converge).
- **Git commits need SSH signing** — before any `git commit`, run `export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"` (key lives in the OS ssh-agent via `bw-ssh-add`). Commit messages include the HAPI co-author trailer.
- **Don't touch `~/.claude/settings.json` directly** — it's Claude Code's high-churn file. Plugin registration goes through `claude plugin marketplace add` / `claude plugin install`, which write to it themselves.
- **Source dir deploys to `$HOME`** — only chezmoi-prefixed files deploy. `dot_claude/...` → `~/.claude/...`.

---

## Task 1: Add plannotator data fields + external clone template

Establishes the declarative foundation: the version/ref the rest of the plan reads, and the git-external clone declaration.

**Files:**
- Modify: `.chezmoidata.yaml` (append `plugins:` block)
- Create: `.chezmoiexternals/plannotator.yaml.tmpl`

**Interfaces:**
- Produces: `.plugins.plannotator.version` (`"0.21.3"`), `.plugins.plannotator.ref` (`"v0.21.3"`), `.plugins.plannotator.skipSem` (`true`) — consumed by Task 2's script template.

- [ ] **Step 1: Append the `plugins` block to `.chezmoidata.yaml`**

Append this at end of file (the file currently has top-level `ecc:`, `hapi:`, `ssh:` blocks):

```yaml
# Claude Code third-party plugins — managed by chezmoi.
# Each plugin has a matching .chezmoiexternals/<name>.yaml.tmpl and a
# run_onchange_after_7X-<name>-install.sh.tmpl. Bump version/ref to upgrade.
plugins:
  plannotator:
    # Passed to install.sh --version and used to gate binary-layer reinstall.
    version: "0.21.3"
    # git tag/commit the external clone checks out (--branch) AND the run_onchange
    # script force-checks out. Confirmed via `git ls-remote --tags` — upstream uses
    # vX.Y.Z naming. v0.21.3 -> commit ec8342c.
    ref: "v0.21.3"
    # Sets PLANNOTATOR_SKIP_SEM_INSTALL=1 (sem code-review sidecar not currently
    # installed; toggle to false to install sem alongside the binary).
    skipSem: true
```

- [ ] **Step 2: Verify the data renders**

Run: `chezmoi data --format yaml | grep -A4 '^plugins:'`
Expected output includes:
```
plugins:
    plannotator:
        ref: v0.21.3
        skipSem: true
        version: 0.21.3
```

- [ ] **Step 3: Create `.chezmoiexternals/plannotator.yaml.tmpl`**

Full file content (mirrors `.chezmoiexternals/ecc.yaml.tmpl` structure):

```yaml
# plannotator repo clone, consumed by
# .chezmoiscripts/run_onchange_after_71-plannotator-install.sh.tmpl.
# The installer script force-checks out plugins.plannotator.ref before registering
# the plugin, so this external is a declarative bootstrap/clone source only
# (mirrors the ecc / oh-my-zsh / nvim pattern).
#
# refreshPeriod is 0 (disabled): plannotator is pinned to a tag
# ({{ .plugins.plannotator.ref }}), which leaves the working tree in detached HEAD.
# A periodic refresh would run `git pull` on that detached HEAD and abort with
# "You are not currently on a branch", breaking `chezmoi apply`. Version upgrades
# flow through the run_onchange installer script (its content hash changes when
# plugins.plannotator.version bumps), not through this external.
.local/share/plannotator:
  type: git-repo
  url: https://github.com/backnotprop/plannotator.git
  clone:
    args:
      - --branch
      - "{{ .plugins.plannotator.ref }}"
  refreshPeriod: 0
```

- [ ] **Step 4: Verify the external template renders**

Run: `chezmoi execute-template < .chezmoiexternals/plannotator.yaml.tmpl`
Expected: the YAML above with `{{ .plugins.plannotator.ref }}` replaced by `v0.21.3`.

- [ ] **Step 5: Commit**

```bash
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"
git add .chezmoidata.yaml .chezmoiexternals/plannotator.yaml.tmpl
git commit -m "$(cat <<'EOF'
feat(skills): add plannotator data fields + external clone

Declares plugins.plannotator.{version,ref,skipSem} in .chezmoidata.yaml and
the .chezmoiexternals/plannotator.yaml.tmpl clone pinned to v0.21.3. The
run_onchange installer script in the next commit consumes these.

via [HAPI](https://hapi.run)

Co-Authored-By: HAPI <noreply@hapi.run>
EOF
)"
```

---

## Task 2: Write the `run_onchange` installer script

The core logic: pin the clone, register the plugin with a directory-source marketplace, and run upstream `install.sh` for the binary layer when missing or out of date.

**Files:**
- Create: `.chezmoiscripts/run_onchange_after_71-plannotator-install.sh.tmpl`

**Interfaces:**
- Consumes: `.plugins.plannotator.{version,ref,skipSem}` (from Task 1).
- Produces: a registered `plannotator@plannotator` plugin (directory source) + `~/.local/bin/plannotator` binary at the pinned version, on every `chezmoi apply` where the script's content hash changed.

**Why `after_71`:** strictly after the ecc installer at `after_70`, mirroring the established numbering.

- [ ] **Step 1: Create the script file with the full content below**

Full file content:

```bash
#!/usr/bin/env bash
# Manage plannotator (https://github.com/backnotprop/plannotator) via chezmoi.
# Registers plannotator as a Claude Code plugin via a directory-source marketplace
# (pinned to {{ .plugins.plannotator.ref }}) AND installs the binary layer via
# upstream install.sh. Re-runs whenever plugins.plannotator.version changes
# (version is embedded in the comment on the next line, so bumping it in
# .chezmoidata.yaml changes this script's content hash and retriggers run_onchange).
# Idempotent.
# version={{ .plugins.plannotator.version }}
#
# No `set -e`: this is a chezmoi lifecycle script and must tolerate partial failure
# (missing mise tools, network errors) without blocking `chezmoi apply`.

PLN_SRC="$HOME/.local/share/plannotator"
PLN_VERSION="{{ .plugins.plannotator.version }}"
PLN_REF="{{ .plugins.plannotator.ref }}"
PLN_SKIP_SEM="{{ .plugins.plannotator.skipSem }}"
INSTALL_DIR="$HOME/.local/bin"

# Tooling is mise-managed on this machine. Skip gracefully if absent — the plugin
# registration and binary install both need node/bun/claude.
for tool in node bun claude; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "[plannotator] $tool not found on PATH — skipping install." >&2
    exit 0
  }
done

# Ensure the repo is present at the pinned ref. .chezmoiexternals/plannotator.yaml.tmpl
# usually clones it first, but this self-clone makes the script correct regardless of
# apply ordering (and when apply runs with --exclude=externals).
if [ ! -d "$PLN_SRC/.git" ]; then
  if ! git clone --quiet --branch "$PLN_REF" https://github.com/backnotprop/plannotator.git "$PLN_SRC"; then
    echo "[plannotator] clone failed — skipping." >&2
    exit 0
  fi
fi

cd "$PLN_SRC" || exit 0
git fetch --tags --quiet
git checkout --quiet --force "$PLN_REF" || \
  echo "[plannotator] checkout $PLN_REF failed, continuing on current HEAD" >&2

# Register as a directory-source plugin so the pin sticks (a github-source marketplace
# would track upstream HEAD). remove-then-add handles the github->directory source-type
# change idempotently (R1 in the design doc).
claude plugin marketplace remove plannotator >/dev/null 2>&1 || true
claude plugin marketplace add "$PLN_SRC" --scope user || \
  echo "[plannotator] marketplace add failed" >&2
claude plugin install plannotator@plannotator --scope user || \
  echo "[plannotator] plugin install failed" >&2

# Binary layer: install.sh always re-downloads (it rm's the binary first), so gate
# the call on the installed version to keep re-runs cheap and offline-safe.
NEEDS_BINARY=1
if [ -x "$INSTALL_DIR/plannotator" ]; then
  CURRENT="$("$INSTALL_DIR/plannotator" --version 2>/dev/null | awk '{print $2}')"
  if [ "$CURRENT" = "$PLN_VERSION" ]; then
    NEEDS_BINARY=0
  fi
fi

if [ "$NEEDS_BINARY" = "1" ]; then
  echo "[plannotator] installing binary layer v$PLN_VERSION via upstream install.sh"
  if [ "$PLN_SKIP_SEM" = "true" ]; then
    export PLANNOTATOR_SKIP_SEM_INSTALL=1
  fi
  if ! timeout 300 bash "$PLN_SRC/scripts/install.sh" \
      --version "$PLN_VERSION" \
      --non-interactive \
      --no-extras \
      --model-invocable none \
      --skip-attestation; then
    echo "[plannotator] install.sh failed (timeout or error) — binary layer not installed, continuing." >&2
  fi
else
  echo "[plannotator] binary layer already at v$PLN_VERSION, skipping install.sh"
fi

echo "[plannotator] done (ref=$PLN_REF, version=$PLN_VERSION)"
exit 0
```

- [ ] **Step 2: Render the template and lint it**

The `.tmpl` extension means shellcheck can't read it directly — render first.

Run:
```bash
chezmoi execute-template < .chezmoiscripts/run_onchange_after_71-plannotator-install.sh.tmpl > /tmp/plannotator-install-rendered.sh
shellcheck /tmp/plannotator-install-rendered.sh
```
Expected: shellcheck exits 0 (no warnings). If it flags anything, fix the source `.tmpl` (not the rendered file) and re-render until clean.

- [ ] **Step 3: Verify chezmoi sees the new managed script**

Run: `chezmoi managed | grep plannotator`
Expected: a line like `.chezmoiscripts/run_onchange_after_71-plannotator-install.sh` ( chezmoi reports the rendered target path under `.local/share/chezmoi` semantics — the exact prefix may differ; the key check is that `plannotator` appears).

- [ ] **Step 4: Commit**

```bash
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"
git add .chezmoiscripts/run_onchange_after_71-plannotator-install.sh.tmpl
git commit -m "$(cat <<'EOF'
feat(skills): add plannotator run_onchange installer

Pins the clone to plugins.plannotator.ref, registers plannotator@plannotator
via a directory-source marketplace (remove-then-add for github->directory
idempotency), and runs upstream install.sh for the 151MB binary layer only
when ~/.local/bin/plannotator is missing or out of date. No set -e — tolerates
missing tools / network failure without blocking apply.

via [HAPI](https://hapi.run)

Co-Authored-By: HAPI <noreply@hapi.run>
EOF
)"
```

---

## Task 3: Self-authored skill scaffolding

Establishes the `dot_claude/skills/` directory in chezmoi source so future self-authored skills drop in cleanly, and records the namespace convention.

**Files:**
- Create: `dot_claude/skills/.keep`

**Interfaces:**
- Produces: a chezmoi-managed `~/.claude/skills/` directory. (Self-authored skills added later go in `dot_claude/skills/<name>/SKILL.md`; suggested prefix `my-` to avoid collisions with plugin-flat-copied skills.)

- [ ] **Step 1: Create the placeholder**

```bash
mkdir -p /home/zhao/.local/share/chezmoi/dot_claude/skills
: > /home/zhao/.local/share/chezmoi/dot_claude/skills/.keep
```

(The `.keep` file is empty — its only job is to make git + chezmoi track the otherwise-empty directory.)

- [ ] **Step 2: Verify chezmoi will manage it**

Run: `chezmoi managed | grep '.claude/skills'`
Expected: a line containing `.claude/skills/.keep`.

- [ ] **Step 3: Commit**

```bash
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"
git add dot_claude/skills/.keep
git commit -m "$(cat <<'EOF'
feat(skills): scaffold dot_claude/skills for self-authored skills

Establishes the chezmoi source directory so future self-authored skills
(SKILL.md per subdir, suggested my- prefix to avoid plugin collisions)
deploy to ~/.claude/skills/. Third-party skills stay out of source — they
flow through the plugin system (see plannotator installer).

via [HAPI](https://hapi.run)

Co-Authored-By: HAPI <noreply@hapi.run>
EOF
)"
```

---

## Task 4: End-to-end verification + docs

Apply for real, confirm the plugin re-registered as a directory source and the binary layer is intact, and leave a pointer in the quick-reference docs.

**Files:**
- Modify: `CLAUDE.md` (add one row to the commands/handoff tables)
- Verify only: `~/.claude/plugins/installed_plugins.json`, `~/.local/bin/plannotator`

- [ ] **Step 1: Preview the diff (REQUIRED before apply)**

Run: `chezmoi diff --exclude=externals`
Expected: shows the new script being created under `~/.chezmoiscripts/` (run_onchange target) and `.keep` under `~/.claude/skills/`. No surprises, no deletions of existing files.

- [ ] **Step 2: Apply (excluding externals — required by the repo's detached-HEAD ecc external)**

Run: `chezmoi apply --exclude=externals`
Expected: chezmoi writes the script + `.keep`, then runs the `run_onchange` script. Look for the lines:
```
[plannotator] binary layer already at v0.21.3, skipping install.sh
[plannotator] done (ref=v0.21.3, version=0.21.3)
```
(The first line confirms the version-gating works — the binary is already at 0.21.3 so install.sh is skipped. If the directory-source marketplace re-registration needs the github marketplace removed first, you may also see `[plannotator] marketplace add failed` once during the transition — re-run `chezmoi apply --exclude=externals`; the second run should be clean.)

- [ ] **Step 3: Verify the plugin is now a directory source**

Run: `cat ~/.claude/plugins/installed_plugins.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(d["plugins"]["plannotator@plannotator"][0], indent=2))'`
Expected: `"version": "0.21.3"` and the install path points under `~/.local/share/plannotator` (directory-source semantics). The exact field shape may vary; the key assertion is version `0.21.3` is present and stable across two applies.

Run a second time to confirm idempotence:
```bash
chezmoi apply --exclude=externals
```
Expected: no `[plannotator] installing binary layer` line (binary already current), exit 0.

- [ ] **Step 4: Verify the binary layer version**

Run: `~/.local/bin/plannotator --version`
Expected: `plannotator 0.21.3`.

- [ ] **Step 5: Add a quick-reference pointer to `CLAUDE.md`**

In `/home/zhao/.local/share/chezmoi/CLAUDE.md`, find the "Chezmoi prefix cheat sheet" section (the `run_onchange_` bullet). After that bullet, add a short pointer (do not restructure existing content):

Find this exact line:
```
- Scripts: `run_` (every apply), `run_once_` (once per machine),
  `run_onchange_` (when content hash changes).
```

Insert immediately after it:
```
- Third-party Claude plugins (plannotator, ecc): `.chezmoiexternals/<name>.yaml.tmpl`
  clones pin a tag; `run_onchange_after_7X-<name>-install.sh.tmpl` re-registers the
  plugin + runs upstream installer. Bump `plugins.<name>.{version,ref}` in
  `.chezmoidata.yaml` to upgrade. Self-authored skills go in `dot_claude/skills/`.
```

- [ ] **Step 6: Commit the doc update**

```bash
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(skills): note plugin + self-authored skill management in CLAUDE.md

Quick-reference pointer to the .chezmoiexternals + run_onchange pattern for
third-party plugins and the dot_claude/skills/ location for self-authored ones.

via [HAPI](https://hapi.run)

Co-Authored-By: HAPI <noreply@hapi.run>
EOF
)"
```

- [ ] **Step 7: Final clean-state check**

Run: `chezmoi diff --exclude=externals`
Expected: empty (no pending changes — everything applied).

---

## Definition of Done

- `.chezmoidata.yaml` carries `plugins.plannotator.{version,ref,skipSem}`.
- `.chezmoiexternals/plannotator.yaml.tmpl` declares the pinned clone.
- `run_onchange_after_71-plannotator-install.sh.tmpl` renders, passes `shellcheck`, and on `chezmoi apply --exclude=externals` registers `plannotator@plannotator` as a directory-source plugin + ensures the binary layer without re-downloading when already current.
- `dot_claude/skills/.keep` exists in source.
- Two consecutive `chezmoi apply --exclude=externals` runs are clean and idempotent.
- `~/.local/bin/plannotator --version` prints `plannotator 0.21.3`.
- `CLAUDE.md` points at the new pattern.
- All four commits landed on `main`.
