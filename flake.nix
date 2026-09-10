{
  description = "Psyche portable settings and installer tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        core = with pkgs; [ git ripgrep starship ];
        extras = with pkgs; [ fzf jq zoxide direnv tmux ];
      in {
        packages = {
          default = pkgs.buildEnv { name = "psyche-core"; paths = core; };
          extras = pkgs.buildEnv { name = "psyche-extras"; paths = extras; };
          inherit (pkgs) python3 git ripgrep starship fzf jq zoxide direnv tmux;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux { inherit (pkgs) ghostty; };
        devShells.default = pkgs.mkShell {
          packages = core ++ (with pkgs; [ python3 shellcheck zsh bashInteractive ]);
        };
      });
}
