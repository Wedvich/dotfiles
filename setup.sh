#!/bin/zsh

set -e

DOTFILES=$(realpath "$0")
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
  files+="$DOTFILES_PATH/starship.toml"

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
  if [[ "$OSTYPE" != "darwin"* ]]; then
    return
  fi

  if ! command -v brew >/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  brew bundle --file "$DOTFILES_PATH/Brewfile" --no-lock
}

install_tmux() {
  if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    return
  fi

  if ! command -v tmux >/dev/null; then
    echo "Installing tmux..."
    sudo apt install -y tmux
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

  if [ ! -d "$zsh/zsh-z" ]; then
    show_install_zsh_plugins_message
    git clone --depth 1 https://github.com/agkozak/zsh-z.git "$zsh/zsh-z"
  fi

  if [ ! -d "$zsh/zsh-autocomplete" ]; then
    show_install_zsh_plugins_message
    git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git "$zsh/zsh-autocomplete"
  fi
}

install_starship() {
  if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    return
  fi

  if ! command -v starship >/dev/null; then
    echo "Installing starship..."
    curl -sS https://starship.rs/install.sh | sh -- -y
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

install_fonts() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    return
  fi

  local font_dir="/tmp/install_fonts"

  rm -rf "$font_dir"
  mkdir -p "$font_dir"
  cd "$font_dir"
  curl -sLO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.tar.xz
  unxz FiraCode.tar.xz
  tar -xf FiraCode.tar
  find . -type f -name '*.ttf' -exec cp '{}' "$HOME/Library/Fonts/" ';'
  cd -
}

install_rust() {
  if ! command -v rustup >/dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path -y
    source "$HOME/.cargo/env"
  fi

  mkdir -p "$HOME/.zfunc"
  rustup completions zsh > "$HOME/.zfunc/_rustup"
}

install_eza() {
  if command -v eza >/dev/null; then
    return
  fi

  echo "Installing eza..."
  cargo install eza
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
    echo "🔔 \\033[33m$1\\033[0m"
  }

  git config --global --get-all include.path | grep -q "$HOME/.gitconfig_dotfile" || git config --global --add include.path "$HOME/.gitconfig_dotfile"

  local keys=(user.name user.email user.signingkey gpg.ssh.program)

  for i in "${keys[@]}"; do
    if [ -z "$(git config --global --includes $i)" ]; then
      show_configure_git_message
      show_configure_git_warning "$i is missing"
      has_missing=true
    fi
  done

  if [ $has_missing = false ]; then
    echo "✅ Git config is valid"
  fi
}

configure_xcode() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    return
  fi

  if ! command -v xcode-select >/dev/null; then
    echo "Installing Xcode..."
    sudo xcode-select --install
  fi

  local xcode_version=`xcodebuild -version | grep '^Xcode\s' | sed -E 's/^Xcode[[:space:]]+([0-9\.]+)/\1/'`
  local accepted_license_version=`defaults read /Library/Preferences/com.apple.dt.Xcode 2> /dev/null | grep IDEXcodeVersionForAgreedToGMLicense | cut -d '"' -f 2`
  if [ "$xcode_version" != "$accepted_license_version" ]; then
    sudo xcodebuild -license accept;
  fi
}

main() {
  echo "Setting up environment..."

  source "$DOTFILES_PATH/.zshenv"

  link_dotfiles

  configure_xcode

  install_homebrew
  install_tmux
  install_zsh_plugins
  install_starship
  install_themes
  install_fonts
  install_rust
  install_eza

  configure_git

  echo "\nManual steps:"
  echo "- Install terminal themes\n  \\033[2mhttps://github.com/sindresorhus/hyper-snazzy?tab=readme-ov-file#related\\033[0m"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "- Disable Ctrl+Arrow keyboard shortcuts in macOS\n  \\033[2mSystem Settings > Keyboard > Keyboard Shortcuts... > Mission Control\\033[0m"
    echo "- Install 1password\n  \\033[2mhttps://downloads.1password.com/mac/1Password.zip\\033[0m"
  fi
  echo "- Log in to 1Password"
  echo "- Log in to VS Code"
  echo "- Log in to Firefox"

  local local_zshrc="$HOME/.zshrc.local"
  [[ -f $local_zshrc ]] || touch $local_zshrc

  exec zsh
  tmux source "$HOME/.tmux.conf"
}

main
