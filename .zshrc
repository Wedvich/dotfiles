# Create or attach to tmux session if not already in one
if ! { [ "$TERM" = "screen" ] && [ -n "$TMUX" ]; } then
  tmux new -As0
fi

if [[ $(uname -r) == *WSL2* ]]; then
  source ~/.agent-bridge.sh
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
