# Editor Server Deploy Tool

`scripts/editor-server-deploy.sh` is a separate tool for VS Code-core server deployments. It does not modify `scripts/cursor-deploy.sh`.

## CLI Compatibility

The command model now matches `cursor-deploy`:

- Actions: `--update`, `--rollback`, `--list`, `--current`, `--clean`
- Shared options: `-v`, `-c`, `-p`, `-a`, `-o`, `-y`, `--no-proxy`, `--no-backup`, `--no-cache`, `-h`
- Extra options for the open provider model: `--provider`, `--channel`, `--install-root`, `--manifest-dir`, `--dry-run`, `--list-providers`

## Provider Manifest Mode

Providers are defined under:

```text
manifests/providers/*.conf
```

Start from:

```text
manifests/providers/_template.conf
```

Each manifest controls:

- required inputs (`version` and/or `commit`)
- download URL templates
- install paths
- cache naming
- extraction behavior
- post-install hint text

To support another VS Code-core server, add a new manifest instead of changing the script.

Recommended workflow for a new provider:

1. Copy `_template.conf` to `<provider>.conf`
2. Fill in URL, path, cache, and extract templates
3. Run `editor-server-deploy --provider <provider> --dry-run`
4. Install once and verify the resulting layout

## Built-in Providers

- `vscode-remote`
  Uses the modern VS Code Remote-SSH layout under `~/.vscode-server`
- `openvscode-server`
  Installs standalone OpenVSCode Server tarballs
- `code-server`
  Installs standalone coder/code-server tarballs

## Example Commands

VS Code Remote-SSH style install:

```bash
editor-server-deploy --provider vscode-remote -c ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb -y
```

VS Code Remote-SSH style install with the verified proxy example:

```bash
editor-server-deploy --provider vscode-remote -c ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb -p http://10.10.10.215:7897 -y
```

Inspect resolved URLs and paths:

```bash
editor-server-deploy --provider vscode-remote -c ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb --dry-run
```

Install OpenVSCode Server:

```bash
editor-server-deploy --provider openvscode-server -v 1.105.1 -y
```

Install code-server:

```bash
editor-server-deploy --provider code-server -v 4.106.3 -a arm64 -y
```

## How To Check Success

For `vscode-remote`, run:

```bash
editor-server-deploy --provider vscode-remote --current
ls -l ~/.vscode-server/cli/servers/Stable-current
test -f ~/.vscode-server/cli/servers/Stable-ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb/server/product.json && echo ok
ls -l ~/.vscode-server/code-ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb
```

Successful state means:

- `--current` shows the installed provider state
- `Stable-current` points to `Stable-ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb`
- `product.json` exists under the server directory
- the `code-ce099...` CLI binary exists and is executable

## State And Rollback

- Current state is tracked under `INSTALL_ROOT/.deploy-state/`
- Cache is stored under `INSTALL_ROOT/cache/`
- Backups are stored under `INSTALL_ROOT/backups/`
- `--rollback` restores the latest backup for the selected provider

For `vscode-remote`, the tool also updates:

```text
~/.vscode-server/cli/servers/Stable-current
```
