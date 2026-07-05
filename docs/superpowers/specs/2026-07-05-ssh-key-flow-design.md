# Design: SSH key flow without bwssh

- **Date:** 2026-07-05
- **Status:** Approved
- **Scope:** chezmoi source repo at `~/.local/share/chezmoi`
- **Target OS:** Arch Linux (primary), macOS

## Context

SSH private keys are currently served by **bwssh** — a Python daemon (mise
`pipx:bwssh`) that runs as a socket-activated SSH agent backed by a self-hosted
vaultwarden at `https://vaultwarden.raenzo.com`.

- Linux: systemd user unit `bwssh-agent.service`, socket `/run/user/<uid>/bwssh/agent.sock`.
- macOS: launchd `io.github.reidond.bwssh-agent.plist`, socket `~/Library/Caches/bwssh/agent.sock`.
- `~/.ssh/config` → `Host *` sets `IdentityAgent` to the bwssh socket.
- `~/.zshrc` exports `SSH_AUTH_SOCK` to the same socket.
- A single SSH key lives in the Bitwarden vault, item id `1fc48db0-b2a7-4eb4-9877-33847b9f3075`.
- chezmoi's `.chezmoiexternals` clone over SSH (`git@github.com`); `before_20`
  auto-starts/unlocks bwssh so a fresh-machine `chezmoi apply` works.

### Problem

bwssh is in the **hot path of every SSH connection**. If vaultwarden is down
(or the network to it), the daemon cannot unlock, no key is served, and **all
SSH stops working** — including git, the chezmoi externals bootstrap, and any
remote box. There is no offline fallback.

## Decision

**Drop bwssh. Use the OS-native ssh-agent. Load the key from Bitwarden via
`bw` CLI into the agent with `ssh-add`.** Vaultwarden is touched only for the
~1 second it takes to fetch the key; afterwards the key lives in the agent's
memory and SSH works independently of vaultwarden uptime.

Chosen operational shape (confirmed with user):

- **Trigger:** manual `bw-ssh-add` command; `~/.zshrc` prints a one-line hint
  when the agent is empty. No auto-load, no login-time prompt.
- **Agent lifetime:** persistent OS service — systemd user unit on Linux, the
  built-in launchd ssh-agent on macOS. Keys survive across shells until
  reboot/logout.
- **Externals bootstrap:** keep SSH cloning; rewrite `before_20` to invoke
  `bw-ssh-add` (prompts for the Bitwarden master password during apply when a
  TTY is present). Same fresh-machine UX as today.
- **Loader session strategy:** stateless + idempotent. `bw-ssh-add` exits early
  if the key is already loaded; otherwise `bw unlock` (prompt), fetch, pipe to
  `ssh-add -`. **No `BW_SESSION` written to disk.**

### Why this approach (vs alternatives considered)

- **Stateless loader** *(chosen)* over **cache `BW_SESSION` on disk with TTL**:
  the agent retains the key until reboot anyway, so a cached session only
  benefits re-runs within a boot — not worth a session key at rest.
- **Persistent OS service** over **per-shell `ssh-agent` spawned from zshrc**:
  one agent per machine, no agent proliferation, standard systemd/launchd
  supervision.
- **Keep SSH externals** over **migrate to HTTPS**: preserves SSH-only auth;
  the `before_20` rewrite keeps the bootstrap automatic.
- **Env-var `SSH_AUTH_SOCK`** over **`IdentityAgent` in ssh_config**: ssh_config
  cannot expand `$XDG_RUNTIME_DIR`, and a templated literal would hard-code the
  UID. The env var is the standard mechanism and propagates to all shell children.

## Architecture

```
 ┌───────────────────────┐    ssh-add -    ┌──────────────────────┐
 │ bw-ssh-add (manual)   │ ──────────────▶ │  system ssh-agent     │
 │  1. unlock via bw CLI │                 │  Linux: systemd unit  │
 │  2. bw get item <id>  │                 │  macOS: launchd-builtin│
 │  3. pipe PEM → ssh-add│                 └──────────┬─────────────┘
 └──────────┬────────────┘                            │ SSH_AUTH_SOCK
            │ also called by                           │
            │ before_20 chezmoi script                 ▼
            │                                  ssh / git over ssh
 ┌───────────┴────────────┐                 (vaultwarden NOT in the
 │ Bitwarden vault (bw)   │                  hot path after load)
 └────────────────────────┘
```

## Files added to chezmoi source

1. **`dot_local/bin/executable_bw-ssh-add.tmpl`** — POSIX sh, OS-portable.
   The loader. Logic:
   1. Idempotence: `--force` skips the check; otherwise, if `ssh-add -l`
      succeeds (exit 0 → agent already holds ≥1 identity), exit 0. Proceed only
      when it reports "no identities" (exit 1) or "error connecting to agent".
   2. Guard on `command -v bw` / `command -v jq`.
   3. If `BW_SESSION` is already exported and `bw status --session "$BW_SESSION"`
      confirms unlocked → reuse it. Otherwise inspect `bw status` (no session):
      - `unauthenticated` → error "run `bw login` first", exit non-zero.
      - `locked` or `unlocked` → run `bw unlock` (TTY prompt; works in either
        state, returns a fresh session key), parse `BW_SESSION` from stdout.
      Rationale: `bw status` never prints the session, so an unlocked vault with
      no env session still requires `bw unlock` to obtain one.
   4. For each id in `ssh.keyItemIds`:
      `bw get item <id> --session "$BW_SESSION" | jq -r '.sshKey.privateKey' | ssh-add -`.
   5. Confirm with `ssh-add -l`.

2. **`dot_config/systemd/user/ssh-agent.service`** (Linux only) — Arch standard:
   ```ini
   [Unit]
   Description=OpenSSH key agent
   [Service]
   Type=simple
   Environment=SSH_AUTH_SOCK=%t/ssh-agent.sock
   ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK
   [Install]
   WantedBy=default.target
   ```
   macOS needs **no** new unit — its launchd ssh-agent already provides the socket.

3. **`.chezmoiscripts/run_onchange_after_81-ssh-agent.sh.tmpl`** — loader for
   the agent service (replaces the bwssh plist loader):
   - Linux: `systemctl --user daemon-reload`, `enable --now ssh-agent.service`,
     `loginctl enable-linger "$USER"` (boot-start, mirroring hapi-runner).
   - macOS: no-op; print a confirm line that the system agent is in use.
   - `# config-version={{ .ssh.agent.version }}` so a yaml bump forces re-run,
     matching the existing hapi-runner/bwssh pattern.

## Files modified

4. **`.chezmoidata.yaml`** — drop the `bwssh:` block; add:
   ```yaml
   ssh:
     agent:
       version: "1"
     keyItemIds:
       - "1fc48db0-b2a7-4eb4-9877-33847b9f3075"
   ```

5. **`dot_zprofile.tmpl`** — on Linux only, export
   `SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.sock"` so non-interactive children
   (chezmoi apply, git, the `before_20` script) inherit it. macOS: leave the
   OS-provided value untouched.

6. **`dot_zshrc.tmpl`** — replace the bwssh `SSH_AUTH_SOCK` export block with
   the native-agent block (Linux: `$XDG_RUNTIME_DIR/ssh-agent.sock`; macOS:
   nothing). Add an interactive-shell hint: when `ssh-add -l` reports no
   identities, print `[ssh] agent empty — run 'bw-ssh-add' to load keys`.

7. **`private_dot_ssh/encrypted_private_config.tmpl.age`** — remove the
   `IdentityAgent /run/user/1000/bwssh/agent.sock` line under `Host *` so ssh
   falls back to `SSH_AUTH_SOCK`. Edited via `chezmoi edit` so cleartext never
   leaves the chezmoi/age workflow.

8. **`.chezmoiscripts/run_onchange_before_20-ensure-ssh-for-externals.sh.tmpl`**
   — rewrite. Same `materialize()` skeleton, swap the bwssh daemon dance for:
   ensure `ssh-agent` is up (Linux: `systemctl --user start ssh-agent` if down) →
   ensure `bw` logged in → materialize `~/.local/bin/bw-ssh-add` early via
   `chezmoi cat` → invoke it (prompts on TTY, clear error otherwise). Preserves
   today's "fresh-machine `chezmoi apply` just works" UX.

9. **`.chezmoiscripts/run_once_before_10-install-bootstrap-tools.sh.tmpl`** —
   trim. Drop `mise install pipx:bwssh` and all "ssh-critical chain for bwssh"
   framing. Keep `bitwarden-cli` + `mise` install (still needed to fetch the key).

## Files deleted (full bwssh removal)

- `dot_config/systemd/user/bwssh-agent.service`
- `dot_config/systemd/user/bwssh-agent.socket`
- `dot_config/systemd/user/sockets.target.wants/symlink_bwssh-agent.socket.tmpl`
- `private_Library/private_LaunchAgents/io.github.reidond.bwssh-agent.plist.tmpl`
- `dot_config/bwssh/config.toml.tmpl` (the whole `dot_config/bwssh/` dir)
- `.chezmoiscripts/run_onchange_after_81-bwssh-agent.sh.tmpl`
- `"pipx:bwssh" = "latest"` line in `dot_config/mise/mise.toml`

## Files KEPT (often confused with bwssh)

- `bitwarden-cli` in `Brewfile` and `Packages.pacman` — still need `bw`.
- `cask "bitwarden"` — desktop app, separate concern.
- `private_Library/private_Application Support/private_Bitwarden CLI/symlink_data.json.tmpl`
  — `bw` CLI vault state (`data.json`), not bwssh.
- `private_dot_ssh/encrypted_private_known_hosts.age` — unchanged.

## Out of scope (YAGNI)

- Multi-key rotation logic — the `ssh.keyItemIds` list scales when more ids are
  added to yaml; no extra code today (1 key).
- Session caching on disk (stateless loader chosen).
- ssh wrapper / lazy-load hook (manual trigger chosen).
- Migrating `.chezmoiexternals` to HTTPS (SSH bootstrap kept).

## Risks / to verify at implementation time

- **Exact bw JSON path** for the private key. Assumed `.sshKey.privateKey`. The
  native Bitwarden SSH-key item type is what bwssh's `mode = "explicit"` reads,
  so the field should be present — but verify by running `bw get item <id>`
  once while unlocked during implementation, and adjust the `jq` filter if the
  path differs (e.g. nested under a different key).
- **`IdentityAgent` removal** touches an age-encrypted file — use `chezmoi edit`
  / `chezmoi cat` so cleartext never sits on disk outside chezmoi.
- **macOS `SSH_AUTH_SOCK`** is set by the OS; the loader and zshrc must not
  override it. All Linux exports are gated `{{ if not .is_darwin }}`.
- **`before_20` non-interactive fallback**: when `chezmoi apply` runs without a
  TTY, the script prints a clear "run `bw login` then `bw-ssh-add`" message and
  exits 0 (lifecycle scripts tolerate partial failure) — matching current
  behavior.
- **systemd unit socket path** uses `%t` (`$XDG_RUNTIME_DIR`); the zshrc/zprofile
  export must use the same `$XDG_RUNTIME_DIR/ssh-agent.sock` so they agree.
