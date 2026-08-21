#!/bin/sh
# Draws a full-width rule along the bottom of a pane running a nested tmux, so
# the remote status line stops blending into the local one.
#
# Mechanism: pane-border-status bottom with an empty pane-border-format makes
# tmux fill the row with the border character. Those are window options, so the
# rule is per window, and the window's bottom-most pane decides — it is the only
# pane whose own status line abuts ours. Turning it on for a split window
# borders every pane, which is the price of tmux having no per-pane switch.
#
# No tmux event fires when ssh starts or exits, so .tmux.conf polls this from
# the status line and nudges it from hooks. Idempotent by design: it only writes
# an option whose value would change, since every write forces a redraw.
#
# Usage: .tmux-nested-frame.sh   (no arguments; scans every window)

# A pull that outran setup.sh must not leave half a feature behind: without the
# SSH check there is nothing to gate the rule on, so draw nothing.
[ -x "$HOME/.tmux-pane-ssh.sh" ] || exit 0

_frame_fg="$(tmux show -gqv '@nested-frame-fg' 2>/dev/null)"
: "${_frame_fg:=238}"

# A remote tmux is invisible from here — no process of ours, no OSC report. What
# is visible is its status line, and it is always the pane's bottom row: our
# window-status-format renders as " 1:name", and any stock tmux config puts an
# "index:name" tab list in the same place.
#
# The digit after the colon is rejected so a tailed log ending in "12:34:56 …"
# on a full screen doesn't read as a tab list. Cost: a remote window named
# "2fa-fix" gets no rule. A missed rule beats a phantom one that flickers with
# whatever the remote pane prints.
#
# Usage: _has_status_line <pane_id> <pane_height>
_has_status_line() {
  _row="$(tmux capture-pane -p -t "$1" -S "$(($2 - 1))" -E "$(($2 - 1))" 2>/dev/null)"
  while :; do
    case "$_row" in
      ' '*) _row="${_row# }";;
      *) break;;
    esac
  done
  case "$_row" in
    [0-9]:[!0-9\ ]* | [0-9][0-9]:[!0-9\ ]*) return 0;;
  esac
  return 1
}

# `top` means someone asked for a border status themselves; leave that window be.
_apply() {
  _win="$1"
  _want="$2"
  _have="$3"
  [ "$_want" = "$_have" ] && return 0
  case "$_have" in
    top) return 0;;
  esac
  if [ "$_want" = bottom ]; then
    tmux setw -t "$_win" pane-border-format '' ';' \
         setw -t "$_win" pane-active-border-style "fg=colour$_frame_fg" ';' \
         setw -t "$_win" pane-border-status bottom
  else
    tmux setw -u -t "$_win" pane-border-status ';' \
         setw -u -t "$_win" pane-border-format ';' \
         setw -u -t "$_win" pane-active-border-style
  fi
}

# pane_path last: it can be empty, and `read` would otherwise shift the fields.
tmux list-panes -a -F '#{window_id} #{pane_bottom} #{pane_id} #{pane_height} #{pane_pid} #{pane-border-status} #{pane_path}' \
  2>/dev/null | {
  cur_win=''
  cur_status=''
  best_bottom=-1
  best_pane=''
  best_height=0
  best_pid=''
  best_path=''

  _flush() {
    [ -n "$cur_win" ] || return 0
    _want=off
    if [ "$("$HOME/.tmux-pane-ssh.sh" "$best_pid" "$best_path")" = 1 ] &&
      _has_status_line "$best_pane" "$best_height"; then
      _want=bottom
    fi
    _apply "$cur_win" "$_want" "$cur_status"
  }

  while read -r win bottom pane height pid status path; do
    if [ "$win" != "$cur_win" ]; then
      _flush
      cur_win="$win"
      cur_status="$status"
      best_bottom=-1
    fi
    # Height, not layout order, picks the bottom pane: pane_bottom shifts by a
    # row once the border status is on, but the largest one stays the largest.
    if [ "$bottom" -gt "$best_bottom" ]; then
      best_bottom="$bottom"
      best_pane="$pane"
      best_height="$height"
      best_pid="$pid"
      best_path="$path"
    fi
  done
  _flush
}
