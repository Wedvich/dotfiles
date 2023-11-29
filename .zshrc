# Create or attach to tmux session if not already in one
if ! { [[ "$TERM" == "screen"* ]] && [ -n "$TMUX" ]; } then
  tmux new -As0
fi

if [[ $(uname -r) == *WSL2* ]]; then
  source ~/.agent-bridge.sh
  init-1pw() {
    echo "removing previous socket..."
    rm $SSH_AUTH_SOCK
    echo "Starting SSH-Agent relay..."
    (setsid socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
  }
fi

# Autocompletion
zstyle ':completion:*' menu select matcher-list 'm:{a-z}={A-Za-z}'
bindkey '^[[Z' reverse-menu-complete

# Plugins
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source ~/.zsh/zsh-nvm/zsh-nvm.plugin.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

# Init Starship prompt
eval "$(starship init zsh)"
