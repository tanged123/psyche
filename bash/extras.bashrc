# .bashrc additions for Pysche

# 1. FZF Setup (Fuzzy Finder)
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
    
    # Use fd instead of find (faster, ignores .git)
    export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# 2. Modern Replacements
if command -v eza >/dev/null 2>&1; then
    alias ls='eza'
    alias ll='eza -l --git'
    alias la='eza -la --git'
    alias tree='eza --tree'
fi

if command -v bat >/dev/null 2>&1; then
    alias cat='bat --style=plain'
fi

# 3. Direnv (Auto-loads environment)
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi

# 4. Zoxide (Smarter cd)
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
    alias cd='z'
fi

# 5. Lazygit
if command -v lazygit >/dev/null 2>&1; then
    alias lg='lazygit'
fi

# 6. Modern Replacements (ps, du)
if command -v procs >/dev/null 2>&1; then
    alias ps='procs'
fi

if command -v dust >/dev/null 2>&1; then
    alias du='dust'
fi

# 7. Productivity Aliases
if command -v hyperfine >/dev/null 2>&1; then
    alias bench='hyperfine --warmup 3'
fi



if command -v ncdu >/dev/null 2>&1; then
    alias diskuse='ncdu'
fi

if command -v glow >/dev/null 2>&1; then
    alias md='glow'
fi

# 8. Entr (file watcher) convenience function
# Usage: watch-run "*.cpp" make
if command -v entr >/dev/null 2>&1; then
    watch-run() {
        find . -name "$1" | entr -c "${@:2}"
    }
fi
