import os
import stat
import subprocess
from pathlib import Path

ROOT = Path('/home/data/fhz/Documents/cursor-deploy')
SCRIPT = ROOT / 'scripts' / 'editor-server-deploy.sh'


def run_cmd(*args, env=None):
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        [str(SCRIPT), *args],
        text=True,
        capture_output=True,
        env=merged_env,
        check=False,
    )


def test_script_is_executable():
    mode = SCRIPT.stat().st_mode
    assert mode & stat.S_IXUSR


def test_help_works():
    res = run_cmd('--help')
    assert res.returncode == 0
    assert 'Usage: editor-server-deploy' in res.stdout
    assert '--rollback' in res.stdout
    assert '--current' in res.stdout
    assert 'Success checks:' in res.stdout


def test_list_providers_works():
    res = run_cmd('--list-providers')
    assert res.returncode == 0
    assert 'vscode-remote' in res.stdout
    assert 'code-server' in res.stdout


def test_invalid_provider_fails():
    res = run_cmd('--provider', 'unknown', '--dry-run')
    assert res.returncode != 0
    assert "Unknown provider" in (res.stdout + res.stderr)


def test_current_without_state(tmp_path):
    res = run_cmd('--provider', 'vscode-remote', '--current', env={'HOME': str(tmp_path)})
    assert res.returncode == 0
    assert 'No current version is set' in res.stdout


def test_vscode_remote_requires_commit():
    res = run_cmd('--provider', 'vscode-remote', '--dry-run')
    assert res.returncode != 0
    assert 'Invalid commit hash' in (res.stdout + res.stderr)


def test_vscode_remote_dry_run_with_commit():
    res = run_cmd(
        '--provider',
        'vscode-remote',
        '-c',
        'ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb',
        '--dry-run',
    )
    assert res.returncode == 0
    assert 'update.code.visualstudio.com/commit:ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb' in res.stdout


def test_openvscode_requires_version():
    res = run_cmd('--provider', 'openvscode-server', '--dry-run')
    assert res.returncode != 0
    assert 'Invalid version' in (res.stdout + res.stderr)
