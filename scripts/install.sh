#!/bin/bash

# Get the directory of the script
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# --- HELPER FUNCTIONS ---

log() { echo -e "🔹 $1"; }
success() { echo -e "✅ $1"; }
warn() { echo -e "⚠️  $1"; }
error() { echo -e "❌ $1"; }

# Check for package manager
get_pkg_manager() {
    if command -v apt-get >/dev/null; then echo "apt";
    elif command -v dnf >/dev/null; then echo "dnf";
    elif command -v pacman >/dev/null; then echo "pacman";
    elif command -v brew >/dev/null; then echo "brew";
    elif command -v nix-env >/dev/null; then echo "nix";
    else echo "unknown"; fi
}

install_pkg() {
    local pkg=$1
    local manager=$(get_pkg_manager)
    
    if command -v $pkg >/dev/null; then
        log "$pkg is already installed."
        return
    fi

    echo "📦 Installing $pkg..."
    case $manager in
        apt) sudo apt-get install -y $pkg ;;
        dnf) sudo dnf install -y $pkg ;;
        pacman) sudo pacman -S --noconfirm $pkg ;;
        brew) brew install $pkg ;;
        nix) 
            # Handle package name mapping for Nix
            if [ "$pkg" == "fd-find" ]; then pkg="fd"; fi
            
            # Modern Nix (Fast)
            if nix profile install nixpkgs#$pkg 2>/dev/null; then
                success "Installed $pkg via nix profile"
            else
                 warn "Could not install $pkg via 'nix profile'. Skipping legacy install to save time."
            fi
            ;;
        *) warn "Could not install $pkg. Please install it manually." ;;
    esac
}

# --- INSTALLATION MAIN ---

echo "🚀 Setting up Pysche Environment..."

# 1. Install Dependencies
PKG_MANAGER=$(get_pkg_manager)
echo "Detected Package Manager: $PKG_MANAGER"

# List of tools to install
# eza: modern ls, zoxide: smart cd, direnv: auto-env, lazygit: git ui, btop: monitor
# delta: better git diffs, tldr: cheat sheets, jq: json processor
# hyperfine: benchmarking, tokei: code stats, ncdu: disk usage, entr: file watcher
# procs: better ps, dust: better du, xsv: csv toolkit, glow: markdown viewer
TOOLS="git tmux curl ripgrep fd-find bat eza fzf zoxide direnv lazygit btop jq tldr delta hyperfine tokei ncdu entr xsv procs dust glow" 

if [ "$PKG_MANAGER" != "unknown" ]; then
    log "Installing core tools..."
    
    # Update first if apt
    if [ "$PKG_MANAGER" == "apt" ]; then
        sudo apt-get update
    fi

    for tool in $TOOLS; do
        # Ubuntu specific overrides
        if [ "$PKG_MANAGER" == "apt" ]; then
             if [ "$tool" == "eza" ]; then continue; fi 
             if [ "$tool" == "fd-find" ]; then install_pkg fd-find; continue; fi
             if [ "$tool" == "bat" ]; then install_pkg bat; continue; fi
             if [ "$tool" == "delta" ]; then install_pkg git-delta; continue; fi # apt calls it git-delta
        fi
        
        install_pkg $tool
    done
else
    warn "No supported package manager found. Skipping dependency installation."
fi

# 2. Install Starship (Cross-platform script)
if ! command -v starship >/dev/null; then
    log "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
else
    log "Starship is already installed."
fi

# 3. Handle Ubuntu/Debian 'batcat' -> 'bat' mapping
if command -v batcat >/dev/null && ! command -v bat >/dev/null; then
    log "Aliasing batcat -> bat"
    mkdir -p ~/.local/bin
    ln -s /usr/bin/batcat ~/.local/bin/bat
    export PATH=$HOME/.local/bin:$PATH
fi

# 4. Perform Symlinks
echo "🔗 Linking Configuration Files..."

create_link() {
    local src=$1
    local dest=$2
    
    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ]; then
        log "$dest is already a link (skipping)"
    elif [ -f "$dest" ]; then
        warn "Backup created for existing $dest"
        mv "$dest" "${dest}.backup"
        ln -s "$src" "$dest"
        success "Linked $dest"
    else
        ln -s "$src" "$dest"
        success "Linked $dest"
    fi
}

# Bash
create_link "$DOTFILES_DIR/bash/.bashrc" "$HOME/.bashrc"

# Starship
create_link "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"

# Git
create_link "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
create_link "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"

# Tmux
create_link "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

echo "🎉 Done! please restart your shell or run 'source ~/.bashrc'"
