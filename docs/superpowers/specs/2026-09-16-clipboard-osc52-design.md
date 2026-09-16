# Design: Clipboard and OSC 52 under tmux/WSLg

- **Date:** 2026-09-16
- **Status:** Accepted — deliberately **no behaviour change** to tmux; one package added, one `just doctor` check added
- **Scope:** chezmoi source repo at `~/.local/share/chezmoi` — `dot_tmux.conf.local`,
  `dot_config/pacman/Packages.pacman`, `dot_config/just/justfile`
- **Environment:** WSL2 + Arch (`default-terminal screen-256color`) → tmux 3.7c →
  WezTerm on Windows, with WSLg providing a real Wayland socket

## Context

Copying out of a TUI app failed, and the investigation produced a rule that is easy to
get wrong, so it is recorded here rather than left in the config.

Two reproduction commands defined the problem. The first did nothing; the second worked:

```sh
printf '\033]52;c;%s\a' "$(printf 'hello from pi' | base64 -w0)"            # fails
printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$(printf 'x' | base64 -w0)"    # works
```

The initial diagnosis ("tmux eats it, wrap it in DCS") was right, but the reasoning
attached to it was wrong three times before it was measured properly. What follows is
only what was reproduced by experiment.

## Findings

Measured by attaching a real tmux client to a pty, driving copy-mode, and decoding the
bytes that reached that pty.

1. **tmux's own copy (`y`) works and needs nothing — not even `set-clipboard on`.**
   With `set-clipboard external` (this repo's setting), `y` puts the selection in tmux's
   buffer **and** tmux emits OSC 52 to the terminal itself. The emitted sequence is
   `\e]52;;<base64>\a` — an **empty selection field**, not `c` — and the payload has a
   trailing newline. Matching on `]52;c;` + the exact source text therefore reports a
   false negative. tmux emits nothing when `set-clipboard off`.
2. **An application's bare OSC 52 is swallowed under `set-clipboard external`** — it is
   neither forwarded to the terminal nor turned into a buffer. Under `set-clipboard on`
   all four variants (`]52;c;`, `]52;;`, `]52;p;`, BEL- and ST-terminated) are forwarded
   verbatim. Under `off` none are. This is the mechanism behind the two commands above.
3. **`Ms` / `terminal-features` do not gate tmux's own OSC 52 output.** Adding
   `terminal-overrides` `Ms=`, or `terminal-features xterm*:clipboard`, changed nothing
   observable; a client's terminfo `Ms` was irrelevant. (tmux's own `xterm*` built-in
   matches `xterm-256color`; a non-`xterm` client termname has its own `clipboard`
   feature, e.g. `screen*` here. In practice this needs no configuration.)
4. **A missing native backend is the actual silent failure.** pi 0.85.1 emits OSC 52
   when its platform-tool path finds no `wl-copy`/`xclip`. There is no `xclip`/`xsel` on
   this machine, and gpakosz's auto-detection for `tmux_conf_copy_to_os_clipboard`
   requires `XDG_SESSION_TYPE=wayland`, which is **unset** here — so that knob silently
   does nothing even with `wl-copy` installed.
5. **`wl-copy` is the working path.** With `wl-clipboard` installed, `wl-copy` (written
   from WSL) lands in the Windows clipboard, verified via `Get-Clipboard`, including a
   60 KB payload byte-for-byte. WezTerm accepts a raw OSC 52 written directly to its
   pty, so the terminal end was never the problem.

## Decision

**Change no tmux behaviour.** Concretely:

- Keep `set -gq allow-passthrough on` and the default `set-clipboard external`.
- Do **not** switch to `set-clipboard on`. Switching would make third-party bare OSC 52
  work with no configuration, at the cost of breaking the DCS form that currently works
  (incl. over ssh/nested tmux) — trading one working path for another, for no gain.
- `y` copy-mode copying needs no fix: finding 1 shows it already reaches the terminal.
- Rely on a **native clipboard backend** (`wl-copy`) as the supported path for apps;
  bare OSC 52 remains a fallback that is only meaningful outside tmux.

### Why this approach (vs alternatives considered)

- **`set-clipboard on`** — rejected. It is a global semantic flip that trades the DCS
  path for the bare-OSC-52 path; both cannot be had at once. This env needs the DCS path
  (ssh/nested tmux).
- **Adding `Ms` / `terminal-features`** — rejected as cargo cult; finding 3 shows no
  observable effect.
- **A pi extension to wrap OSC 52 in DCS** — unavailable. pi's extension API exposes no
  clipboard/copy hook. A source patch upstream would be the only route, and it is not
  needed once `wl-copy` exists.
- **`tmux_conf_copy_to_os_clipboard=true`** — rejected. It only rewrites copy-mode
  bindings when the `XDG_SESSION_TYPE` probe passes (finding 4), it touches every
  copy-mode binding, and finding 1 makes it redundant.

### What is added instead

Documentation and a guard, so the failure mode stops being silent:

- `dot_tmux.conf.local` — comment at `allow-passthrough` recording that it does **not**
  forward a bare OSC 52.
- `dot_config/pacman/Packages.pacman` — `wl-clipboard` (was installed by hand and
  unrecorded).
- `dot_config/just/justfile` — a `clipboard backend` doctor section: on a Wayland
  session require `wl-copy`, on X11 require `xclip`/`xsel`, otherwise pass. Deliberately
  no Windows-side assertion, because this repo also targets macOS.

## Out of scope

- Changing pi's clipboard code. Upstream `main` already replaces the silent-success path
  with a loud, platform-specific error; upgrading pi surfaces this failure rather than
  fixing it, so it is not the remedy here.
- Copying *images* across the boundary.
- `~/.tmux/` — that is a clone of gpakosz/.tmux, not ours to edit.

## Verification performed

- Byte-level matrix for `external` / `on` / `off` against bare OSC 52 and the DCS form.
- The real config chain (`~/.tmux/.tmux.conf` → `~/.tmux.conf.local`) driven through an
  attached client; OSC 52 payloads decoded from the client pty.
- `wl-copy` → Windows clipboard readback, small and 60 KB payloads.
- `just doctor` and `chezmoi diff` after the edits.

## Reporter's note

The reporter's `y`-copies-to-Windows observation was correct and initially contradicted
by a wrong test. Three separate flaws in the test rig each produced a false negative
(no `prefix C-a`; `C-a` bound away with `send-prefix`; and the `]52;c;`-plus-exact-text
match). **When an observation and a test disagree about a clipboard path, decode the
bytes on the wire before believing the test.**
