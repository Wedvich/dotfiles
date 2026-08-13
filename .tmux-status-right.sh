#!/bin/sh
# Outputs the tmux status-right string, including tmux colour format tags.
# Usage: .tmux-status-right.sh <pane_pid> <pane_current_path>

pane_pid="$1"
pane_current_path="$2"

# SSH detection: matches direct ssh, gcloud compute ssh, and wrappers.
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
  *ssh*) _host_color=81;;   # cyan — this pane is SSH'd elsewhere
  *)     _host_color=205;;  # pink — local
esac

# Path with ~ substituted for $HOME
path="$(printf '%s' "$pane_current_path" | sed "s|$HOME|~|")"
printf '#[fg=colour8]%s' "$path"

# Machine name — color signals whether this pane is SSH'd out; the name
# itself is always the local host tmux is running on.
printf '#[default] #[fg=colour%s]%s' "$_host_color" "$(hostname -s)"
