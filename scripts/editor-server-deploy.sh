#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${EDITOR_SERVER_MANIFEST_DIR:-$SCRIPT_DIR/../manifests/providers}"

PROVIDER="vscode-remote"
VERSION=""
COMMIT=""
CHANNEL="stable"
REMOTE_OS="${REMOTE_OS:-linux}"
REMOTE_ARCH="${REMOTE_ARCH:-x64}"
PROXY_URL="${PROXY_URL:-}"
NO_PROXY="false"
NO_BACKUP="false"
USE_CACHE="true"
YES_MODE="false"
DRY_RUN="false"
ACTION="deploy"
INSTALL_ROOT=""

MANIFEST_FILE=""
DISPLAY_NAME=""
ARTIFACT_MODE=""
REQUIRES_VERSION="false"
REQUIRES_COMMIT="false"
DEFAULT_INSTALL_ROOT=""
PRIMARY_URL_TEMPLATE=""
SECONDARY_URL_TEMPLATE=""
PRIMARY_PATH_TEMPLATE=""
SECONDARY_PATH_TEMPLATE=""
PRIMARY_CACHE_TEMPLATE=""
SECONDARY_CACHE_TEMPLATE=""
PRIMARY_EXTRACT_MODE=""
SECONDARY_EXTRACT_MODE=""
ARCH_MAP_X64="x64"
ARCH_MAP_ARM64="arm64"
CURRENT_POINTER_TEMPLATE=""
LIST_GLOB=""
POST_INSTALL_HINT_TEMPLATE=""
CURRENT_ID=""
CACHE_DIR=""
BACKUP_DIR=""
STATE_DIR=""
PRIMARY_URL=""
SECONDARY_URL=""
PRIMARY_PATH=""
SECONDARY_PATH=""
PRIMARY_CACHE=""
SECONDARY_CACHE=""
CURRENT_POINTER=""
POST_INSTALL_HINT=""

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
    print_message blue "  Editor Server Deploy Tool"
    print_separator
    printf "\n"
}

die() {
    print_message red "Error: $1"
    exit 1
}

show_help() {
    cat <<'EOF'
Usage: editor-server-deploy [options] [action]

Actions:
  (none)              Interactive deploy (default)
  --update            Print update guidance
  --rollback          Roll back to previous installed version
  --list              List installed versions for the selected provider
  --current           Show current active version for the selected provider
  --clean             Clean cache and old backups for the selected provider
  --list-providers    List supported providers from manifests

Options:
  --provider <name>       Provider name (default: vscode-remote)
  -v, --version <ver>     Product version when required by provider
  -c, --commit <hash>     Commit hash when required by provider
  -p, --proxy <URL>       Proxy URL
  -a, --arch <arch>       Target arch (x64 or arm64, default: x64)
  -o, --os <os>           Target OS (default: linux)
  -y, --yes               Skip all confirmations
  --channel <name>        Release channel (default: stable)
  --install-root <path>   Override install root
  --manifest-dir <path>   Override provider manifest directory
  --no-proxy              Disable proxy usage
  --no-backup             Skip backup before deploy
  --no-cache              Disable download cache
  --dry-run               Resolve URLs and paths without downloading
  -h, --help              Show this help

Examples:
  editor-server-deploy --provider vscode-remote -c ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb -y
  editor-server-deploy --provider vscode-remote -c ce099c1ed25d9eb3076c11e4a280f3eb52b4fbeb -p http://10.10.10.215:7897 -y
  editor-server-deploy --provider openvscode-server -v 1.105.1 -y
  editor-server-deploy --provider code-server -v 4.106.3 -a arm64 -y
  editor-server-deploy --provider vscode-remote --list
  editor-server-deploy --provider vscode-remote --rollback

Success checks:
  editor-server-deploy --provider vscode-remote --current
  ls -l ~/.vscode-server/cli/servers/Stable-current
  test -f ~/.vscode-server/cli/servers/Stable-<commit>/server/product.json && echo ok
  ls -l ~/.vscode-server/code-<commit>
EOF
}

require_value() {
    local flag="$1"
    local value="${2:-}"
    if [ -z "$value" ] || [[ "$value" == -* ]]; then
        die "Option $flag requires a value"
    fi
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
    if ! [[ "$COMMIT" =~ ^[a-f0-9]{40}$ ]]; then
        die "Invalid commit hash. Expected 40 lowercase hex chars."
    fi
}

validate_version() {
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "Invalid version '$VERSION'. Expected pattern like 1.111.0"
    fi
}

prepare_proxy() {
    if [ "$NO_PROXY" = "true" ] || [ -z "$PROXY_URL" ]; then
        PROXY_URL=""
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
        return
    fi

    print_message cyan "Checking proxy connectivity: $PROXY_URL"
    if ! curl -s --max-time 5 -x "$PROXY_URL" https://www.google.com/generate_204 >/dev/null 2>&1; then
        die "Proxy $PROXY_URL is not reachable. Use --no-proxy or provide another --proxy URL."
    fi

    export https_proxy="$PROXY_URL"
    export http_proxy="$PROXY_URL"
}

load_manifest() {
    MANIFEST_FILE="$MANIFEST_DIR/${PROVIDER}.conf"
    [ -f "$MANIFEST_FILE" ] || die "Unknown provider '$PROVIDER'. Manifest not found: $MANIFEST_FILE"

    # shellcheck disable=SC1090
    source "$MANIFEST_FILE"

    [ -n "$DISPLAY_NAME" ] || die "Manifest missing DISPLAY_NAME: $MANIFEST_FILE"
    [ -n "$ARTIFACT_MODE" ] || die "Manifest missing ARTIFACT_MODE: $MANIFEST_FILE"
    [ -n "$DEFAULT_INSTALL_ROOT" ] || die "Manifest missing DEFAULT_INSTALL_ROOT: $MANIFEST_FILE"
}

provider_arch() {
    case "$REMOTE_ARCH" in
        x64) printf "%s\n" "$ARCH_MAP_X64" ;;
        arm64) printf "%s\n" "$ARCH_MAP_ARM64" ;;
        *) die "Unsupported architecture '$REMOTE_ARCH' for provider '$PROVIDER'" ;;
    esac
}

render_template() {
    local template="$1"
    local arch_provider
    arch_provider="$(provider_arch)"

    template="${template//\{provider\}/$PROVIDER}"
    template="${template//\{version\}/$VERSION}"
    template="${template//\{commit\}/$COMMIT}"
    template="${template//\{channel\}/$CHANNEL}"
    template="${template//\{os\}/$REMOTE_OS}"
    template="${template//\{arch\}/$REMOTE_ARCH}"
    template="${template//\{provider_arch\}/$arch_provider}"
    template="${template//\{install_root\}/$INSTALL_ROOT}"
    printf "%s\n" "$template"
}

resolve_paths() {
    validate_arch
    validate_os

    if [ "$REQUIRES_COMMIT" = "true" ]; then
        validate_commit
    fi
    if [ "$REQUIRES_VERSION" = "true" ]; then
        validate_version
    fi

    if [ -z "$INSTALL_ROOT" ]; then
        INSTALL_ROOT="$DEFAULT_INSTALL_ROOT"
    fi

    CURRENT_ID="${COMMIT:-$VERSION}"
    CACHE_DIR="$INSTALL_ROOT/cache"
    BACKUP_DIR="$INSTALL_ROOT/backups"
    STATE_DIR="$INSTALL_ROOT/.deploy-state"

    PRIMARY_URL="$(render_template "$PRIMARY_URL_TEMPLATE")"
    PRIMARY_PATH="$(render_template "$PRIMARY_PATH_TEMPLATE")"
    PRIMARY_CACHE="$(render_template "$PRIMARY_CACHE_TEMPLATE")"
    CURRENT_POINTER="$(render_template "$CURRENT_POINTER_TEMPLATE")"

    if [ -n "$SECONDARY_URL_TEMPLATE" ]; then
        SECONDARY_URL="$(render_template "$SECONDARY_URL_TEMPLATE")"
    else
        SECONDARY_URL=""
    fi
    if [ -n "$SECONDARY_PATH_TEMPLATE" ]; then
        SECONDARY_PATH="$(render_template "$SECONDARY_PATH_TEMPLATE")"
    else
        SECONDARY_PATH=""
    fi
    if [ -n "$SECONDARY_CACHE_TEMPLATE" ]; then
        SECONDARY_CACHE="$(render_template "$SECONDARY_CACHE_TEMPLATE")"
    else
        SECONDARY_CACHE=""
    fi
    if [ -n "$POST_INSTALL_HINT_TEMPLATE" ]; then
        POST_INSTALL_HINT="$(render_template "$POST_INSTALL_HINT_TEMPLATE")"
    else
        POST_INSTALL_HINT=""
    fi
}

initialize_provider_dirs() {
    if [ -z "$INSTALL_ROOT" ]; then
        INSTALL_ROOT="$DEFAULT_INSTALL_ROOT"
    fi
    CACHE_DIR="$INSTALL_ROOT/cache"
    BACKUP_DIR="$INSTALL_ROOT/backups"
    STATE_DIR="$INSTALL_ROOT/.deploy-state"
}

state_file_for_id() {
    local id="$1"
    printf "%s/%s-%s.env\n" "$STATE_DIR" "$PROVIDER" "$id"
}

current_state_pointer() {
    printf "%s/current-%s\n" "$STATE_DIR" "$PROVIDER"
}

save_state() {
    mkdir -p "$STATE_DIR"
    local state_file pointer
    state_file="$(state_file_for_id "$CURRENT_ID")"
    pointer="$(current_state_pointer)"
    cat > "$state_file" <<EOF
PROVIDER='$PROVIDER'
DISPLAY_NAME='$DISPLAY_NAME'
VERSION='$VERSION'
COMMIT='$COMMIT'
INSTALL_ROOT='$INSTALL_ROOT'
PRIMARY_PATH='$PRIMARY_PATH'
SECONDARY_PATH='$SECONDARY_PATH'
CURRENT_ID='$CURRENT_ID'
CURRENT_POINTER='$CURRENT_POINTER'
EOF
    ln -sfn "$(basename "$state_file")" "$pointer"
}

load_current_state() {
    local pointer state_file
    pointer="$(current_state_pointer)"
    if [ ! -L "$pointer" ]; then
        return 1
    fi
    state_file="$STATE_DIR/$(readlink "$pointer")"
    [ -f "$state_file" ] || return 1
    # shellcheck disable=SC1090
    source "$state_file"
    return 0
}

backup_path_if_exists() {
    local src="$1"
    local dst="$2"
    if [ -z "$src" ] || [ ! -e "$src" ]; then
        return
    fi
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
}

backup_current_install() {
    local desired_version="$VERSION"
    local desired_commit="$COMMIT"
    local desired_install_root="$INSTALL_ROOT"
    local desired_current_id="$CURRENT_ID"
    local desired_primary_path="$PRIMARY_PATH"
    local desired_secondary_path="$SECONDARY_PATH"
    local desired_current_pointer="$CURRENT_POINTER"

    if [ "$NO_BACKUP" = "true" ]; then
        return
    fi
    if ! load_current_state; then
        VERSION="$desired_version"
        COMMIT="$desired_commit"
        INSTALL_ROOT="$desired_install_root"
        CURRENT_ID="$desired_current_id"
        PRIMARY_PATH="$desired_primary_path"
        SECONDARY_PATH="$desired_secondary_path"
        CURRENT_POINTER="$desired_current_pointer"
        return
    fi

    local timestamp backup_root
    timestamp="$(date +%Y%m%d_%H%M%S)"
    backup_root="$BACKUP_DIR/${PROVIDER}-${CURRENT_ID}-${timestamp}"

    print_message yellow "Backing up current install..."
    backup_path_if_exists "$PRIMARY_PATH" "$backup_root/primary"
    backup_path_if_exists "$SECONDARY_PATH" "$backup_root/secondary"

    local state_file
    state_file="$(state_file_for_id "$CURRENT_ID")"
    if [ -f "$state_file" ]; then
        mkdir -p "$backup_root"
        cp "$state_file" "$backup_root/state.env"
    fi

    mkdir -p "$BACKUP_DIR"
    printf "%s\n" "$backup_root" > "$BACKUP_DIR/previous-${PROVIDER}.txt"

    VERSION="$desired_version"
    COMMIT="$desired_commit"
    INSTALL_ROOT="$desired_install_root"
    CURRENT_ID="$desired_current_id"
    PRIMARY_PATH="$desired_primary_path"
    SECONDARY_PATH="$desired_secondary_path"
    CURRENT_POINTER="$desired_current_pointer"
}

download_file() {
    local url="$1"
    local cache_file="$2"
    local output_file="$3"

    mkdir -p "$(dirname "$cache_file")"
    if [ "$USE_CACHE" = "true" ] && [ -f "$cache_file" ]; then
        cp "$cache_file" "$output_file"
        return 0
    fi

    if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 --progress-bar "$url" -o "$output_file"; then
        return 1
    fi

    cp "$output_file" "$cache_file"
}

extract_primary() {
    local archive="$1"
    case "$PRIMARY_EXTRACT_MODE" in
        rename_code_binary)
            mkdir -p "$INSTALL_ROOT"
            tar -xzf "$archive" -C "$INSTALL_ROOT"
            [ -f "$INSTALL_ROOT/code" ] || die "Primary extraction did not produce $INSTALL_ROOT/code"
            mv "$INSTALL_ROOT/code" "$PRIMARY_PATH"
            chmod +x "$PRIMARY_PATH"
            ;;
        strip_to_dir)
            rm -rf "$PRIMARY_PATH"
            mkdir -p "$PRIMARY_PATH"
            tar -xzf "$archive" -C "$PRIMARY_PATH" --strip-components=1
            ;;
        *)
            die "Unsupported PRIMARY_EXTRACT_MODE '$PRIMARY_EXTRACT_MODE'"
            ;;
    esac
}

extract_secondary() {
    local archive="$1"
    case "$SECONDARY_EXTRACT_MODE" in
        strip_to_dir)
            rm -rf "$SECONDARY_PATH"
            mkdir -p "$SECONDARY_PATH"
            tar -xzf "$archive" -C "$SECONDARY_PATH" --strip-components=1
            ;;
        "")
            ;;
        *)
            die "Unsupported SECONDARY_EXTRACT_MODE '$SECONDARY_EXTRACT_MODE'"
            ;;
    esac
}

update_current_pointer() {
    if [ -n "$CURRENT_POINTER" ]; then
        mkdir -p "$(dirname "$CURRENT_POINTER")"
        ln -sfn "$(basename "$(dirname "$SECONDARY_PATH")")" "$CURRENT_POINTER"
    fi
}

verify_install() {
    case "$PROVIDER" in
        vscode-remote)
            [ -f "$PRIMARY_PATH" ] || die "CLI binary missing after install: $PRIMARY_PATH"
            [ -f "$SECONDARY_PATH/product.json" ] || die "Server product.json missing after install: $SECONDARY_PATH/product.json"
            ;;
        openvscode-server)
            [ -f "$PRIMARY_PATH/bin/openvscode-server" ] || die "Missing executable: $PRIMARY_PATH/bin/openvscode-server"
            ;;
        code-server)
            [ -f "$PRIMARY_PATH/bin/code-server" ] || die "Missing executable: $PRIMARY_PATH/bin/code-server"
            ;;
        *)
            [ -e "$PRIMARY_PATH" ] || die "Primary path missing after install: $PRIMARY_PATH"
            ;;
    esac
}

print_verification_summary() {
    print_message cyan "Verification summary:"
    printf "  Primary path: %s\n" "$PRIMARY_PATH"

    case "$PROVIDER" in
        vscode-remote)
            local server_version cli_check current_target
            server_version="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$SECONDARY_PATH/product.json" | head -1 | cut -d'"' -f4 || true)"
            [ -n "$server_version" ] || server_version="unknown"
            current_target="not-set"
            if [ -L "$CURRENT_POINTER" ]; then
                current_target="$(readlink "$CURRENT_POINTER")"
            fi
            if "$PRIMARY_PATH" --version >/dev/null 2>&1; then
                cli_check="ok"
            else
                cli_check="failed"
            fi
            printf "  CLI executable: %s\n" "$cli_check"
            printf "  Server version: %s\n" "$server_version"
            printf "  Current link: %s -> %s\n" "$CURRENT_POINTER" "$current_target"
            printf "  Server product.json: %s\n" "$SECONDARY_PATH/product.json"
            ;;
        openvscode-server)
            printf "  Executable: %s\n" "$PRIMARY_PATH/bin/openvscode-server"
            ;;
        code-server)
            printf "  Executable: %s\n" "$PRIMARY_PATH/bin/code-server"
            ;;
        *)
            printf "  Provider state file: %s\n" "$(state_file_for_id "$CURRENT_ID")"
            ;;
    esac
}

show_plan() {
    print_title
    print_message blue "Deploy configuration:"
    printf "  Provider: %s\n" "$PROVIDER"
    printf "  Display name: %s\n" "$DISPLAY_NAME"
    if [ -n "$VERSION" ]; then
        printf "  Version: %s\n" "$VERSION"
    fi
    if [ -n "$COMMIT" ]; then
        printf "  Commit: %s\n" "$COMMIT"
    fi
    printf "  Target: %s-%s\n" "$REMOTE_OS" "$REMOTE_ARCH"
    printf "  Install root: %s\n" "$INSTALL_ROOT"
    printf "  Proxy: %s\n" "${PROXY_URL:-none}"
    printf "  Primary URL: %s\n" "$PRIMARY_URL"
    if [ -n "$SECONDARY_URL" ]; then
        printf "  Secondary URL: %s\n" "$SECONDARY_URL"
    fi
    print_separator
    printf "  Primary path: %s\n" "$PRIMARY_PATH"
    if [ -n "$SECONDARY_PATH" ]; then
        printf "  Secondary path: %s\n" "$SECONDARY_PATH"
    fi
}

install_provider() {
    backup_current_install
    mkdir -p "$CACHE_DIR" "$STATE_DIR"

    local primary_tmp secondary_tmp
    primary_tmp="$(mktemp /tmp/editor-primary.XXXXXX.tar.gz)"
    secondary_tmp=""

    if ! download_file "$PRIMARY_URL" "$PRIMARY_CACHE" "$primary_tmp"; then
        rm -f "$primary_tmp"
        die "Failed to download primary artifact"
    fi
    extract_primary "$primary_tmp"

    if [ -n "$SECONDARY_URL" ]; then
        secondary_tmp="$(mktemp /tmp/editor-secondary.XXXXXX.tar.gz)"
        if ! download_file "$SECONDARY_URL" "$SECONDARY_CACHE" "$secondary_tmp"; then
            rm -f "$primary_tmp" "$secondary_tmp"
            die "Failed to download secondary artifact"
        fi
        extract_secondary "$secondary_tmp"
    fi

    rm -f "$primary_tmp"
    if [ -n "$secondary_tmp" ]; then
        rm -f "$secondary_tmp"
    fi

    verify_install
    update_current_pointer
    save_state
}

show_current() {
    initialize_provider_dirs
    if ! load_current_state; then
        print_message yellow "No current version is set for provider '$PROVIDER'"
        return 0
    fi
    print_message green "Current provider state:"
    if [ -n "${VERSION:-}" ]; then
        printf "  Version: %s\n" "$VERSION"
    fi
    if [ -n "${COMMIT:-}" ]; then
        printf "  Commit: %s\n" "$COMMIT"
    fi
    printf "  Primary path: %s\n" "$PRIMARY_PATH"
    if [ -n "${SECONDARY_PATH:-}" ]; then
        printf "  Secondary path: %s\n" "$SECONDARY_PATH"
    fi
}

list_installed_versions() {
    initialize_provider_dirs
    print_title
    print_message cyan "Installed versions for provider '$PROVIDER':"

    local found="false"
    case "$PROVIDER" in
        vscode-remote)
            local current_id current_link dir version_file version commit
            current_id=""
            if load_current_state; then
                current_id="$CURRENT_ID"
            fi
            for dir in "$INSTALL_ROOT"/cli/servers/Stable-*; do
                [ -d "$dir" ] || continue
                [ "$(basename "$dir")" = "Stable-current" ] && continue
                commit="${dir##*/Stable-}"
                version_file="$dir/server/product.json"
                version="unknown"
                if [ -f "$version_file" ]; then
                    version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$version_file" | head -1 | cut -d'"' -f4 || true)
                    [ -n "$version" ] || version="unknown"
                fi
                printf "  Version: %s\n" "$version"
                printf "  Commit: %s" "$commit"
                if [ "$commit" = "$current_id" ]; then
                    printf " [current]"
                fi
                printf "\n  Path: %s\n\n" "$dir"
                found="true"
            done
            ;;
        openvscode-server|code-server)
            local current_version dir name
            current_version=""
            if load_current_state; then
                current_version="$CURRENT_ID"
            fi
            for dir in "$INSTALL_ROOT"/"$PROVIDER"/*; do
                [ -d "$dir" ] || continue
                name="$(basename "$dir")"
                printf "  Release: %s" "$name"
                if [[ "$name" == *"$current_version"* ]]; then
                    printf " [current]"
                fi
                printf "\n  Path: %s\n\n" "$dir"
                found="true"
            done
            ;;
    esac

    if [ "$found" != "true" ]; then
        print_message yellow "No installed versions found"
    fi
}

rollback_to_previous() {
    initialize_provider_dirs
    local previous_file backup_root
    previous_file="$BACKUP_DIR/previous-${PROVIDER}.txt"
    [ -f "$previous_file" ] || die "No previous backup record found for provider '$PROVIDER'"
    backup_root="$(cat "$previous_file")"
    [ -d "$backup_root" ] || die "Backup directory not found: $backup_root"

    if [ "$YES_MODE" != "true" ]; then
        read -r -p "Proceed with rollback for provider '$PROVIDER'? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_message cyan "Cancelled"
            exit 0
        fi
    fi

    if [ -f "$backup_root/state.env" ]; then
        # shellcheck disable=SC1090
        source "$backup_root/state.env"
        if [ -e "$backup_root/primary" ]; then
            rm -rf "$PRIMARY_PATH"
            mkdir -p "$(dirname "$PRIMARY_PATH")"
            cp -R "$backup_root/primary" "$PRIMARY_PATH"
        fi
        if [ -n "$SECONDARY_PATH" ] && [ -e "$backup_root/secondary" ]; then
            rm -rf "$SECONDARY_PATH"
            mkdir -p "$(dirname "$SECONDARY_PATH")"
            cp -R "$backup_root/secondary" "$SECONDARY_PATH"
        fi
        mkdir -p "$STATE_DIR"
        cp "$backup_root/state.env" "$(state_file_for_id "$CURRENT_ID")"
        ln -sfn "$(basename "$(state_file_for_id "$CURRENT_ID")")" "$(current_state_pointer)"
        if [ -n "$CURRENT_POINTER" ]; then
            mkdir -p "$(dirname "$CURRENT_POINTER")"
            if [ -n "$SECONDARY_PATH" ]; then
                ln -sfn "$(basename "$(dirname "$SECONDARY_PATH")")" "$CURRENT_POINTER"
            fi
        fi
    fi

    print_message green "Rollback completed"
}

clean_cache() {
    initialize_provider_dirs
    print_title
    print_message yellow "Cleaning cache and old backups for provider '$PROVIDER'..."
    local cleaned="false"

    if [ -d "$CACHE_DIR" ]; then
        find "$CACHE_DIR" -mindepth 1 -delete
        print_message green "Removed cache files"
        cleaned="true"
    fi

    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -maxdepth 1 -type d -name "${PROVIDER}-*" | sort -r | tail -n +4 | while IFS= read -r d; do
            rm -rf "$d"
        done
        print_message green "Kept latest 3 backup generations"
        cleaned="true"
    fi

    if [ "$cleaned" != "true" ]; then
        print_message cyan "Nothing to clean"
    fi
}

list_providers() {
    print_title
    print_message cyan "Supported providers:"
    local manifest
    for manifest in "$MANIFEST_DIR"/*.conf; do
        [ -f "$manifest" ] || continue
        local provider_name
        provider_name="$(basename "$manifest" .conf)"
        DISPLAY_NAME=""
        # shellcheck disable=SC1090
        source "$manifest"
        printf "  %s\n" "$provider_name"
        printf "    %s\n" "$DISPLAY_NAME"
    done
}

prompt_missing_values() {
    print_title
    print_message yellow "Please enter provider details"
    printf "  Provider: %s\n" "$PROVIDER"
    if [ "$REQUIRES_VERSION" = "true" ] && [ -z "$VERSION" ]; then
        read -r -p "Version (example: 1.111.0): " VERSION
    fi
    if [ "$REQUIRES_COMMIT" = "true" ] && [ -z "$COMMIT" ]; then
        read -r -p "Commit (40-char hash): " COMMIT
    fi
}

ensure_required_inputs() {
    if [ "$REQUIRES_VERSION" = "true" ] && [ -z "$VERSION" ]; then
        if [ "$DRY_RUN" = "true" ] || [ "$YES_MODE" = "true" ]; then
            validate_version
        fi
    fi

    if [ "$REQUIRES_COMMIT" = "true" ] && [ -z "$COMMIT" ]; then
        if [ "$DRY_RUN" = "true" ] || [ "$YES_MODE" = "true" ]; then
            validate_commit
        fi
    fi

    if { [ "$REQUIRES_VERSION" = "true" ] && [ -z "$VERSION" ]; } || { [ "$REQUIRES_COMMIT" = "true" ] && [ -z "$COMMIT" ]; }; then
        prompt_missing_values
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --provider)
                require_value "$1" "${2:-}"
                PROVIDER="$2"
                shift 2
                ;;
            -v|--version)
                require_value "$1" "${2:-}"
                VERSION="$2"
                shift 2
                ;;
            -c|--commit)
                require_value "$1" "${2:-}"
                COMMIT="$2"
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
            --channel)
                require_value "$1" "${2:-}"
                CHANNEL="$2"
                shift 2
                ;;
            --install-root)
                require_value "$1" "${2:-}"
                INSTALL_ROOT="$2"
                shift 2
                ;;
            --manifest-dir)
                require_value "$1" "${2:-}"
                MANIFEST_DIR="$2"
                shift 2
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
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -y|--yes)
                YES_MODE="true"
                shift
                ;;
            -h|--help)
                ACTION="help"
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
            --list-providers)
                ACTION="list-providers"
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    case "$ACTION" in
        help)
            show_help
            exit 0
            ;;
        list-providers)
            list_providers
            exit 0
            ;;
    esac

    load_manifest
    prepare_proxy

    case "$ACTION" in
        list)
            list_installed_versions
            exit 0
            ;;
        current)
            show_current
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
            print_message yellow "Update requires provider-specific version details."
            print_message cyan "Use: editor-server-deploy --provider <name> -v <version> -c <commit>"
            exit 0
            ;;
    esac

    ensure_required_inputs

    resolve_paths
    show_plan

    if [ "$DRY_RUN" = "true" ]; then
        exit 0
    fi

    if [ "$YES_MODE" != "true" ]; then
        read -r -p "Continue with install? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_message cyan "Cancelled"
            exit 0
        fi
    fi

    install_provider
    print_separator
    print_message green "Deployment completed successfully"
    print_separator
    printf "  Provider: %s\n" "$PROVIDER"
    printf "  Primary path: %s\n" "$PRIMARY_PATH"
    if [ -n "$SECONDARY_PATH" ]; then
        printf "  Secondary path: %s\n" "$SECONDARY_PATH"
    fi
    print_verification_summary
    if [ -n "$POST_INSTALL_HINT" ]; then
        printf "  Hint: %s\n" "$POST_INSTALL_HINT"
    fi
}

main "$@"
