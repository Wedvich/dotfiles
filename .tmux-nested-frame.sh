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

# Fired per client per status redraw and from hooks, and a scan asks about every
# bottom pane, so: one scan at a time, starting at most every 2s. Unbounded,
# scans outlived the status-interval and stacked up by the dozen. A skipped
# trigger loses at most a status poll's wait. Socket in a directory that isn't
# ours alone (-S into /tmp, where others could plant files at the state path;
# sticky catches /tmp even for root), or no lock helper (a pull that outran
# setup.sh): run unthrottled rather than not at all. tmux's default socket dir
# is ours, 0700.
_sock="${TMUX%%,*}"
# -O/-k aren't POSIX but dash, bash and busybox have them; a test without fails safe.
# shellcheck disable=SC3065,SC3067
if [ -n "$TMUX" ] && [ -O "${_sock%/*}" ] && [ ! -k "${_sock%/*}" ] &&
  [ -r "$HOME/.tmux-lock.sh" ]; then
  . "$HOME/.tmux-lock.sh"
  _state="$_sock.nested-frame"
  _now="$(date +%s)"
  _read_last() {
    _last=0
    read -r _last 2>/dev/null <"$_state.last"
    case "$_last" in
      '' | *[!0-9]*) _last=0;;
    esac
    # Clock stepped back: a future stamp would hold off every scan until it passes.
    [ "$_last" -le "$_now" ] || _last=0
  }
  _read_last
  [ $((_now - _last)) -ge 2 ] || exit 0
  # A scan finishes in seconds; the backstop is for a reused PID.
  _lock_take "$_state.held" "$_now" 120 || exit 0
  trap '_lock_drop "$_state.held" "$_now"' EXIT
  trap 'exit 1' HUP INT TERM
  # Check again under the lock: a whole scan may have run since our first read.
  _read_last
  [ $((_now - _last)) -ge 2 ] || exit 0
  printf '%s\n' "$_now" >"$_state.last"
fi

_frame_fg="$(tmux show -gqv '@nested-frame-fg' 2>/dev/null)"
: "${_frame_fg:=238}"

# A remote tmux is invisible from here — no process of ours, no OSC report. What
# is visible is its status line, and it is always the pane's bottom row: our
# window-status-format renders as " 1:name", and any stock tmux config puts an
# "index:name" tab list in the same place.
#
# The tab list is not anchored to column 0, though. Once it outgrows the status
# width tmux scrolls it to keep the current window visible and marks the cut with
# "<", so the row opens with the tail of a clipped name: "<ollow-up  5:next …".
# Hence a tab is accepted anywhere in the row as long as a space (or the row
# start) precedes it — with window-status-separator '' the tabs' own padding
# supplies that space.
#
# The digit after the colon is rejected so a tailed log ending in "12:34:56 …"
# on a full screen doesn't read as a tab list. Cost: a remote window named
# "2fa-fix" gets no rule. A missed rule beats a phantom one that flickers with
# whatever the remote pane prints.
#
# Usage: _has_status_line <pane_id> <pane_height>
_has_status_line() {
  _row="$(tmux capture-pane -p -t "$1" -S "$(($2 - 1))" -E "$(($2 - 1))" 2>/dev/null)"
  case " $_row" in
    *\ [0-9]:[!0-9\ ]* | *\ [0-9][0-9]:[!0-9\ ]*) return 0;;
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

# Every pane on the window's bottom row is a candidate, since side-by-side panes
# share pane_bottom and any one of them may hold the nested tmux. Records are
# newline-separated with pane_path last: it can be empty, and `read` would
# otherwise shift the fields.
tmux list-panes -a -F '#{window_id} #{pane_bottom} #{pane_id} #{pane_height} #{pane_tty} #{pane-border-status} #{pane_path}' \
  2>/dev/null | {
  cur_win=''
  cur_status=''
  best_bottom=-1
  candidates=''

  _flush() {
    [ -n "$cur_win" ] || return 0
    _want=off
    while read -r c_pane c_height c_tty c_path; do
      [ -n "$c_pane" ] || continue
      if [ "$("$HOME/.tmux-pane-ssh.sh" "$c_tty" "$c_path")" = 1 ] &&
        _has_status_line "$c_pane" "$c_height"; then
        _want=bottom
        break
      fi
    done <<EOF_CANDIDATES
$candidates
EOF_CANDIDATES
    _apply "$cur_win" "$_want" "$cur_status"
  }

  while read -r win bottom pane height tty status path; do
    if [ "$win" != "$cur_win" ]; then
      _flush
      cur_win="$win"
      cur_status="$status"
      best_bottom=-1
      candidates=''
    fi
    # Height, not layout order, picks the bottom row: pane_bottom shifts by one
    # once the border status is on, but the largest stays the largest.
    if [ "$bottom" -gt "$best_bottom" ]; then
      best_bottom="$bottom"
      candidates=''
    fi
    if [ "$bottom" -eq "$best_bottom" ]; then
      candidates="$candidates
$pane $height $tty $path"
    fi
  done
  _flush
}
