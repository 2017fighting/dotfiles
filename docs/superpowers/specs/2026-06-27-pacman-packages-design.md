# Design: pacman-managed packages for Arch Linux (WSL)

- **Date:** 2026-06-27
- **Status:** Approved
- **Scope:** chezmoi source repo at `~/.local/share/chezmoi`
- **Target environment:** Arch Linux under WSL (command-line tools only)

## Context

The repo currently manages packages on **macOS only**, via a declarative Homebrew
Brewfile (`dot_config/homebrew/Brewfile`) restored by a Darwin-only chezmoi script
(`run_once_after_10-restore-homebrew.sh.tmpl`). There is no Linux equivalent, so a
fresh `chezmoi apply` on the user's WSL Arch machine installs none of the same
command-line toolset.

The user runs GUI apps (Chrome, VS Code, WezTerm, Bitwarden desktop, etc.) on the
**Windows** host, not inside WSL. So the Arch side needs **CLI tools only** — the
desktop apps, fonts, App Store apps, and VS Code extensions from the Brewfile are
intentionally out of scope.

## Decision

**Approach A — two static package lists + one thin Linux-only restore script.** This
mirrors the existing Homebrew layout (declarative list file + thin restore script)
so the repo stays structurally consistent across platforms.

- `dot_config/pacman/Packages.pacman` — official-repo packages, one per line with
  `# description` comments (Brewfile style).
- `dot_config/pacman/Packages.aur` — AUR-only packages (same style).
- `.chezmoiscripts/run_once_after_11-restore-pacman.sh.tmpl` — Linux-only; installs
  both lists idempotently.

### Why this approach (vs alternatives considered)

- **Template-generate the pacman list from the Brewfile** — rejected: name mapping is
  full of exceptions (`gh`→`github-cli`, `android-platform-tools`→`android-tools`,
  two `tree-sitter` brew entries → one package), and the cask/mas/vscode entries
  don't map at all. A static list is simpler and more readable (KISS/YAGNI).
- **Hardcode packages inline in one script** — rejected: diverges from the
  established "declarative list file + thin restore script" pattern used by the
  Homebrew setup.
- **Static lists + thin script** *(chosen)* — direct structural analog of the Homebrew
  setup; easy to read, edit, and diff.

## Package-name verification (done during design)

Every candidate name was verified against the live Arch package database
(`archlinux.org/packages/search/json/`) and AUR RPC API (`aur.archlinux.org/rpc/`),
not guessed — a wrong name makes `pacman -S` fail.

**Notable finding:** most tools originally assumed to be AUR-only have graduated into
the official `extra` repo. After verification, **only `fpp`** is genuinely AUR-only.

### Name changes from the Brewfile

| Brewfile entry | pacman name | reason |
|---|---|---|
| `brew "gh"` | `github-cli` | renamed upstream |
| `cask "android-platform-tools"` | `android-tools` | cask→repo; adb/fastboot are CLI, user wants them |
| `brew "tree-sitter"` + `brew "tree-sitter-cli"` | `tree-sitter` | one package covers both |
| `go "cmd/go"`, `go "cmd/gofmt"` | (covered by `go`) | bundled in the `go` package |
| `npm "corepack"` | `corepack` | Arch package (pulls `nodejs`) |

### Skipped (out of scope)

- `pam-reattach`, `mas` — macOS-only.
- `docker-completion` — Homebrew-specific; the Arch `docker` package ships its own
  completions.
- All `cask` entries except `android-platform-tools` — desktop apps, belong on the
  Windows host.
- All `mas` entries — App Store, macOS-only.
- All `vscode` entries — VS Code runs on Windows; extensions live there.

## Files added to chezmoi source

### 1. `dot_config/pacman/Packages.pacman` (45 packages, all in `extra`)

```
atuin bat bitwarden-cli bottom chezmoi cmake composer corepack difftastic direnv
docker eza fzf gdu github-cli git git-delta git-lfs go htop jq just lazygit libyaml
markdownlint-cli mise navi neovim nginx prettier rclone ripgrep shellcheck shfmt
sshpass starship tmux tree tree-sitter urlscan wget yazi yq zoxide android-tools
```

### 2. `dot_config/pacman/Packages.aur` (1 package)

```
fpp
```

### 3. `.chezmoiscripts/run_once_after_11-restore-pacman.sh.tmpl`

Linux-only (`{{ if eq .chezmoi.os "linux" }}`). Behavior:

- **Idempotency** — uses the same hash-comment trick as the Homebrew script: a
  rendered comment embeds the sha256 of both list files, so editing either list
  changes the script's content hash and chezmoi re-runs it. `pacman -S --needed`
  and the AUR helper's `--needed` make re-runs no-ops for already-installed packages.
- **Official list** — loop per-package with `sudo pacman -S --needed --noconfirm`,
  continuing past any failure and collecting the names that failed. This way one bad
  name never aborts the whole install; failures are reported at the end. (`pacman -S`
  with a multi-name list aborts on the first unknown package, so a per-package loop
  is more robust.)
- **AUR list** — detect an AUR helper at runtime (`command -v yay` then `paru`), run
  as the **non-root user** (AUR helpers refuse root). If neither helper is present,
  print a clear message naming the AUR packages and skip (do not fail the script).
  Uses `--needed --noconfirm`.
- **No hard failure** — missing helper or a few failed packages print warnings, so
  `chezmoi apply` completes and the user sees what needs manual attention.

## Verification

On the WSL Arch host:

1. `chezmoi apply` deploys the two list files to `~/.config/pacman/` and runs the
   restore script (Linux only).
2. `pacman -Q <pkg>` confirms each official package is installed.
3. `yay -Q fpp` (or `paru -Q fpp`) confirms the AUR package if a helper is present.
4. Re-running `chezmoi apply` with no list change is a no-op (script content hash
   unchanged → `run_once` skips).
5. Adding a package to a list and re-running installs only the new package.

## Updating later

- Add/remove a line in `Packages.pacman` or `Packages.aur`; the hash comment changes,
  so the next `chezmoi apply` re-runs the script and reconciles (`--needed` makes
  removals a no-op; the user uninstalls explicitly if desired).

## Out of scope

- Desktop apps, fonts, App Store apps, VS Code extensions (Windows host owns these).
- An AUR helper bootstrap (installing yay/paru itself) — the script detects an
  existing helper but does not install one; that's a one-time manual setup step.
- Removal/drift detection — packages removed from the lists are not auto-uninstalled.
- Templating the list from the Brewfile.
