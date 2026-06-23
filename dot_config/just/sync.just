# Shared sync recipe. Import from project justfiles:
#   import '~/.config/just/sync.just'
# Project justfile must define `project_path`.

dry_run := env("DRY_RUN", "true")
rclone_opts := "-v -P" + (if dry_run == "true" { " --dry-run" } else { "" })

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
