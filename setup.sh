#!/bin/zsh

set -e

DOTFILES=$(realpath "$0")
DOTFILES_PATH=$(dirname "$DOTFILES")

[[ "$OSTYPE" == "darwin"* ]] && IS_MACOS=true || IS_MACOS=false
[[ "$OSTYPE" == "linux-gnu"* ]] && IS_LINUX=true || IS_LINUX=false

# --minimal: appliance-ish hosts (Proxmox VE, LXCs) — shell comfort only, no dev
# tooling. Sticky via marker so re-runs without the flag (e.g. updot) stay
# minimal; --full clears the marker.
MINIMAL_MARKER="$HOME/.dotfiles_minimal"
if [[ " $* " == *" --full "* ]]; then
  rm -f "$MINIMAL_MARKER"
  MINIMAL=false
elif [[ " $* " == *" --minimal "* ]] || [[ -f "$MINIMAL_MARKER" ]]; then
  MINIMAL=true
else
  MINIMAL=false
fi

# Root logins without sudo (Proxmox VE, LXC): shim it so our call sites work
# unchanged. A function doesn't reach child processes, so bootstrap.sh installs
# the real package for piped installers that elevate on their own (starship).
if (( EUID == 0 )) && ! command -v sudo >/dev/null 2>&1; then
  sudo() { "$@"; }
fi

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
  # An explicit map, deliberately not a glob over the repo's dot-files: a glob
  # links anything added later (a .gitignore, say) straight into $HOME.
  local -a links=(
    .agent-bridge.sh       "$HOME/.agent-bridge.sh"
    .allowed_signers       "$HOME/.allowed_signers"
    .editorconfig          "$HOME/.editorconfig"
    .gitconfig_dotfile     "$HOME/.gitconfig_dotfile"
    .tmux-status-right.sh  "$HOME/.tmux-status-right.sh"
    .tmux.conf             "$HOME/.tmux.conf"
    .tmux.snazzy.theme     "$HOME/.tmux.snazzy.theme"
    .zshenv_dotfile        "$HOME/.zshenv_dotfile"
    .zshrc_dotfile         "$HOME/.zshrc_dotfile"

    # CLAUDE.md and the status line script go into ~/.claude/, not ~/
    CLAUDE.md              "$HOME/.claude/CLAUDE.md"
    statusline-command.sh  "$HOME/.claude/statusline-command.sh"

    # Ghostty reads $XDG_CONFIG_HOME/ghostty/config on both macOS and Linux
    ghostty.config         "$HOME/.config/ghostty/config"
  )

  if [[ "$MINIMAL" != true ]]; then
    links+=(starship.toml "$HOME/.config/starship.toml")
  fi

  # WSL ships no xdg-open, so tools that shell out to a browser (gh auth login)
  # find nothing. Provide the name they probe for.
  if [[ "$IS_WSL" == true ]]; then
    links+=(wslview.sh "$HOME/.local/bin/wslview")
  fi

  local src dst
  for src dst in "${links[@]}"; do
    mkdir -p "${dst:h}"
    link_file "$DOTFILES_PATH/$src" "$dst"
  done

  # starship.toml used to land undotted in $HOME, found via $STARSHIP_CONFIG.
  # An if, not &&: a false tail would make the function return 1 under set -e.
  if [ -L "$HOME/starship.toml" ]; then
    rm "$HOME/starship.toml"
  fi
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

# Debian netinst/LXC images ship without a generated UTF-8 locale, so anything
# locale-aware (zsh completion, eza glyphs, git log) falls back to C. Ubuntu
# normally has one already, and both steps below are then no-ops.
configure_locale() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  apt_ensure locale-gen locales

  # locale -a prints glibc's spelling (en_US.utf8), not locale.gen's.
  if ! locale -a 2>/dev/null | tr -d '-' | grep -qixF en_US.utf8; then
    echo "Generating en_US.UTF-8 locale..."
    sudo sed -i 's/^# *en_US\.UTF-8/en_US.UTF-8/' /etc/locale.gen
    # Stripped images can drop the line entirely, leaving nothing to uncomment.
    grep -q '^en_US\.UTF-8' /etc/locale.gen || \
      echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen > /dev/null
    sudo locale-gen
  fi

  if ! grep -qxF 'LANG=en_US.UTF-8' /etc/default/locale 2>/dev/null; then
    echo "Setting default LANG to en_US.UTF-8..."
    sudo update-locale LANG=en_US.UTF-8
  fi

  # /etc/default/locale is only read at login, so carry it into this run too.
  export LANG=en_US.UTF-8
}

install_apt_packages() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  apt_ensure curl
  apt_ensure git
  apt_ensure tmux
  apt_ensure jq

  # Minimal hosts sign commits too, and need an editor for `git commit` without -m.
  apt_ensure ssh-keygen openssh-client
  apt_ensure vi vim

  # Directory jumping is shell comfort, which is what minimal hosts are for.
  # Non-fatal: older suites don't carry it, and .zshrc_dotfile guards on presence.
  apt_ensure zoxide || true

  if [[ "$MINIMAL" == true ]]; then
    # Same reasoning for eza, but from the distro rather than install_eza's upstream
    # repo: an appliance host shouldn't grow a third-party apt source it then
    # depends on at every `apt upgrade`.
    apt_ensure eza || true
    return
  fi

  apt_ensure cc build-essential
  apt_ensure pkg-config
  apt_ensure hyperfine
  apt_ensure gpg gnupg
  apt_ensure git-lfs

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

install_eza() {
  if [[ "$IS_LINUX" != true ]]; then
    return
  fi

  if command -v eza >/dev/null 2>&1; then
    return
  fi

  echo "Installing eza..."

  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | \
  sudo gpg --yes --dearmor --output /etc/apt/keyrings/gierens.gpg

  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | \
  sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null

  sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

  sudo apt update -qy && sudo apt install -qy eza
}

install_zsh_plugins() {
  local zsh="$HOME/.zsh"
  mkdir -p "$zsh"

  local plugins=(
    zsh-autosuggestions=zsh-users/zsh-autosuggestions
    zsh-syntax-highlighting=zsh-users/zsh-syntax-highlighting
    zsh-autocomplete=marlonrichert/zsh-autocomplete
  )

  for plugin in "${plugins[@]}"; do
    local dir="${plugin%%=*}"
    local repo="${plugin#*=}"
    if [ ! -d "$zsh/$dir" ]; then
      show_once zsh_plugins "Installing ZSH plugins..."
      git clone --depth 1 "https://github.com/$repo.git" "$zsh/$dir"
    else
      # Cloning once and never pulling freezes each machine at whatever upstream
      # looked like on its first setup. fetch+reset rather than pull: the clones are
      # shallow, and zsh-autocomplete rewrites files inside its own checkout at
      # runtime, which makes --ff-only refuse. Nothing here is ours to keep.
      { git -C "$zsh/$dir" fetch --quiet --depth 1 origin &&
        git -C "$zsh/$dir" reset --hard --quiet FETCH_HEAD; } 2>/dev/null ||
        echo "Could not update $dir" >&2
    fi
  done

  # zsh-z was replaced by zoxide.
  rm -rf "$zsh/zsh-z"
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

configure_zoxide() {
  command -v zoxide >/dev/null 2>&1 || return 0

  # One-time import of zsh-z's frecency database. Gated on the zoxide db being
  # empty rather than on a db path: zoxide puts it under ~/.local/share on Linux
  # but ~/Library/Application Support on macOS, and it refuses a non-empty db
  # anyway. zoxide locates zsh-z's own datafile itself, so only the default path
  # is checked here.
  if [ -f "$HOME/.z" ] && [ -z "$(zoxide query -l 2>/dev/null | head -1)" ]; then
    show_once zoxide "Importing zsh-z history into zoxide..."
    zoxide import zsh-z || echo "Could not import $HOME/.z into zoxide" >&2
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

    # The built-in FSMonitor daemon is macOS/Windows only, so this can't live in
    # the shared .gitconfig_dotfile that Linux hosts include too.
    git config --global core.fsmonitor true
  fi

  if command -v git-lfs >/dev/null 2>&1 && [ -z "$(git config --global filter.lfs.clean)" ]; then
    show_once configure_git "Validating Git config..."
    git lfs install --skip-repo
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
    grep -v 'brew shellenv' "$HOME/.zshrc.local" | sed '/./,$!d' >> "$HOME/.zshrc"
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

configure_proxmox() {
  if ! command -v pveversion >/dev/null 2>&1; then
    return
  fi

  local src="$DOTFILES_PATH/proxmox-no-nag.sh"
  local dst="/usr/local/sbin/proxmox-no-nag"

  # The apt hook runs as root long after setup, so copy rather than link — a
  # symlink into the dotfiles clone breaks the moment the repo moves.
  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    echo "Installing Proxmox subscription-nag patch..."
    sudo install -m 755 "$src" "$dst"
  fi

  local hook="/etc/apt/apt.conf.d/99-proxmox-no-nag"
  local hook_line='DPkg::Post-Invoke { "[ -x '"$dst"' ] && '"$dst"' || true"; };'

  if ! grep -qxF "$hook_line" "$hook" 2>/dev/null; then
    echo "Installing apt hook to reapply it after upgrades..."
    printf '%s\n%s\n' '// proxmoxlib.js is not a conffile, so upgrades silently restore the notice.' "$hook_line" | \
    sudo tee "$hook" > /dev/null
  fi

  sudo "$dst"
}

install_cargo() {
  if ! command -v cargo-generate >/dev/null 2>&1; then
    cargo install cargo-generate
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
  mise use -g node@latest
  mise use -g "go:golang.org/x/tools/gopls@latest"

  mise settings add idiomatic_version_file_enable_tools node
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
  echo "\\033[2mmode:    \\033[0m$([[ "$MINIMAL" == true ]] && echo minimal || echo full)"
  echo "\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m\n"

  source "$DOTFILES_PATH/.zshenv_dotfile"

  link_dotfiles

  # Outside the branch below: both apply either way — a UTF-8 locale is baseline
  # shell comfort, and a Proxmox host may be set up in either mode.
  configure_locale
  configure_proxmox

  if [[ "$MINIMAL" == true ]]; then
    touch "$MINIMAL_MARKER"

    install_apt_packages
    install_zsh_plugins
    configure_zoxide

    configure_git
    configure_zsh
    configure_signing
    check_allowed_signers
  else
    configure_xcode
    configure_maxfiles

    install_homebrew
    install_apt_packages
    install_gh
    install_eza
    install_zsh_plugins
    install_starship
    install_rust
    install_cargo
    install_1password_cli
    install_mise
    install_lang_tools
    install_claude
    configure_zoxide

    configure_git
    configure_zsh
    configure_signing
    check_allowed_signers
    configure_credentials
    configure_claude
  fi

  echo "\nManual steps:"

  if [[ "$IS_MACOS" == true ]]; then
    echo "• Disable Ctrl+Arrow keyboard shortcuts in macOS\n  \\033[2mSystem Settings > Keyboard > Keyboard Shortcuts... > Mission Control\\033[0m"
  elif [[ "$MINIMAL" != true ]]; then
    echo "• Install 1Password\n  \\033[2mhttps://1password.com/downloads\\033[0m"
  fi

  if [[ "$_signing_key_changed" == true ]]; then
    echo "• Add this machine's signing key on GitHub as key type \\033[2mSigning Key\\033[0m\n  \\033[2mhttps://github.com/settings/ssh/new\\033[0m"
  fi
  if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
    echo "• Create this machine's fine-grained PAT and run \\033[2mgh auth login\\033[0m with it\n  \\033[2mhttps://github.com/settings/personal-access-tokens/new\\033[0m"
  fi

  echo "\n\033[38;2;254;172;94m~\033[38;2;249;167;104m~\033[38;2;244;163;115m~\033[38;2;239;158;125m~\033[38;2;234;153;135m~\033[38;2;229;149;146m~\033[38;2;224;144;156m~\033[38;2;219;140;167m~\033[38;2;214;135;177m~\033[38;2;209;130;187m~\033[38;2;204;126;198m~\033[38;2;199;121;208m~\033[38;2;188;127;207m~\033[38;2;176;134;207m~\033[38;2;165;140;206m~\033[38;2;154;147;205m~\033[38;2;143;153;204m~\033[38;2;131;160;204m~\033[38;2;120;166;203m~\033[38;2;109;173;202m~\033[38;2;98;179;201m~\033[38;2;86;186;201m~\033[0m"
  echo "\033[38;2;254;172;94mA\033[38;2;242;161;119ml\033[38;2;230;149;145ml\033[38;2;217;138;170m \033[38;2;205;127;195md\033[38;2;185;129;207mo\033[38;2;158;145;205mn\033[38;2;130;160;204me\033[38;2;103;176;202m!\033[0m"

  if [ -n "$TMUX" ]; then
    tmux source "$HOME/.tmux.conf"
  fi
}

main
