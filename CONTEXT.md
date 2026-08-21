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

## workspaceRoots (exemplar of a deep module)

`hapi.runner.workspaceRoots` in `.chezmoidata.yaml` is one data entry expanded by
two adapters (launchd plist on macOS, systemd unit on Linux) — the pattern other
modules in this repo should copy: one interface, platform specifics behind it.
