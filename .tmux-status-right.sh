#!/bin/sh
# Outputs the tmux status-right string, including tmux colour format tags.
# Usage: .tmux-status-right.sh <pane_pid> <pane_current_path>

pane_pid="$1"
pane_current_path="$2"

# SSH indicator: matches direct ssh, gcloud compute ssh, and wrappers.
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
_ssh_cmds="$(ps -o command= -p $_ssh_pids 2>/dev/null | tr '\n' ' ')"
case "$_ssh_cmds" in
  *ssh*) printf '#[fg=colour81]ssh ';;
esac

# Path with ~ substituted for $HOME
path="$(printf '%s' "$pane_current_path" | sed "s|$HOME|~|")"
printf '#[fg=colour8]%s' "$path"

# Git branch
branch="$(cd "$pane_current_path" && git branch --show-current 2>/dev/null)"
if [ -n "$branch" ]; then
  printf '#[default] #[fg=colour205]%s' "$branch"
else
  printf '#[default]'
fi
