# Psyche

Personal shell, Git, prompt and AI preferences for Linux, WSL, macOS and Windows.
Keep the useful defaults small; let individual projects own their toolchains.

## Install settings

Clone `https://github.com/tanged123/psyche.git`, then run from the checkout:

| Platform | Entry point | Prerequisite |
| --- | --- | --- |
| Linux / WSL / macOS | `bash scripts/install.sh` | Python 3.9+ or Nix |
| Native Windows | `powershell -NoProfile -File scripts/install.ps1` | Python 3.9+ |
| PowerShell 7 | `pwsh -NoProfile -File scripts/install.ps1` | Python 3.9+ |

Start with `--dry-run` to see paths without changing anything. Installation is
noninteractive and needs no administrator access. It installs **configuration
only**; it does not install packages, fonts, AI clients, credentials or plugins.

The Unix entry point detects Linux/macOS and uses Python on `PATH`, or this repo's
locked Nix Python package when only Nix is available. Nix may download Python
on first use; an existing Python installation needs no network.
To use Nix explicitly, from the checkout:

```sh
nix --extra-experimental-features 'nix-command flakes' shell .#python3 --command python3 scripts/install.py
nix shell .#python3 --command python3 scripts/tools.py --manager nix
```

On a fresh machine without either runtime, install Python through the OS package
manager, [python.org](https://www.python.org/downloads/), or use an existing Nix
installation. On Windows, install Python with the launcher and open a new terminal;
`install.ps1` supports `python3`, `python` and `py -3`. Nix supports this workflow
on Linux/macOS and inside WSL; native Windows uses Python directly.

PowerShell uses the current host's `$PROFILE.CurrentUserAllHosts`, including
redirected Documents/OneDrive folders. Run the entry point once with each host
(Windows PowerShell and/or PowerShell 7) you use. If local policy blocks scripts,
use the Python entry directly from that host; the installer doesn't change policy:

```powershell
py -3 scripts/install.py --powershell-profile $PROFILE.CurrentUserAllHosts
```

Open a **new terminal** after installation. Existing shells retain old aliases and
functions until restarted. Rerun the installer after pulling changes: deployed
settings are copies, so moving the checkout won't break shell startup.

## What's included

- **Starship:** the familiar decorative symbols, Git diff counts, commit hash and
  Nix context, plus elapsed time for commands taking over two seconds. Choose a
  terminal font with the desired glyph coverage.
- **Ghostty on Unix:** an opaque dark background, readable text, modest padding
  and a steady cursor. Existing local terminal settings override these defaults.
- **Bash / Zsh:** history settings and all original navigation, Git, Nix and utility shortcuts,
  and guarded integration
  for Starship, direnv, zoxide and supported fzf shell bindings. Zsh completion is
  enabled. Older fzf packages remain usable as standalone commands.
- **PowerShell:** history search on arrow keys, plus Starship and zoxide when present.
- **Git:** `main` for new repos, prune deleted remote refs on fetch, fast-forward-only
  pulls, `zdiff3` conflicts and the original Git aliases. A diverged pull stops for an explicit
  merge/rebase decision. Identity, editor, pager and line endings remain local.
- **Tmux on Unix:** the existing mouse support, `Ctrl-a` prefix and pane bindings.
- **AI:** the same [personal preferences](ai/preferences.md) deployed to Codex and
  Claude Code's native user instruction files.

All original shell macros and shorthands are preserved, including `search`, `f`,
`loc`, `mk`, `new`, `copy`, `move`, `del`, `logrun`, the navigation aliases, Nix
helpers, `aliases`, `reload`, `bashconfig`/`zshconfig`, and `git-nuke`/`gwipe`.
The repository-wipe helper retains its confirmation prompt. The original Git
wrapper also retains its `master` to `main` mapping when only `main` exists.

Optional-tool shortcuts and replacements return when their tools are installed:
`lg`, `bench`, `diskuse`, `md`, `watch-run`, eza's listing aliases, bat's `cat`,
zoxide's `cd`, procs' `ps` and dust's `du`. They are not mandatory packages.
`bashconfig`/`zshconfig` edit this checkout in VS Code, reinstall shell settings
when the editor closes, and reload the shell. Keep the checkout at the installed
path for those editing helpers; rerun installation after moving it.

Git shortcuts in Bash and Zsh:

| Shortcut | Command |
| --- | --- |
| `gs` | `git status` |
| `ga` / `gaa` | `git add` / `git add .` |
| `gc "message"` | `git commit -m "message"` |
| `gp` / `gpl` | `git push` / `git pull` |
| `gd` / `gco` | `git diff` / `git checkout` |
| `gl` | `git log --oneline --graph --decorate` |
| `gsu` | `git submodule update --init --recursive` |

Native Git aliases work in every shell: `git s`, `git co`, `git c`, `git a`,
`git b`, `git p` and `git l`. After pulling updates, rerun the installer and open
a new terminal to refresh aliases.

## Optional packages

Core tools are **Git, ripgrep, Starship**. Install only what you want:

```sh
python3 scripts/tools.py --dry-run                 # plan missing core tools
python3 scripts/tools.py                          # install missing core tools
python3 scripts/tools.py fzf jq zoxide             # explicit extras
python3 scripts/tools.py direnv tmux              # Unix only
python3 scripts/tools.py --manager brew           # macOS with Homebrew
python3 scripts/tools.py --manager nix            # pinned Nix packages
python3 scripts/tools.py ghostty --manager brew   # macOS app, installed as a cask
python3 scripts/tools.py ghostty --manager nix    # Linux GUI, separate from core
```

On native Windows use `py -3 scripts/tools.py --manager winget` (or `python` if
that's how Python is installed). WinGet uses exact package IDs. It may request
OS elevation for individual packages; reopen the terminal afterward for PATH changes.

Automatic manager selection uses WinGet on Windows, Homebrew then Nix on macOS,
Nix on NixOS, and apt/dnf/pacman/Homebrew/Nix elsewhere. `--manager` makes selection
explicit. apt refreshes metadata; other managers use their existing repositories.
The script checks executable names (`rg`, not `ripgrep`), skips installed tools,
stops on failure and never falls back to a remote shell installer.

Package availability and versions depend on the OS release. In particular,
[Starship's package guide](https://starship.rs/guide/#step-1-install-starship) lists
apt support for Ubuntu 25.04+: older apt releases may need Nix or a separate
Starship installation. Configuration still works without Starship or any extras.
Use the locked Nix packages when matching versions across Unix machines matters:

```sh
nix profile install .#default   # Git, ripgrep, Starship
nix profile install .#extras    # fzf, jq, zoxide, direnv, tmux
```

The flake supports Linux and macOS on x86_64 and aarch64. The existing `flake.lock`
is retained. Changing its pins is an explicit maintenance task.

## Terminal and shell choices

Use **Ghostty with Bash on Linux or Zsh on macOS**, and **Windows Terminal with
PowerShell on native Windows**. Ghostty is the window hosting the shell; Starship
draws the prompt. Keep these independent so SSH, WSL, an editor terminal and a
desktop terminal share the same shell behavior. The installer doesn't change your
login shell or system default terminal.

The [Ghostty package guide](https://ghostty.org/docs/install/binary) documents
Linux/macOS support. Use the Homebrew cask on macOS and your distribution's package
on Linux when available. Ubuntu's official package starts at 26.04; older apt
releases may lack it. Fedora needs a separately configured community repository;
this installer doesn't add one. On NixOS the pinned Nix package works directly;
other Linux distributions may need graphics-driver integration such as nixGL.
Nix supplies Python on macOS too, but this lock's Ghostty output targets Linux.

Ghostty settings use `~/.config/ghostty/config`, or `config.ghostty` if that file
already exists. Both names are supported by current Ghostty. On macOS, a config
under `~/Library/Application Support/com.mitchellh.ghostty` can override the XDG
file. This [load order](https://ghostty.org/docs/config) lets existing machine
preferences remain authoritative. Install only these defaults with:

```sh
bash scripts/install.sh --components terminal
```

Your existing Starship layout and symbols remain intact, including `git_metrics`.
Diff counts deliberately cost more work on each prompt in large repositories;
they are a chosen preference. The only visual addition is the already-configured
`cmd_duration` module, which was previously missing from the prompt format.

## Local settings, migration and recovery

The installer copies shared shell/Git/tmux files into `~/.config/psyche` and adds
one marked block to each user config. Defaults precede existing settings, so local
overrides remain effective. Starship's config is copied to `~/.config/starship.toml`.
Known symlinks and source lines from the old `pysche` installer are migrated;
unrelated file symlinks are rejected with an actionable error.

Custom `XDG_CONFIG_HOME`, `ZDOTDIR`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR`,
`GIT_CONFIG_GLOBAL` and `STARSHIP_CONFIG` are respected. With `--home`, environment
path overrides are ignored, so a test install stays isolated. Explicit path flags
still work; on Windows an isolated shell install also needs `--powershell-profile`.

```sh
bash scripts/install.sh --components shell git prompt   # only shell/Git/prompt
bash scripts/install.sh --components ai                 # only personal AI rules
bash scripts/install.sh --home /tmp/psyche-demo --dry-run
bash scripts/install.sh --zsh-dir "$HOME/custom-zsh"
```

Every changed existing file is backed up before writing any configuration. Backup
sets live in `~/.local/state/psyche/backups/<timestamp-id>` and contain a manifest
mapping numbered copies to original paths. On Unix the backup directory is private;
on Windows it inherits the user's profile ACLs. Backups can contain private local
settings: keep them on the machine. Unchanged reruns create no backups.

```sh
bash scripts/install.sh --restore /path/to/backup-set --dry-run
bash scripts/install.sh --restore /path/to/backup-set
```

Restore recovers original bytes/symlinks and removes files first created in that
installation. It refuses the entire restore if any target has since changed;
recover those numbered backups manually after inspecting your local edits. Restore
successive installs in reverse order. A filesystem failure during installation may
leave only some files updated; use the saved manifest and numbered copies for
manual recovery. Package installations are separate and are not rolled back.
If restoring a backup from before the directory rename, recreate the old `pysche`
path as a link to `psyche` first: those original configs can reference the old path.

Keep secrets, machine PATH additions and identity outside this repository. Put
shell overrides below the managed block and Git overrides below the include.
Don't edit deployed copies; edit this checkout and rerun installation. Check the
dry run when migrating an older clone at a different path; automatic migration
recognizes the current checkout and its sibling named `pysche`.

## AI preferences

[ai/preferences.md](ai/preferences.md) is the source of personal beliefs, distilled
from Pantheon's and SignalScope's agent guidance. It covers concise speech/code,
small concrete implementations, explicit ownership, deterministic behavior,
restrained accessible UI, useful testing and autonomous work within authorization.
Project-specific languages, schemas, palettes and release rituals stay in projects.

The installer embeds that file in managed blocks in `~/.codex/AGENTS.md` and
`~/.claude/CLAUDE.md`, preserving existing instructions outside the block. These are
native user-level files documented by
[Codex](https://developers.openai.com/codex/guides/agents-md) and
[Claude Code](https://code.claude.com/docs/en/memory). Start a new agent session after
updating them. Codex's `AGENTS.override.md` takes precedence; the installer reports
its presence without changing it. Review existing personal instructions if they
conflict with the new defaults.

The repository's `AGENTS.md` points to the same preference source; `CLAUDE.md`
imports it. No model names, account state, approval bypasses, MCP connections or
provider configuration are synchronized. Other AI clients can use the preference
file as context, but are not claimed to load these native files automatically.

## Validation

```sh
python3 scripts/test.py
shellcheck scripts/*.sh bash/.bashrc
# Or use the locked development environment:
nix develop --command python3 scripts/test.py
```

The suite uses temporary homes and mocked package managers. It exercises reruns,
legacy migration, preserved local overrides, quoting/Unicode paths, encoding,
private backups, restore conflicts, package failure propagation and shell startup
with absent/older optional tools. CI runs on Linux, macOS and Windows. It does not
install packages on test machines or prove every distribution's package availability.
