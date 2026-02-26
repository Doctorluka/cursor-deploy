import os
import stat
import subprocess
from pathlib import Path

ROOT = Path('/home/data/fhz/Documents/cursor-deploy')
SCRIPT = ROOT / 'scripts' / 'cursor-deploy.sh'


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
    assert 'Usage: cursor-deploy' in res.stdout
    assert '--current' in res.stdout


def test_current_without_state(tmp_path):
    cursor_home = tmp_path / '.cursor-server'
    res = run_cmd('--current', env={'CURSOR_HOME': str(cursor_home)})
    assert res.returncode == 0
    assert 'No current version is set' in res.stdout


def test_invalid_arch_fails():
    res = run_cmd('-v', '2.5.25', '-c', '7150844152b426ed50d2b68dd6b33b5c5beb73c0', '-a', 'x86', '-y')
    assert res.returncode != 0
    assert 'Invalid architecture' in (res.stdout + res.stderr)


def test_missing_value_fails():
    res = run_cmd('-v')
    assert res.returncode != 0
    assert 'requires a value' in (res.stdout + res.stderr)
