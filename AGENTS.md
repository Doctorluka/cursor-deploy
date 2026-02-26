# Repository Guidelines

## Project Structure & Module Organization
- `scripts/cursor-deploy.sh`: main and only maintained deploy entrypoint.
- `scripts/deploy-cursor-server.sh`: retired compatibility stub; do not add new logic here.
- `guides/USAGE_GUIDE.md`: extended usage and troubleshooting.
- `README.md`: canonical quick start and command reference.
- `tests/test_cursor_deploy_cli.py`: CLI behavior checks.
- `backups/` and `logs/`: historical artifacts; treat as records, not active source.

## Build, Test, and Development Commands
- Syntax check shell scripts:
  - `bash -n scripts/cursor-deploy.sh`
  - `bash -n scripts/deploy-cursor-server.sh`
- Show CLI help and basic behavior:
  - `scripts/cursor-deploy.sh --help`
  - `scripts/cursor-deploy.sh --current`
- Run tests (when `pytest` is available):
  - `pytest -q`
- Search files/content quickly:
  - `rg --files`
  - `rg "pattern"`

## Coding Style & Naming Conventions
- Shell: Bash with `set -euo pipefail`, quoted variables, and explicit error messages.
- Prefer small functions (`verb_noun` style) and single-responsibility blocks.
- Keep user-facing output in English.
- Preserve stable CLI flags (`--list`, `--current`, `--rollback`, `--clean`).
- Python tests: 4-space indent, `test_<behavior>` naming.

## Testing Guidelines
- Add tests for any CLI interface or state-management change.
- Minimum checks before submitting changes:
  1. `bash -n scripts/cursor-deploy.sh`
  2. `scripts/cursor-deploy.sh --help`
  3. `scripts/cursor-deploy.sh --current`
- For deploy/rollback logic, prefer isolated tests with temporary `CURSOR_HOME`.

## Commit & Pull Request Guidelines
- This repo currently has no commit history; adopt Conventional Commits:
  - `feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `refactor: ...`
- Keep each PR focused (script logic, docs, or tests).
- PRs should include:
  - what changed,
  - how it was validated (commands + key output),
  - any behavior changes to CLI flags or defaults.
