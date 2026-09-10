# shellcheck shell=bash
# ~/.bashrc

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# -----------------------------------------------------------
# 1. HISTORY & DEFAULTS
# -----------------------------------------------------------
shopt -s histappend
shopt -s checkwinsize
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000

alias grep='grep --color=auto'

# -----------------------------------------------------------
# 2. NAVIGATION SHORTHANDS
# -----------------------------------------------------------
if [[ ${OSTYPE:-} == darwin* ]]; then
    alias ls='ls -G'
else
    alias ls='ls --color=auto'
fi
alias ll='ls -l'
alias la='ls -A'
alias lla='ls -lA'
alias l='ls -CF'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# -----------------------------------------------------------
# 3. HUMAN-FRIENDLY FILE OPS
# -----------------------------------------------------------

# -- FINDING STUFF --
alias search='grep -rnI --exclude-dir={.git,.roo,node_modules,target,dist} .'
function f() { find . -type f -iname "*$1*"; }

# -- COUNTING LINES --
function loc() {
    if command -v tokei &> /dev/null; then
        tokei "$@"
    else
        # Fallback: Count lines in non-binary files, ignoring git/node_modules
        # 1. Find files (skipping common junk folders)
        # 2. Filter out likely binary extensions/files
        # 3. Count lines
        find . -type f \
            -not -path '*/.*' \
            -not -path '*/node_modules/*' \
            -not -path '*/target/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -exec env grep -Iq . {} \; -print0 | xargs -0 wc -l | tail -n 1
    fi
}

# -- CREATING STUFF --
alias mk='mkdir -p'
function new() { mkdir -p "$(dirname "$1")" && touch "$1"; echo "✨ Created: $1"; }

# -- MOVING & COPYING --
alias copy='cp -iv'
alias move='mv -iv'
alias del='rm -I'

# -- CLIPBOARD & LOGGING (New!) --

# 1. LOGRUN: Runs a command and saves output to a file automatically
# Usage: logrun make build
# Usage: logrun python script.py
function logrun() {
    # Create logs folder if it doesn't exist
    mkdir -p logs
    
    # Create a safe filename: logs/YYYY-MM-DD_command-name.log
    local cmd_name=${1//[^a-zA-Z0-9]/_}
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H-%M-%S) || return
    local logfile="logs/${timestamp}_${cmd_name}.log"
    
    echo "📝 Logging output to: $logfile"
    echo "---------------------------------------------------"
    
    # Run command | capture stderr | display on screen AND write to file
    "$@" 2>&1 | tee "$logfile"
}

# 2. WCOPY: Copy output directly to Windows Clipboard (WSL specific)
# Usage: cat file.txt | wcopy
# Usage: echo "some api key" | wcopy
alias wcopy='clip.exe'

# -----------------------------------------------------------
# 4. GIT SHORTCUTS
# -----------------------------------------------------------
alias gs='git status'
# GIT WRAPPER: Auto-maps master -> main if master is missing
function git() {
    # 1. If command is not a checkout/switch/pull/push/merge/rebase/branch/diff, just run git
    if [[ "$1" != "checkout" && "$1" != "co" && "$1" != "switch" && "$1" != "pull" && "$1" != "push" && "$1" != "merge" && "$1" != "rebase" && "$1" != "branch" && "$1" != "diff" ]]; then
        command git "$@"
        return $?
    fi

    # 2. Check if we are trying to use 'master'
    local args=("$@")
    local has_master=false
    for arg in "${args[@]}"; do
        if [[ "$arg" == "master" ]]; then
            has_master=true
            break
        fi
    done

    # 3. If no 'master' arg, just run git
    if [[ "$has_master" == "false" ]]; then
        command git "$@"
        return $?
    fi

    # 4. Check if 'master' branch actually exists
    # We use verify to check local packed/loose refs
    if command git rev-parse --verify master >/dev/null 2>&1 || \
       command git rev-parse --verify remotes/origin/master >/dev/null 2>&1; then
        # Master exists, so respect the user's wish
        command git "$@"
        return $?
    fi

    # 5. Master does NOT exist. Check if 'main' exists
    if command git rev-parse --verify main >/dev/null 2>&1 || \
       command git rev-parse --verify remotes/origin/main >/dev/null 2>&1; then
        # 6. Replace 'master' with 'main' in the args
        local new_args=()
        for arg in "${args[@]}"; do
            if [[ "$arg" == "master" ]]; then
                new_args+=("main")
            else
                new_args+=("$arg")
            fi
        done
        
        echo "💡 'master' branch not found. Assuming you meant 'main'..."
        command git "${new_args[@]}"
        return $?
    fi

    # 7. Neither exists (or both missing), let git handle the error
    command git "$@"
}

alias ga='git add'
alias gaa='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gl='git log --oneline --graph --decorate'
alias gsu='git submodule update --init --recursive'

# -----------------------------------------------------------
# 5. NIXOS & FLAKE HELPERS
# -----------------------------------------------------------
alias nixdev="nix develop '.?submodules=1'"
alias nixrun='nix run'
alias nsh='nix-shell -p'

alias nixlock='nix flake update'
alias nixup='nix flake lock --update-input'
alias nixcheck='nix flake check'
alias nixs='nix search nixpkgs'

alias rebuild='sudo nixos-rebuild switch'
alias nix-hist='nix-env --list-generations --profile /nix/var/nix/profiles/system'
alias nix-clean='sudo nix-collect-garbage -d && sudo nix-store --optimize'

# -----------------------------------------------------------
# 6. THE "NUCLEAR" GIT WIP ALIAS
# -----------------------------------------------------------
function git-nuke() {
    # 1. Check if git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Not a git repository. Aborting."
        return 1
    fi

    # Parse exclusion patterns
    local clean_args=("-fdx")
    for arg in "$@"; do
        clean_args+=("-e" "$arg")
    done

    # 2. Safety checklist: No Home, No Root
    if [[ "$PWD" == "$HOME" ]]; then
        echo "❌ DANGER: You are in your HOME directory. git-nuke is not allowed here."
        return 1
    fi
    if [[ "$PWD" == "/" ]]; then
        echo "❌ DANGER: You are in the ROOT directory. git-nuke is not allowed here."
        return 1
    fi
    # 3. Confirmation
    echo "☢️  NUKING REPOSITORY & SUBMODULES... ☢️"
    echo "Current directory: $PWD"
    echo "This will destroy all untracked files and reset everything to HEAD."
    if [ ${#@} -gt 0 ]; then
        echo "Excluding patterns: $*"
    fi
    read -p "Are you absolutely sure? (y/N) " -n 1 -r
    echo    # Move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        return 1
    fi
    echo "Step 1: Resetting main repo..."
    git reset --hard HEAD
    echo "Step 2: Cleaning untracked files..."
    git clean "${clean_args[@]}"
    echo "Step 3: Nuking submodules..."
    git submodule foreach --recursive git clean "${clean_args[@]}"
    git submodule foreach --recursive git reset --hard HEAD
    echo "Step 4: Pulling fresh code..."
    git pull
    echo "Step 5: Updating submodules..."
    git submodule update --init --recursive
    echo "✅ Repo is fresh and clean."
}
alias gwipe='git-nuke'

# -----------------------------------------------------------
# 7. STARSHIP INIT
# -----------------------------------------------------------
if [[ ${TERM:-dumb} != dumb ]] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

# 8. CONFIG HELPERS
# Quickly edit this file (the repo version, not the local loader)
alias bashconfig='code --wait "$PSYCHE_REPO_ROOT/bash/.bashrc" && bash "$PSYCHE_REPO_ROOT/scripts/install.sh" --components shell && source "$HOME/.bashrc"'
alias reload='source "$HOME/.bashrc"'

# Helper to remember aliases: 'aliases git' shows all git aliases
function aliases() {
    if [ -z "$1" ]; then
        alias
    else
        alias | grep --color=always "$1"
    fi
}

# Shared settings are copied beside this file by the installer.
PSYCHE_BASH_DIR="${BASH_SOURCE[0]%/*}"
PSYCHE_REPO_ROOT=${PSYCHE_REPO_ROOT:-${PSYCHE_BASH_DIR%/*}}
if [ -f "$PSYCHE_BASH_DIR/extras.bashrc" ]; then
    # shellcheck source=bash/extras.bashrc
    source "$PSYCHE_BASH_DIR/extras.bashrc"
fi
return 0
