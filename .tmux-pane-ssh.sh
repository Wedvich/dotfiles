#!/bin/sh
# Prints whether a tmux pane is SSH'd out: <ssh_out> (default 1) if so, else
# <local_out> (default 0). The optional outputs let tmux formats ask for a
# colour number directly, e.g. #[fg=colour#(... 123 81)].
# Usage: .tmux-pane-ssh.sh <pane_tty> <pane_path> [local_out] [ssh_out]
#
# Two signals, either one wins:
#   - a process on the pane's tty is ssh (or mosh-client)
#   - pane_path (the pane's last OSC 7 report) names a host that isn't this
#     machine — covers cases where the ssh process isn't visible but a remote
#     shell sharing these dotfiles is reporting its location

pane_tty="$1"
pane_path="$2"
local_out="${3:-0}"
ssh_out="${4:-1}"

# Process check by controlling tty, not by walking the pane's process tree: one
# kernel-filtered lookup however deep ssh sits (gcloud compute ssh is shell →
# gcloud → ssh; an agent's ssh deeper still). The walk forked a pgrep per
# process, and macOS pgrep goes through sysmond — it pinned sysmond at 150%+
# with a dozen agent panes. comm is a full path on macOS, a basename on procps.
# Empty tty guarded: BSD ps -t '' reads garbage instead of failing cleanly.
if [ -n "$pane_tty" ] && ps -t "$pane_tty" -o comm= 2>/dev/null | {
  while IFS= read -r _comm; do
    case "${_comm##*/}" in
      ssh | mosh-client) exit 0;;
    esac
  done
  exit 1
}; then
  printf '%s' "$ssh_out"
  exit 0
fi

# OSC 7 check: a reported hostname that isn't this machine means remote.
# A missing hostname (file:///path) means the reporter is local.
# Missing helper (a pull that outran setup.sh) must not take the pane with it:
# `.` on an absent file kills a non-interactive shell, which would blank the
# tmux format entirely. Fail closed to "local" instead.
if [ -r "$HOME/.tmux-local-host.sh" ]; then
  . "$HOME/.tmux-local-host.sh"
else
  _is_local_host() { return 0; }
fi
case "$pane_path" in
  file://*/*)
    _rest="${pane_path#file://}"
    _reported="${_rest%%/*}"
    _is_local_host "$_reported" || { printf '%s' "$ssh_out"; exit 0; }
    ;;
esac

printf '%s' "$local_out"
