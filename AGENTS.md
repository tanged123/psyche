# Psyche

Read [ai/preferences.md](ai/preferences.md) for the shared personal defaults.
This repo owns portable shell, Git, prompt and AI preferences, not machine secrets
or project toolchains. Keep package installation separate from configuration.

Use `python3 scripts/test.py` for installer behavior and shell smoke tests.
Use `shellcheck scripts/*.sh bash/.bashrc bash/extras.bashrc` when available. CI additionally runs
the same suite on native Windows and checks PowerShell and Zsh startup.
Test installation against temporary homes, never the real home directory unless
applying a tested installation explicitly within the user's requested setup.
Preserve Starship's decorative symbols and enabled Git diff counts; these are
intentional user preferences. Keep Bash on Linux, Zsh on macOS and PowerShell on
Windows usable without a shell framework. Ghostty is a terminal, not a shell.
Preserve all existing macros and shorthands, including navigation, Git, Nix,
utility and optional-tool aliases. The user actively uses them. Do not remove or
rename them as cleanup. Keep installation improvements separate from shell habits.
