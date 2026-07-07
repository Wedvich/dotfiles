#!/bin/sh

# Minimal bootstrap: ensure zsh exists and is the default shell, then run setup.sh in zsh.

set -e

dotfiles=$(dirname "$0")
if [ ! -f "$dotfiles/setup.sh" ]; then
  dotfiles="$HOME/dotfiles"
  if [ ! -d "$dotfiles" ]; then
    git clone https://github.com/Wedvich/dotfiles.git "$dotfiles"
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
