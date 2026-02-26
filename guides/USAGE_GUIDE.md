# Cursor-Deploy Usage Guide

## 1. Install the Script

```bash
cp ~/Documents/cursor-deploy/scripts/cursor-deploy.sh ~/.local/bin/cursor-deploy
chmod +x ~/.local/bin/cursor-deploy
```

## 2. Required Inputs

From Cursor desktop (`Help -> About`):

- `Version` (example: `2.5.25`)
- `Commit` (40-char hash)

## 3. Deploy Modes

Interactive:

```bash
cursor-deploy
```

Non-interactive:

```bash
cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -y
```

## 4. Proxy Usage

Default is no proxy.

Use proxy only if required:

```bash
cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -p http://127.0.0.1:7899 -y
```

Optional mihomo extraction:

```bash
MIHOMO_PROXY=$(grep -E '^mixed-port:' ~/.config/mihomo/config.yaml | awk '{print "http://127.0.0.1:"$2}')
cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -p "$MIHOMO_PROXY" -y
```

## 5. Operational Commands

```bash
cursor-deploy --help
cursor-deploy --list
cursor-deploy --current
cursor-deploy --rollback
cursor-deploy --clean
```

## 6. Troubleshooting

### Case: Invalid option value

Check:

```bash
cursor-deploy -v 2.5 -c abc
```

Expected: validation error for version and commit format.

Fix: provide `X.Y.Z` version and 40-char lowercase commit hash.

### Case: Download failure

Check:

```bash
curl -I https://cursor.blob.core.windows.net/remote-releases/
```

Expected: reachable endpoint.

Fix:

1. Retry with proxy `-p <proxy-url>`.
2. Use `--no-cache` to force redownload.

### Case: Current version not set

Check:

```bash
cursor-deploy --current
ls -l ~/.cursor-server/cli/servers/Stable-current
```

Expected: symlink exists and points to a `Stable-<commit>` directory.

Fix: redeploy one valid version.

### Case: Rollback cannot find backup

Check:

```bash
ls -la ~/.cursor-server/backups/
```

Expected: `Stable-<commit>_<timestamp>` and optional `cursor-<commit>_<timestamp>` files.

Fix: perform one successful deploy with backup enabled, then rollback.

## 7. Directory Layout

```text
~/.cursor-server/
├── cursor-<commit>
├── cache/
│   ├── cursor-cli-<commit>.tar.gz
│   └── cursor-server-<version>-<commit>.tar.gz
├── backups/
│   ├── Stable-<commit>_<timestamp>/
│   ├── cursor-<commit>_<timestamp>
│   ├── previous_version.txt
│   └── current_version.txt
└── cli/servers/
    ├── Stable-<commit>/server/
    └── Stable-current -> Stable-<commit>
```
