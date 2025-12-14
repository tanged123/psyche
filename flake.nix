{
  description = "Pysche Developer Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core Tools
            git
            tmux
            starship
            bashInteractive
            
            # Superpowers
            fzf      # Fuzzy finder
            ripgrep  # Better grep
            bat      # Better cat
            eza      # Better ls
            fd       # Better find
            jq       # JSON processor
            delta    # Better git diffs
            
            # Navigation & Git
            zoxide   # Smarter cd
            lazygit  # Git TUI
            
            # Monitoring & Analysis
            btop     # System monitor
            ncdu     # Disk usage analyzer
            procs    # Better ps
            dust     # Better du
            
            # Productivity
            tldr     # Simplified man pages
            hyperfine # Benchmarking
            tokei    # Code statistics
            entr     # Run on file change
            xsv      # CSV toolkit
            glow     # Markdown renderer
            
            # Shell integration
            direnv
          ];

          shellHook = ''
            # Initialize Starship
            eval "$(starship init bash)"
            
            # Initialize Direnv hook
            eval "$(direnv hook bash)"

            echo "🚀 Pysche Dev Environment Loaded!"
            echo "   - Tmux, Starship, Fzf, Ripgrep, Bat, Eza ready."
          '';
        };
      }
    );
}
