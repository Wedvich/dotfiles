#!/bin/sh
# Firefox for exclaves (the /exclave skill):
#   exclave-browser <url>...                 as $BROWSER: open in profile $FIREFOX_PROFILE
#   exclave-browser --create-profile <name>  create profile <name> unless it exists,
#                                            and add 1Password to it
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
# Reads $name; prints the profile's dir, or fails. The dirs replace the positional args.
profile_dir() {
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
    [ -f "$dir/profiles.ini" ] || continue
    entry=$(tr -d '\r' < "$dir/profiles.ini" | awk -v name="$name" '
      function out() { if (hit) { print rel " " path; done = 1; exit } }
      /^\[/ { out(); hit = 0; rel = 1; path = ""; next }
      /^Name=/ { hit = substr($0, 6) == name }
      /^IsRelative=/ { rel = substr($0, 12) }
      /^Path=/ { path = substr($0, 6) }
      END { if (!done) out() }')
    [ -n "$entry" ] || continue
    rel=${entry%% *} path=${entry#* }
    if [ "$rel" = 1 ]; then
      echo "$dir/$path"
    elif is_wsl; then
      wslpath "$path"
    else
      echo "$path"
    fi
    return 0
  done
  return 1
}

onepassword_id='{d634138d-c276-4fc8-924b-40a0ea21d284}'
onepassword_url=https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi

# Sideloads 1Password into profile dir $1; AMO keeps it updated from there. Firefox
# disables a sideloaded extension until the profile's user approves it (scope 1 in the
# default autoDisableScopes=15), so drop that scope. Leaves an existing pref alone.
add_1password() {
  xpi="$1/extensions/$onepassword_id.xpi"
  if [ -f "$xpi" ]; then
    echo "1Password already in profile $name"
  else
    mkdir -p "$1/extensions" || return 1
    if ! curl -fsSL -o "$xpi.part" "$onepassword_url"; then
      rm -f "$xpi.part"
      echo "exclave-browser: couldn't download 1Password" >&2
      return 1
    fi
    mv "$xpi.part" "$xpi" && echo "Added 1Password to profile $name"
  fi
  grep -qF '"extensions.autoDisableScopes"' "$1/user.js" 2>/dev/null ||
    echo 'user_pref("extensions.autoDisableScopes", 14);' >> "$1/user.js"
}

# Safe to re-run on an existing profile: adds 1Password where it's missing.
if [ "$1" = --create-profile ]; then
  name=$2
  case $name in
    [a-z0-9]*) ;;
    *) echo "usage: exclave-browser --create-profile <name>" >&2; exit 2 ;;
  esac
  if profile_dir >/dev/null; then
    echo "Firefox profile $name already exists"
  else
    run_firefox -CreateProfile "$name" || exit
  fi
  dir=$(profile_dir) || { echo "exclave-browser: profile $name not in any profiles.ini" >&2; exit 1; }
  add_1password "$dir"
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
