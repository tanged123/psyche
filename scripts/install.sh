#!/usr/bin/env bash
set -euo pipefail
case $(uname -s) in
    Linux|Darwin) ;;
    *) printf '%s\n' 'Use scripts/install.ps1 on native Windows; this entry point supports Linux/WSL and macOS.' >&2; exit 1 ;;
esac
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))'; then
    if command -v nix >/dev/null 2>&1; then
        exec nix --extra-experimental-features 'nix-command flakes' shell "path:$root#python3" \
            --command python3 "$root/scripts/install.py" "$@"
    fi
    printf '%s\n' 'Python 3.9+ or Nix is required. Install python3 with your package manager.' >&2
    exit 1
fi
exec python3 "$root/scripts/install.py" "$@"
