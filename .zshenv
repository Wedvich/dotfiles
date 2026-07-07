local zsh_history_size=10000

export EDITOR="code"
export VISUAL="code"
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=$zsh_history_size
export SAVEHIST=$zsh_history_size
export STARSHIP_CONFIG="$HOME/starship.toml"
export NODE_COMPILE_CACHE="$HOME/.cache/nodejs-compile-cache"
export MISE_NODE_COREPACK=true
export COLORTERM=truecolor

# Prepend ~/.local/bin. Guard instead of `typeset -U` because setup.sh sources
# this file inside a function, where `typeset` would shadow path with an empty local.
(( ${path[(I)$HOME/.local/bin]} )) || path=("$HOME/.local/bin" $path)

skip_global_compinit=1
fpath+="$HOME/.zfunc"
