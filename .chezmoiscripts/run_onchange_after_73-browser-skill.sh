#!/bin/sh
# Install the browser-skill agent skill into pi.
#
# `bsk install-skill` writes a self-contained copy of the skill that is EMBEDDED in
# the bsk binary — no network, ~50ms. The binary itself comes from mise
# (github:Tencent/BrowserSkill, installed by run_once_before_30-install-package), so
# this script only has to place the skill files.
#
# The Pi harness is named explicitly and `--all` must never be used here: bsk maps the
# Codex harness to ~/.agents/skills, the chezmoi-managed directory, so `--all` would
# drop an unmanaged browser-skill copy in among the archive externals.
#
# Re-runs only when this script's content changes. Error philosophy: LOUD — a missing
# skill is a silent failure at agent runtime, so exit 1 and let chezmoi retry.
set -eu

if ! command -v bsk >/dev/null 2>&1; then
  echo "[browser-skill] bsk not on PATH (run 'mise install --yes') — exiting 1 so chezmoi retries." >&2
  exit 1
fi

bsk install-skill --harness pi --yes --force
echo "[browser-skill] installed into ~/.pi/agent/skills/browser-skill"
exit 0
