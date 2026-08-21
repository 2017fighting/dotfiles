# Shared sync recipe. Import from project justfiles:
#   import '~/.config/just/sync.just'
# Project justfile must define `project_path`.

dry_run := env("DRY_RUN", "true")
rclone_opts := "-v -P" + (if dry_run == "true" { " --dry-run" } else { "" })
rsync_opts := "-az -i --stats" + (if dry_run == "true" { " -n" } else { "" })

# Sync a subdirectory under {{ project_path }}/ to a remote rclone target.
# Usage: just _sync <dir> <host:path>
_sync dir target:
    #!/usr/bin/env bash
    set -euo pipefail
    combined_file=$(mktemp)
    trap 'rm -f "$combined_file"' EXIT
    echo "==> Syncing {{ project_path }}/{{ dir }} -> {{ target }}/{{ project_path }}/{{ dir }}"
    rclone copy "{{ project_path }}/{{ dir }}" "{{ target }}/{{ project_path }}/{{ dir }}" {{ rclone_opts }} --combined "$combined_file"
    echo ""
    # + = new (only on source), * = different (overwritten)
    synced=$(grep -E '^[+*] ' "$combined_file" | sed 's/^[+*] //' | sort -u || true)
    if [ -n "$synced" ]; then
        if [ "{{ dry_run }}" = "true" ]; then
            echo "==> Would sync:"
        else
            echo "==> Synced:"
        fi
        printf '  %s\n' "$synced"
    else
        echo "==> Nothing to sync."
    fi

# Sync the whole {{ project_path }} tree to a remote host over ssh. Unlike the
# rclone recipe above, this goes through the system ssh and therefore reuses
# the ControlMaster socket from ~/.ssh/config (no fresh handshake per run).
# No --delete: files removed locally stay on the remote (same semantics as
# rclone copy above).
# Usage: just _sync_all <host:path>
_sync_all target:
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ project_path }}"
    dest="{{ target }}/$src"
    parent=$(dirname "$dest")
    echo "==> Syncing $src -> $dest"
    rsync {{ rsync_opts }} \
        --exclude '__pycache__/' --exclude '*.pyc' --exclude '.ruff_cache/' \
        "$src" "$parent/"
    if [ "{{ dry_run }}" = "true" ]; then
        echo ""
        echo "==> DRY_RUN=true, nothing was pushed. Re-run with DRY_RUN=false."
    fi
