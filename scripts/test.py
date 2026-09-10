#!/usr/bin/env python3
"""Behavior tests against temporary homes; no packages or account state touched."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import install
import tools

ROOT = Path(__file__).resolve().parent.parent


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='psyche tests ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home with space and 'quote-é"
        self.home.mkdir()
        self.profile = self.home / 'Documents/PowerShell/profile.ps1'

    def run_install(self, *args, ok=True):
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/install.py'),
                                 '--home', str(self.home), '--powershell-profile', str(self.profile), *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr + result.stdout)
        return result

    def backups(self):
        return sorted((self.home / '.local/state/psyche/backups').glob('*/manifest.json'))

    def write(self, relative, text):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def test_dry_run_does_not_create_files(self):
        self.run_install('--dry-run')
        self.assertEqual(list(self.home.iterdir()), [])

    @unittest.skipIf(os.name == 'nt', 'Bash configuration')
    def test_handwritten_shell_is_kept_until_explicit_adoption(self):
        original = '#!/bin/bash\nexport KEEP_ME=yes\nalias gs="git status -sb"\n'
        path = self.write('.bashrc', original)
        self.run_install('--components', 'shell')
        self.assertEqual(path.read_text(encoding='utf-8'), original)
        self.assertTrue((self.home / '.config/psyche/INTEGRATION.md').exists())
        self.run_install('--components', 'shell', '--adopt-shell')
        self.assertTrue(path.read_text(encoding='utf-8').endswith(original))
        self.assertEqual(path.read_text(encoding='utf-8').count('# >>> psyche >>>'), 1)

    def test_manual_mode_keeps_all_user_configs(self):
        paths = {'.gitconfig': '[user]\n name = Mine\n', '.codex/AGENTS.md': 'My rules\n',
                 '.config/starship.toml': 'add_newline = false\n'}
        for path, content in paths.items():
            self.write(path, content)
        self.run_install('--manual')
        for path, content in paths.items():
            self.assertEqual((self.home / path).read_text(encoding='utf-8'), content)
        self.assertFalse(self.profile.exists())

    def test_custom_prompt_and_later_edits_are_preserved(self):
        path = self.write('.config/starship.toml', 'add_newline = false\n')
        self.run_install('--components', 'prompt')
        self.assertEqual(path.read_text(encoding='utf-8'), 'add_newline = false\n')
        self.run_install('--components', 'prompt', '--replace-prompt')
        self.assertEqual(path.read_bytes(), (ROOT / 'starship/starship.toml').read_bytes())
        content = path.read_text(encoding='utf-8') + '\n# My local change\n'
        path.write_text(content, encoding='utf-8')
        self.run_install('--components', 'prompt')
        self.assertEqual(path.read_text(encoding='utf-8'), content)

    @unittest.skipIf(os.name == 'nt', 'Unix entry point')
    def test_unix_entry_point(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/install.sh'), '--home', str(self.home), '--dry-run'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])

    @unittest.skipIf(os.name == 'nt', 'Ghostty targets Unix desktops')
    def test_ghostty_defaults_preserve_local_overrides(self):
        path = self.write('.config/ghostty/config.ghostty', 'font-size = 16\n')
        self.run_install('--components', 'terminal')
        self.assertTrue(path.read_text(encoding='utf-8').endswith('font-size = 16\n'))
        self.assertIn('background = #1e1e2e', path.read_text(encoding='utf-8'))
        self.assertFalse((path.parent / 'config').exists())
        self.run_install('--components', 'terminal')
        self.assertEqual(len(self.backups()), 1)

    def test_install_is_idempotent_and_prompt_unchanged(self):
        self.run_install()
        first = {p.relative_to(self.home): p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        self.run_install()
        second = {p.relative_to(self.home): p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        self.assertEqual(first, second)
        self.assertEqual((self.home / '.config/starship.toml').read_bytes(),
                         (ROOT / 'starship/starship.toml').read_bytes())

    def test_git_overrides_and_identity_survive(self):
        local = '[user]\n name = Local Name\n email = local@example.invalid\n[pull]\n ff = false\n[core]\n pager = more\n'
        path = self.write('.gitconfig', local)
        self.run_install('--components', 'git')
        self.assertTrue(path.read_text(encoding='utf-8').endswith(local))
        if shutil.which('git'):
            def config(key):
                return subprocess.check_output(['git', 'config', '--file', str(path), '--includes', '--get', key], text=True).strip()
            self.assertEqual(config('user.name'), 'Local Name')
            self.assertEqual(config('pull.ff'), 'false')
            self.assertEqual(config('core.pager'), 'more')
            self.assertEqual(config('init.defaultBranch'), 'main')

    def test_native_ai_rules_preserve_existing_content(self):
        self.write('.codex/AGENTS.md', 'Existing Codex preference.\n')
        self.write('.claude/CLAUDE.md', 'Existing Claude preference.\n')
        self.run_install('--components', 'ai')
        for path in ['.codex/AGENTS.md', '.claude/CLAUDE.md']:
            content = (self.home / path).read_text(encoding='utf-8')
            self.assertIn((ROOT / 'ai/preferences.md').read_text(encoding='utf-8'), content)
            self.assertIn('Existing', content)
        self.run_install('--components', 'ai')
        self.assertEqual(len(self.backups()), 1)

    def test_xdg_only_git_config_stays_authoritative(self):
        path = self.write('.config/git/config', '[pull]\n ff = false\n')
        self.run_install('--components', 'git')
        self.assertFalse((self.home / '.gitconfig').exists())
        self.assertTrue(path.read_text(encoding='utf-8').endswith('[pull]\n ff = false\n'))

    def test_codex_override_is_reported(self):
        self.write('.codex/AGENTS.override.md', 'Special profile\n')
        result = self.run_install('--components', 'ai')
        self.assertIn('takes precedence', result.stderr)

    def test_explicit_paths_and_isolated_environment(self):
        outside = Path(self.temp.name) / 'must not touch'
        with mock.patch.dict(os.environ, {'CODEX_HOME': str(outside), 'STARSHIP_CONFIG': str(outside / 'prompt')}):
            self.run_install('--components', 'ai', 'prompt')
        self.assertFalse(outside.exists())
        custom = self.home / 'custom codex'
        self.run_install('--components', 'ai', '--codex-home', str(custom))
        self.assertTrue((custom / 'AGENTS.md').exists())

    def test_malformed_block_fails_before_any_writes(self):
        path = self.write('.codex/AGENTS.md', '<!-- psyche:start -->\nbroken\n')
        self.run_install(ok=False)
        self.assertEqual(path.read_text(encoding='utf-8'), '<!-- psyche:start -->\nbroken\n')
        self.assertFalse((self.home / '.config').exists())

    def test_directory_conflict_fails_before_any_writes(self):
        (self.home / '.gitconfig').mkdir()
        self.run_install(ok=False)
        self.assertFalse((self.home / '.config').exists())

    @unittest.skipIf(os.name == 'nt', 'symlink creation can require Windows privileges')
    def test_unrelated_symlink_is_not_modified(self):
        target = self.write('outside', 'untouched\n')
        (self.home / '.bashrc').symlink_to(target)
        self.run_install()
        self.assertEqual(target.read_text(encoding='utf-8'), 'untouched\n')
        self.assertTrue((self.home / '.bashrc').is_symlink())
        self.assertTrue((self.home / '.config/psyche/INTEGRATION.md').exists())

    @unittest.skipIf(os.name == 'nt', 'Unix legacy installation')
    def test_legacy_source_lines_and_links_migrate(self):
        old = ROOT.parent / 'pysche'
        self.write('.bashrc', f'# Pysche Tools\nsource {old}/bash/.bashrc\nexport KEEP_ME=yes\n')
        self.write('.gitconfig', f'[include]\n    path = {old}/git/.gitconfig\n[user]\n name = Kept\n')
        (self.home / '.config').mkdir()
        (self.home / '.config/starship.toml').symlink_to(old / 'starship/starship.toml')
        (self.home / '.gitignore_global').symlink_to(old / 'git/.gitignore_global')
        self.run_install()
        self.assertNotIn(str(old), (self.home / '.bashrc').read_text(encoding='utf-8'))
        self.assertNotIn(str(old), (self.home / '.gitconfig').read_text(encoding='utf-8'))
        self.assertIn('export KEEP_ME=yes', (self.home / '.bashrc').read_text(encoding='utf-8'))
        self.assertFalse((self.home / '.config/starship.toml').is_symlink())
        self.assertFalse((self.home / '.gitignore_global').is_symlink())

    def test_restore_original_bytes_and_remove_new_files(self):
        original = b'[user]\r\n name = Original\r\n'
        path = self.home / '.gitconfig'
        path.write_bytes(original)
        self.run_install()
        backup = self.backups()[0].parent
        self.run_install('--restore', str(backup), '--dry-run')
        self.assertNotEqual(path.read_bytes(), original)
        self.run_install('--restore', str(backup))
        self.assertEqual(path.read_bytes(), original)
        self.assertFalse((self.home / '.config/starship.toml').exists())

    def test_restore_refuses_later_edits_without_partial_restore(self):
        self.run_install()
        backup = self.backups()[0].parent
        path = self.home / '.gitconfig'
        path.write_text(path.read_text(encoding='utf-8') + '# Later edit\n', encoding='utf-8')
        self.run_install('--restore', str(backup), ok=False)
        self.assertTrue((self.home / '.config/starship.toml').exists())
        self.assertIn('Later edit', path.read_text(encoding='utf-8'))

    def test_utf16_powershell_profile_is_preserved(self):
        self.profile.parent.mkdir(parents=True)
        self.profile.write_bytes('# Local preference\r\n'.encode('utf-16'))
        self.run_install('--components', 'shell', '--adopt-shell')
        data = self.profile.read_bytes()
        self.assertTrue(data.startswith(b'\xff\xfe'))
        self.assertIn('# Local preference\r\n', data.decode('utf-16'))
        self.run_install('--components', 'shell')
        self.assertEqual(data, self.profile.read_bytes())

    @unittest.skipIf(os.name == 'nt', 'Unix login files')
    def test_macos_uses_existing_login_file(self):
        self.write('.profile', 'export KEEP_LOGIN=yes\n')
        args = mock.Mock(home=str(self.home), config_home=None, codex_home=None,
                         claude_home=None, zsh_dir=None, powershell_profile=None, components=['shell'],
                         manual=False, adopt_shell=True, replace_prompt=False)
        with mock.patch('install.platform.system', return_value='Darwin'):
            plan, _ = install.make_plan(args)
        self.assertIn(self.home / '.profile', plan)
        self.assertNotIn(self.home / '.bash_profile', plan)
        self.assertIn(b'KEEP_LOGIN=yes', plan[self.home / '.profile'])

    @unittest.skipIf(os.name == 'nt', 'Unix permissions')
    def test_backups_are_private(self):
        self.write('.gitconfig', '[user]\n name = Private\n')
        self.run_install('--components', 'git')
        backup = self.backups()[0].parent
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        for path in backup.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    @unittest.skipIf(os.name == 'nt', 'Unix shell behavior')
    def test_shells_without_optional_tools_or_with_old_fzf(self):
        self.run_install('--components', 'shell')
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        fake_fzf = bin_dir / 'fzf'
        fake_fzf.write_text('#!/bin/sh\necho unsupported >&2\nexit 2\n', encoding='utf-8')
        fake_fzf.chmod(0o755)
        fake_starship = bin_dir / 'starship'
        fake_starship.write_text('#!/bin/sh\necho prompt-on-dumb-terminal >&2\nexit 1\n', encoding='utf-8')
        fake_starship.chmod(0o755)
        # compinit uses the system mv when persisting its completion cache.
        (bin_dir / 'mv').symlink_to(shutil.which('mv'))
        (bin_dir / 'uname').symlink_to(shutil.which('uname'))
        env = {**os.environ, 'HOME': str(self.home), 'ZDOTDIR': str(self.home), 'PATH': str(bin_dir), 'TERM': 'dumb'}
        for shell, relative in [('bash', 'bash/.bashrc'), ('zsh', 'zsh/.zshrc')]:
            executable = shutil.which(shell)
            if not executable:
                continue
            flags = ['--noprofile', '--norc', '-ic'] if shell == 'bash' else ['-df', '-ic']
            # Pass paths as positional parameters to cover spaces, quotes and Unicode.
            script = '. "$1"; . "$1"; for name in gs ga gaa gc gp gpl gd gco gl gsu ll la lla l .. ... .... mk copy move del nixdev nixrun nsh nixlock nixup nixcheck nixs rebuild nix-hist nix-clean gwipe reload; do alias "$name" >/dev/null 2>&1 || exit 9; done; for name in git git-nuke f loc new logrun aliases; do typeset -f "$name" >/dev/null || exit 8; done; printf "READY\\n"'
            loader = self.home / ('.bashrc' if shell == 'bash' else '.zshrc')
            result = subprocess.run([executable, *flags, script, 'test', str(loader)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'READY\n')
            self.assertNotIn('unsupported', result.stderr)
            self.assertNotIn('prompt-on-dumb-terminal', result.stderr)
            self.assertNotIn('command not found', result.stderr)
            script = '. "$1"; test -z "${PSYCHE_BASH_LOADED:-}${PSYCHE_ZSH_LOADED:-}"'
            result = subprocess.run([executable, '-c', script, 'test', str(ROOT / relative)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which('pwsh') or shutil.which('powershell'), 'PowerShell unavailable')
    def test_powershell_entry_and_profile(self):
        executable = shutil.which('pwsh') or shutil.which('powershell')
        result = subprocess.run([executable, '-NoProfile', '-File', str(ROOT / 'scripts/install.ps1'),
                                 '--home', str(self.home), '--powershell-profile', str(self.profile), '--components', 'shell'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        escaped = str(self.profile).replace("'", "''")
        command = f"$ErrorActionPreference = 'Stop'; . '{escaped}'; . '{escaped}'; Write-Output READY"
        # Optional executables should be absent, leaving native PowerShell usable.
        result = subprocess.run([executable, '-NoProfile', '-Command', command],
                                env={**os.environ, 'PATH': '', 'HOME': str(self.home)}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'READY')


class PackageTests(unittest.TestCase):
    def test_ghostty_platform_packages(self):
        with mock.patch('tools.platform.system', return_value='Darwin'):
            self.assertEqual(tools.package_command('brew', 'ghostty'), ['brew', 'install', '--cask', 'ghostty'])
            with self.assertRaises(ValueError):
                tools.package_command('nix', 'ghostty')
        with mock.patch('tools.platform.system', return_value='Linux'):
            self.assertIn(f'path:{ROOT}#ghostty', tools.package_command('nix', 'ghostty'))
        with self.assertRaises(ValueError):
            tools.package_command('winget', 'ghostty')

    def test_default_core_request(self):
        manager = 'winget' if os.name == 'nt' else 'brew'
        with mock.patch.object(sys, 'argv', ['tools.py', '--manager', manager, '--dry-run']), \
             mock.patch('tools.shutil.which', return_value=None), \
             mock.patch('tools.subprocess.run') as run, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(tools.main(), 0)
            self.assertEqual(output.getvalue().count('Run:'), 3)
            run.assert_not_called()

    def test_windows_ids_and_nix_pins(self):
        self.assertIn('BurntSushi.ripgrep.MSVC', tools.package_command('winget', 'ripgrep'))
        self.assertIn(f'path:{ROOT}#starship', tools.package_command('nix', 'starship'))
        with self.assertRaises(ValueError):
            tools.package_command('winget', 'tmux')

    def test_package_failure_is_nonzero_and_stops(self):
        manager = 'winget' if os.name == 'nt' else 'brew'
        def which(name):
            return '/mock/' + name if name == manager else None
        with mock.patch.object(sys, 'argv', ['tools.py', '--manager', manager, 'git', 'ripgrep']), \
             mock.patch('tools.shutil.which', side_effect=which), \
             mock.patch('tools.subprocess.run', side_effect=subprocess.CalledProcessError(1, manager)) as run, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(tools.main(), 1)
            self.assertEqual(run.call_count, 1)

    def test_dry_run_and_installed_command_detection(self):
        manager = 'winget' if os.name == 'nt' else 'apt'
        with mock.patch.object(sys, 'argv', ['tools.py', '--manager', manager, '--dry-run', 'ripgrep']), \
             mock.patch('tools.shutil.which', return_value=None), \
             mock.patch('tools.subprocess.run') as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(tools.main(), 0)
            run.assert_not_called()
        with mock.patch.object(sys, 'argv', ['tools.py', '--manager', manager, 'ripgrep']), \
             mock.patch('tools.shutil.which', side_effect=lambda name: '/bin/rg' if name == 'rg' else None), \
             mock.patch('tools.subprocess.run') as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(tools.main(), 0)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
