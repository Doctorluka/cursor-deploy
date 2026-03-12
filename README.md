# Cursor Remote Server Deploy Tool

Deploy and manage Cursor Remote-SSH server components on Linux hosts when automatic download is slow, unstable, or blocked.

## Use The Active Entrypoint

This repo maintains one active deploy script:

- `scripts/cursor-deploy.sh` (active)
- `scripts/deploy-cursor-server.sh` (retired compatibility stub, no new logic)
- `scripts/editor-server-deploy.sh` (active, manifest-driven tool for VS Code-core servers)

## Install The Command

Run:

```bash
cp ~/Documents/cursor-deploy/scripts/cursor-deploy.sh ~/.local/bin/cursor-deploy
chmod +x ~/.local/bin/cursor-deploy
```

Then:

```bash
cursor-deploy --help
```

## Deploy A Specific Version

Use this when you already have **Version** and **Commit** from Cursor **Help -> About**.

```bash
cursor-deploy -v 2.6.11 -c 8c95649f251a168cc4bb34c89531fae7db4bd990 -y
```

If you need a proxy:

```bash
cursor-deploy -v 2.6.11 -c 8c95649f251a168cc4bb34c89531fae7db4bd990 -p http://10.10.10.216:7897 -y
```

Real-world verified flow for the command above:

- Proxy connectivity check runs first.
- CLI package is downloaded from `/{commit}/cli-alpine-{arch}.tar.gz`.
- Server package is downloaded from `/{version}-{commit}/vscode-reh-{os}-{arch}.tar.gz`.
- Script verifies `server/product.json` exists and CLI executable can run.
- On success, `Stable-current` points to `Stable-{commit}`.

## Understand What Gets Installed

Cursor remote attach needs two artifacts for the same target commit:

1. CLI component
   Target path: `~/.cursor-server/cursor-{COMMIT}`
2. Server component
   Target path: `~/.cursor-server/cli/servers/Stable-{COMMIT}/server/`

## Use Proxy Only When Needed

Default behavior is no proxy.

- Set proxy explicitly with `-p/--proxy`.
- Force direct connection with `--no-proxy`.
- When proxy is set, script validates it with `curl ... https://www.google.com/generate_204`.

Example with a local mihomo mixed port:

```bash
MIHOMO_PROXY=$(grep -E '^mixed-port:' ~/.config/mihomo/config.yaml | awk '{print "http://127.0.0.1:"$2}')
cursor-deploy -v 2.6.11 -c 8c95649f251a168cc4bb34c89531fae7db4bd990 -p "$MIHOMO_PROXY" -y
```

## Use CLI Actions

```bash
cursor-deploy [options] [action]
```

Actions:

- `(none)` interactive deploy (default)
- `--update` print update guidance
- `--rollback` roll back to previous version
- `--list` list installed versions
- `--current` show current active commit
- `--clean` clean download cache and old backups

Options:

- `-v, --version <version>` (example: `2.6.11`)
- `-c, --commit <hash>` (40-char lowercase hex)
- `-p, --proxy <URL>`
- `-a, --arch <arch>` (`x64` or `arm64`, default `x64`)
- `-o, --os <os>` (`linux`, default `linux`)
- `-y, --yes` skip confirmations
- `--no-proxy` disable proxy usage
- `--no-backup` skip backup before deploy
- `--no-cache` disable download cache reuse
- `-h, --help`

## Manage State, Backups, And Rollback

- Active version is tracked by symlink:
  `~/.cursor-server/cli/servers/Stable-current`
- Backups are stored under:
  `~/.cursor-server/backups/`
- Before deploy, current version is backed up unless `--no-backup` is set.
- `--rollback` restores latest backup for `previous_version.txt`, including CLI backup when present.
- `--clean` removes cached tarballs and keeps only the latest 3 backup generations.

## Validate After Deploy

Run:

```bash
cursor-deploy --current
cursor-deploy --list
```

Then:

```bash
ls ~/.cursor-server/cli/servers/Stable-*/server/product.json
ls ~/.cursor-server/cursor-*
```

If needed, check CLI binary directly:

```bash
~/.cursor-server/cursor-8c95649f251a168cc4bb34c89531fae7db4bd990 --version
```

Note: CLI `--version` output can include its own internal commit string. The script's hard requirement is executable health, plus matching server directory for your target commit.

## Use The Open Provider Tool

Use `editor-server-deploy` when you need a more generic tool for VS Code-core servers.

- Provider manifests live under `manifests/providers/`
- Built-in providers:
  - `vscode-remote`
  - `openvscode-server`
  - `code-server`

Install:

```bash
cp ~/Documents/cursor-deploy/scripts/editor-server-deploy.sh ~/.local/bin/editor-server-deploy
chmod +x ~/.local/bin/editor-server-deploy
```

Examples:

```bash
editor-server-deploy --provider vscode-remote -c ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb -y
editor-server-deploy --provider openvscode-server -v 1.105.1 -y
editor-server-deploy --provider code-server -v 4.106.3 -y
editor-server-deploy --provider vscode-remote --list
```

More detail:

- [EDITOR_SERVER_DEPLOY.md](/home/data/fhz/Documents/cursor-deploy/guides/EDITOR_SERVER_DEPLOY.md)

## Version And Commit Source

Get values from Cursor:

- **Help** -> **About**

Example:

```text
Version: 2.6.11
Commit: 8c95649f251a168cc4bb34c89531fae7db4bd990
```
