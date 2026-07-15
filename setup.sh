#!/bin/zsh

set -e

DOTFILES=$(realpath "$0")
DOTFILES_PATH=$(dirname "$DOTFILES")

[[ "$OSTYPE" == "darwin"* ]] && IS_MACOS=true || IS_MACOS=false
[[ "$OSTYPE" == "linux-gnu"* ]] && IS_LINUX=true || IS_LINUX=false

typeset -A _shown
show_once() {
  [[ -n "${_shown[$1]}" ]] && return
  _shown[$1]=1
  echo "$2"
}

_apt_updated=false
apt_update_once() {
  [[ "$_apt_updated" == true ]] && return
  sudo apt update -qy
  _apt_updated=true
}

apt_ensure() {
  command -v "$1" >/dev/null 2>&1 && return
  apt_update_once
  echo "Installing $1..."
  sudo apt install -qy "${2:-$1}"
}

link_file() {
  [ -e "$2" ] && [ "$2" -ef "$1" ] && return
  show_once link "Linking dotfiles..."
  ln -fsv "$1" "$2"
}

link_dotfiles() {
  local files=($(find "$DOTFILES_PATH" -maxdepth 1 -name '.*' -type f -not -name '.DS_Store'))
  files+="$DOTFILES_PATH/starship.toml"

  for i in "${files[@]}"; do
    local file=$(basename "$i")
    link_file "$DOTFILES_PATH/$file" "$HOME/$file"
  done

  # CLAUDE.md needs to go into ~/.claude/, not ~/
  mkdir -p "$HOME/.claude"
  link_file "$DOTFILES_PATH/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

  # Ghostty reads $XDG_CONFIG_HOME/ghostty/config on both macOS and Linux
  mkdir -p "$HOME/.config/ghostty"
  link_file "$DOTFILES_PATH/ghostty.config" "$HOME/.config/ghostty/config"
}

install_homebrew() {
  if [[ "$IS_MACOS" != true ]]; then
    return
  fi

  local brew_prefix="/opt/homebrew"
  if [[ "$(uname -m)" == "x86_64" ]]; then
    brew_prefix="/usr/local"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$($brew_prefix/bin/brew shellenv)"
  fi

  brew bundle --file "$DOTFILES_PATH/Brewfile"
}

install_apt_packages() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  apt_ensure curl
  apt_ensure cc build-essential
  apt_ensure tmux
  apt_ensure pkg-config
  apt_ensure hyperfine
  apt_ensure bat
  apt_ensure gpg gnupg

  pkg-config --exists openssl || { apt_update_once; echo "Installing libssl-dev..."; sudo apt install -qy libssl-dev; }
}

install_gh() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    return
  fi

  echo "Installing GitHub CLI..."

  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
  sudo gpg --yes --dearmor --output /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
  sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

  sudo apt update -qy && sudo apt install -qy gh
}

install_zsh_plugins() {
  local zsh="$HOME/.zsh"
  mkdir -p "$zsh"

  local plugins=(
    zsh-autosuggestions=zsh-users/zsh-autosuggestions
    zsh-syntax-highlighting=zsh-users/zsh-syntax-highlighting
    zsh-z=agkozak/zsh-z
    zsh-autocomplete=marlonrichert/zsh-autocomplete
  )

  for plugin in "${plugins[@]}"; do
    local dir="${plugin%%=*}"
    local repo="${plugin#*=}"
    if [ ! -d "$zsh/$dir" ]; then
      show_once zsh_plugins "Installing ZSH plugins..."
      git clone --depth 1 "https://github.com/$repo.git" "$zsh/$dir"
    fi
  done
}

install_starship() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if ! command -v starship >/dev/null 2>&1; then
    echo "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi
}

install_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path -y
  fi

  if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
  fi

  mkdir -p "$HOME/.zfunc"
  rustup completions zsh > "$HOME/.zfunc/_rustup"
}

configure_git() {
  show_configure_git_warning() {
    echo "🔔 \\033[33m$1\\033[0m"
  }

  git config --global --get-all include.path | grep -q "$HOME/.gitconfig_dotfile" || git config --global --add include.path "$HOME/.gitconfig_dotfile"

  if [[ "$IS_MACOS" == true ]]; then
    git config --global credential.helper osxkeychain
  fi

  local keys=(user.name user.email user.signingkey gpg.ssh.program gpg.ssh.allowedSignersFile)

  for i in "${keys[@]}"; do
    if [ -z "$(git config --global --includes $i)" ]; then
      show_once configure_git "Validating Git config..."
      show_configure_git_warning "$i is missing"
    fi
  done

  if ! git -C "$DOTFILES_PATH" remote -v | grep -q "https://github.com/Wedvich/dotfiles.git (fetch)"; then
    echo "Converting git fetch URL from SSH to HTTPS"
    git -C "$DOTFILES_PATH" remote set-url origin https://github.com/Wedvich/dotfiles.git
    git -C "$DOTFILES_PATH" remote set-url origin --push git@github.com:Wedvich/dotfiles.git
  fi
}

configure_xcode() {
  if [[ "$IS_MACOS" != true ]]; then
    return
  fi

  # Xcode Command Line Tools are installed by bootstrap.sh. Only full Xcode.app
  # requires license acceptance.
  if [ ! -d /Applications/Xcode.app ]; then
    return
  fi

  local xcode_version=`xcodebuild -version | grep '^Xcode\s' | sed -E 's/^Xcode[[:space:]]+([0-9\.]+)/\1/'`
  local accepted_license_version=`defaults read /Library/Preferences/com.apple.dt.Xcode 2> /dev/null | grep IDEXcodeVersionForAgreedToGMLicense | cut -d '"' -f 2`
  if [ "$xcode_version" != "$accepted_license_version" ]; then
    sudo xcodebuild -license accept;
  fi
}

install_cargo() {
  if ! command -v cargo-generate >/dev/null 2>&1; then
    cargo install cargo-generate
  fi

  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if ! command -v eza >/dev/null 2>&1; then
    cargo install eza
  fi
}

install_1password_cli() {
  if [[ "$IS_LINUX" != true ]]; then
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

  sudo apt update -qy && sudo apt install -qy 1password-cli
}

install_mise() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if ! command -v mise >/dev/null 2>&1; then
    echo "Installing mise..."
    sudo install -dm 755 /etc/apt/keyrings
    curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor | sudo tee /etc/apt/keyrings/mise-archive-keyring.gpg 1> /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://mise.jdx.dev/deb stable main" | sudo tee /etc/apt/sources.list.d/mise.list
    sudo apt update -qy
    sudo apt install -qy mise
  fi
}

install_lang_tools() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if ! command -v mise >/dev/null 2>&1; then
    return
  fi

  mise use -g go@latest
  mise use -g bun@latest
  mise use -g "go:golang.org/x/tools/gopls@latest"
}

install_rtk() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if [ -x "$HOME/.local/bin/rtk" ]; then
    return
  fi

  echo "Installing rtk..."
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
}

main() {
  echo "\n\033[38;2;254;172;94mS\033[38;2;249;167;104me\033[38;2;244;163;115mt\033[38;2;239;158;125mt\033[38;2;234;153;135mi\033[38;2;229;149;146mn\033[38;2;224;144;156mg\033[38;2;219;140;167m \033[38;2;214;135;177mu\033[38;2;209;130;187mp\033[38;2;204;126;198m \033[38;2;199;121;208me\033[38;2;188;127;207mn\033[38;2;176;134;207mv\033[38;2;165;140;206mi\033[38;2;154;147;205mr\033[38;2;143;153;204mo\033[38;2;131;160;204mn\033[38;2;120;166;203mm\033[38;2;109;173;202me\033[38;2;98;179;201mn\033[38;2;86;186;201mt\033[0m 🦄"
  echo "\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m"

  cd "$DOTFILES_PATH"
  local git_sha=$(git rev-parse --short HEAD)
  test "$(git status --porcelain)" && git_sha+=" (dirty)"
  cd -
  echo "\\033[2mhome:    \\033[0m$HOME"
  echo "\\033[2msystem:  \\033[0m$OSTYPE $(uname -m) ($(uname -r))"
  echo "\\033[2mversion: \\033[0m$git_sha"
  echo "\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m\n"

  source "$DOTFILES_PATH/.zshenv"

  [[ -f "$HOME/.zshrc.local" ]] || touch "$HOME/.zshrc.local"

  link_dotfiles

  configure_xcode

  install_homebrew
  install_apt_packages
  install_gh
  install_zsh_plugins
  install_starship
  install_rust
  install_cargo
  install_1password_cli
  install_mise
  install_lang_tools
  install_rtk

  configure_git

  echo "\nManual steps:"

  if [[ "$IS_MACOS" == true ]]; then
    echo "• Disable Ctrl+Arrow keyboard shortcuts in macOS\n  \\033[2mSystem Settings > Keyboard > Keyboard Shortcuts... > Mission Control\\033[0m"
  else
    echo "• Install 1Password\n  \\033[2mhttps://1password.com/downloads\\033[0m"
  fi

  echo "\n\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m"
  echo "\033[38;2;254;172;94mA\033[38;2;242;161;119ml\033[38;2;230;149;145ml\033[38;2;217;138;170m \033[38;2;205;127;195md\033[38;2;185;129;207mo\033[38;2;158;145;205mn\033[38;2;130;160;204me\033[38;2;103;176;202m!\033[0m"

  if [ -n "$TMUX" ]; then
    tmux source "$HOME/.tmux.conf"
  fi
}

main
