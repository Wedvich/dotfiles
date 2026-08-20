#!/bin/sh
# Shared by .tmux-pane-ssh.sh and .tmux-status-right.sh: which names does this
# machine answer to, and does a reported one refer to us?
#
# Not a plain compare against hostname(1), because that name is not stable.
# With scutil's HostName unset, macOS rebuilds the transient hostname from DHCP
# on every network change, so the same Mac is "Martins-MacBook-Pro" on one WiFi
# and "Martins-MBP.lan" on the next. zsh freezes $HOST at startup, so a
# long-lived shell keeps reporting whichever name was current then — and a naive
# compare reads that stale-but-local name as a remote host.

# Sets $_local_names: names this machine answers to, most stable first, so
# ${_local_names%% *} is the one worth displaying. Resolved once per process.
_resolve_local_names() {
  [ -n "${_local_names+set}" ] && return 0

  # LocalHostName leads: it survives network changes, and it is what our own
  # OSC 7 reporters emit, so our panes match on the first name.
  _local_names=''
  if command -v scutil >/dev/null 2>&1; then
    _local_names="$(scutil --get LocalHostName 2>/dev/null)"
  fi

  # hostname(1) as well — the only name off macOS, and still ours when
  # LocalHostName is unset (Sharing prefs can clear it) or when an old report
  # predates a rename. Both forks run every time rather than deferring the
  # second: the saving is one exec per status redraw, not worth a lazy path
  # that silently stops covering the case it was written for.
  _local_names="${_local_names:+$_local_names }$(hostname -s)"
}

# Usage: _is_local_host <reported-name>   → true when the name is this machine
_is_local_host() {
  _name="${1%%.*}"
  case "$_name" in
    '' | localhost) return 0;;
  esac

  _resolve_local_names
  for _candidate in $_local_names; do
    [ "$_name" = "$_candidate" ] && return 0
  done

  return 1
}
