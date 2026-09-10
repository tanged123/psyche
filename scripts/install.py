#!/usr/bin/env python3
"""Install portable settings. Standard library only; never runs package managers."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import stat
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
if sys.version_info < (3, 9):
    sys.exit('Python 3.9+ is required.')


def absolute(value):
    return Path(os.path.abspath(os.path.expanduser(str(value))))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.psyche-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_text(path):
    data = path.read_bytes() if path.exists() else b''
    encoding = 'utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig'
    text = data.decode(encoding)
    newline = '\r\n' if '\r\n' in text else '\n'
    # Preserve a preexisting BOM, but don't add one to ordinary UTF-8 files.
    if encoding == 'utf-8-sig' and not data.startswith(b'\xef\xbb\xbf'):
        encoding = 'utf-8'
    return text.replace('\r\n', '\n'), encoding, newline


def managed(text, body, markdown=False):
    start, end = ('<!-- psyche:start -->', '<!-- psyche:end -->') if markdown else (
        '# >>> psyche >>>', '# <<< psyche <<<')
    if text.count(start) != text.count(end) or text.count(start) > 1:
        raise ValueError('malformed or duplicate Psyche markers; repair them first')
    block = start + '\n' + body.rstrip() + '\n' + end + '\n'
    if start in text:
        pattern = re.compile(r'^' + re.escape(start) + r'\n.*?^' + re.escape(end) + r'(?:\n|$)', re.M | re.S)
        text, count = pattern.subn(lambda _: block, text)
        if count != 1:
            raise ValueError('Psyche markers must be on separate lines and in order')
        return text
    # Defaults precede machine overrides, and Bash's usual early return.
    return block + text


def legacy_paths(relative):
    return {str(ROOT / relative), str(ROOT.parent / 'pysche' / relative)}


def remove_legacy(text, relative, kind):
    for source in legacy_paths(relative):
        if kind == 'git':
            pattern = r'^\[include\]\n[ \t]*path[ \t]*=[ \t]*(?:' + re.escape(source) + '|' + re.escape(json.dumps(source)) + r')[ \t]*\n'
        else:
            command = 'source-file' if kind == 'tmux' else '(?:source|\\.)'
            pattern = r'^' + command + r'\s+(?:' + re.escape(source) + '|' + re.escape(shlex.quote(source)) + r')[ \t]*\n'
        text = re.sub(pattern, '', text, flags=re.M)
    return re.sub(r'^# Pysche (?:Tools(?: \(zsh\))?|Tmux)\n', '', text, flags=re.M)


def make_plan(args):
    home = absolute(args.home or Path.home())
    isolated = args.home is not None

    def location(option, env, fallback):
        return absolute(option or (None if isolated else os.environ.get(env)) or fallback)

    config = location(args.config_home, 'XDG_CONFIG_HOME', home / '.config')
    bundle = config / 'psyche'
    codex = location(args.codex_home, 'CODEX_HOME', home / '.codex')
    claude = location(args.claude_home, 'CLAUDE_CONFIG_DIR', home / '.claude')
    zsh_dir = location(args.zsh_dir, 'ZDOTDIR', home)
    state = home / '.local/state/psyche'
    plan = {}
    snippets = []

    def keep(path, body=None):
        print(f'Keep existing {path}')
        if body is not None:
            snippets.append(f'## {path}\n\n```text\n{body.rstrip()}\n```\n')

    def known_link(path, relative):
        return path.is_symlink() and relative and str(absolute(path.parent / os.readlink(path))) in legacy_paths(relative)

    def unchanged_install(path):
        if not path.is_file():
            return False
        for manifest in sorted((state / 'backups').glob('*/manifest.json'), reverse=True):
            for entry in json.loads(manifest.read_text(encoding='utf-8')):
                if entry['path'] == str(path):
                    return entry['after'] == digest(path.read_bytes())
        return False

    def add(path, data, legacy=None):
        path = absolute(path)
        # Don't follow user symlinks and accidentally edit a different repository.
        if path.is_symlink():
            target = absolute(path.parent / os.readlink(path))
            if legacy is None or str(target) not in legacy_paths(legacy):
                raise ValueError(f'{path}: unrelated symlink; manage this file separately')
        elif path.exists() and not path.is_file():
            raise ValueError(f'{path}: expected a file')
        for parent in path.parents:
            if parent.exists() and not parent.is_dir():
                raise ValueError(f'{parent}: expected a directory')
        if path in plan and plan[path] != data:
            raise ValueError(f'{path}: conflicting installation destinations')
        plan[path] = data

    def copy(relative, destination=None):
        path = destination or bundle / relative
        add(path, (ROOT / relative).read_bytes(), relative)
        return path

    def merge(path, body, relative=None, kind='shell', markdown=False, shell=False):
        legacy_link = known_link(path, relative)
        if (path.is_symlink() and not legacy_link) or args.manual:
            keep(path, body)
            return
        if legacy_link:
            text, encoding, newline = '', 'utf-8', '\n'
        else:
            text, encoding, newline = read_text(path)
        legacy_source = relative and remove_legacy(text, relative, kind) != text
        if shell and path.exists() and text.strip() and '# >>> psyche >>>' not in text and not legacy_link and not legacy_source and not args.adopt_shell:
            keep(path, body)
            return
        if relative:
            text = remove_legacy(text, relative, kind)
        result = managed(text, body, markdown).replace('\n', newline).encode(encoding)
        add(path, result, relative)

    components = args.components or ['shell', 'git', 'prompt', 'ai'] + ([] if os.name == 'nt' else ['tmux', 'terminal'])
    if 'shell' in components:
        if os.name != 'nt':
            for relative, dest in [('bash/.bashrc', home / '.bashrc'), ('zsh/.zshrc', zsh_dir / '.zshrc')]:
                shell = relative.split('/')[0]
                copy(f'{shell}/extras.{shell}rc')
                source = shlex.quote(str(copy(relative)))
                merge(dest, f'PSYCHE_REPO_ROOT={shlex.quote(str(ROOT))}\n[ ! -f {source} ] || . {source}', relative, shell=True)
            if platform.system() == 'Darwin':
                login = next((home / name for name in ['.bash_profile', '.bash_login', '.profile']
                              if (home / name).exists()), home / '.bash_profile')
                source = shlex.quote(str(home / '.bashrc'))
                merge(login, f'[ -z "${{BASH_VERSION:-}}" ] || [ ! -f {source} ] || . {source}', shell=True)
        if args.powershell_profile:
            source = str(copy('powershell/profile.ps1')).replace("'", "''")
            merge(absolute(args.powershell_profile), f"if (Test-Path -LiteralPath '{source}') {{ . '{source}' }}", shell=True)
        elif os.name == 'nt':
            raise ValueError('use install.ps1 or provide --powershell-profile on Windows')
    if 'git' in components:
        source = copy('git/.gitconfig')
        ignore = copy('git/.gitignore_global')
        # The user's existing excludesFile below this block still wins.
        body = '[include]\n    path = ' + json.dumps(source.as_posix(), ensure_ascii=False)
        body += '\n[core]\n    excludesFile = ' + json.dumps(ignore.as_posix(), ensure_ascii=False)
        git_default = home / '.gitconfig'
        if not git_default.exists() and (config / 'git/config').exists():
            git_default = config / 'git/config'
        git_config = location(None, 'GIT_CONFIG_GLOBAL', git_default)
        merge(git_config, body, 'git/.gitconfig', 'git')
        old_ignore = home / '.gitignore_global'
        if not args.manual and old_ignore.is_symlink() and str(absolute(old_ignore.parent / os.readlink(old_ignore))) in legacy_paths('git/.gitignore_global'):
            copy('git/.gitignore_global', old_ignore)
    if 'prompt' in components:
        prompt = location(None, 'STARSHIP_CONFIG', config / 'starship.toml')
        source = copy('starship/starship.toml')
        if args.manual or (prompt.is_symlink() and not known_link(prompt, 'starship/starship.toml')):
            keep(prompt, f'Set STARSHIP_CONFIG to {source} in your shell to use Psyche\'s prompt.')
        elif prompt.exists() and not known_link(prompt, 'starship/starship.toml') and not unchanged_install(prompt) and not args.replace_prompt:
            keep(prompt, 'Use --replace-prompt to back up and replace this config with Psyche\'s prompt.')
        else:
            copy('starship/starship.toml', prompt)
    if 'terminal' in components:
        if os.name == 'nt':
            raise ValueError('Ghostty settings target Linux/macOS; use Windows Terminal on native Windows')
        # The legacy filename also works with Ghostty versions before 1.2.3.
        target = config / 'ghostty/config.ghostty'
        if not target.exists():
            target = config / 'ghostty/config'
        merge(target, (ROOT / 'ghostty/config').read_text(encoding='utf-8'))
    if 'tmux' in components:
        if os.name == 'nt':
            raise ValueError('tmux is supported in Linux/WSL, not native Windows')
        source = copy('tmux/.tmux.conf')
        merge(home / '.tmux.conf', 'source-file ' + shlex.quote(str(source)), 'tmux/.tmux.conf', 'tmux')
    if 'ai' in components:
        if (codex / 'AGENTS.override.md').exists():
            print(f'Notice: {codex / "AGENTS.override.md"} takes precedence over AGENTS.md.', file=sys.stderr)
        preferences = (ROOT / 'ai/preferences.md').read_text(encoding='utf-8')
        merge(codex / 'AGENTS.md', preferences, markdown=True)
        merge(claude / 'CLAUDE.md', preferences, markdown=True)
    if snippets:
        guide = bundle / 'INTEGRATION.md'
        add(guide, ('# Manual integration\n\nExisting files were kept. Add the relevant loader where it fits your\nstartup order, or use --adopt-shell for a backed-up prepend. Inspect overlapping\nalias/function names before adopting; arbitrary shell programs cannot be merged\nsemantically. Local settings below a loader normally override Psyche defaults.\n\n'
                    + '\n'.join(snippets)).encode('utf-8'))
        print(f'Integration instructions: {guide}')
    return plan, state


def install(plan, state, dry_run):
    changes = [(path, data) for path, data in plan.items()
               if path.is_symlink() or not path.exists() or path.read_bytes() != data]
    for path, _ in changes:
        print(f'{"Would update" if dry_run else "Update"} {path}')
    if dry_run or not changes:
        print(f'{len(changes)} file(s) would change.' if dry_run else 'Already up to date.')
        return
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = state / 'backups' / (stamp + '-' + uuid.uuid4().hex[:8])
    backup.mkdir(parents=True, mode=0o700)
    entries = []
    # Back up every original before writing any destination. Backups may contain secrets.
    for index, (path, data) in enumerate(changes):
        entry = {'path': str(path), 'after': digest(data), 'existed': path.exists() or path.is_symlink()}
        if path.is_symlink():
            entry['link'] = os.readlink(path)
        if path.exists():
            entry['mode'] = stat.S_IMODE(path.stat().st_mode)
            entry['backup'] = str(index)
            atomic_write(backup / str(index), path.read_bytes())
        entries.append(entry)
    atomic_write(backup / 'manifest.json', json.dumps(entries, indent=2).encode())
    print(f'Backups: {backup}')
    for (path, data), entry in zip(changes, entries):
        atomic_write(path, data, entry.get('mode', 0o600))
    print('Installed. Open a new shell. Rerun after updating this repo.')


def restore(directory, dry_run):
    backup = absolute(directory)
    entries = json.loads((backup / 'manifest.json').read_text(encoding='utf-8'))
    # Refuse to discard edits made since this installation, before restoring anything.
    for entry in entries:
        path = Path(entry['path'])
        if path.is_symlink() or not path.is_file() or digest(path.read_bytes()) != entry['after']:
            raise ValueError(f'{path}: changed since installation; recover its backup manually')
        if 'backup' in entry:
            (backup / entry['backup']).read_bytes()
    for entry in reversed(entries):
        path = Path(entry['path'])
        print(f'{"Would restore" if dry_run else "Restore"} {path}')
        if dry_run:
            continue
        if 'link' in entry:
            path.unlink()
            path.symlink_to(entry['link'])
        elif entry['existed']:
            atomic_write(path, (backup / entry['backup']).read_bytes(), entry['mode'])
        else:
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--manual', action='store_true', help='deploy shared files and write integration snippets without editing user configs')
    parser.add_argument('--adopt-shell', action='store_true', help='back up and prepend loaders to existing hand-written shell files')
    parser.add_argument('--replace-prompt', action='store_true', help='back up and replace an existing or locally edited Starship config')
    parser.add_argument('--components', nargs='+', choices=['shell', 'git', 'prompt', 'tmux', 'terminal', 'ai'])
    parser.add_argument('--home', help='isolated target home; ignores environment path overrides')
    parser.add_argument('--config-home')
    parser.add_argument('--codex-home')
    parser.add_argument('--claude-home')
    parser.add_argument('--zsh-dir')
    parser.add_argument('--powershell-profile', help='CurrentUserAllHosts profile path from PowerShell')
    parser.add_argument('--restore', metavar='BACKUP_DIRECTORY')
    args = parser.parse_args()
    try:
        if args.restore:
            restore(args.restore, args.dry_run)
        else:
            plan, state = make_plan(args)
            install(plan, state, args.dry_run)
    except (OSError, ValueError, UnicodeError) as error:
        print(f'psyche: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
