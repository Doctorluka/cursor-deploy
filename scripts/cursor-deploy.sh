#!/usr/bin/env bash

set -euo pipefail

CURSOR_HOME="${CURSOR_HOME:-$HOME/.cursor-server}"
CURSOR_VERSIONS_DIR="$CURSOR_HOME/cli/servers"
BACKUP_DIR="$CURSOR_HOME/backups"
DOWNLOAD_CACHE_DIR="$CURSOR_HOME/cache"

REMOTE_ARCH="${REMOTE_ARCH:-x64}"
REMOTE_OS="${REMOTE_OS:-linux}"

CURSOR_VERSION=""
CURSOR_COMMIT=""
PROXY_URL="${PROXY_URL:-}"
NO_PROXY="false"
NO_BACKUP="false"
USE_CACHE="true"
YES_MODE="false"
ACTION="deploy"

print_message() {
    local color="$1"
    local message="$2"
    case "$color" in
        green)  printf "\033[0;32m%s\033[0m\n" "$message" ;;
        red)    printf "\033[0;31m%s\033[0m\n" "$message" ;;
        yellow) printf "\033[0;33m%s\033[0m\n" "$message" ;;
        blue)   printf "\033[0;34m%s\033[0m\n" "$message" ;;
        cyan)   printf "\033[0;36m%s\033[0m\n" "$message" ;;
        *)      printf "%s\n" "$message" ;;
    esac
}

print_separator() {
    printf "==========================================\n"
}

print_title() {
    printf "\n"
    print_separator
    print_message blue "  Cursor Remote Server Deploy Tool"
    print_separator
    printf "\n"
}

die() {
    print_message red "Error: $1"
    exit 1
}

validate_arch() {
    case "$REMOTE_ARCH" in
        x64|arm64) ;;
        *) die "Invalid architecture '$REMOTE_ARCH'. Supported: x64, arm64" ;;
    esac
}

validate_os() {
    case "$REMOTE_OS" in
        linux) ;;
        *) die "Invalid OS '$REMOTE_OS'. Supported: linux" ;;
    esac
}

validate_commit() {
    if ! [[ "$CURSOR_COMMIT" =~ ^[a-f0-9]{40}$ ]]; then
        die "Invalid commit hash. Expected 40 lowercase hex chars."
    fi
}

validate_version() {
    if ! [[ "$CURSOR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "Invalid version '$CURSOR_VERSION'. Expected pattern like 2.5.25"
    fi
}

require_value() {
    local flag="$1"
    local value="${2:-}"
    if [ -z "$value" ] || [[ "$value" == -* ]]; then
        die "Option $flag requires a value"
    fi
}

get_current_version() {
    local current_link
    if [ -L "$CURSOR_VERSIONS_DIR/Stable-current" ]; then
        current_link=$(readlink "$CURSOR_VERSIONS_DIR/Stable-current")
        if [[ "$current_link" =~ Stable-([a-f0-9]{40}) ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return
        fi
    fi
    printf '\n'
}

list_installed_versions() {
    print_title
    print_message cyan "Installed Cursor Server versions:"
    printf "\n"

    if [ ! -d "$CURSOR_VERSIONS_DIR" ]; then
        print_message yellow "No installed versions found"
        return
    fi

    local current
    current=$(get_current_version)
    local count=0

    for dir in "$CURSOR_VERSIONS_DIR"/Stable-*; do
        [ -d "$dir" ] || continue
        local base commit version_file version marker
        base=$(basename "$dir")
        [ "$base" = "Stable-current" ] && continue
        commit="${base#Stable-}"
        version_file="$dir/server/product.json"
        version="unknown"

        if [ -f "$version_file" ]; then
            version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$version_file" | head -1 | cut -d'"' -f4 || true)
            [ -n "$version" ] || version="unknown"
        fi

        marker=""
        if [ "$commit" = "$current" ]; then
            marker=" [current]"
        fi

        printf "  Version: %s\n" "$version"
        printf "  Commit: %s%s\n" "$commit" "$marker"
        printf "  Path: %s\n\n" "$dir"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        print_message yellow "No installed versions found"
    else
        print_message green "Found $count version(s)"
    fi
}

get_version_info_interactive() {
    print_title
    print_message yellow "Please enter Cursor version details"
    print_message cyan "  (Cursor -> Help -> About)"
    printf "\n"

    read -r -p "Version (example: 2.5.25): " CURSOR_VERSION
    read -r -p "Commit (40-char hash): " CURSOR_COMMIT

    [ -n "$CURSOR_VERSION" ] || die "Version cannot be empty"
    [ -n "$CURSOR_COMMIT" ] || die "Commit cannot be empty"
}

prepare_proxy() {
    if [ "$NO_PROXY" = "true" ] || [ -z "$PROXY_URL" ]; then
        PROXY_URL=""
        return
    fi

    if [ -n "$PROXY_URL" ]; then
        print_message cyan "Checking proxy connectivity: $PROXY_URL"
        if ! curl -s --max-time 5 -x "$PROXY_URL" https://www.google.com/generate_204 >/dev/null 2>&1; then
            die "Proxy $PROXY_URL is not reachable. Use --no-proxy or provide another --proxy URL."
        fi
        export https_proxy="$PROXY_URL"
        export http_proxy="$PROXY_URL"
        print_message green "Proxy is reachable"
    fi
}

backup_current_version() {
    local current_commit
    current_commit=$(get_current_version)

    [ -n "$current_commit" ] || return
    [ -d "$CURSOR_VERSIONS_DIR/Stable-$current_commit" ] || return

    mkdir -p "$BACKUP_DIR"

    local timestamp backup_name
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_name="Stable-${current_commit}_${timestamp}"

    print_message yellow "Backing up current version..."
    cp -r "$CURSOR_VERSIONS_DIR/Stable-$current_commit" "$BACKUP_DIR/$backup_name"

    # Also back up matching CLI component when present.
    if [ -f "$CURSOR_HOME/cursor-$current_commit" ]; then
        cp "$CURSOR_HOME/cursor-$current_commit" "$BACKUP_DIR/cursor-${current_commit}_${timestamp}"
    fi

    printf '%s\n' "$current_commit" > "$BACKUP_DIR/previous_version.txt"
    printf '%s\n' "$current_commit" > "$BACKUP_DIR/current_version.txt"

    print_message green "Backup created: $backup_name"
}

set_current_symlink() {
    local commit="$1"
    mkdir -p "$CURSOR_VERSIONS_DIR" "$BACKUP_DIR"
    ln -sfn "Stable-$commit" "$CURSOR_VERSIONS_DIR/Stable-current"
    printf '%s\n' "$commit" > "$BACKUP_DIR/current_version.txt"
}

download_file() {
    local url="$1"
    local cache_file="$2"
    local output_file="$3"

    if [ -f "$cache_file" ] && [ "$USE_CACHE" = "true" ]; then
        cp "$cache_file" "$output_file"
        return 0
    fi

    if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 --progress-bar "$url" -o "$output_file"; then
        return 1
    fi

    cp "$output_file" "$cache_file"
    return 0
}

deploy_cursor_server() {
    print_title

    print_message blue "Deploy configuration:"
    printf "  Version: %s\n" "$CURSOR_VERSION"
    printf "  Commit: %s\n" "$CURSOR_COMMIT"
    printf "  Target: %s-%s\n" "$REMOTE_OS" "$REMOTE_ARCH"
    printf "  Proxy: %s\n" "${PROXY_URL:-none}"
    print_separator
    printf "\n"

    local target_dir cli_path
    target_dir="$CURSOR_VERSIONS_DIR/Stable-$CURSOR_COMMIT"
    cli_path="$CURSOR_HOME/cursor-$CURSOR_COMMIT"

    if [ -d "$target_dir/server" ] && [ -f "$cli_path" ]; then
        print_message yellow "Version already installed"
        printf "  Server: %s\n" "$target_dir/server"
        printf "  CLI: %s\n" "$cli_path"

        if [ "$YES_MODE" != "true" ]; then
            read -r -p "Reinstall this version? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                print_message cyan "Cancelled"
                return
            fi
        fi

        rm -rf "$target_dir"
        rm -f "$cli_path"
    fi

    if [ "$NO_BACKUP" != "true" ]; then
        backup_current_version
    fi

    mkdir -p "$target_dir/server" "$DOWNLOAD_CACHE_DIR" "$BACKUP_DIR"

    local cli_url server_url
    cli_url="https://cursor.blob.core.windows.net/remote-releases/${CURSOR_COMMIT}/cli-alpine-${REMOTE_ARCH}.tar.gz"
    server_url="https://cursor.blob.core.windows.net/remote-releases/${CURSOR_VERSION}-${CURSOR_COMMIT}/vscode-reh-${REMOTE_OS}-${REMOTE_ARCH}.tar.gz"

    local cli_cache server_cache
    cli_cache="$DOWNLOAD_CACHE_DIR/cursor-cli-${CURSOR_COMMIT}.tar.gz"
    server_cache="$DOWNLOAD_CACHE_DIR/cursor-server-${CURSOR_VERSION}-${CURSOR_COMMIT}.tar.gz"

    local cli_tmp server_tmp
    cli_tmp=$(mktemp /tmp/cursor-cli.XXXXXX.tar.gz)
    server_tmp=$(mktemp /tmp/cursor-server.XXXXXX.tar.gz)

    print_message yellow "Downloading CLI component..."
    printf "  URL: %s\n" "$cli_url"
    if ! download_file "$cli_url" "$cli_cache" "$cli_tmp"; then
        rm -f "$cli_tmp" "$server_tmp"
        die "CLI download failed"
    fi

    print_message yellow "Installing CLI component..."
    tar -xzf "$cli_tmp" -C "$CURSOR_HOME"
    if [ -f "$CURSOR_HOME/cursor" ]; then
        mv "$CURSOR_HOME/cursor" "$cli_path"
    fi
    [ -f "$cli_path" ] || die "CLI install failed"
    chmod +x "$cli_path"

    print_message yellow "Downloading server component..."
    printf "  URL: %s\n" "$server_url"
    if ! download_file "$server_url" "$server_cache" "$server_tmp"; then
        rm -f "$cli_tmp" "$server_tmp"
        die "Server download failed"
    fi

    print_message yellow "Installing server component..."
    tar -xzf "$server_tmp" -C "$target_dir/server" --strip-components=1

    rm -f "$cli_tmp" "$server_tmp"

    local verify_errors
    verify_errors=0

    if [ ! -f "$target_dir/server/product.json" ]; then
        print_message red "Server verification failed: product.json missing"
        verify_errors=1
    fi

    if ! "$cli_path" --version >/dev/null 2>&1; then
        print_message red "CLI verification failed: executable check failed"
        verify_errors=1
    fi

    if [ "$verify_errors" -ne 0 ]; then
        die "Deployment verification failed"
    fi

    set_current_symlink "$CURSOR_COMMIT"

    print_separator
    print_message green "Deployment completed successfully"
    print_separator
    printf "  CLI: %s\n" "$cli_path"
    printf "  Server: %s\n" "$target_dir/server"
    printf "  Current commit: %s\n" "$CURSOR_COMMIT"
}

rollback_to_previous() {
    print_title

    local previous_file previous_commit
    previous_file="$BACKUP_DIR/previous_version.txt"

    [ -f "$previous_file" ] || die "No previous version record found"
    previous_commit=$(cat "$previous_file")
    [ -n "$previous_commit" ] || die "Previous version record is empty"

    local server_backup
    server_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "Stable-${previous_commit}_*" | sort -r | head -1)
    [ -n "$server_backup" ] || die "No server backup found for commit $previous_commit"

    local cli_backup
    cli_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "cursor-${previous_commit}_*" | sort -r | head -1 || true)

    print_message yellow "Rollback target commit: $previous_commit"
    print_message cyan "Server backup: $server_backup"
    if [ -n "$cli_backup" ]; then
        print_message cyan "CLI backup: $cli_backup"
    else
        print_message yellow "CLI backup not found for commit $previous_commit"
    fi

    if [ "$YES_MODE" != "true" ]; then
        read -r -p "Proceed with rollback? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_message cyan "Cancelled"
            return
        fi
    fi

    local target_dir target_cli
    target_dir="$CURSOR_VERSIONS_DIR/Stable-$previous_commit"
    target_cli="$CURSOR_HOME/cursor-$previous_commit"

    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    cp -r "$server_backup"/* "$target_dir/"

    if [ -n "$cli_backup" ]; then
        cp "$cli_backup" "$target_cli"
        chmod +x "$target_cli"
    fi

    set_current_symlink "$previous_commit"

    print_separator
    print_message green "Rollback completed"
    print_separator
    printf "  Commit: %s\n" "$previous_commit"
    printf "  Server: %s\n" "$target_dir/server"
    if [ -f "$target_cli" ]; then
        printf "  CLI: %s\n" "$target_cli"
    fi
}

clean_cache() {
    print_title
    print_message yellow "Cleaning cache and old backups..."

    local cleaned
    cleaned=0

    if [ -d "$DOWNLOAD_CACHE_DIR" ]; then
        local cache_size
        cache_size=$(du -sh "$DOWNLOAD_CACHE_DIR" 2>/dev/null | cut -f1 || printf '0')
        find "$DOWNLOAD_CACHE_DIR" -mindepth 1 -delete
        print_message green "Removed download cache: $cache_size"
        cleaned=1
    fi

    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -maxdepth 1 -type d -name 'Stable-*_*' | sort -r | tail -n +4 | while IFS= read -r d; do
            rm -rf "$d"
        done
        find "$BACKUP_DIR" -maxdepth 1 -type f -name 'cursor-*_*' | sort -r | tail -n +4 | while IFS= read -r f; do
            rm -f "$f"
        done
        print_message green "Kept latest 3 backup generations"
        cleaned=1
    fi

    if [ "$cleaned" -eq 0 ]; then
        print_message cyan "Nothing to clean"
    fi
}

show_help() {
    cat <<'EOF'
Usage: cursor-deploy [options] [action]

Actions:
  (none)            Interactive deploy (default)
  --update          Print update guidance
  --rollback        Roll back to previous version
  --list            List installed versions
  --current         Show current active commit
  --clean           Clean cache and old backups

Options:
  -v, --version <version>   Cursor version (example: 2.5.25)
  -c, --commit <hash>       Commit hash (40-char lowercase hex)
  -p, --proxy <URL>         Proxy URL (example: http://127.0.0.1:7899)
  -a, --arch <arch>         Target arch: x64 or arm64 (default: x64)
  -o, --os <os>             Target OS: linux (default: linux)
  -y, --yes                 Skip confirmations (non-interactive)
  --no-proxy                Disable proxy usage
  --no-backup               Skip backup before deploy
  --no-cache                Disable download cache
  -h, --help                Show this help

Examples:
  cursor-deploy
  cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0
  cursor-deploy -v 2.5.25 -c 7150844152b426ed50d2b68dd6b33b5c5beb73c0 -p http://127.0.0.1:7899 -y
  cursor-deploy --list
  cursor-deploy --rollback
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -v|--version)
                require_value "$1" "${2:-}"
                CURSOR_VERSION="$2"
                shift 2
                ;;
            -c|--commit)
                require_value "$1" "${2:-}"
                CURSOR_COMMIT="$2"
                shift 2
                ;;
            -p|--proxy)
                require_value "$1" "${2:-}"
                PROXY_URL="$2"
                shift 2
                ;;
            -a|--arch)
                require_value "$1" "${2:-}"
                REMOTE_ARCH="$2"
                shift 2
                ;;
            -o|--os)
                require_value "$1" "${2:-}"
                REMOTE_OS="$2"
                shift 2
                ;;
            -y|--yes)
                YES_MODE="true"
                shift
                ;;
            --no-proxy)
                NO_PROXY="true"
                shift
                ;;
            --no-backup)
                NO_BACKUP="true"
                shift
                ;;
            --no-cache)
                USE_CACHE="false"
                shift
                ;;
            --list)
                ACTION="list"
                shift
                ;;
            --current)
                ACTION="current"
                shift
                ;;
            --rollback)
                ACTION="rollback"
                shift
                ;;
            --clean)
                ACTION="clean"
                shift
                ;;
            --update)
                ACTION="update"
                shift
                ;;
            -h|--help)
                ACTION="help"
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

main() {
    local current

    parse_args "$@"

    case "$ACTION" in
        help)
            show_help
            exit 0
            ;;
        list)
            list_installed_versions
            exit 0
            ;;
        current)
            current=$(get_current_version)
            if [ -n "$current" ]; then
                print_message green "Current commit: $current"
            else
                print_message yellow "No current version is set"
            fi
            exit 0
            ;;
        rollback)
            rollback_to_previous
            exit 0
            ;;
        clean)
            clean_cache
            exit 0
            ;;
        update)
            print_message yellow "Update requires version details from Cursor -> Help -> About"
            print_message cyan "Use: cursor-deploy -v <version> -c <commit>"
            exit 0
            ;;
        deploy)
            ;;
        *)
            die "Unsupported action: $ACTION"
            ;;
    esac

    validate_arch
    validate_os

    if [ -z "$CURSOR_VERSION" ] || [ -z "$CURSOR_COMMIT" ]; then
        get_version_info_interactive
    fi

    validate_version
    validate_commit

    printf "\n"
    print_message yellow "About to deploy Cursor Server $CURSOR_VERSION ($CURSOR_COMMIT)"

    if [ "$YES_MODE" != "true" ]; then
        read -r -p "Continue? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_message cyan "Cancelled"
            exit 0
        fi
    fi

    prepare_proxy
    deploy_cursor_server

    printf "\n"
    print_message green "Done"
    print_message cyan "You can now reconnect from Cursor Remote-SSH"
}

main "$@"
