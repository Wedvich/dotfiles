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

  # CLAUDE.md and the status line script go into ~/.claude/, not ~/
  mkdir -p "$HOME/.claude"
  link_file "$DOTFILES_PATH/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_file "$DOTFILES_PATH/statusline-command.sh" "$HOME/.claude/statusline-command.sh"

  mkdir -p "$HOME/.claude/commands"
  link_file "$DOTFILES_PATH/spawn.md" "$HOME/.claude/commands/spawn.md"

  # Ghostty reads $XDG_CONFIG_HOME/ghostty/config on both macOS and Linux
  mkdir -p "$HOME/.config/ghostty"
  link_file "$DOTFILES_PATH/ghostty.config" "$HOME/.config/ghostty/config"
}

configure_claude() {
  local settings="$HOME/.claude/settings.json"

  local schema='"https://json.schemastore.org/claude-code-settings.json"'

  local status_line='{
    "type": "command",
    "command": "bash '"$HOME"'/.claude/statusline-command.sh"
  }'

  # Ring the terminal bell on notifications.
  local notification='[
    {
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "jq -nc '"'"'{terminalSequence: \"\\u0007\"}'"'"'" }
      ]
    }
  ]'

  mkdir -p "$HOME/.claude"
  # Guard against a missing OR malformed file: either would break every jq call
  # below, and a corrupt file would otherwise leave the run stuck on the same
  # parse error forever. Back up anything unparseable before recreating it.
  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
  elif ! jq empty "$settings" >/dev/null 2>&1; then
    local backup="$settings.corrupt.$(date +%Y%m%dT%H%M%S)"
    echo "Warning: $settings is not valid JSON; backing up to $backup and recreating." >&2
    mv "$settings" "$backup"
    echo '{}' > "$settings"
  fi

  # Idempotent: only rewrite when the desired config isn't already applied.
  if jq --argjson sc "$schema" --argjson sl "$status_line" --argjson nf "$notification" -e \
    '.["$schema"] == $sc and .env.USE_BUILTIN_RIPGREP == "0"
      and .tui == "fullscreen" and .skipDangerousModePermissionPrompt == true
      and .remoteControlAtStartup == true
      and .statusLine == $sl and .hooks.Notification == $nf
      and (keys_unsorted[0]) == "$schema"' "$settings" >/dev/null 2>&1; then
    return
  fi

  show_once claude "Configuring Claude Code..."
  local tmp=$(mktemp)
  # Keep "$schema" as the first key by rebuilding the object with it up front.
  jq --argjson sc "$schema" --argjson sl "$status_line" --argjson nf "$notification" \
    '.env.USE_BUILTIN_RIPGREP = "0" | .tui = "fullscreen"
      | .skipDangerousModePermissionPrompt = true
      | .remoteControlAtStartup = true
      | .statusLine = $sl | .hooks.Notification = $nf
      | {"$schema": $sc} + del(.["$schema"])' "$settings" > "$tmp" && mv "$tmp" "$settings"
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

  brew bundle --file "$DOTFILES_PATH/Brewfile" --quiet
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
  apt_ensure jq
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

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    return
  fi

  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
}

configure_git() {
  show_configure_git_warning() {
    echo "🔔 \\033[33m$1\\033[0m"
  }

  git config --global --get-all include.path | grep -q "$HOME/.gitconfig_dotfile" || git config --global --add include.path "$HOME/.gitconfig_dotfile"

  if [[ "$IS_MACOS" == true ]]; then
    git config --system --unset-all credential.helper 2>/dev/null || true
    git config --global --unset-all credential.helper 2>/dev/null || true
    git config --global credential.helper manager
  fi

  local keys=(user.name user.email)

  for i in "${keys[@]}"; do
    if [ -z "$(git config --global --includes $i)" ]; then
      show_once configure_git "Validating Git config..."
      show_configure_git_warning "$i is missing"
    fi
  done
}

configure_zsh() {
  # ~/.zshrc and ~/.zshenv stay per-machine and source the linked dotfiles
  # halves. .zshenv is the split that reaches non-interactive shells (tmux
  # spawns, seance sessions) — per-machine env exports belong there.
  local file
  for file in .zshrc .zshenv; do
    local target="$HOME/$file"
    local dotfile="${file}_dotfile"
    local source_line="[ -f \"\$HOME/$dotfile\" ] && source \"\$HOME/$dotfile\""

    [ -L "$target" ] && rm "$target"

    if [ ! -f "$target" ]; then
      echo "$source_line" > "$target"
    elif ! grep -qF "$dotfile" "$target"; then
      show_once configure_zsh "Configuring $file..."
      printf '%s\n%s\n' "$source_line" "$(cat "$target")" > "$target"
    fi
  done

  if [ -f "$HOME/.zshrc.local" ]; then
    show_once configure_zsh "Migrating ~/.zshrc.local into ~/.zshrc..."
    grep -v 'brew shellenv' "$HOME/.zshrc.local" | sed '/./,$!d' >> "$rc"
    rm "$HOME/.zshrc.local"
  fi
}

_signing_key_changed=false
configure_signing() {
  # Per-machine, signing-only file keys that never prompt. The 1Password key
  # stays for interactive SSH auth; these keys exist so unattended Claude Code
  # sessions (remote control) can sign commits - including while the screen is
  # locked, which rules out Secure Enclave keys (Secretive hardcodes
  # kSecAttrAccessibleWhenUnlockedThisDeviceOnly; maxgoedjen/secretive#462).
  # Extractable, accepted: signing-only scope + per-machine revocation keeps
  # the downside bounded - forged signatures until revoked, no repo access.

  git config --global gpg.ssh.allowedSignersFile "$HOME/.allowed_signers"

  local key="$HOME/.ssh/git-signing"

  if [ ! -f "$key" ]; then
    show_once signing "Configuring commit signing..."
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$key" -N "" -C "signing-$(hostname -s)" -q
  fi

  if [[ "$(git config --global user.signingkey)" != "$key" ]]; then
    show_once signing "Configuring commit signing..."
    git config --global gpg.ssh.program ssh-keygen
    git config --global user.signingkey "$key"
    _signing_key_changed=true
  fi
}

check_allowed_signers() {
  # Keys are committed with wildcard principals so every machine can verify
  # every machine's commits, while email addresses stay out of the repo.
  local signingkey=$(git config --global --includes user.signingkey)
  [ -z "$signingkey" ] && return

  # user.signingkey is the private key path; check the public half.
  local pubfile="$signingkey.pub"
  [ -f "$pubfile" ] || return

  local pubkey=$(awk '{print $1" "$2}' "$pubfile")
  if ! grep -qF "$pubkey" "$DOTFILES_PATH/.allowed_signers" 2>/dev/null; then
    echo "🔔 \\033[33mThis machine's signing key is not in .allowed_signers - add and commit:\\033[0m"
    echo "* namespaces=\"git\" $pubkey"
  fi
}

configure_credentials() {
  # HTTPS push credentials for unattended sessions. Scoped, expiring,
  # revocable - unlike an SSH auth key.

  # GitHub: gh acts as the credential helper, holding this machine's
  # fine-grained PAT (Contents RW on selected repos only, 90-day expiry).
  if gh auth status >/dev/null 2>&1; then
    gh auth setup-git 2>/dev/null
  fi

  # Azure DevOps: Git Credential Manager with Entra OAuth (short-lived,
  # silently refreshing tokens). Scoped to dev.azure.com so it doesn't fight
  # osxkeychain/gh elsewhere; the leading empty helper resets inherited ones.
  local gcm=""
  if [[ "$IS_MACOS" == true ]] && command -v git-credential-manager >/dev/null 2>&1; then
    gcm="manager"
  elif [[ "$IS_LINUX" == true ]] && [ -x "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe" ]; then
    # WSL: reuse the Windows-side GCM so the OAuth browser dance happens in
    # Windows and tokens live in the Windows credential store.
    gcm="/mnt/c/Program\\ Files/Git/mingw64/bin/git-credential-manager.exe"
  fi

  if [ -n "$gcm" ]; then
    git config --global --replace-all credential.https://dev.azure.com.helper ""
    git config --global --add credential.https://dev.azure.com.helper "$gcm"
    git config --global credential.https://dev.azure.com.useHttpPath true
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

configure_maxfiles() {
  if [[ "$IS_MACOS" != true ]]; then
    return
  fi

  local src="$DOTFILES_PATH/limit.maxfiles.plist"
  local dst="/Library/LaunchDaemons/limit.maxfiles.plist"

  # launchd requires the daemon be root-owned and not a symlink, so copy rather
  # than link. Skip when the installed copy already matches.
  cmp -s "$src" "$dst" 2>/dev/null && return

  echo "Installing launchd open-file limit daemon (limit.maxfiles)..."
  sudo cp "$src" "$dst"
  sudo chown root:wheel "$dst"
  sudo chmod 644 "$dst"

  # bootout first so a re-run reloads changed limits; ignore "not loaded".
  sudo launchctl bootout system "$dst" 2>/dev/null || true
  sudo launchctl bootstrap system "$dst"
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

  source "$DOTFILES_PATH/.zshenv_dotfile"

  link_dotfiles

  configure_xcode
  configure_maxfiles

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
  install_claude

  configure_git
  configure_zsh
  configure_signing
  check_allowed_signers
  configure_credentials
  configure_claude

  echo "\nManual steps:"

  if [[ "$IS_MACOS" == true ]]; then
    echo "• Disable Ctrl+Arrow keyboard shortcuts in macOS\n  \\033[2mSystem Settings > Keyboard > Keyboard Shortcuts... > Mission Control\\033[0m"
  else
    echo "• Install 1Password\n  \\033[2mhttps://1password.com/downloads\\033[0m"
  fi

  if [[ "$_signing_key_changed" == true ]]; then
    echo "• Add this machine's signing key on GitHub as key type \\033[2mSigning Key\\033[0m\n  \\033[2mhttps://github.com/settings/ssh/new\\033[0m"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "• Create this machine's fine-grained PAT and run \\033[2mgh auth login\\033[0m with it\n  \\033[2mhttps://github.com/settings/personal-access-tokens/new\\033[0m"
  fi

  echo "\n\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m"
  echo "\033[38;2;254;172;94mA\033[38;2;242;161;119ml\033[38;2;230;149;145ml\033[38;2;217;138;170m \033[38;2;205;127;195md\033[38;2;185;129;207mo\033[38;2;158;145;205mn\033[38;2;130;160;204me\033[38;2;103;176;202m!\033[0m"

  if [ -n "$TMUX" ]; then
    tmux source "$HOME/.tmux.conf"
  fi
}

main
