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

# 4. Configure Dotfiles (Smart Merge)
echo "🔗 Configuring Dotfiles..."

# Helper: Smart Symlink (Backs up if exists)
link_file() {
    local src=$1
    local dest=$2

    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ]; then
        # Check if it already points to the right place
        local current_target=$(readlink -f "$dest")
        if [ "$current_target" == "$src" ]; then
             log "$dest is already correctly linked."
             return
        fi
        # Correcting link
        log "Updating link for $dest"
        rm "$dest"
        ln -s "$src" "$dest"
        success "Linked $dest -> $src"
    elif [ -f "$dest" ]; then
        warn "Backup created for existing $dest"
        mv "$dest" "${dest}.backup.$(date +%s)"
        ln -s "$src" "$dest"
        success "Linked $dest -> $src"
    else
        ln -s "$src" "$dest"
        success "Linked $dest -> $src"
    fi
}

# Helper: Append source if not present
append_source() {
    local file=$1
    local line=$2
    local comment=$3
    
    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -Fq "$line" "$file"; then
        log "$file already includes config."
    else
        echo "" >> "$file"
        echo "$comment" >> "$file"
        echo "$line" >> "$file"
        success "Updated $file"
    fi
}

# Helper: Git Config Merge (Prepend include)
configure_git() {
    local src=$1
    local config_file="$HOME/.gitconfig"
    
    # Handle symlink case: if it's a symlink, we want to replace it with a real file that INCLUDES the source,
    # rather than BE the source. This allows local overrides.
    if [ -L "$config_file" ]; then
        warn "Detected existing symlink for .gitconfig. Replacing with standard config that includes the repo file."
        local link_target=$(readlink -f "$config_file")
        if [ "$link_target" == "$src" ]; then
            # It was just our simple link. Safe to remove.
            rm "$config_file"
            touch "$config_file"
            log "Removed symlink to repo."
        else
            # It was a link to somewhere else. We should probably back it up.
            mv "$config_file" "${config_file}.backup.$(date +%s)"
            touch "$config_file"
            warn "Backed up prior symlink."
        fi
    fi

    if [ ! -f "$config_file" ]; then
        touch "$config_file"
    fi
    
    # Check if already included
    if grep -q "path = $src" "$config_file"; then
        log "Git config already includes pysche config."
        return
    fi
    
    # Prepend include to ensure local settings (at bottom) override global defaults (at top)
    echo "Prepending include to $config_file..."
    
    # Create temp file
    echo "[include]" > "${config_file}.tmp"
    echo "    path = $src" >> "${config_file}.tmp"
    echo "" >> "${config_file}.tmp" 
    cat "$config_file" >> "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"
    
    success "Added include to start of .gitconfig"
}

# Helper: Configure Bash (Smart Merge & Symlink Handle)
configure_bash() {
    local src="$DOTFILES_DIR/bash/.bashrc"
    local dest="$HOME/.bashrc"
    
    # Handle symlink case: .bashrc should NOT be a symlink if we want to support local configs + repo configs
    if [ -L "$dest" ]; then
        warn "Detected existing symlink for .bashrc. Replacing with standard file that sources the repo file."
        local link_target=$(readlink -f "$dest")
        if [ "$link_target" == "$src" ]; then
            rm "$dest"
            touch "$dest"
            log "Removed symlink to repo."
        else
            mv "$dest" "${dest}.backup.$(date +%s)"
            touch "$dest"
            warn "Backed up prior symlink."
        fi
    fi

    append_source "$dest" "source $src" "# Pysche Tools"
}

# Bash
configure_bash

# Starship (Config file usually needs to be at a specific path, symlinking is best)
link_file "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"

# Git
configure_git "$DOTFILES_DIR/git/.gitconfig"
link_file "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"

# Git Identity Setup
echo ""
echo "🔐 Git Identity Setup"
echo "---------------------"

# Check if already configured
CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -n "$CURRENT_NAME" ] && [ -n "$CURRENT_EMAIL" ]; then
    log "Git identity already configured:"
    echo "   Name:  $CURRENT_NAME"
    echo "   Email: $CURRENT_EMAIL"
    read -p "Do you want to change it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Keeping existing git identity."
    else
        CURRENT_NAME=""
        CURRENT_EMAIL=""
    fi
fi

if [ -z "$CURRENT_NAME" ] || [ -z "$CURRENT_EMAIL" ]; then
    read -p "Enter your name for git commits: " GIT_NAME
    read -p "Enter your email for git commits: " GIT_EMAIL
    
    if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
        git config --global user.name "$GIT_NAME"
        git config --global user.email "$GIT_EMAIL"
        success "Git identity configured: $GIT_NAME <$GIT_EMAIL>"
    else
        warn "Skipped git identity setup. You can set it later with:"
        echo "   git config --global user.name 'Your Name'"
        echo "   git config --global user.email 'you@example.com'"
    fi
fi

# Tmux
append_source "$HOME/.tmux.conf" "source-file $DOTFILES_DIR/tmux/.tmux.conf" "# Pysche Tmux"

echo "🎉 Done! please restart your shell or run 'source ~/.bashrc'"
