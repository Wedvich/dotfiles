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
#
# The same pane is asked about by its window tab (per client), status-right and
# every .tmux-nested-frame.sh scan, each up to once a second. So answers are
# cached per pane for a few seconds, and one run at a time refreshes a pane:
# the others serve the last answer rather than queue behind it.

pane_tty="$1"
pane_path="$2"
local_out="${3:-0}"
ssh_out="${4:-1}"

_detect() {
  # Process check by controlling tty, not by walking the pane's process tree:
  # one kernel-filtered lookup however deep ssh sits (gcloud compute ssh is
  # shell → gcloud → ssh; an agent's ssh deeper still). The walk forked a pgrep
  # per process, and macOS pgrep goes through sysmond — it pinned sysmond with
  # a dozen agent panes. comm is a full path on macOS, a basename on procps.
  # Empty tty guarded: BSD ps -t '' reads garbage instead of failing cleanly.
  if [ -n "$pane_tty" ] && ps -t "$pane_tty" -o comm= 2>/dev/null | {
    while IFS= read -r _comm; do
      case "${_comm##*/}" in
        ssh | mosh-client) exit 0;;
      esac
    done
    exit 1
  }; then
    return 0
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
      _is_local_host "$_reported" || return 0
      ;;
  esac

  return 1
}

_answer() {
  if [ "$1" = 1 ]; then
    printf '%s' "$ssh_out"
  else
    printf '%s' "$local_out"
  fi
}

_uncached() {
  if _detect; then _answer 1; else _answer 0; fi
  exit 0
}

_sock="${TMUX%%,*}"
# Run by hand (no server to cache beside), without a tty to key on, or with a
# socket in a directory that isn't ours alone (-S into /tmp, where others could
# plant files at the cache path; sticky catches /tmp even for root): just ask.
# tmux's default socket dir is ours, 0700.
# -O/-k aren't POSIX but dash, bash and busybox have them; a test without fails safe.
# shellcheck disable=SC3065,SC3067
[ -n "$TMUX" ] && [ -n "$pane_tty" ] && [ -O "${_sock%/*}" ] && [ ! -k "${_sock%/*}" ] ||
  _uncached

# Missing helper (a pull that outran setup.sh): no lock means no cache either,
# since unlocked refreshes are what piled up.
[ -r "$HOME/.tmux-lock.sh" ] || _uncached
. "$HOME/.tmux-lock.sh"

_dir="$_sock.pane-ssh"
_cache="$_dir/${pane_tty##*/}"
_lock="$_cache.held"
_now="$(date +%s)"

# Sets _stamp and _cached; _cached stays empty when there is no answer yet.
_read_cache() {
  _stamp=0
  _cached=''
  read -r _stamp _cached 2>/dev/null <"$_cache"
  # Guards the arithmetic below: dash exits on a non-numeric operand.
  case "$_stamp" in
    '' | *[!0-9]*) _stamp=0;;
  esac
  # Clock stepped back: a future stamp would pin this answer until it passes.
  [ "$_stamp" -le "$_now" ] || _stamp=0
}

_read_cache
if [ -n "$_cached" ] && [ $((_now - _stamp)) -lt 3 ]; then
  _answer "$_cached"
  exit 0
fi

_refresh() {
  if _detect; then _result=1; else _result=0; fi
  printf '%s %s\n' "$_now" "$_result" >"$_cache"
  _answer "$_result"
  exit 0
}

[ -d "$_dir" ] || mkdir -p "$_dir" 2>/dev/null || _uncached
# A run takes well under a second; the backstop is for a reused PID.
if ! _lock_take "$_lock" "$_now" 60; then
  # A refresh is under way: serve the last answer rather than queue behind it.
  # Read again, as the holder may have written since we looked. No answer yet
  # (a new pane): ask directly rather than serve a blank, and record it.
  _read_cache
  [ -n "$_cached" ] || _refresh
  _answer "$_cached"
  exit 0
fi
trap '_lock_drop "$_lock" "$_now"' EXIT
trap 'exit 1' HUP INT TERM

_refresh
