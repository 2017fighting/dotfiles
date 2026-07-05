# SSH key flow without bwssh — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace bwssh with the OS-native ssh-agent; load the Bitwarden SSH key via `bw` CLI + `ssh-add` so vaultwarden is no longer in the hot path of SSH connections.

**Architecture:** A manual `bw-ssh-add` command unlocks the vault, fetches the private key, and pipes it into a persistent system ssh-agent (systemd user unit on Linux, launchd-built-in on macOS). `~/.zshrc` prints a hint when the agent is empty. chezmoi's `before_20` script calls `bw-ssh-add` so fresh-machine `chezmoi apply` still works.

**Tech Stack:** POSIX sh, chezmoi Go templates, systemd user units, launchd, jq, Bitwarden CLI (`bw`).

## Global Constraints

Copied verbatim from the spec + repo conventions (`AGENTS.md`, `CLAUDE.md`):

- **POSIX sh** for scripts unless a bash/zsh feature is genuinely needed; **2-space indent**; always quote variables; keep lifecycle scripts **idempotent** and **`set -e`-free** (they run on every machine and must tolerate partial failure).
- **Always run `chezmoi diff` before `chezmoi apply`.** Apply writes to `$HOME`.
- **Never commit unencrypted secrets.** Encrypted files use age; key at `~/.config/chezmoi/key.txt`; recipient `age16nnlyeqwxfc0v8wn9y9px8kv6gev9jr4487d6su20l55ehjdpsgqp8chnk`.
- **Single SSH key today**, Bitwarden item id `1fc48db0-b2a7-4eb4-9877-33847b9f3075`.
- **Commit signing:** `commit.gpgsign=true`, signing key `ssh-ed25519 …NG91v`, served by the ssh-agent. Until Task 4 is applied and `bw-ssh-add` has been run once, commits **cannot be signed** (the signing key is not in any agent). Therefore this plan **defers all commits to Task 9** (one signed commit, or a small set) rather than committing per-task. Do NOT run `git commit` in Tasks 1–8.
- **No test suite** in this repo — "tests" are `shellcheck` on rendered shell, `chezmoi diff`, `chezmoi apply --dry-run --verbose`, and functional checks (`ssh-add -l`, `ssh -G`, `systemctl --user status`).

## File Structure

| File | Responsibility |
|---|---|
| `dot_local/bin/executable_bw-ssh-add.tmpl` *(new)* | The loader: unlock bw → fetch key → `ssh-add -`. Stateless, idempotent. |
| `dot_config/systemd/user/ssh-agent.service` *(new, Linux)* | Persistent ssh-agent user unit. |
| `.chezmoiscripts/run_onchange_after_81-ssh-agent.sh.tmpl` *(new)* | Enable the agent unit on Linux; no-op on macOS. Replaces the bwssh plist loader. |
| `.chezmoidata.yaml` *(modify)* | Drop `bwssh:`; add `ssh.agent.version` + `ssh.keyItemIds`. |
| `dot_zprofile.tmpl` *(modify)* | Export `SSH_AUTH_SOCK` on Linux for non-interactive children. |
| `dot_zshrc.tmpl` *(modify)* | Replace bwssh socket with native socket; add empty-agent hint. |
| `private_dot_ssh/encrypted_private_config.tmpl.age` *(modify)* | Remove the bwssh `IdentityAgent` line under `Host *`. |
| `.chezmoiscripts/run_onchange_before_20-ensure-ssh-for-externals.sh.tmpl` *(rewrite)* | Drop bwssh daemon dance; materialize + invoke `bw-ssh-add`. |
| `.chezmoiscripts/run_once_before_10-install-bootstrap-tools.sh.tmpl` *(trim)* | Drop `pipx:bwssh` install; keep `bitwarden-cli` + `mise`. |
| 6 bwssh files + 1 mise line *(delete)* | Full bwssh removal. |
| `CLAUDE.md`, `AGENTS.md`, `README.md`, `BOOTSTRAP.md` *(modify)* | Doc accuracy: stop claiming bwssh manages SSH keys. |

---

### Task 1: Verify bw SSH-key JSON shape + migrate `.chezmoidata.yaml`

**Files:**
- Verify (manual, no edit): the `.sshKey.privateKey` path used by Task 2.
- Modify: `.chezmoidata.yaml`.

**Interfaces:**
- Produces: template data `.ssh.agent.version` ("1") and `.ssh.keyItemIds` (list), consumed by Tasks 2, 3.
- Produces: confirmed `jq` private-key path, consumed by Task 2's loader.

- [ ] **Step 1: Verify the bw private-key field path (requires TTY + master password).**

Run (the vault is currently `locked`):
```sh
bw unlock                            # enter master password, exports BW_SESSION
bw get item 1fc48db0-b2a7-4eb4-9877-33847b9f3075 \
  | jq '.sshKey | keys'
```
Expected output includes `privateKey` (and `publicKey`, `keyFingerprint`, `keyType`). Then confirm the value is an OpenSSH PEM key:
```sh
bw get item 1fc48db0-b2a7-4eb4-9877-33847b9f3075 \
  | jq -r '.sshKey.privateKey' | head -1
```
Expected first line: `-----BEGIN OPENSSH PRIVATE KEY-----`.

If the field is **not** at `.sshKey.privateKey` (e.g. nested elsewhere), record the actual path and use it in Task 2's `jq` filter instead of `.sshKey.privateKey`. Do not proceed to Task 2 without this confirmation.

- [ ] **Step 2: Edit `.chezmoidata.yaml` — remove the `bwssh:` block, add the `ssh:` block.**

Open `.chezmoidata.yaml`. Remove this block (lines may differ slightly; match the content):
```yaml
# bwssh-agent LaunchAgent (macOS only) — loaded by
# .chezmoiscripts/run_onchange_after_81-bwssh-agent.sh.tmpl. Bump `version` to
# force a reload after editing the plist.
bwssh:
  agent:
    version: "1"
```
Add immediately after the `hapi:` block:
```yaml
# System ssh-agent + bw-ssh-add key loader. The agent unit is enabled by
# .chezmoiscripts/run_onchange_after_81-ssh-agent.sh.tmpl; bump `version` to
# force a re-enable after editing the unit file. `keyItemIds` lists Bitwarden
# SSH-key item ids that `bw-ssh-add` loads into the agent.
ssh:
  agent:
    version: "1"
  keyItemIds:
    - "1fc48db0-b2a7-4eb4-9877-33847b9f3075"
```

- [ ] **Step 3: Verify template data renders.**

Run: `chezmoi data --format json | jq '.ssh, .bwssh'`
Expected:
```json
{
  "agent": { "version": "1" },
  "keyItemIds": ["1fc48db0-b2a7-4eb4-9877-33847b9f3075"]
}
null
```
(`bwssh` must be `null` — fully removed from template data.)

- [ ] **Step 4: Verify no target drift yet.**

Run: `chezmoi diff`
Expected: no changes related to `.chezmoidata.yaml` (it is template data, not a deployed target). Other diffs should be absent at this point.

---

### Task 2: Create the `bw-ssh-add` loader script

**Files:**
- Create: `dot_local/bin/executable_bw-ssh-add.tmpl`

**Interfaces:**
- Consumes: `.ssh.keyItemIds` (from Task 1) — rendered as a JSON array literal inside the script.
- Produces: `~/.local/bin/bw-ssh-add` (executable) — invoked manually and by Task 6's `before_20`.

- [ ] **Step 1: Create the loader script.**

Create `dot_local/bin/executable_bw-ssh-add.tmpl` with this exact content:

```sh
#!/bin/sh
# bw-ssh-add — unlock the Bitwarden vault via the bw CLI and load the SSH
# private key(s) into the system ssh-agent. Stateless: nothing is written to
# disk (no BW_SESSION persisted). Re-running once a key is loaded is a no-op;
# pass --force to reload.
#
# Item ids come from .chezmoidata.yaml (ssh.keyItemIds), rendered below.
set -eu

# Rendered JSON array, e.g. ["1fc48db0-..."]. Parsed with jq below.
ITEM_IDS_JSON='{{ .ssh.keyItemIds | toJson }}'

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

# Idempotence: skip if the agent already holds ≥1 identity.
if [ "$FORCE" -eq 0 ] && ssh-add -l >/dev/null 2>&1; then
  echo "[bw-ssh-add] agent already has an identity — nothing to do (use --force to reload)."
  exit 0
fi

for cmd in bw jq ssh-add; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[bw-ssh-add] '$cmd' not found on PATH" >&2
    exit 1
  }
done

# Obtain a Bitwarden session. Reuse $BW_SESSION if it still unlocks; otherwise
# inspect status and unlock. `bw status` never prints the session, so an
# unlocked vault with no env session still requires `bw unlock`.
if [ -n "${BW_SESSION:-}" ] && bw status --session "$BW_SESSION" >/dev/null 2>&1; then
  :
else
  bw_state=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unknown)
  case "$bw_state" in
    unauthenticated)
      echo "[bw-ssh-add] bw is not logged in — run 'bw login' first." >&2
      exit 1
      ;;
    locked | unlocked)
      echo "[bw-ssh-add] unlocking vault (enter Bitwarden master password)..." >&2
      BW_SESSION=$(bw unlock --raw) || {
        echo "[bw-ssh-add] unlock failed." >&2
        exit 1
      }
      export BW_SESSION
      ;;
    *)
      echo "[bw-ssh-add] unexpected bw status: ${bw_state}" >&2
      exit 1
      ;;
  esac
fi

# Load each configured key. Native SSH-key items expose the OpenSSH private
# key at .sshKey.privateKey (verified in Task 1). If Task 1 found a different
# path, update the jq filter here to match.
for id in $(printf '%s' "$ITEM_IDS_JSON" | jq -r '.[]'); do
  printf '[bw-ssh-add] loading key %s...\n' "$id"
  key=$(bw get item "$id" --session "$BW_SESSION" | jq -r '.sshKey.privateKey')
  if [ -z "$key" ] || [ "$key" = "null" ]; then
    echo "[bw-ssh-add] WARNING: no privateKey at .sshKey.privateKey for $id — check the field path." >&2
    continue
  fi
  printf '%s\n' "$key" | ssh-add -
done

echo "[bw-ssh-add] done. Agent identities:"
ssh-add -l
```

- [ ] **Step 2: Lint the rendered script.**

Render + lint (the template only injects a JSON literal, so the rendered output is valid POSIX sh):
```sh
chezmoi cat ~/.local/bin/bw-ssh-add > /tmp/bw-ssh-add.rendered
shellcheck /tmp/bw-ssh-add.rendered
```
Expected: no warnings. (If `shellcheck` is missing, install via `pacman -S shellcheck` / `brew install shellcheck`, or skip with a note.)

- [ ] **Step 3: Preview the deployment.**

Run: `chezmoi diff ~/.local/bin/bw-ssh-add`
Expected: a single added file, mode `0755` (from `executable_`), content matching the rendered script.

- [ ] **Step 4: Apply + functional test (interactive — requires TTY + master password).**

```sh
chezmoi apply ~/.local/bin/bw-ssh-add
~/.local/bin/bw-ssh-add --force
```
Expected: prompts for the Bitwarden master password, then prints `[bw-ssh-add] done. Agent identities:` followed by the key fingerprint (e.g. `256 SHA256:… agent (UNAUTHENTICATED)` — exact label depends on agent). Confirm `ssh-add -l` lists the identity.

- [ ] **Step 5: Verify idempotence.**

```sh
~/.local/bin/bw-ssh-add
```
Expected: `[bw-ssh-add] agent already has an identity — nothing to do (use --force to reload).` and exit 0.

---

### Task 3: Add the systemd ssh-agent unit + Linux enable-loader

**Files:**
- Create: `dot_config/systemd/user/ssh-agent.service` (Linux only — `.chezmoiignore` already excludes `.config/systemd` on macOS).
- Create: `.chezmoiscripts/run_onchange_after_81-ssh-agent.sh.tmpl`

**Interfaces:**
- Produces: a running `ssh-agent.service` listening on `$XDG_RUNTIME_DIR/ssh-agent.sock` (Linux). Consumed by Task 4's `SSH_AUTH_SOCK` export and by the loader in Task 2.

- [ ] **Step 1: Create the systemd user unit.**

Create `dot_config/systemd/user/ssh-agent.service` with this exact content:

```ini
[Unit]
Description=OpenSSH key agent
Documentation=https://man.archlinux.org/man/ssh-agent.1

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.sock
ExecStart=/usr/bin/ssh-agent -D -a ${SSH_AUTH_SOCK}

[Install]
WantedBy=default.target
```

`%t` expands to `$XDG_RUNTIME_DIR`; systemd substitutes `${SSH_AUTH_SOCK}` from the `Environment=` line.

- [ ] **Step 2: Create the enable-loader script (replaces the bwssh plist loader).**

Create `.chezmoiscripts/run_onchange_after_81-ssh-agent.sh.tmpl` with this exact content:

```sh
#!/bin/sh
# Enable the system ssh-agent user service (Linux) so SSH keys loaded by
# `bw-ssh-add` survive across shells until reboot. macOS needs no setup — its
# launchd already provides SSH_AUTH_SOCK — so this script is a no-op there.
#
# Idempotent. Re-runs whenever ssh.agent.version changes — bump it in
# .chezmoidata.yaml to force a re-enable (e.g. after editing the unit file).
# config-version={{ .ssh.agent.version }}
set -eu

{{ if eq .chezmoi.os "linux" }}
UNIT="ssh-agent.service"
UNIT_PATH="$HOME/.config/systemd/user/$UNIT"

if [ ! -f "$UNIT_PATH" ]; then
  echo "[ssh-agent] unit not found at $UNIT_PATH — re-run 'chezmoi apply'." >&2
  exit 0
fi

systemctl --user daemon-reload
systemctl --user enable --now "$UNIT"

# Boot-start: ensure the user manager runs before login so the agent is up
# whenever `bw-ssh-add` runs. Matches the hapi-runner linger behaviour.
loginctl enable-linger "$USER" 2>/dev/null \
  || sudo loginctl enable-linger "$USER" 2>/dev/null || true

echo "[ssh-agent] systemd user unit enabled: $UNIT (linger on)"
{{ else }}
echo "[ssh-agent] {{ .chezmoi.os }} uses the OS-provided ssh-agent — nothing to do."
{{ end }}
```

- [ ] **Step 3: Lint the rendered loader (Linux only — skip the macOS branch).**

```sh
chezmoi cat ~/.config/systemd/user/ssh-agent.service >/dev/null && echo "unit renders OK"
# shellcheck the templated file directly (template markers are comments to sh):
shellcheck .chezmoiscripts/run_onchange_after_81-ssh-agent.sh.tmpl || true
```
Expected: unit renders OK; shellcheck may flag the `{{ }}` lines (harmless — they're not real shell). Confirm there are no real shell warnings beyond template-marker lines.

- [ ] **Step 4: Preview + dry-run.**

```sh
chezmoi diff
chezmoi apply --dry-run --verbose
```
Expected: new unit + new script; dry-run reports the script will execute on apply (Linux) or print the macOS no-op line.

- [ ] **Step 5: Apply (Linux) and verify the agent is running.**

```sh
chezmoi apply
systemctl --user status ssh-agent.service --no-pager
ls -la "$XDG_RUNTIME_DIR/ssh-agent.sock"
```
Expected: service `active (running)`; socket file exists at `/run/user/<uid>/ssh-agent.sock`.

---

### Task 4: Wire `SSH_AUTH_SOCK` into shell init

**Files:**
- Modify: `dot_zprofile.tmpl`
- Modify: `dot_zshrc.tmpl`

**Interfaces:**
- Produces: `SSH_AUTH_SOCK` exported in login + interactive shells (Linux), pointing at Task 3's socket; macOS untouched. Consumed by ssh/git and by Task 2's loader.

- [ ] **Step 1: Add the Linux export to `dot_zprofile.tmpl`.**

The current file sets `EDITOR`/`VISUAL`/`MANPAGER` and has an OrbStack block. Append, before the final `{{ if .is_darwin }} ... {{ end }}` block (or at end of file):

```sh
{{ if not .is_darwin }}
# Use the systemd-managed ssh-agent (~/.config/systemd/user/ssh-agent.service)
# as the single SSH agent. Set in zprofile (not zshrc) so non-interactive
# children — chezmoi apply, git, the before_20 lifecycle script — inherit it.
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock"
{{ end }}
```

- [ ] **Step 2: Replace the bwssh block in `dot_zshrc.tmpl`.**

The current top of `dot_zshrc.tmpl` (lines 1–16) is:
```sh
# make bitwarden as ssh-agent
# export SSH_AUTH_SOCK=~/.bitwarden-ssh-agent.sock
{{ if .is_darwin }}
export SSH_AUTH_SOCK=~/Library/Caches/bwssh/agent.sock
{{ else }}
export SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/bwssh/agent.sock
{{ end }}

# # start ssh-agent and add private key
# export SSH_AUTH_SOCK=~/.ssh/ssh-agent.sock
# if ! pgrep -u "$USER" ssh-agent > /dev/null; then
#     eval "$(ssh-agent -a ~/.ssh/ssh-agent.sock | grep -v 'Agent pid')"
#     ssh-add -q ~/.ssh/id_ed25519
# fi
# export SSH_AGENT_PID=$(pidof ssh-agent)
# 
```

Replace that entire block (lines 1–16, through the commented-out native block and its trailing blank line) with:
```sh
# SSH_AUTH_SOCK is exported in ~/.zprofile (Linux) so non-interactive children
# inherit it; macOS provides its own. Here we only emit a one-line hint when
# the agent has no identities, so a fresh shell reminds you to load keys.
if [[ -o interactive ]]; then
  if ! ssh-add -l >/dev/null 2>&1; then
    echo "[ssh] agent empty — run 'bw-ssh-add' to load keys"
  fi
fi
```

- [ ] **Step 3: Lint both rendered files.**

```sh
chezmoi cat ~/.zprofile   > /tmp/zprofile.rendered && shellcheck /tmp/zprofile.rendered || true
chezmoi cat ~/.zshrc      > /tmp/zshrc.rendered
# zsh syntax check (zshrc is zsh, not POSIX):
zsh -n /tmp/zshrc.rendered
```
Expected: no errors. (`shellcheck` may warn on zsh-isms in zshrc — use `zsh -n` for that file instead.)

- [ ] **Step 4: Preview + apply.**

```sh
chezmoi diff
chezmoi apply ~/.zprofile ~/.zshrc
```
Expected: `chezmoi diff` shows the bwssh block replaced and the zprofile export added.

- [ ] **Step 5: Functional check in a fresh login shell.**

```sh
zsh -lic 'echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"'
```
Expected (Linux): `SSH_AUTH_SOCK=/run/user/<uid>/ssh-agent.sock`. On macOS: the OS-provided path (unchanged).

```sh
zsh -lic 'ssh-add -l'
```
Expected: lists the identity loaded in Task 2 (or the empty-agent hint if you've since rebooted).

> **Commit unlock:** After this task is applied and `bw-ssh-add` has been run once, the signing key is in the native agent and `git commit` signing works. All commits remain deferred to Task 9 unless the user opts otherwise.

---

### Task 5: Remove the bwssh `IdentityAgent` from ssh config

**Files:**
- Modify: `private_dot_ssh/encrypted_private_config.tmpl.age` (age-encrypted template).

**Interfaces:**
- Produces: `~/.ssh/config` no longer forces `IdentityAgent` to the dead bwssh socket; ssh falls back to `SSH_AUTH_SOCK`.

- [ ] **Step 1: Decrypt, strip the bwssh IdentityAgent line, re-encrypt (non-interactive).**

Confirm `age` is available:
```sh
command -v age >/dev/null || { echo "age not found — install via brew/pacman" >&2; exit 1; }
```

Run the surgical edit:
```sh
SOURCE="$HOME/.local/share/chezmoi/private_dot_ssh/encrypted_private_config.tmpl.age"
KEY="$HOME/.config/chezmoi/key.txt"
RECIPIENT="age16nnlyeqwxfc0v8wn9y9px8kv6gev9jr4487d6su20l55ehjdpsgqp8chnk"

# Decrypt in place to a temp, strip any IdentityAgent line pointing at bwssh,
# re-encrypt back over the source. Targets ONLY the bwssh socket so any other
# IdentityAgent line is preserved.
age -d -i "$KEY" "$SOURCE" \
  | grep -v 'IdentityAgent .*bwssh/agent\.sock' \
  | age -e -r "$RECIPIENT" -o "$SOURCE.new"
mv "$SOURCE.new" "$SOURCE"
```

- [ ] **Step 2: Verify the line is gone.**

```sh
chezmoi cat ~/.ssh/config | grep -i identityagent || echo "(no IdentityAgent lines — OK)"
```
Expected: either `(no IdentityAgent lines — OK)` or only non-bwssh `IdentityAgent` lines.

- [ ] **Step 3: Confirm ssh will use `SSH_AUTH_SOCK`.**

```sh
ssh -G github.com | grep -iE 'identityagent|identityfile'
```
Expected: `identityagent /run/user/<uid>/ssh-agent.sock` (Linux — resolved from `SSH_AUTH_SOCK`) or none (macOS). No `bwssh` path anywhere.

- [ ] **Step 4: Preview + apply.**

```sh
chezmoi diff ~/.ssh/config
chezmoi apply ~/.ssh/config
```
Expected: the live `~/.ssh/config` loses the bwssh `IdentityAgent` line.

---

### Task 6: Rewrite `before_20` to use `bw-ssh-add`

**Files:**
- Rewrite: `.chezmoiscripts/run_onchange_before_20-ensure-ssh-for-externals.sh.tmpl`

**Interfaces:**
- Consumes: the agent from Task 3, `SSH_AUTH_SOCK` from Task 4, the loader from Task 2 (materialized early via `chezmoi cat`).
- Produces: a fresh-machine `chezmoi apply` that prompts for the master password and loads the key before the SSH externals clone.

- [ ] **Step 1: Replace the entire file with the new version.**

Overwrite `.chezmoiscripts/run_onchange_before_20-ensure-ssh-for-externals.sh.tmpl` with:

```sh
#!/bin/sh
# Phase: before_  (after run_once_before_10). Ensure SSH readiness before the
# normal-phase external clones (nvim, oh-my-zsh + plugins, oh-my-tmux, ecc).
#
# Trigger: run_onchange_ — runs ONCE, then only when THIS script's content
# changes. It does NOT re-run if the vault re-locks later (ephemeral state no
# file hash captures). If a later `chezmoi apply` fails on an external SSH
# clone, run `bw-ssh-add` (after `bw login` if needed), then re-apply.
#
# Key delivery: system ssh-agent + SSH_AUTH_SOCK. The externals' git clones
# inherit chezmoi's process env, which this child script CANNOT mutate, so we
# rely on SSH_AUTH_SOCK being exported already (set in ~/.zprofile on Linux,
# or provided by macOS). We materialize ~/.ssh/config + known_hosts here
# because the early externals (.config/*, .oh-my-zsh, .local/*) sort BEFORE
# .ssh and would otherwise hit a missing-config / unknown-host failure. We
# also materialize ~/.local/bin/bw-ssh-add (a normal-phase file) so we can
# invoke it here.
set -eu

_ms="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
[ -d "$_ms" ] && case ":$PATH:" in *":$_ms:"*) ;; *) PATH="$_ms:$PATH"; export PATH ;; esac
unset _ms

command -v chezmoi >/dev/null 2>&1 || exit 0

# Materialize a chezmoi-managed file early (atomic temp+mv; avoids partial
# writes and shellcheck SC2094). $1 = target path whose source exists; $2 =
# optional chmod. NOTE: `return 0` is load-bearing under `set -e` - without it,
# a 1-arg call leaves `[ -n "${2:-}" ] && chmod` as the last statement, which
# returns 1 when $2 is empty, killing the whole script at the call site.
materialize() {
  _dst="$1"; _tmp="$_dst.tmp"
  if chezmoi cat "$_dst" > "$_tmp" 2>/dev/null; then
    mv "$_tmp" "$_dst"; [ -n "${2:-}" ] && chmod "$2" "$_dst"
  else
    rm -f "$_tmp"
  fi
  return 0
}

# 1. ~/.ssh/config + known_hosts EARLY (host aliases + known hosts; ssh falls
#    back to SSH_AUTH_SOCK — no IdentityAgent line anymore).
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
materialize "$HOME/.ssh/config" 600
materialize "$HOME/.ssh/known_hosts" 600

# 2. Start the system ssh-agent if down (Linux). macOS provides its own.
{{ if eq .chezmoi.os "linux" }}
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl --user is-active ssh-agent.service >/dev/null 2>&1; then
    systemctl --user start ssh-agent.service 2>/dev/null || true
  fi
fi
# Fall back to the runtime socket if the unit/env isn't wired yet.
[ -n "${SSH_AUTH_SOCK:-}" ] || export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.sock"
{{ end }}

# 3. Materialize bw-ssh-add (normal-phase file) and load the key.
if command -v bw >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  materialize "$HOME/.local/bin/bw-ssh-add" 755
  if [ -x "$HOME/.local/bin/bw-ssh-add" ]; then
    if [ -t 0 ]; then
      "$HOME/.local/bin/bw-ssh-add" \
        || echo "[ssh-ensure] bw-ssh-add failed - external SSH clones may fail" >&2
    else
      # Non-interactive: can't prompt for the master password. Surface the
      # next step instead of failing the apply (lifecycle scripts tolerate
      # partial failure).
      echo "[ssh-ensure] no TTY - run 'bw-ssh-add' before re-applying for the external SSH clones" >&2
    fi
  fi
else
  echo "[ssh-ensure] bw CLI not on PATH - skipping key load" >&2
fi
```

- [ ] **Step 2: Lint.**

```sh
shellcheck .chezmoiscripts/run_onchange_before_20-ensure-ssh-for-externals.sh.tmpl || true
```
Expected: no real warnings (template markers may show as comments).

- [ ] **Step 3: Preview + dry-run.**

```sh
chezmoi diff
chezmoi apply --dry-run --verbose
```
Expected: the script is marked changed (its hash changed). The dry-run reports the script will run on next apply.

- [ ] **Step 4: Apply (interactive — will prompt for the master password).**

```sh
chezmoi apply
```
Expected: `[ssh-ensure]` lines, then a master-password prompt from `bw-ssh-add`, then `[bw-ssh-add] done.`

- [ ] **Step 5: Verify non-interactive fallback (synthetic).**

```sh
chezmoi apply </dev/null 2>&1 | grep -q "no TTY" && echo "fallback OK"
```
Expected: `fallback OK` (the script detects no TTY and emits the guidance line instead of failing).

---

### Task 7: Trim `before_10` (remove bwssh bootstrap)

**Files:**
- Modify: `.chezmoiscripts/run_once_before_10-install-bootstrap-tools.sh.tmpl`

**Interfaces:**
- Produces: bootstrap installs only `bitwarden-cli` + `mise` (the `bw` + shim chain that `before_20` and `bw-ssh-add` need). No longer installs `pipx:bwssh`.

- [ ] **Step 1: Edit the script — drop the bwssh install block and update framing.**

In `.chezmoiscripts/run_once_before_10-install-bootstrap-tools.sh.tmpl`:

**a.** Replace the header comment block (lines 1–14):
```sh
#!/bin/sh
# Phase: before_  (runs BEFORE file writes + .chezmoiexternals SSH clones).
# Trigger: run_once_ — installs the SSH-critical chain once per machine, then
# never again (it self-guards via `command -v bw` anyway).
# Install the minimal chain `bw-ssh-add` needs to serve SSH keys for the
# external clones later in the normal phase:
#   bitwarden-cli (bw)  <- `bw-ssh-add` shells out to `bw`
#   mise               <- provides shims + installs/manages runtimes
#
# Fast-exit: once bw is on PATH this is a no-op on later applies. The full
# package set (Brewfile / Packages.pacman) is still restored by the after_
# scripts (run_once_after_10/11); this script only guarantees the SSH-critical
# tools early.
set -eu
```

**b.** Replace the fast-exit check (was `command -v bwssh`):
```sh
# Fast-exit: bw + mise already installed.
command -v bw >/dev/null 2>&1 && command -v mise >/dev/null 2>&1 && exit 0
```

**c.** Replace the trailing install block (the `mise install --yes python`, `mise install --yes pipx:bwssh` lines and their surrounding comment about bwssh), i.e. remove:
```sh
# Install ONLY the SSH-critical chain here. A bare `mise install` would also try
# to build lua 5.1 via the vfox-lua plugin, which compiles from source and needs
# make/gcc (base-devel) - absent in this before_ phase (base-devel is restored
# later by run_once_after_11). The full toolset is installed by
# run_once_after_30 once the toolchain exists. python first (prebuilt, no compile)
# so the pipx backend has an interpreter for bwssh.
mise install --yes python || true
mise install --yes pipx:bwssh || echo "[bootstrap] mise install (bwssh) failed" >&2
```
Leave the rest of the file (mise.toml materialization, the `add_mise_shims` helper, OS-specific install blocks) intact.

- [ ] **Step 2: Lint + preview.**

```sh
shellcheck .chezmoiscripts/run_once_before_10-install-bootstrap-tools.sh.tmpl || true
chezmoi diff
```
Expected: no real warnings; diff shows the script changed (its hash changed — `run_once_` will not re-run on already-bootstrapped machines, which is fine).

- [ ] **Step 3: Verify no `bwssh` references remain in the script.**

```sh
grep -n bwssh .chezmoiscripts/run_once_before_10-install-bootstrap-tools.sh.tmpl || echo "(clean)"
```
Expected: `(clean)`.

---

### Task 8: Delete all bwssh artifacts + update docs

**Files:**
- Delete: `dot_config/systemd/user/bwssh-agent.service`
- Delete: `dot_config/systemd/user/bwssh-agent.socket`
- Delete: `dot_config/systemd/user/sockets.target.wants/symlink_bwssh-agent.socket.tmpl`
- Delete: `private_Library/private_LaunchAgents/io.github.reidond.bwssh-agent.plist.tmpl`
- Delete: `dot_config/bwssh/config.toml.tmpl` (whole `dot_config/bwssh/` dir)
- Delete: `.chezmoiscripts/run_onchange_after_81-bwssh-agent.sh.tmpl`
- Modify: `dot_config/mise/mise.toml` (remove the `"pipx:bwssh"` line)
- Modify: `CLAUDE.md`, `AGENTS.md`, `README.md`, `BOOTSTRAP.md` (doc accuracy)

**Interfaces:**
- Produces: a source tree with no live bwssh references (only historical doc mentions if any).

- [ ] **Step 1: Delete the seven bwssh source files.**

```sh
cd "$HOME/.local/share/chezmoi"
git rm \
  dot_config/systemd/user/bwssh-agent.service \
  dot_config/systemd/user/bwssh-agent.socket \
  dot_config/systemd/user/sockets.target.wants/symlink_bwssh-agent.socket.tmpl \
  private_Library/private_LaunchAgents/io.github.reidond.bwssh-agent.plist.tmpl \
  dot_config/bwssh/config.toml.tmpl \
  .chezmoiscripts/run_onchange_after_81-bwssh-agent.sh.tmpl
# git rm leaves the staging; do not commit yet (Task 9 commits everything).
```
If `dot_config/bwssh/` becomes empty, also remove the dir: `rmdir dot_config/bwssh 2>/dev/null || true`.

- [ ] **Step 2: Remove `pipx:bwssh` from `dot_config/mise/mise.toml`.**

Delete the line:
```toml
"pipx:bwssh" = "latest"
```
(under the `# pipx` comment). Leave `copier` and the rest.

- [ ] **Step 3: Stop + disable the live bwssh services (Linux + macOS, best-effort).**

Linux:
```sh
systemctl --user disable --now bwssh-agent.service bwssh-agent.socket 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/bwssh-agent.service" \
      "$HOME/.config/systemd/user/bwssh-agent.socket" \
      "$HOME/.config/systemd/user/sockets.target.wants/bwssh-agent.socket" \
      "$XDG_RUNTIME_DIR/bwssh/agent.sock" 2>/dev/null || true
systemctl --user daemon-reload
```
macOS (run on the mac, not now):
```sh
launchctl bootout "gui/$(id -u)/io.github.reidond.bwssh-agent" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/io.github.reidond.bwssh-agent.plist"
rm -rf "$HOME/Library/Caches/bwssh"
```

- [ ] **Step 4: Apply the deletions to `$HOME`.**

```sh
chezmoi diff
chezmoi apply
```
Expected: chezmoi removes the deployed bwssh unit/socket/plist/config files from `$HOME`. The `bwssh` config dir under `~/.config` should be gone.

- [ ] **Step 5: Verify no live bwssh references remain in the source.**

```sh
cd "$HOME/.local/share/chezmoi"
grep -ril bwssh --exclude-dir=.git --exclude-dir=docs . || echo "(no live bwssh refs)"
```
Expected: `(no live bwssh refs)` — any remaining mentions live only under `docs/` (the design + plan you're reading) or are intentional history.

- [ ] **Step 6: Update doc accuracy in `CLAUDE.md`, `AGENTS.md`, `README.md`, `BOOTSTRAP.md`.**

Find every prose mention:
```sh
grep -nE "bwssh|Bitwarden SSH agent|SSH keys managed via Bitwarden" CLAUDE.md AGENTS.md README.md BOOTSTRAP.md
```
For each hit, replace the claim with the new reality. Replacement text (adapt tense to the sentence):
> SSH keys are loaded into the OS-native ssh-agent by `bw-ssh-add` (unlocks the Bitwarden vault via `bw` CLI, then `ssh-add`). The agent runs as a systemd user unit on Linux and the built-in launchd agent on macOS. Run `bw-ssh-add` after each reboot.

Specifically:
- `CLAUDE.md` project file, the "SSH keys managed via Bitwarden SSH agent" line → use the replacement above.
- `AGENTS.md` section "Encryption and Secrets", same line → use the replacement.
- `README.md` / `BOOTSTRAP.md` — update any bootstrap step that says to start/unlock bwssh to instead say: install `bitwarden-cli`, then `bw login`, then `bw-ssh-add` before `chezmoi apply`.

- [ ] **Step 7: Uninstall the bwssh runtime (best-effort).**

```sh
mise uninstall pipx:bwssh 2>/dev/null || true
# Also drop the pipx venv residue if present:
rm -rf "$HOME/.local/share/mise/installs/pipx-bwssh" 2>/dev/null || true
```

---

### Task 9: End-to-end verification + final commit

**Files:** none (verification + commit only).

- [ ] **Step 1: Full apply is clean.**

```sh
chezmoi diff    # should be empty
chezmoi apply   # should report no changes
```
Expected: clean — no pending diffs.

- [ ] **Step 2: Reboot-simulation: agent survives logout, key loads on demand.**

Either reboot, or:
```sh
systemctl --user restart ssh-agent.service
# Clear any cached identity:
ssh-add -D 2>/dev/null || true
```
Then open a fresh shell and confirm the hint fires:
```sh
zsh -lic 'true'
```
Expected: `[ssh] agent empty — run 'bw-ssh-add' to load keys`.

- [ ] **Step 3: Load + use the key end-to-end.**

```sh
bw-ssh-add                       # prompts for master password
ssh-add -l                       # lists the identity
ssh -T git@github.com            # GitHub: "Hi <user>! You've successfully authenticated..."
```
Expected: GitHub (or your gitea/host) authenticates via the native agent.

- [ ] **Step 4: Verify the resilience property (the whole point).**

Simulate vaultwarden being down and confirm SSH still works:
```sh
# Block the vaultwarden host at the resolver level, temporarily:
echo "0.0.0.0 vaultwarden.raenzo.com" | sudo tee -a /etc/hosts
ssh -T git@github.com            # should STILL succeed — key is in agent memory
# Restore:
sudo sed -i '/0.0.0.0 vaultwarden.raenzo.com/d' /etc/hosts
```
Expected: SSH succeeds with vaultwarden unreachable. (This is the core property the new design delivers.)

- [ ] **Step 5: Verify git commit signing now works via the native agent.**

```sh
git -c commit.gpgsign=true commit --allow-empty -m "test: verify ssh signing via native agent" --signoff
git log -1 --show-signature
```
Expected: `Good "git" signature with ED25519 key …`. Then drop the test commit:
```sh
git reset --hard HEAD~1
```

- [ ] **Step 6: Stage everything and commit.**

Now that signing works, commit the whole change as one signed commit (or split if the user prefers):

```sh
cd "$HOME/.local/share/chezmoi"
git status      # confirm the staged bwssh removals + new files + edits
git add -A
git commit -m "feat(ssh): replace bwssh with native ssh-agent + bw-ssh-add

Drop bwssh and its socket-activated daemon (systemd unit, launchd plist,
config, lifecycle scripts, mise entry). SSH keys now live in the OS-native
ssh-agent: a systemd user unit on Linux, the built-in launchd agent on macOS.
A new 'bw-ssh-add' command unlocks the Bitwarden vault via bw CLI and pipes
the private key into ssh-add. Vaultwarden is no longer in the hot path — once
the key is loaded, SSH works even with vaultwarden down.

Spec: docs/superpowers/specs/2026-07-05-ssh-key-flow-design.md
Plan: docs/superpowers/plans/2026-07-05-ssh-key-flow.md"
```
Expected: a single signed commit. Verify `git log -1 --show-signature` shows a good signature.

---

## Self-Review

**1. Spec coverage** — every spec item maps to a task:
- Loader script (spec §Files added #1) → Task 2 ✓
- systemd unit (§#2) → Task 3 ✓
- agent loader script (§#3) → Task 3 ✓
- `.chezmoidata.yaml` (§Modified #4) → Task 1 ✓
- `dot_zprofile.tmpl` (§#5) → Task 4 ✓
- `dot_zshrc.tmpl` (§#6) → Task 4 ✓
- encrypted ssh config `IdentityAgent` removal (§#7) → Task 5 ✓
- `before_20` rewrite (§#8) → Task 6 ✓
- `before_10` trim (§#9) → Task 7 ✓
- 7 deletions (§Files deleted) → Task 8 ✓
- KEPT items (`bitwarden-cli`, `cask bitwarden`, `data.json` symlink, `known_hosts`) → none of the tasks touch these ✓
- Risks (`bw` JSON path, `IdentityAgent` edit, macOS gating, `before_20` TTY fallback, socket-path agreement) → Task 1 Step 1, Task 5, Task 4 zshenv gating, Task 6 Step 5, Task 3 socket = Task 4 export ✓

**2. Placeholder scan** — no TBD/TODO; every code step shows the full content; the `jq` path is pinned to `.sshKey.privateKey` and Task 1 verifies it before Task 2 runs.

**3. Type/name consistency** — `ssh.agent.version`, `ssh.keyItemIds`, the `$XDG_RUNTIME_DIR/ssh-agent.sock` socket path, and the `bw-ssh-add` command name are used identically across Tasks 1–9. The systemd unit `Environment=SSH_AUTH_SOCK=%t/ssh-agent.sock` matches the zprofile export `${XDG_RUNTIME_DIR}/ssh-agent.sock` (`%t` = `$XDG_RUNTIME_DIR`).

**4. Ordering for safety** — the new flow (Tasks 2–4) is in place and applied before bwssh is removed (Task 8). At no point is the user left without a working SSH path during the transition.

No issues found.
