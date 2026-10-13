#!/bin/sh
# Firefox for exclaves (the /exclave skill):
#   exclave-browser <url>...                 as $BROWSER: open in profile $FIREFOX_PROFILE
#   exclave-browser --create-profile <name>  create profile <name> unless it exists
# $BROWSER can't carry args (Claude Code execs it as argv[0]), so profile comes from env.

is_macos() { [ "$(uname -s)" = Darwin ]; }
is_wsl() {
  [ -r /proc/sys/fs/binfmt_misc/WSLInterop ] || [ -r /proc/sys/fs/binfmt_misc/WSLInterop-late ]
}

# WSL: the Windows Firefox, matching BROWSER=wslview. Linux: apt and snap (/snap/bin)
# both answer to `firefox`; flatpak doesn't.
if is_macos; then
  firefox=/Applications/Firefox.app/Contents/MacOS/firefox
elif is_wsl; then
  firefox="/mnt/c/Program Files/Mozilla Firefox/firefox.exe"
elif command -v firefox >/dev/null 2>&1; then
  firefox=firefox
elif command -v flatpak >/dev/null 2>&1 && flatpak info org.mozilla.firefox >/dev/null 2>&1; then
  firefox=flatpak
fi
if [ -z "$firefox" ] || { [ "${firefox#/}" != "$firefox" ] && [ ! -x "$firefox" ]; }; then
  echo "exclave-browser: Firefox not found" >&2
  exit 1
fi

run_firefox() {
  if [ "$firefox" = flatpak ]; then
    flatpak run org.mozilla.firefox "$@"
  else
    "$firefox" "$@"
  fi
}

# Each install keeps its own profiles.ini, so check every one this platform may use.
# Reads $name: the dirs replace the positional args.
profile_exists() {
  if is_macos; then
    set -- "$HOME/Library/Application Support/Firefox"
  elif is_wsl; then
    # cd: cmd.exe warns and falls back when started from a Linux-side cwd.
    set -- "$(wslpath "$(cd /mnt/c && cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')")/Mozilla/Firefox"
  else
    set -- "$HOME/.mozilla/firefox" "$HOME/snap/firefox/common/.mozilla/firefox" \
      "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox"
  fi
  for dir do
    [ -f "$dir/profiles.ini" ] && tr -d '\r' < "$dir/profiles.ini" | grep -qxF "Name=$name" && return 0
  done
  return 1
}

if [ "$1" = --create-profile ]; then
  name=$2
  case $name in
    [a-z0-9]*) ;;
    *) echo "usage: exclave-browser --create-profile <name>" >&2; exit 2 ;;
  esac
  if profile_exists; then
    echo "Firefox profile $name already exists"
    exit 0
  fi
  run_firefox -CreateProfile "$name"
  exit
fi

profile=${FIREFOX_PROFILE:?not inside an exclave}

# Detached, so Firefox neither writes into the caller's terminal nor exits with it.
if is_macos; then
  # -n: plain `open -a` hands off to an already running Firefox, which drops -P.
  exec open -na Firefox --args -P "$profile" "$@"
fi

if is_wsl; then
  # Windows Firefox can't resolve Linux paths.
  for arg do
    shift
    [ -e "$arg" ] && arg=$(wslpath -w "$arg")
    set -- "$@" "$arg"
  done
fi

(trap '' HUP; run_firefox -P "$profile" "$@") </dev/null >/dev/null 2>&1 &
