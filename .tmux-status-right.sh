#!/bin/sh
# Outputs the tmux status-right string, including tmux colour format tags.
# Usage: .tmux-status-right.sh <pane_pid> <pane_current_path> [pane_path]
#
# pane_path is tmux's record of the last OSC 7 report from whatever runs in the
# pane. tmux itself runs locally, so the only way it can know where an SSH'd
# pane really is, is if the remote shell says so — .zshrc_dotfile emits OSC 7 on
# every prompt, which covers any host sharing these dotfiles.

pane_pid="$1"
pane_current_path="$2"
pane_path="$3"

# Missing helper (a pull that outran setup.sh) must not take the pane with it:
# `.` on an absent file kills a non-interactive shell, which would blank the
# tmux format entirely. Fail closed to "local" instead.
if [ -r "$HOME/.tmux-local-host.sh" ]; then
  . "$HOME/.tmux-local-host.sh"
else
  _is_local_host() { return 0; }
fi

# Display the same stable name the matching uses, so the status bar host and the
# OSC 7 reports can't disagree after a DHCP rename.
_resolve_local_names 2>/dev/null
local_host="${_local_names%% *}"
: "${local_host:=$(hostname -s)}"

# SSH detection shared with the window-tab colouring in .tmux.conf.
_is_ssh="$("$HOME/.tmux-pane-ssh.sh" "$pane_pid" "$pane_path")"

# Remote host + cwd, when the pane's OSC 7 report names a host that isn't this
# one. A missing hostname (file:///path) means the reporter is local.
remote_host=''
remote_path=''
case "$pane_path" in
  file://*/*)
    _rest="${pane_path#file://}"
    _reported="${_rest%%/*}"
    if ! _is_local_host "$_reported"; then
      remote_host="$_reported"
      remote_path="/${_rest#*/}"
    fi
    ;;
esac

if [ -n "$remote_host" ]; then
  host="$remote_host"
  path="$remote_path"
  # The report carries no $HOME, so ~-substitute by assuming the conventional
  # home layouts. Anything else stays absolute.
  case "$path" in
    /root) path='~';;
    /root/*) path="~${path#/root}";;
    /home/?* | /Users/?*)
      _tail="${path#/*/}"        # martin/src/x — or just martin at the home root
      # literal ~ for display, not a path to expand
      # shellcheck disable=SC2088
      case "$_tail" in
        */*) path="~/${_tail#*/}";;
        *)   path='~';;
      esac
      ;;
  esac
  _host_color=81                 # cyan — reporting host is not this machine
else
  host="$local_host"
  path="$(printf '%s' "$pane_current_path" | sed "s|$HOME|~|")"
  # Cyan still flags an SSH'd pane whose remote never reported a path.
  [ "$_is_ssh" = 1 ] && _host_color=81 || _host_color=205  # pink — local
fi

printf '#[fg=colour8]%s' "$path"
printf '#[default] #[fg=colour%s]%s' "$_host_color" "$host"
