[[ -o interactive ]] || return 0
[[ ${PSYCHE_ZSH_LOADED:-} == 1 ]] && return 0
PSYCHE_ZSH_LOADED=1

setopt APPEND_HISTORY HIST_IGNORE_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY
HISTSIZE=20000
SAVEHIST=40000
HISTFILE=${HISTFILE:-$HOME/.zsh_history}
alias ll='ls -l'
alias la='ls -A'
alias ..='cd ..'
autoload -Uz compinit
compinit

if [[ ${TERM:-dumb} != dumb ]] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook zsh)"
fi
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi
if command -v fzf >/dev/null 2>&1; then
    if _psyche_fzf=$(fzf --zsh 2>/dev/null); then
        eval "$_psyche_fzf"
    fi
    unset _psyche_fzf
fi
return 0
