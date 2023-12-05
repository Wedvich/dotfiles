local zsh_history_size=10000

export EDITOR="code"
export VISUAL="code"
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=$zsh_history_size
export NVM_AUTO_USE=true
export SAVEHIST=$zsh_history_size
export STARSHIP_CONFIG="$HOME/starship.toml"

skip_global_compinit=1
