# Cursor Remote Server Deploy Tool

Deploy and manage Cursor Remote-SSH server components on Linux hosts when automatic download is slow or blocked.

## Scope

This repository now maintains a single deployment entrypoint:

- `scripts/cursor-deploy.sh` (active)
- `scripts/deploy-cursor-server.sh` (retired stub)

## What It Installs

Cursor remote attach requires two artifacts for the same commit:

1. CLI component
- URL: `{COMMIT}/cli-alpine-{ARCH}.tar.gz`
- Target: `~/.cursor-server/cursor-{COMMIT}`

2. Server component
- URL: `{VERSION}-{COMMIT}/vscode-reh-{OS}-{ARCH}.tar.gz`
- Target: `~/.cursor-server/cli/servers/Stable-{COMMIT}/server/`

## Quick Start

```bash
cp ~/Documents/cursor-deploy/scripts/cursor-deploy.sh ~/.local/bin/cursor-deploy
chmod +x ~/.local/bin/cursor-deploy

# Interactive
cursor-deploy

# Non-interactive
cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -y
```

## Proxy Behavior

Default behavior is **no proxy**.

Use proxy only when needed:

```bash
cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -p http://127.0.0.1:7899 -y
```

Optional mihomo usage (manual):

```bash
MIHOMO_PROXY=$(grep -E '^mixed-port:' ~/.config/mihomo/config.yaml | awk '{print "http://127.0.0.1:"$2}')
cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -p "$MIHOMO_PROXY" -y
```

## Command Reference

```bash
cursor-deploy [options] [action]

Actions:
  (none)            Interactive deploy (default)
  --update          Print update guidance
  --rollback        Roll back to previous version
  --list            List installed versions
  --current         Show current active commit
  --clean           Clean cache and old backups

Options:
  -v, --version <version>
  -c, --commit <hash>
  -p, --proxy <URL>
  -a, --arch <arch>         x64 or arm64
  -o, --os <os>             linux
  -y, --yes
  --no-proxy
  --no-backup
  --no-cache
  -h, --help
```

## Validation and State

- `Stable-current` symlink is updated on successful deploy/rollback.
- Backups are stored under `~/.cursor-server/backups/`.
- Rollback restores both server directory and CLI binary when backup exists.

## Common Checks

```bash
# Show active commit
cursor-deploy --current

# Show installed versions
cursor-deploy --list

# Verify server metadata
ls ~/.cursor-server/cli/servers/Stable-*/server/product.json

# Verify CLI artifact
ls ~/.cursor-server/cursor-*
```

## Version Source

Get version and commit from Cursor:

- `Help -> About`

Example:

```text
Version: 2.5.25
Commit: 7150844152b426ed50d2b68dd6b33b5c5beb73c0
```
