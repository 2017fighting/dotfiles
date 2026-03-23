# Agent Guide for Chezmoi Dotfiles Repository

This repository is a **dotfiles management system** using [chezmoi](https://www.chezmoi.io/). It manages configuration files for macOS and Linux environments, with encrypted secrets, Homebrew packages, and system settings.

## Repository Type

- **Language**: Shell scripts (sh/bash/zsh), Go templates (`.tmpl`), TOML, YAML, Lua
- **Purpose**: Dotfiles management and system configuration
- **Target OS**: macOS (primary), Linux (servers)
- **Not an application**: No compiled code, no test suite

## Core Commands

### Chezmoi Operations

```bash
# View differences between source and target
chezmoi diff

# Apply changes (deploys files, runs scripts)
chezmoi apply

# Update from remote git repository
chezmoi update

# Re-add a modified file to chezmoi
chezmoi re-add <file>

# Navigate to source directory
chezmoi cd

# Initialize chezmoi from git repository
chezmoi init --apply 2017fighting

# Merge all differences interactively
chezmoi merge-all

# Verify configuration
chezmoi verify
```

### Just Task Runner

The `just` command provides shortcuts (defined in `dot_config/just/justfile`):

```bash
# List all available tasks
just

# Dump current Homebrew packages to Brewfile and re-add to chezmoi
just dump

# View differences
just diff

# Apply changes
just apply

# Update from remote
just update

# Re-add files
just re-add

# Merge all differences
just merge-all

# Navigate to chezmoi directory
just cd

# Initialize chezmoi
just init
```

### Homebrew Management

```bash
# Install packages from Brewfile
brew bundle --file ~/.config/homebrew/Brewfile

# Create/update Brewfile from installed packages
brew bundle dump --force --file="~/.config/homebrew/Brewfile"

# After updating Brewfile, always re-add to chezmoi
chezmoi re-add ~/.config/homebrew/Brewfile
```

### Mise (Runtime Manager)

```bash
# Install all tools defined in mise.toml
mise install --yes

# List installed tools
mise list

# Update mise tool versions
mise upgrade
```

### Linting and Validation

```bash
# Lint shell scripts (via shellcheck, installed via Homebrew)
shellcheck path/to/script.sh

# Format shell scripts (via shfmt, installed via Homebrew)
shfmt -w path/to/script.sh

# Lint YAML files
yamllint path/to/file.yaml

# Lint markdown files
markdownlint path/to/file.md

# Format with prettier (for YAML, JSON, etc.)
prettier --write path/to/file
```

### Testing

**No traditional test suite exists** for this repository. Validation consists of:

1. Dry-run chezmoi apply: `chezmoi apply --dry-run --verbose`
2. Manual verification after `chezmoi apply`
3. Syntax checking with shellcheck/shfmt

## Directory Structure

```
.
├── .chezmoi.yaml.tmpl           # Chezmoi configuration template
├── .chezmoiignore               # Files to exclude from deployment
├── .chezmoiversion              # Required chezmoi version
├── .chezmoidata/                # Data files for templates
├── .chezmoitemplates/           # Reusable template fragments
├── .chezmoiexternals/           # External git repositories (oh-my-zsh, nvim, etc.)
├── .chezmoiscripts/             # Lifecycle scripts (before/after apply)
├── dot_config/                  # Maps to ~/.config/
│   ├── git/                     # Git configuration
│   ├── homebrew/Brewfile        # Homebrew package declarations
│   ├── mise/mise.toml           # Runtime version manager config
│   ├── starship.toml            # Shell prompt configuration
│   ├── wezterm/                 # Terminal emulator config (Lua)
│   ├── just/justfile            # Task runner shortcuts
│   └── ...
├── dot_local/                   # Maps to ~/.local/
├── private_dot_ssh/             # Maps to ~/.ssh/ (age-encrypted)
├── private_Library/             # Maps to ~/Library/ (VSCode, lazygit)
└── README.md                    # Chinese documentation
```

## Code Style Guidelines

### Shell Scripts

**Shebang**:

- Use `#!/bin/sh` for POSIX-compatible scripts
- Use `#!/bin/bash` when bash-specific features are required
- Use `#!/bin/zsh` for zsh-specific scripts

**Formatting**:

- Indent with **2 spaces** (not tabs)
- Use `shfmt -i 2 -ci -bn` style
- Maximum line length: flexible, but prefer < 120 characters

**Variables**:

- UPPER_CASE for constants and environment variables: `SUDO_LOCAL="/etc/pam.d/sudo_local"`
- lowercase for local variables (rare in this codebase)
- Always quote variables: `"$SUDO_LOCAL"` not `$SUDO_LOCAL`

**Commands**:

- Prefer built-in commands over external tools when possible
- Use `echo` for simple output
- Use `printf` for formatted output
- Pipe to `> /dev/null` to suppress unwanted output

**Error Handling**:

- Scripts should generally succeed silently
- Use `echo` to log meaningful status messages
- Check file existence before operations: `if [ -f "$FILE" ]; then`

**Comments**:

- Use Chinese or English, this codebase uses both
- Comment complex logic, especially in Go templates
- Header comments explain script purpose

### Go Templates (.tmpl files)

**Templating**:

- Use `{{ }}` for template directives
- Access chezmoi variables: `{{ .chezmoi.homeDir }}`, `{{ .chezmoi.os }}`
- Access custom data: `{{ .user.name }}`, `{{ .user.email }}`, `{{ .is_darwin }}`
- Conditional logic: `{{ if .is_darwin }}...{{ end }}`
- Include files: `{{ include "path/to/file" }}`
- Hash for change detection: `{{ include $file | sha256sum }}`

**Whitespace Control**:

- Use `{{-` to trim preceding whitespace
- Use `-}}` to trim following whitespace
- Example: `{{- $var := "value" -}}`

**Variable Assignment**:

- Prefer explicit assignment: `{{ $brewfile := print .chezmoi.homeDir "/.config/homebrew/Brewfile" }}`
- Use dash for assignment ending: `{{- $var := value -}}`

### TOML Files

**Formatting**:

- Use standard TOML formatting
- Group related settings in sections: `[section]`
- Use lowercase keys with underscores: `default_branch = "main"`
- Quote string values: `name = "value"`
- Boolean values: `true`/`false` (lowercase)

### YAML Files

**Formatting**:

- Indent with **2 spaces**
- Use lowercase keys with hyphens: `auto-setup-remote: true`
- Quote strings when necessary
- Use flow style for short arrays: `args: ["-d", "-o", "-"]`
- Use block style for long arrays/objects

### Configuration Files

**Git Config** (`dot_config/git/config.tmpl`):

- Group settings by section: `[user]`, `[core]`, `[alias]`
- Indent with 4 spaces under section headers
- Use descriptive alias names
- Always use templates for user-specific values

**Brewfile** (`dot_config/homebrew/Brewfile`):

- Group by type: `tap`, `brew`, `cask`, `mas`, `vscode`, `golang`
- Sort alphabetically within groups
- Add comments for non-obvious packages
- After modification, run: `just dump`

## Naming Conventions

### Chezmoi Special Prefixes

**File Prefixes** (modify target path):

- `dot_` → `.` (creates hidden file: `dot_zshrc` → `~/.zshrc`)
- `private_` → (indicates private/sensitive, combine with other prefixes)
- `executable_` → (makes file executable)
- `symlink_` → (creates symbolic link)
- `encrypted_` → (encrypted with age, requires key)

**Script Prefixes** (execution behavior):

- `run_` → runs every `chezmoi apply`
- `run_once_` → runs once per machine (tracks execution state)
- `run_onchange_` → runs when script content changes (hash-based)

**Script Timing** (execution order):

- `before_` → runs before `chezmoi apply` deploys files
- `after_` → runs after `chezmoi apply` deploys files
- No timing prefix → runs during apply (between file updates)
- Numeric prefixes control order: `10-`, `20-`, `30-`, `40-`

### Examples

- `dot_zshrc` → `~/.zshrc`
- `private_dot_ssh/encrypted_config.age` → `~/.ssh/config` (encrypted)
- `run_once_before_20-restore-homebrew.sh.tmpl` → runs once, before apply, order 20
- `executable_dot_local/bin/my-script` → `~/.local/bin/my-script` (executable)

## Error Handling

**Shell Scripts**:

- Don't use `set -e` in lifecycle scripts (allows partial success)
- Check critical conditions explicitly: `if [ -f "$FILE" ]; then`
- Use `|| true` to ignore non-critical failures
- Log errors with `echo` to stderr if needed: `echo "Error: ..." >&2`

**Chezmoi Operations**:

- Always test changes with `chezmoi diff` before `chezmoi apply`
- Use `chezmoi apply --dry-run --verbose` for safe validation
- If apply fails, check logs and re-run after fixes
- For merge conflicts: `chezmoi merge <file>` or `chezmoi merge-all`

## Important Workflow Rules

### Modifying Configuration Files

1. **For files managed by chezmoi**:
   - Edit source: `chezmoi edit <file>` (opens source in editor)
   - Or edit directly in chezmoi source directory: `chezmoi cd`
   - Apply changes: `chezmoi apply`
   - Commit to git if desired

2. **For files modified on target system**:
   - Re-add to chezmoi: `chezmoi re-add <file>`
   - This updates the source from the target
   - Review changes: `chezmoi diff`
   - Commit to git

3. **For Brewfile updates**:
   - Install new package: `brew install <package>`
   - Update Brewfile: `just dump` (or `brew bundle dump --force ...`)
   - Apply to chezmoi: already done by `just dump`
   - Commit to git

### Encryption and Secrets

- Encrypted files use **age** encryption
- Private key location: `~/.config/chezmoi/key.txt`
- Public key (recipient): `age16nnlyeqwxfc0v8wn9y9px8kv6gev9jr4487d6su20l55ehjdpsgqp8chnk`
- SSH keys managed via Bitwarden SSH agent
- Never commit unencrypted secrets to git

### Git Workflow

- Default branch: `main`
- Auto-setup remote on push: enabled
- Pull with rebase: enabled
- Commit signing: SSH (required)
- Commit messages: verbose, use template at `~/.config/git/message`
- Use conventional commit aliases if needed (defined in git config)

## Common Tasks for Agents

### Adding a New Configuration File

```bash
# 1. Create or edit the file in chezmoi source
chezmoi cd
# Edit the file with appropriate prefix (e.g., dot_config/app/config)

# 2. If file needs to be executable
# Use executable_ prefix: executable_dot_local/bin/my-script

# 3. If file contains secrets
# Use encrypted_private_ prefix and .age suffix
# Example: encrypted_private_dot_config/secret.yaml.age

# 4. Apply to test
chezmoi apply --dry-run --verbose
chezmoi apply

# 5. Commit to git
cd ~/.local/share/chezmoi
git add .
git commit -m "feat: add new configuration for X"
git push
```

### Adding a New Package

```bash
# 1. Install the package
brew install package-name

# 2. Update Brewfile
just dump

# 3. Verify Brewfile was updated
chezmoi diff

# 4. Commit changes
cd ~/.local/share/chezmoi
git add dot_config/homebrew/Brewfile
git commit -m "feat: add package-name to Brewfile"
git push
```

### Creating a New Lifecycle Script

```bash
# 1. Navigate to chezmoi source
chezmoi cd

# 2. Create script in .chezmoiscripts/
# Name format: run_{once|onchange}_{before|after}_NN-description.sh.tmpl
# Example: .chezmoiscripts/run_once_after_50-setup-thing.sh.tmpl

# 3. Write script with proper shebang and Go template guards
#!/bin/sh
{{ if .is_darwin }}
# Your macOS-specific commands here
{{ end }}

# 4. Test with dry-run
chezmoi apply --dry-run --verbose

# 5. Apply and verify
chezmoi apply
```

## Notes for AI Coding Agents

- This is **not a software project** with tests or builds
- Focus on **configuration correctness** and **idempotency**
- Always use **chezmoi diff** before applying changes
- Respect **encryption boundaries** (never expose secrets)
- Maintain **consistency** with existing patterns
- Test changes on **non-production systems** first
- Shell scripts should be **POSIX-compliant** unless bash-specific features are required
- Go templates must be **syntactically valid** and handle missing data gracefully
- When in doubt, check the [chezmoi documentation](https://www.chezmoi.io/)
