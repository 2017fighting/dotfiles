# Domain Glossary

Terms for the architecture of this dotfiles repo. Keep entries short; each names a
module or concept that architecture reviews should use instead of describing files.

## environment intake (`env.d`)

Every `*.zsh` under `~/.config/zsh/env.d/` is sourced by `~/.zshenv` in **every**
shell — interactive, non-interactive, and the login shells that launchd/systemd
spawn for hapi-runner (which rely on zshenv supplying `HAPI_API_URL`). Plain
snippets (e.g. `ecc.zsh`) and chezmoi-decrypted files (e.g. `hapi.zsh.age`) are
equivalent citizens: drop a file in, every shell inherits it. New tool environment
belongs here, never as a decrypt-edit-encrypt cycle on a shared blob.

## manifest sync (`just dump`)

Machine → source sync for the declarative package manifests: Brewfile
(`brew bundle dump --force` + re-add) and `mise.toml` (explicit-path re-add —
bare `chezmoi re-add` would sweep unrelated churn). `Packages.pacman`/`.aur`
are source-curated manifests with comments — never dumped. Boundary: package
manifests only; drifting content files (settings.json, known_hosts) are
`chezmoi diff` discipline, not manifest sync.

## doctor (`just doctor`)

The repo's executable check surface — the closest thing this repo has to a
test suite. Three sections: SSH chain (agent, loaded key, GitHub auth),
externals (derived from `.chezmoiexternals/` — new externals are checked
automatically; git-repos need `.git`, `type: file` entries need the file),
and environment intake (every env.d source entry present on target + a
`zsh -lc` sentinel proving the glob loop runs in the login-shell shape).

## workspaceRoots (exemplar of a deep module)

`hapi.runner.workspaceRoots` in `.chezmoidata.yaml` is one data entry expanded by
two adapters (launchd plist on macOS, systemd unit on Linux) — the pattern other
modules in this repo should copy: one interface, platform specifics behind it.
