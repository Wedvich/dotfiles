#!/bin/zsh

set -e

DOTFILES=$(realpath -s "$0")
DOTFILES_PATH=$(dirname "$DOTFILES")

link_dotfiles() {
  local has_shown_message=false
  show_link_dotfiles_message() {
    if ! $has_shown_message; then
      echo "Linking dotfiles..."
      has_shown_message=true
    fi
  }

  local files=($(find "$DOTFILES_PATH" -maxdepth 1 -name '.*' -type f -not -name '.DS_Store'))

  for i in "${files[@]}"; do
    local file=$(basename $i)
    local source="$DOTFILES_PATH/$file"
    local target="$HOME/$file"

    if [ -f "$target" ] && [ "$(readlink -f "$target")" = "$source" ] && [ "$target" -ef "$source" ]; then
      continue
    fi

    show_link_dotfiles_message
    ln -fsv "$source" "$target"
  done
}

install_homebrew() {
  if [[ "$OSTYPE" != "Darwin" ]]; then
    return
  fi

  if ! command -v brew >/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
}

install_tmux() {
  if command -v tmux >/dev/null; then
    return
  elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    echo "Installing tmux..."
    sudo apt install -y tmux
  elif [[ "$OSTYPE" == "Darwin" ]]; then
    echo "Installing tmux..."
    brew install tmux
  else
    echo "Unrecognized OS: $OSTYPE"
  fi
}

install_zsh_plugins() {
  local zsh="$HOME/.zsh"
  mkdir -p "$zsh"

  local has_shown_message=false
  show_install_zsh_plugins_message() {
    if ! $has_shown_message; then
      echo "Installing ZSH plugins..."
      has_shown_message=true
    fi
  }

  if [ ! -d "$zsh/zsh-autosuggestions" ]; then
    show_install_zsh_plugins_message
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git "$zsh/zsh-autosuggestions"
  fi

  if [ ! -d "$zsh/zsh-nvm" ]; then
    show_install_zsh_plugins_message
    git clone --depth 1 https://github.com/lukechilds/zsh-nvm.git "$zsh/zsh-nvm"
  fi

  if [ ! -d "$zsh/zsh-syntax-highlighting" ]; then
    show_install_zsh_plugins_message
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$zsh/zsh-syntax-highlighting"
  fi
}

install_starship() {
  if command -v starship >/dev/null; then
    return
  elif [[ "$OSTYPE" == "linux-gnu" ]]; then
    echo "Installing starship..."
    curl -sS https://starship.rs/install.sh | sh
  elif [[ "$OSTYPE" == "Darwin" ]]; then
    echo "Installing starship..."
    brew install starship
  else
    echo "Unrecognized OS: $OSTYPE"
  fi
}

install_themes() {
  local has_shown_message=false
  show_install_themes_message() {
    if ! $has_shown_message; then
      echo "Installing themes..."
      has_shown_message=true
    fi
  }

  if [ ! -f "$HOME/.tmux.snazzy.theme" ]; then
    show_install_themes_message
    curl -o "$HOME/.tmux.snazzy.theme" https://raw.githubusercontent.com/ivnvxd/tmux-snazzy/main/.tmux.snazzy.theme
  fi
}

configure_git() {
  local has_shown_message=false
  local has_missing=false
  show_configure_git_message() {
    if ! $has_shown_message; then
      echo "Validating Git config..."
      has_shown_message=true
    fi
  }

  show_configure_git_warning() {
    echo "⚠️ \\033[33m$1\\033[0m"
  }

  if [ ! -z "$(git config --global --includes user.name)" ]; then
    show_configure_git_message
    show_configure_git_warning "name is missing"
    has_missing=true
  fi

  if [ ! -z "$(git config --global --includes user.email)" ]; then
    show_configure_git_message
    show_configure_git_warning "email is missing"
    has_missing=true
  fi

  if [ ! -z "$(git config --global --includes user.signingkey)" ]; then
    show_configure_git_message
    show_configure_git_warning "signingkey is missing"
    has_missing=true
  fi
}

main() {
  source "$DOTFILES_PATH/.zshenv"

  link_dotfiles

  install_homebrew
  install_tmux
  install_zsh_plugins
  install_starship
  install_themes

  configure_git

  echo "\nTerminal themes:\n🔗 https://github.com/sindresorhus/hyper-snazzy?tab=readme-ov-file#related"

  source "$HOME/.zshrc"
  tmux source "$HOME/.tmux.conf"
}

main
