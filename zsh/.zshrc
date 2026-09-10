# ~/.zshrc - Pysche Zsh Config

# If not running interactively, don't do anything
[[ ! -o interactive ]] && return

# -----------------------------------------------------------
# 1. HISTORY & DEFAULTS
# -----------------------------------------------------------
setopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
HISTSIZE=10000
SAVEHIST=20000
HISTFILE=~/.zsh_history

alias grep='grep --color=auto'

# -----------------------------------------------------------
# 2. NAVIGATION SHORTHANDS
# -----------------------------------------------------------
# Use -G for color on macOS, --color=auto on Linux
if [[ "$(uname)" == "Darwin" ]]; then
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
        find . -type f \
            -not -path '*/.*' \
            -not -path '*/node_modules/*' \
            -not -path '*/target/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -exec grep -Iq . {} \; -print0 | xargs -0 wc -l | tail -n 1
    fi
}

# -- CREATING STUFF --
alias mk='mkdir -p'
function new() { mkdir -p "$(dirname "$1")" && touch "$1"; echo "Created: $1"; }

# -- MOVING & COPYING --
alias copy='cp -iv'
alias move='mv -iv'
alias del='rm -I'

# -- CLIPBOARD & LOGGING --

# LOGRUN: Runs a command and saves output to a file
function logrun() {
    mkdir -p logs
    local cmd_name=$(echo "$1" | sed 's/[^a-zA-Z0-9]/_/g')
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local logfile="logs/${timestamp}_${cmd_name}.log"

    echo "Logging output to: $logfile"
    echo "---------------------------------------------------"
    "$@" 2>&1 | tee "$logfile"
}

# macOS clipboard
if [[ "$(uname)" == "Darwin" ]]; then
    alias clip='pbcopy'
else
    alias wcopy='clip.exe'
fi

# -----------------------------------------------------------
# 4. GIT SHORTCUTS
# -----------------------------------------------------------
alias gs='git status'

# GIT WRAPPER: Auto-maps master -> main if master is missing
function git() {
    if [[ "$1" != "checkout" && "$1" != "co" && "$1" != "switch" && "$1" != "pull" && "$1" != "push" && "$1" != "merge" && "$1" != "rebase" && "$1" != "branch" && "$1" != "diff" ]]; then
        command git "$@"
        return $?
    fi

    local args=("$@")
    local has_master=false
    for arg in "${args[@]}"; do
        if [[ "$arg" == "master" ]]; then
            has_master=true
            break
        fi
    done

    if [[ "$has_master" == "false" ]]; then
        command git "$@"
        return $?
    fi

    if command git rev-parse --verify master >/dev/null 2>&1 || \
       command git rev-parse --verify remotes/origin/master >/dev/null 2>&1; then
        command git "$@"
        return $?
    fi

    if command git rev-parse --verify main >/dev/null 2>&1 || \
       command git rev-parse --verify remotes/origin/main >/dev/null 2>&1; then
        local new_args=()
        for arg in "${args[@]}"; do
            if [[ "$arg" == "master" ]]; then
                new_args+=("main")
            else
                new_args+=("$arg")
            fi
        done

        echo "'master' branch not found. Assuming you meant 'main'..."
        command git "${new_args[@]}"
        return $?
    fi

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
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not a git repository. Aborting."
        return 1
    fi

    local clean_args=("-fdx")
    for arg in "$@"; do
        clean_args+=("-e" "$arg")
    done

    if [[ "$PWD" == "$HOME" ]]; then
        echo "DANGER: You are in your HOME directory. git-nuke is not allowed here."
        return 1
    fi
    if [[ "$PWD" == "/" ]]; then
        echo "DANGER: You are in the ROOT directory. git-nuke is not allowed here."
        return 1
    fi

    echo "NUKING REPOSITORY & SUBMODULES..."
    echo "Current directory: $PWD"
    echo "This will destroy all untracked files and reset everything to HEAD."
    if [ ${#@} -gt 0 ]; then
        echo "Excluding patterns: $@"
    fi
    read "REPLY?Are you absolutely sure? (y/N) "
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
    echo "Repo is fresh and clean."
}
alias gwipe='git-nuke'

# -----------------------------------------------------------
# 7. STARSHIP INIT
# -----------------------------------------------------------
if [[ ${TERM:-dumb} != dumb ]] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# 8. CONFIG HELPERS
alias zshconfig='code --wait "$PSYCHE_REPO_ROOT/zsh/.zshrc" && bash "$PSYCHE_REPO_ROOT/scripts/install.sh" --components shell && source "$HOME/.zshrc"'
alias reload='source "$HOME/.zshrc"'

function aliases() {
    if [ -z "$1" ]; then
        alias
    else
        alias | grep --color=always "$1"
    fi
}

# Shared settings are copied beside this file by the installer.
PSYCHE_ZSH_DIR="${0:A:h}"
PSYCHE_REPO_ROOT=${PSYCHE_REPO_ROOT:-${PSYCHE_ZSH_DIR%/*}}
if [ -f "$PSYCHE_ZSH_DIR/extras.zshrc" ]; then
    source "$PSYCHE_ZSH_DIR/extras.zshrc"
fi
return 0
