#!/bin/sh
# Prints whether a tmux pane is SSH'd out: <ssh_out> (default 1) if so, else
# <local_out> (default 0). The optional outputs let tmux formats ask for a
# colour number directly, e.g. #[fg=colour#(... 123 81)].
# Usage: .tmux-pane-ssh.sh <pane_pid> <pane_path> [local_out] [ssh_out]
#
# Two signals, either one wins:
#   - the pane's process tree contains an ssh command
#   - pane_path (the pane's last OSC 7 report) names a host that isn't this
#     machine — covers cases where the ssh process isn't visible but a remote
#     shell sharing these dotfiles is reporting its location

pane_pid="$1"
pane_path="$2"
local_out="${3:-0}"
ssh_out="${4:-1}"

# Process-tree check: matches direct ssh, gcloud compute ssh, and wrappers.
# gcloud compute ssh is a 3-level deep process tree (shell → gcloud → ssh),
# so we collect all descendants up to 3 levels deep before checking.
_children() { pgrep -P "$1" 2>/dev/null; }
_ssh_pids="$pane_pid"
for _p in $(_children "$pane_pid"); do
  _ssh_pids="$_ssh_pids $_p"
  for _pp in $(_children "$_p"); do
    _ssh_pids="$_ssh_pids $_pp"
  done
done
# word-splitting intended: $_ssh_pids is a space-separated PID list, one arg each
# shellcheck disable=SC2086
_ssh_cmds="$(ps -o command= -p $_ssh_pids 2>/dev/null | tr '\n' ' ')"
case "$_ssh_cmds" in
  *ssh*) printf '%s' "$ssh_out"; exit 0;;
esac

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
