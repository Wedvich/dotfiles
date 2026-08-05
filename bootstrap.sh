#!/bin/sh

# Minimal bootstrap: ensure zsh exists and is the default shell, then run setup.sh in zsh.

set -e

apt_updated=false
apt_update_once() {
  [ "$apt_updated" = true ] && return 0
  sudo apt update -qy
  apt_updated=true
}

# $1 command to probe, $2 package providing it (defaults to $1)
apt_ensure() {
  command -v "$1" >/dev/null 2>&1 && return 0
  if ! command -v apt >/dev/null 2>&1; then
    echo "$1 is missing and no supported package manager was found" >&2
    return 1
  fi
  apt_update_once
  echo "Installing $1..."
  sudo apt install -qy "${2:-$1}"
}

# Root logins without sudo (Proxmox VE, LXC). A shell function only covers our
# own call sites, not the installers setup.sh pipes to sh (starship), which
# invoke sudo themselves — so get the real package when apt is around.
if [ "$(id -u)" -eq 0 ] && ! command -v sudo >/dev/null 2>&1; then
  sudo() { "$@"; }
  apt_ensure sudo || echo "Could not install sudo; keeping the shell shim" >&2
fi

if [ "$(uname -s)" = "Darwin" ] && ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Xcode Command Line Tools (headless)..."

  if ! sudo -v >/dev/null 2>&1; then
    echo "sudo is required to install Xcode Command Line Tools." >&2
    echo "Run 'sudo -v' to authenticate, then re-run this script." >&2
    exit 1
  fi

  # Keep sudo alive while softwareupdate downloads/installs (can take several minutes).
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  sudo_keepalive_pid=$!
  trap 'kill "$sudo_keepalive_pid" 2>/dev/null' EXIT

  # This sentinel file makes softwareupdate list the CLT package.
  sentinel="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  sudo touch "$sentinel"
  clt_labels=$(softwareupdate -l 2>/dev/null \
    | grep -iE 'Label:.*Command Line Tools' \
    | sed -E 's/.*Label: *//')
  clt_label=$(echo "$clt_labels" | sort -V 2>/dev/null | tail -1)
  [ -z "$clt_label" ] && clt_label=$(echo "$clt_labels" | tail -1)
  if [ -n "$clt_label" ]; then
    sudo softwareupdate -i "$clt_label" --verbose
  else
    echo "Could not find CLT label via softwareupdate; falling back to GUI installer" >&2
    xcode-select --install 2>/dev/null || true
  fi
  sudo rm -f "$sentinel"

  tries=0
  until xcode-select -p >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -gt 180 ] && { echo "CLT installation did not complete" >&2; exit 1; }
    sleep 5
  done

  kill "$sudo_keepalive_pid" 2>/dev/null
  trap - EXIT
fi

dotfiles=$(dirname "$0")
if [ ! -f "$dotfiles/setup.sh" ]; then
  dotfiles="$HOME/dotfiles"
  # Fresh Proxmox VE hosts ship without git, so the clone below can't run yet.
  apt_ensure git || exit 1
  if [ ! -d "$dotfiles" ]; then
    git clone https://github.com/Wedvich/dotfiles.git "$dotfiles"
  elif [ -d "$dotfiles/.git" ]; then
    echo "Updating dotfiles..."
    git -C "$dotfiles" pull --ff-only || echo "Could not fast-forward dotfiles; using existing checkout" >&2
  fi
fi
cd "$dotfiles"

apt_ensure zsh || exit 1

zsh_path=$(command -v zsh)

if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
  echo "Setting zsh as the default shell..."
  grep -qxF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
  sudo chsh -s "$zsh_path" "${USER:-$(id -un)}"
fi

exec zsh ./setup.sh "$@"
