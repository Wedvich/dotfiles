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

  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> "$HOME/.zshrc.local"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  brew bundle --file "$DOTFILES_PATH/Brewfile" --no-lock
}

install_tmux() {
  if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    return
  fi

  if ! command -v tmux >/dev/null 2>&1; then
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

  if ! command -v starship >/dev/null 2>&1; then
    echo "Installing Starship..."
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
  if ! command -v rustup >/dev/null 2>&1; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path -y
    source "$HOME/.cargo/env"
  fi

  mkdir -p "$HOME/.zfunc"
  rustup completions zsh > "$HOME/.zfunc/_rustup"
}

configure_git() {
  local has_shown_message=false
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
    fi
  done

  if $has_shown_message; then
    return
  fi

  if ! git remote -v | grep -q "https://github.com/Wedvich/dotfiles.git (fetch)"; then
    echo "Converting git fetch URL from SSH to HTTPS"
    git remote set-url origin https://github.com/Wedvich/dotfiles.git
    git remote set-url origin --push git@github.com:Wedvich/dotfiles.git
  fi
}

configure_xcode() {
  if [[ "$OSTYPE" != "darwin"* ]]; then
    return
  fi

  if ! command -v xcode-select >/dev/null 2>&1; then
    echo "Installing Xcode..."
    sudo xcode-select --install
  fi

  local xcode_version=`xcodebuild -version | grep '^Xcode\s' | sed -E 's/^Xcode[[:space:]]+([0-9\.]+)/\1/'`
  local accepted_license_version=`defaults read /Library/Preferences/com.apple.dt.Xcode 2> /dev/null | grep IDEXcodeVersionForAgreedToGMLicense | cut -d '"' -f 2`
  if [ "$xcode_version" != "$accepted_license_version" ]; then
    sudo xcodebuild -license accept;
  fi
}

install_pkgconfig() {
  if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    return
  fi

  if dpkg -s pkg-config >/dev/null 2>&1; then
    return
  fi

  sudo apt install -y pkg-config
}

install_cargo() {
  if ! command -v eza >/dev/null 2>&1; then
    cargo install eza
  fi

  if ! command -v cargo-generate >/dev/null 2>&1; then
    cargo install cargo-generate
  fi
}

install_1password_cli() {
  if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    return
  fi

  if command -v op >/dev/null 2>&1; then
    return
  fi

  echo "Installing 1Password CLI..."

  curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --yes --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list > /dev/null

  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22
  curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
  sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol > /dev/null

  sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

  sudo apt update -y && sudo apt install 1password-cli
}

install_hyperfine() {
  if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    return
  fi

  if command -v hyperfine >/dev/null 2>&1; then
    return
  fi

  echo "Installing Hyperfine..."

  sudo apt update -y && sudo apt install hyperfine
}

main() {
  echo "\n\033[38;2;254;172;94mS\033[38;2;249;167;104me\033[38;2;244;163;115mt\033[38;2;239;158;125mt\033[38;2;234;153;135mi\033[38;2;229;149;146mn\033[38;2;224;144;156mg\033[38;2;219;140;167m \033[38;2;214;135;177mu\033[38;2;209;130;187mp\033[38;2;204;126;198m \033[38;2;199;121;208me\033[38;2;188;127;207mn\033[38;2;176;134;207mv\033[38;2;165;140;206mi\033[38;2;154;147;205mr\033[38;2;143;153;204mo\033[38;2;131;160;204mn\033[38;2;120;166;203mm\033[38;2;109;173;202me\033[38;2;98;179;201mn\033[38;2;86;186;201mt\033[0m 🦄"
  echo "\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m"

  cd $DOTFILES_PATH
  local git_sha=$(git rev-parse --short HEAD)
  test "$(git status --porcelain)" && git_sha+=" (dirty)"
  cd -
  echo "\\033[2mhome:    \\033[0m$HOME"
  echo "\\033[2msystem:  \\033[0m$OSTYPE $(uname -m) ($(uname -r))"
  echo "\\033[2mversion: \\033[0m$git_sha"
  echo "\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m\n"

  source "$DOTFILES_PATH/.zshenv"

  link_dotfiles

  configure_xcode

  install_homebrew
  install_tmux
  install_zsh_plugins
  install_starship
  install_themes
  install_fonts
  install_pkgconfig
  install_rust
  install_cargo
  install_1password_cli
  install_hyperfine

  configure_git

  echo "\nManual steps:"
  echo "• Install 1Password\n  \\033[2mhttps://1password.com/downloads\\033[0m"
  echo "• Install terminal themes\n  \\033[2mhttps://github.com/sindresorhus/hyper-snazzy?tab=readme-ov-file#related\\033[0m"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "• Disable Ctrl+Arrow keyboard shortcuts in macOS\n  \\033[2mSystem Settings > Keyboard > Keyboard Shortcuts... > Mission Control\\033[0m"
  fi

  local local_zshrc="$HOME/.zshrc.local"
  [[ -f $local_zshrc ]] || touch $local_zshrc

  echo "\n\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m"
  echo "\033[38;2;254;172;94mA\033[38;2;242;161;119ml\033[38;2;230;149;145ml\033[38;2;217;138;170m \033[38;2;205;127;195md\033[38;2;185;129;207mo\033[38;2;158;145;205mn\033[38;2;130;160;204me\033[38;2;103;176;202m!\033[0m"

  exec zsh
  tmux source "$HOME/.tmux.conf"
}

main
