# Create or attach to tmux session if not already in one
if ! { [[ "$TERM" == "screen"* ]] && [ -n "$TMUX" ]; } then
  tmux new -As0
fi

# Set up SSH agent bridge with Windows host on WSL2
if [[ $(uname -r) == *WSL2* ]]; then
  source ~/.agent-bridge.sh
  init-1pw() {
    echo "removing previous socket..."
    rm $SSH_AUTH_SOCK
    echo "Starting SSH-Agent relay..."
    (setsid socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
  }
fi

# Aliases
alias ls="eza --icons"

# History
setopt extended_history       # record timestamp of command in HISTFILE
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
setopt share_history          # share command history data

# Plugins
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source ~/.zsh/zsh-nvm/zsh-nvm.plugin.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh
source ~/.zsh/zsh-z/zsh-z.plugin.zsh

# Autocompletion
zstyle ':completion:*' menu select matcher-list 'm:{a-z}={A-Za-z}'
bindkey '^[[Z' reverse-menu-complete
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search # Up
bindkey "^[[B" down-line-or-beginning-search # Down
autoload -U compinit; compinit

# Rust
source "$HOME/.cargo/env"

# Init Starship prompt
eval "$(starship init zsh)"
