# chezmoi owns the global agent skill set

Global skills used to be installed per machine by hand (`skills add -g`), documented
as a boundary chezmoi must not cross. They are now chezmoi-owned: one `archive`
external per upstream source in `.chezmoiexternals/skills.yaml`, each landing in its
own wrapper directory under `~/.agents/skills/`, plus `run_onchange_after_73-browser-skill.sh`
for the one skill whose content lives inside a binary (bsk). `~/.agents/.skill-lock.json`
and the `npm:skills` CLI are gone: the lockfile tracked installs that no longer exist,
and `skills update -g` would rewrite the managed directory. pi's recursive skill
discovery is what makes the wrapper layout work, so nothing is symlinked and no
source file lives outside this repo's control.

## Considered Options

- **Vendored copies** (`dot_agents/skills/<name>/`, sync via `chezmoi re-add`) —
  rejected: 3.1MB of third-party markdown in git history, and updates needed the CLI.
- **`.chezmoiexternals` with `type: git-repo`** — impossible: that type ignores
  `include`/`stripComponents` and clones the whole repo, `.git` included.
- **Symlinks into a clone** — worked, but the user asked for real files over links.
- **`run_onchange` + `skills add`** — rejected: apply depends on GitHub, upstream
  renames lose a skill silently, and the CLI has no version pinning.

## Consequences

- Flat `~/.agents/skills/<name>` is gone; paths carry provenance instead
  (`~/.agents/skills/mattpocock-engineering/tdd`). Anything that expects the CLI's
  layout (the CLI itself, other agents' installers) no longer sees these skills.
- `exclude` cannot be used in any external entry: it silently disables `include`.
- Upstream is followed by branch; a bad upstream commit lands on the next
  `just skills`. Pin a tag/SHA URL if that ever bites.
- Adding a skill means editing this repo, not running a CLI. `just doctor` derives
  its expectations from the externals file, so it fails loudly on a stray or missing
  wrapper directory.
