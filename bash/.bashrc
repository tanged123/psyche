# shellcheck shell=bash
# Sourced by ~/.bashrc; keep noninteractive commands untouched.
[[ $- == *i* ]] || return 0
[[ ${PSYCHE_BASH_LOADED:-} == 1 ]] && return 0
PSYCHE_BASH_LOADED=1

shopt -s histappend checkwinsize
HISTCONTROL=ignoreboth
HISTSIZE=20000
HISTFILESIZE=40000
alias ll='ls -l'
alias la='ls -A'
alias ..='cd ..'

if [[ ${TERM:-dumb} != dumb ]] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi
# Older distro packages lack --bash; fzf itself still works.
if command -v fzf >/dev/null 2>&1; then
    if _psyche_fzf=$(fzf --bash 2>/dev/null); then
        eval "$_psyche_fzf"
    fi
    unset _psyche_fzf
fi
return 0
