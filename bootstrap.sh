#!/bin/sh

# Minimal bootstrap: ensure zsh exists and is the default shell, then run setup.sh in zsh.

set -e

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
  if [ ! -d "$dotfiles" ]; then
    git clone https://github.com/Wedvich/dotfiles.git "$dotfiles"
  elif [ -d "$dotfiles/.git" ]; then
    echo "Updating dotfiles..."
    git -C "$dotfiles" pull --ff-only || echo "Could not fast-forward dotfiles; using existing checkout" >&2
  fi
fi
cd "$dotfiles"

if ! command -v zsh >/dev/null 2>&1; then
  if command -v apt >/dev/null 2>&1; then
    echo "Installing zsh..."
    sudo apt update -qy
    sudo apt install -qy zsh
  else
    echo "zsh is missing and no supported package manager was found" >&2
    exit 1
  fi
fi

zsh_path=$(command -v zsh)

if [ "$(basename "${SHELL:-}")" != "zsh" ]; then
  echo "Setting zsh as the default shell..."
  grep -qxF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
  sudo chsh -s "$zsh_path" "${USER:-$(id -un)}"
fi

exec zsh ./setup.sh
