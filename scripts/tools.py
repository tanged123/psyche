#!/usr/bin/env python3
"""Install explicitly selected tools through one package manager."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
# Commands and package identifiers differ. Never probe using the package name.
PACKAGES = {
    'git': {'command': 'git', 'winget': 'Git.Git'},
    'ripgrep': {'command': 'rg', 'winget': 'BurntSushi.ripgrep.MSVC'},
    'starship': {'command': 'starship', 'winget': 'Starship.Starship'},
    'fzf': {'command': 'fzf', 'winget': 'junegunn.fzf'},
    'jq': {'command': 'jq', 'winget': 'jqlang.jq'},
    'zoxide': {'command': 'zoxide', 'winget': 'ajeetdsouza.zoxide'},
    'direnv': {'command': 'direnv', 'winget': None},
    'tmux': {'command': 'tmux', 'winget': None},
    'ghostty': {'command': 'ghostty', 'winget': None, 'dnf': None},
}
MANAGERS = ['apt', 'dnf', 'pacman', 'brew', 'nix', 'winget']
BINARIES = {'apt': 'apt-get', **{name: name for name in MANAGERS if name != 'apt'}}


def detect_manager():
    if os.name == 'nt':
        candidates = ['winget']
    elif platform.system() == 'Darwin':
        candidates = ['brew', 'nix']
    elif Path('/etc/NIXOS').exists():
        candidates = ['nix']
    else:
        candidates = ['apt', 'dnf', 'pacman', 'brew', 'nix']
    return next((name for name in candidates if shutil.which(BINARIES[name])), None)


def package_command(manager, name):
    package = PACKAGES[name].get(manager, name)
    if package is None:
        raise ValueError(f'{name} is not supported by this {manager} installer; see README for platform options')
    if name == 'ghostty':
        if manager == 'brew':
            if platform.system() != 'Darwin':
                raise ValueError('the Ghostty Homebrew cask requires macOS')
            return ['brew', 'install', '--cask', 'ghostty']
        if manager == 'nix' and platform.system() != 'Linux':
            raise ValueError('the pinned Ghostty package targets Linux; use Homebrew on macOS')
    if manager == 'nix':
        # Resolve the same locked nixpkgs input as the development shell.
        return ['nix', '--extra-experimental-features', 'nix-command flakes',
                'profile', 'install', f'path:{ROOT}#{name}']
    if manager == 'winget':
        return ['winget', 'install', '--id', package, '--exact', '--source', 'winget',
                '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity']
    return {
        'apt': ['apt-get', 'install', '-y', package],
        'dnf': ['dnf', 'install', '-y', package],
        'pacman': ['pacman', '-S', '--needed', '--noconfirm', package],
        'brew': ['brew', 'install', package],
    }[manager]


def installed(name):
    if shutil.which(PACKAGES[name]['command']):
        return True
    # A macOS app need not expose its executable on PATH.
    return name == 'ghostty' and platform.system() == 'Darwin' and any(
        path.is_dir() for path in [Path('/Applications/Ghostty.app'), Path.home() / 'Applications/Ghostty.app'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tools', nargs='*', metavar='TOOL', help=', '.join(PACKAGES))
    parser.add_argument('--manager', choices=MANAGERS)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    args.tools = args.tools or ['git', 'ripgrep', 'starship']
    unknown = set(args.tools) - PACKAGES.keys()
    if unknown:
        parser.error('unknown tools: ' + ', '.join(sorted(unknown)))
    manager = args.manager or detect_manager()
    if not manager:
        parser.error('no supported package manager found; configure settings without installing tools')
    if os.name == 'nt' and manager != 'winget':
        parser.error('native Windows uses winget; use Linux/WSL for Unix package managers')
    try:
        # Validate the entire request before running a package manager.
        commands = [(name, package_command(manager, name)) for name in dict.fromkeys(args.tools)]
        missing = [(name, cmd) for name, cmd in commands if not installed(name)]
        if not missing:
            print('Requested tools are already on PATH.')
            return 0
        prefix = []
        if manager in ('apt', 'dnf', 'pacman') and os.geteuid() != 0:
            prefix = ['sudo']
            if not args.dry_run and not shutil.which('sudo'):
                raise ValueError('sudo is unavailable; ask the machine administrator to install these tools')
        if not args.dry_run and not shutil.which(BINARIES[manager]):
            raise ValueError(f'{BINARIES[manager]} is not installed')
        if manager == 'apt':
            print('Run: ' + subprocess.list2cmdline(prefix + ['apt-get', 'update']))
            if not args.dry_run:
                subprocess.run(prefix + ['apt-get', 'update'], check=True)
        for name, command in missing:
            command = prefix + command
            print('Run: ' + subprocess.list2cmdline(command), flush=True)
            if not args.dry_run:
                subprocess.run(command, check=True)
                if manager != 'winget' and not installed(name):
                    raise ValueError(f'{name}: installation returned success but {PACKAGES[name]["command"]} is not on PATH')
        if not args.dry_run and manager == 'winget':
            print('Open a new terminal to pick up installed tools on PATH.')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'psyche: {error}', file=sys.stderr)
        print('Package availability depends on the OS release. No fallback installer was run.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
