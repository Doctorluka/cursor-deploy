#!/bin/bash

# =========================================================
# Cursor Remote Server 自动部署脚本
#
# 功能:
# - 自动下载并安装 CLI 客户端和服务器两个组件
# - 自动获取版本信息 (手动输入或自动检测)
# - 支持代理下载
# - 支持版本更新和回滚
# - 自动备份旧版本
#
# 重要: Cursor 远程连接需要两个独立的压缩包:
#   1. CLI 客户端: {COMMIT}/cli-alpine-{ARCH}.tar.gz
#      → 解压到 ~/.cursor-server/cursor-{COMMIT}
#   2. 服务器: {VERSION}-{COMMIT}/vscode-reh-{OS}-{ARCH}.tar.gz
#      → 解压到 cli/servers/Stable-{COMMIT}/server/
#
# 使用方法:
#   cursor-deploy                              # 交互式输入版本
#   cursor-deploy -v 2.4.21 -c dc8361355d...  # 指定版本部署
#   cursor-deploy --list                       # 列出已安装版本
#   cursor-deploy --rollback                   # 回滚到上一版本
#   cursor-deploy --clean                      # 清理缓存
#
# 来源: 参考 ShayS (Cursor Forum) 和 Arthals 的脚本
# 日期: 2026-01-26
# 更新: 添加 CLI 客户端下载功能
# =========================================================

set -e

# ==================== 配置区 ====================
# 默认配置
CURSOR_HOME="${CURSOR_HOME:-$HOME/.cursor-server}"
CURSOR_VERSIONS_DIR="$CURSOR_HOME/cli/servers"
BACKUP_DIR="$CURSOR_HOME/backups"
DOWNLOAD_CACHE_DIR="$CURSOR_HOME/cache"

# ==================== 代理配置 ====================
# 优先级: 命令行 -p > 环境变量 $PROXY_URL > 自动检测 mihomo > 默认值
#
# 方式 1: 环境变量 (在 ~/.zshrc 中设置)
#   export PROXY_URL="http://127.0.0.1:7899"
#
# 方式 2: 命令行参数
#   cursor-deploy -p http://127.0.0.1:8080
#
# 方式 3: 自动检测 mihomo (如果可用)
#   脚本会自动查找 ~/.config/mihomo/config.yaml 中的 mixed-port
#
# 方式 4: 默认值 (7899)
#   如果以上都没有，使用 mihomo 默认端口

# 自动检测 mihomo 端口
detect_mihomo_port() {
    local config_file="$HOME/.config/mihomo/config.yaml"
    if [ -f "$config_file" ]; then
        local port=$(grep "mixed-port:" "$config_file" | awk '{print $2}')
        if [ -n "$port" ]; then
            echo "http://127.0.0.1:$port"
            return
        fi
    fi
    echo "http://127.0.0.1:7899"  # mihomo 默认端口
}

# 代理配置 (可通过 --proxy 覆盖)
if [ -z "$PROXY_URL" ]; then
    PROXY_URL="$(detect_mihomo_port)"
fi

# 架构配置
REMOTE_ARCH="${REMOTE_ARCH:-x64}"     # x64 或 arm64
REMOTE_OS="${REMOTE_OS:-linux}"       # 通常是 linux

# ==================== 颜色输出 ====================
print_message() {
    local color=$1 message=$2
    case $color in
        "green")  echo -e "\033[0;32m$message\033[0m" ;;
        "red")    echo -e "\033[0;31m$message\033[0m" ;;
        "yellow") echo -e "\033[0;33m$message\033[0m" ;;
        "blue")   echo -e "\033[0;34m$message\033[0m" ;;
        "cyan")   echo -e "\033[0;36m$message\033[0m" ;;
        *)        echo "$message" ;;
    esac
}

# ==================== 工具函数 ====================

# 打印分隔线
print_separator() {
    echo "=========================================="
}

# 打印标题
print_title() {
    echo ""
    print_separator
    print_message "blue" "  Cursor Remote Server 部署工具"
    print_separator
    echo ""
}

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 [选项] [操作]

操作:
  (无)              交互式部署 (默认)
  --update          更新到最新版本 (需要从 Cursor 获取版本信息)
  --rollback        回滚到上一版本
  --list            列出已安装的版本
  --current         显示当前激活的版本
  --clean           清理缓存和备份

选项:
  -v, --version <版本>      Cursor 版本号 (例如: 2.3.41)
  -c, --commit <hash>      Commit 哈希 (例如: 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30)
  -p, --proxy <URL>        代理地址 (例如: http://127.0.0.1:7899)
  -a, --arch <架构>        目标架构 (x64 或 arm64，默认: x64)
  -o, --os <系统>          目标系统 (默认: linux)
  --no-proxy               禁用代理
  --no-backup              不备份旧版本
  -h, --help               显示此帮助信息

示例:
  # 交互式部署
  $0

  # 指定版本部署
  $0 -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30

  # 使用代理部署
  $0 -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30 -p http://127.0.0.1:7899

  # 列出已安装版本
  $0 --list

  # 回滚到上一版本
  $0 --rollback

版本信息获取:
  在 Cursor 中: Help -> About
  或查看: https://github.com/getcursor/cursor/releases

EOF
    exit 0
}

# ==================== 版本管理函数 ====================

# 获取当前激活的版本
get_current_version() {
    if [ -L "$CURSOR_HOME/cli/servers/Stable-current" ]; then
        current_link=$(readlink "$CURSOR_HOME/cli/servers/Stable-current")
        if [[ $current_link =~ Stable-([a-f0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    fi
    echo ""
}

# 列出已安装的版本
list_installed_versions() {
    print_title
    print_message "cyan" "已安装的 Cursor Server 版本:"
    echo ""

    if [ ! -d "$CURSOR_VERSIONS_DIR" ]; then
        print_message "yellow" "未找到任何已安装的版本"
        return
    fi

    local current=$(get_current_version)
    local count=0

    for dir in "$CURSOR_VERSIONS_DIR"/Stable-*; do
        if [ -d "$dir" ]; then
            local basename=$(basename "$dir")
            local commit="${basename#Stable-}"
            local version_file="$dir/server/product.json"

            if [ -f "$version_file" ]; then
                local version=$(grep -o '"version":[^,]*' "$version_file" | cut -d'"' -f4 | tr -d ' ')
            else
                local version="未知"
            fi

            local marker=""
            if [ "$commit" = "$current" ]; then
                marker=" $(print_message 'green' '[当前]')"
            fi

            echo "  版本: $version"
            echo "  Commit: $commit$marker"
            echo "  路径: $dir"
            echo ""
            count=$((count + 1))
        fi
    done

    if [ $count -eq 0 ]; then
        print_message "yellow" "未找到任何已安装的版本"
    else
        print_message "green" "共找到 $count 个版本"
    fi
}

# 获取版本信息 (交互式)
get_version_info_interactive() {
    print_title
    print_message "yellow" "请输入 Cursor 版本信息:"
    print_message "cyan" "  (在 Cursor 中: Help -> About 查看)"
    echo ""

    read -p "版本号 (例如: 2.3.41): " input_version
    read -p "Commit 哈希 (例如: 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30): " input_commit

    if [ -z "$input_version" ] || [ -z "$input_commit" ]; then
        print_message "red" "错误: 版本号和 Commit 不能为空"
        exit 1
    fi

    CURSOR_VERSION="$input_version"
    CURSOR_COMMIT="$input_commit"
}

# ==================== 部署函数 ====================

# 备份当前版本
backup_current_version() {
    local current_commit=$(get_current_version)

    if [ -n "$current_commit" ] && [ -d "$CURSOR_VERSIONS_DIR/Stable-$current_commit" ]; then
        print_message "yellow" "备份当前版本..."
        mkdir -p "$BACKUP_DIR"

        local backup_name="Stable-${current_commit}_$(date +%Y%m%d_%H%M%S)"
        if [ -d "$BACKUP_DIR/$backup_name" ]; then
            print_message "cyan" "备份已存在: $backup_name"
        else
            cp -r "$CURSOR_VERSIONS_DIR/Stable-$current_commit" "$BACKUP_DIR/$backup_name"
            print_message "green" "备份完成: $backup_name"
        fi

        # 记录当前版本
        echo "$current_commit" > "$BACKUP_DIR/previous_version.txt"
    fi
}

# 部署 Cursor Server（包括 CLI 客户端和服务器）
deploy_cursor_server() {
    print_title

    print_message "blue" "部署配置:"
    echo "  版本: $CURSOR_VERSION"
    echo "  Commit: $CURSOR_COMMIT"
    echo "  架构: ${REMOTE_OS}-${REMOTE_ARCH}"
    echo "  代理: ${PROXY_URL:-无}"
    print_separator
    echo ""

    # 检查是否已安装
    local target_dir="$CURSOR_VERSIONS_DIR/Stable-${CURSOR_COMMIT}"
    local cli_path="$CURSOR_HOME/cursor-${CURSOR_COMMIT}"

    if [ -d "$target_dir/server" ] && [ -f "$cli_path" ]; then
        print_message "yellow" "此版本已安装:"
        echo "  服务器: $target_dir/server"
        echo "  CLI: $cli_path"
        read -p "是否重新安装? [y/N]: " -r confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            print_message "cyan" "操作已取消"
            return
        fi
        print_message "yellow" "删除旧版本..."
        rm -rf "$target_dir"
        rm -f "$cli_path"
    fi

    # 备份当前版本
    if [ "$NO_BACKUP" != "true" ]; then
        backup_current_version
    fi

    # 创建目录
    print_message "yellow" "创建目录..."
    mkdir -p "$target_dir/server"
    mkdir -p "$DOWNLOAD_CACHE_DIR"

    # 设置代理
    if [ -n "$PROXY_URL" ] && [ "$NO_PROXY" != "true" ]; then
        export https_proxy="$PROXY_URL"
        export http_proxy="$PROXY_URL"
        print_message "cyan" "使用代理: $PROXY_URL"
    fi

    # ==================== 下载并安装 CLI 客户端 ====================
    print_message "yellow" "下载 CLI 客户端..."
    local cli_url="https://cursor.blob.core.windows.net/remote-releases/${CURSOR_COMMIT}/cli-alpine-${REMOTE_ARCH}.tar.gz"
    local cli_cache="$DOWNLOAD_CACHE_DIR/cursor-cli-${CURSOR_COMMIT}.tar.gz"
    echo "  URL: $cli_url"

    if [ -f "$cli_cache" ] && [ "$USE_CACHE" != "false" ]; then
        print_message "cyan" "使用缓存文件..."
        cp "$cli_cache" /tmp/cursor-cli.tar.gz
    else
        if curl -L --progress-bar "$cli_url" -o /tmp/cursor-cli.tar.gz; then
            cp /tmp/cursor-cli.tar.gz "$cli_cache"
            print_message "green" "✓ CLI 下载成功！"
        else
            print_message "red" "✗ CLI 下载失败！"
            exit 1
        fi
    fi

    print_message "yellow" "解压 CLI 客户端..."
    tar -xzf /tmp/cursor-cli.tar.gz -C "$CURSOR_HOME"
    if [ -d "$CURSOR_HOME/cursor" ]; then
        mv "$CURSOR_HOME/cursor" "$cli_path"
        print_message "green" "✓ CLI 安装完成: $cli_path"
    else
        print_message "red" "✗ CLI 解压失败！"
        exit 1
    fi
    rm -f /tmp/cursor-cli.tar.gz
    echo ""

    # ==================== 下载并安装服务器 ====================
    print_message "yellow" "下载 Cursor Server..."
    local server_url="https://cursor.blob.core.windows.net/remote-releases/${CURSOR_VERSION}-${CURSOR_COMMIT}/vscode-reh-${REMOTE_OS}-${REMOTE_ARCH}.tar.gz"
    local server_cache="$DOWNLOAD_CACHE_DIR/cursor-server-${CURSOR_VERSION}-${CURSOR_COMMIT}.tar.gz"
    echo "  URL: $server_url"

    if [ -f "$server_cache" ] && [ "$USE_CACHE" != "false" ]; then
        print_message "cyan" "使用缓存文件..."
        cp "$server_cache" /tmp/cursor-server.tar.gz
    else
        if curl -L --progress-bar "$server_url" -o /tmp/cursor-server.tar.gz; then
            cp /tmp/cursor-server.tar.gz "$server_cache"
            print_message "green" "✓ 服务器下载成功！"
        else
            print_message "red" "✗ 服务器下载失败！"
            exit 1
        fi
    fi

    print_message "yellow" "解压服务器..."
    tar -xzf /tmp/cursor-server.tar.gz -C "$target_dir/server" --strip-components=1
    rm -f /tmp/cursor-server.tar.gz

    print_separator
    print_message "green" "✓ 部署成功！"
    print_separator
    echo "  CLI 客户端: $cli_path"
    echo "  服务器: $target_dir/server"
    echo "  Commit: $CURSOR_COMMIT"
    echo ""

    # 验证安装
    print_message "yellow" "验证安装..."
    local verify_errors=0

    if [ -f "$cli_path" ]; then
        local cli_version=$("$cli_path" --version 2>/dev/null | head -1)
        print_message "green" "✓ CLI: $cli_version"
    else
        print_message "red" "✗ CLI 不存在"
        verify_errors=1
    fi

    if [ -f "$target_dir/server/product.json" ]; then
        local server_version=$(grep -o '"version":[^,]*' "$target_dir/server/product.json" | cut -d'"' -f4 | tr -d ' ')
        print_message "green" "✓ 服务器: $server_version"
    else
        print_message "red" "✗ 服务器 product.json 不存在"
        verify_errors=1
    fi

    if [ $verify_errors -eq 0 ]; then
        print_message "green" "所有组件验证成功！"
    else
        print_message "red" "部分组件验证失败，请检查安装！"
    fi
}

# 回滚到上一版本
rollback_to_previous() {
    print_title

    local previous_file="$BACKUP_DIR/previous_version.txt"

    if [ ! -f "$previous_file" ]; then
        print_message "red" "未找到上一版本记录"
        return
    fi

    local previous_commit=$(cat "$previous_file")

    if [ -z "$previous_commit" ]; then
        print_message "red" "上一版本记录为空"
        return
    fi

    print_message "yellow" "上一版本 Commit: $previous_commit"

    # 查找备份
    local backup_dir=$(find "$BACKUP_DIR" -type d -name "Stable-${previous_commit}_*" | sort -r | head -1)

    if [ -z "$backup_dir" ]; then
        print_message "red" "未找到备份文件"
        return
    fi

    print_message "cyan" "备份目录: $backup_dir"

    read -p "确认回滚? [y/N]: " -r confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_message "cyan" "操作已取消"
        return
    fi

    # 当前版本
    local current_commit=$(get_current_version)

    # 恢复备份
    print_message "yellow" "恢复备份..."
    local target_dir="$CURSOR_VERSIONS_DIR/Stable-${previous_commit}"
    mkdir -p "$target_dir"
    cp -r "$backup_dir"/* "$target_dir/"

    print_separator
    print_message "green" "✓ 回滚成功！"
    print_separator
    echo "  Commit: $previous_commit"
    echo "  路径: $target_dir"
}

# 清理缓存
clean_cache() {
    print_title
    print_message "yellow" "清理缓存..."

    local cleaned=0

    # 清理下载缓存
    if [ -d "$DOWNLOAD_CACHE_DIR" ]; then
        local cache_size=$(du -sh "$DOWNLOAD_CACHE_DIR" 2>/dev/null | cut -f1)
        rm -rf "$DOWNLOAD_CACHE_DIR"/*
        print_message "green" "✓ 清理下载缓存: $cache_size"
        cleaned=1
    fi

    # 清理旧备份 (保留最近 3 个)
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -type d -name "Stable-*_*" | sort -r | tail -n +4 | xargs rm -rf
        print_message "green" "✓ 清理旧备份 (保留最近 3 个)"
        cleaned=1
    fi

    if [ $cleaned -eq 0 ]; then
        print_message "cyan" "没有需要清理的内容"
    fi
}

# ==================== 主程序 ====================

# 默认值
CURSOR_VERSION=""
CURSOR_COMMIT=""
NO_BACKUP="false"
NO_PROXY="false"
USE_CACHE="true"

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            CURSOR_VERSION="$2"
            shift 2
            ;;
        -c|--commit)
            CURSOR_COMMIT="$2"
            shift 2
            ;;
        -p|--proxy)
            PROXY_URL="$2"
            shift 2
            ;;
        -a|--arch)
            REMOTE_ARCH="$2"
            shift 2
            ;;
        -o|--os)
            REMOTE_OS="$2"
            shift 2
            ;;
        --no-proxy)
            NO_PROXY="true"
            PROXY_URL=""
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
        -h|--help)
            show_help
            ;;
        --list)
            list_installed_versions
            exit 0
            ;;
        --current)
            local current=$(get_current_version)
            if [ -n "$current" ]; then
                print_message "green" "当前版本 Commit: $current"
            else
                print_message "yellow" "未找到当前版本"
            fi
            exit 0
            ;;
        --rollback)
            rollback_to_previous
            exit 0
            ;;
        --clean)
            clean_cache
            exit 0
            ;;
        --update)
            print_message "yellow" "更新功能需要从 Cursor 获取最新版本信息"
            print_message "cyan" "请使用: $0 -v <新版本> -c <新commit>"
            exit 0
            ;;
        *)
            print_message "red" "未知选项: $1"
            show_help
            ;;
    esac
done

# 如果没有指定版本，使用交互式输入
if [ -z "$CURSOR_VERSION" ] || [ -z "$CURSOR_COMMIT" ]; then
    get_version_info_interactive
fi

# 确认部署
echo ""
print_message "yellow" "即将部署 Cursor Server $CURSOR_VERSION"
read -p "确认继续? [y/N]: " -r confirm

if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_message "cyan" "操作已取消"
    exit 0
fi

echo ""

# 执行部署
deploy_cursor_server

print_message "green" "完成！"
echo ""
print_message "cyan" "现在可以在 Cursor 中连接远程服务器了"

# ==================== 节点测试功能 ====================

# 测试所有节点延迟
test_all_nodes() {
    local api_base="${MIHOMO_API_BASE:-http://127.0.0.1:1235}"
    local all_nodes=$(curl -s --noproxy "127.0.0.1" "$api_base/proxies/Auto" | jq -r '.all[]' 2>/dev/null)
    
    if [ -z "$all_nodes" ]; then
        echo "错误: 无法获取节点列表"
        return 1
    fi
    
    echo "=========================================="
    echo "测试所有节点延迟..."
    echo "=========================================="
    
    local node_count=0
    local results=""
    
    while IFS= read -r node; do
        if [ -n "$node" ]; then
            # 切换到该节点
            curl -s --noproxy "127.0.0.1" -X PUT "$api_base/proxies/Auto" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"$node\"}" > /dev/null 2>&1
            sleep 0.3
            
            # 测试延迟
            local start=$(date +%s%3N)
            if curl -s --noproxy "127.0.0.1" -x "$PROXY_URL" --max-time 3 "https://www.google.com/generate_204" > /dev/null 2>&1; then
                local end=$(date +%s%3N)
                local delay=$(( (end - start) / 1000000 ))
                printf "%-35s %5d ms\n" "$node" "$delay"
                results="$results$delay|$node"$'\n'
                node_count=$((node_count + 1))
            else
                printf "%-35s %5s\n" "$node" "超时"
            fi
        fi
    done <<< "$all_nodes"
    
    echo "=========================================="
    echo "测试完成: 共 $node_count 个节点"
    echo "=========================================="
}

# 处理 --test-nodes 参数
if [[ "$1" == "--test-nodes" ]]; then
    export https_proxy="http://127.0.0.1:7899"
    export http_proxy="http://127.0.0.1:7899"
    test_all_nodes
    exit 0
fi
