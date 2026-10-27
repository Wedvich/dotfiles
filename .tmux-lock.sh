#!/bin/sh
# Shared by .tmux-pane-ssh.sh and .tmux-nested-frame.sh: a lock that knows its
# holder, so a slow run is never taken for a dead one.
#
# Judging staleness by age alone backfires under overload, the one time it
# matters: runs slow down, live holders get taken over, and each one's exit then
# frees its successor's lock. More runs, slower runs — the pileup these locks
# exist to stop. So a lock is taken over only from a holder that is gone, and
# only its owner drops it.
#
# The lock is a symlink whose target is "<pid> <start>": ln -s creates it and
# its owner in one step, leaving no moment where a live lock has no owner to
# check. Don't point it at a path that was ever a directory — ln -s onto one
# links inside it and reports success.

# Usage: _lock_take <path> <now> <backstop-seconds>  → true when the lock is ours
#
# The backstop is for a dead holder whose PID was reused: past it, the lock is
# taken whether its PID answers or not. Set it well beyond a slow run.
_lock_take() {
  ln -s "$$ $2" "$1" 2>/dev/null && return 0
  # Gone between the two calls: its holder just dropped it, so try once more.
  _lock_owner="$(readlink "$1" 2>/dev/null)" || {
    ln -s "$$ $2" "$1" 2>/dev/null
    return
  }
  _lock_pid="${_lock_owner%% *}"
  _lock_since="${_lock_owner#"$_lock_pid" }"
  # Unreadable owner: nothing to wait for. Checked field by field, since dash
  # exits on a non-numeric operand below.
  case "$_lock_pid" in
    '' | *[!0-9]*) _lock_pid='';;
  esac
  case "$_lock_since" in
    '' | *[!0-9]*) _lock_pid='';;
  esac
  if [ -n "$_lock_pid" ]; then
    # Clock stepped back: count a future start as now rather than ancient.
    [ "$_lock_since" -le "$2" ] || _lock_since="$2"
    kill -0 "$_lock_pid" 2>/dev/null && [ $(($2 - _lock_since)) -lt "$3" ] && return 1
  fi
  { rm -f "$1" && ln -s "$$ $2" "$1"; } 2>/dev/null
}

# Usage: _lock_drop <path> <now>   (the <now> given to _lock_take)
# A no-op once someone took the lock over: theirs now, not ours to free.
_lock_drop() {
  [ "$(readlink "$1" 2>/dev/null)" = "$$ $2" ] && rm -f "$1"
}
