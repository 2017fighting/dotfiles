# Terminal attention signal — a single BEL (0x07), the same byte as
# `printf '\a'`, so a long command can call you back to its tmux window.
#
#   long-build && bell     # ring only on success
#   bell long-build        # ring either way, exit code passes through
#   bell                   # ring once, right now
#
# The byte goes to /dev/tty, not stdout: `cmd > build.log && bell` still rings,
# and no stray 0x07 lands in redirected output or logs. Only if there is no
# controlling terminal does it fall back to stdout/stderr, and only when those
# are terminals — so cron, launchd and pipelines stay silent.
_bell_ring() {
  { printf '\a' >/dev/tty; } 2>/dev/null && return 0
  if [ -t 1 ]; then
    printf '\a'
  elif [ -t 2 ]; then
    printf '\a' >&2
  fi
  return 0
}

bell() {
  if [ "$#" -eq 0 ]; then
    _bell_ring
    return 0
  fi
  "$@"
  local rc=$?
  _bell_ring
  return "$rc"
}
