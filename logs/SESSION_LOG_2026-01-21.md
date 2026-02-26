# Cursor Server 手动部署 - 会话记录

**日期:** 2026-01-21
**问题:** Cursor Remote-SSH Server 下载失败/缓慢
**状态:** ✅ 已解决

---

## 问题描述

### 初始症状

用户从 Windows 本地 Cursor 连接到远程 Linux 服务器时，Cursor Remote-SSH 插件在下载服务器端时遇到问题：

```
[22:04:39.833] [server] Installing and setting up Cursor Server...
[22:04:49.502] [server] Downloading Cursor server -> /tmp/.tmpz8tXcR/vscode-reh-linux-x64.tar.gz
[22:04:49.502] [server] server download progress: 0/76890373 (0%)
[22:07:39.206] [server] server download progress: 2104713/76890373 (3%)
```

下载速度极慢（3分钟仅 3%），约 73MB 文件。

---

## 环境信息

### 本地 (Windows)
- **OS:** Windows_NT x64 10.0.22631
- **Cursor Version:** 2.3.41
- **Commit:** 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30
- **代理:** Clash (端口 7897)
  ```bash
  export https_proxy=http://127.0.0.1:7897
  export http_proxy=http://127.0.0.1:7897
  export all_proxy=socks5://127.0.0.1:7897
  ```

### 远程服务器
- **用户:** fhz
- **主机:** biotrainee.vip:14071
- **OS:** Linux (Ubuntu/Debian)
- **代理:** mihomo (端口 7899)

---

## 问题分析

### 根本原因

1. **Cursor 下载机制：**
   - Cursor 在 **Windows 本地**发起下载
   - 下载的是远程 Linux 服务器的 server 文件
   - Windows 代理设置不影响这个下载过程

2. **网络连接分析：**
   ```
   检查结果: cursor-2ca326e0 → 20.209.35.129:443
   ```
   - 连接是直连，**没有通过代理**
   - 导致在国内访问微软服务器速度极慢

---

## 解决方案

### 方案选择过程

| 方案 | 描述 | 结果 |
|------|------|------|
| 方案 1 | Windows 系统代理 | ❌ Cursor 不自动使用 |
| 方案 2 | SSH 端口转发 + 本地代理 | ⚠️ 复杂，需要额外配置 |
| **方案 3** | **远程服务器直接通过 mihomo 下载** | ✅ **最终采用** |

### 最终方案执行

**在远程服务器上通过 mihomo 代理下载：**

```bash
# 1. 设置远程代理
export https_proxy=http://127.0.0.1:7899
export http_proxy=http://127.0.0.1:7899

# 2. 下载 Cursor Server
curl -L --progress-bar \
  https://cursor.blob.core.windows.net/remote-releases/2.3.41-2ca326e0d1ce10956aea33d54c0e2d8c13c58a30/vscode-reh-linux-x64.tar.gz \
  -o ~/.cursor-server/cursor-server.tar.gz

# 3. 解压到目标目录
mkdir -p ~/.cursor-server/cli/servers/Stable-2ca326e0d1ce10956aea33d54c0e2d8c13c58a30/server/
tar -xzf ~/.cursor-server/cursor-server.tar.gz \
  -C ~/.cursor-server/cli/servers/Stable-2ca326e0d1ce10956aea33d54c0e2d8c13c58a30/server/ \
  --strip-components=1

# 4. 清理
rm ~/.cursor-server/cursor-server.tar.gz
```

### 执行结果

```
✓ 下载成功！ (73MB)
✓ 解压完成
✓ 部署路径: /home/data/fhz/.cursor-server/cli/servers/Stable-2ca326e0d1ce10956aea33d54c0e2d8c13c58a30/server/
```

---

## 技术要点

### mihomo 代理配置

确保 mihomo 正常运行：
```bash
# 检查 mihomo 状态
mihomo-status

# 检查 API
proxy-current

# 启用代理
proxy-on
```

### 下载 URL 格式

```
https://cursor.blob.core.windows.net/remote-releases/{VERSION}-{COMMIT}/vscode-reh-{OS}-{ARCH}.tar.gz
```

**参数：**
- `{VERSION}`: Cursor 版本号（如 2.3.41）
- `{COMMIT}`: Commit 哈希（如 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30）
- `{OS}`: linux
- `{ARCH}`: x64 或 arm64

### 目标目录结构

```
~/.cursor-server/cli/servers/
└── Stable-{COMMIT}/
    └── server/
        ├── node
        ├── extensions/
        ├── out/
        └── product.json
```

---

## 自动化脚本

为方便未来版本更新，创建了自动化脚本：

**位置:** `~/Documents/cursor-server-deploy/scripts/deploy-cursor-server.sh`

**功能：**
- ✅ 交互式版本输入
- ✅ 自动代理支持
- ✅ 版本备份和回滚
- ✅ 下载缓存
- ✅ 版本列表管理

**使用方法：**
```bash
# 复制到可执行位置
cp ~/Documents/cursor-server-deploy/scripts/deploy-cursor-server.sh ~/.local/bin/cursor-deploy
chmod +x ~/.local/bin/cursor-deploy

# 运行
cursor-deploy

# 或指定版本
cursor-deploy -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30
```

---

## 扩展性设计

### 未来版本更新流程

```bash
# 1. 在 Cursor 中查看新版本
# Help -> About

# 2. 部署新版本（自动备份旧版本）
cursor-deploy -v <新版本> -c <新commit>

# 3. 如果有问题，回滚
cursor-deploy --rollback
```

### 多架构支持

```bash
# ARM 服务器（如 AWS Graviton）
cursor-deploy -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30 -a arm64
```

### 不同代理配置

```bash
# 使用 mihomo
cursor-deploy -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30 -p http://127.0.0.1:7899

# 不使用代理
cursor-deploy -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30 --no-proxy
```

---

## 参考资料

### 来源

1. **ShayS 脚本** (Cursor Forum)
   - https://forum.cursor.com/t/how-to-download-cursor-remote-ssh-server-manually/30455/6
   - 本地下载后 scp 上传到远程

2. **Arthals 改进版**
   - https://arthals.ink/blog/cursor-remote-ssh-solution
   - 支持远程直接下载、代理、版本管理

3. **mihomo 代理配置**
   - `~/Documents/mihomo_docs/2026-01-21_current/`

### 相关文档

- **使用指南:** `~/Documents/cursor-server-deploy/guides/USAGE_GUIDE.md`
- **部署脚本:** `~/Documents/cursor-server-deploy/scripts/deploy-cursor-server.sh`

---

## 经验总结

### 关键发现

1. **Cursor 下载不使用系统代理**
   - 需要在远程服务器层面解决

2. **mihomo mixed-port (7899) 是最佳选择**
   - 支持 HTTP + SOCKS
   - 与 `proxy-on` 一致

3. **自动化脚本的必要性**
   - 版本更新频繁
   - 手动操作容易出错
   - 需要版本回滚能力

### 最佳实践

1. **始终备份旧版本**
2. **使用代理加速下载**
3. **验证下载文件完整性**
4. **记录版本变更历史**

---

## 后续改进建议

### 短期

- [ ] 添加版本自动检测功能
- [ ] 集成到 mihomo 函数库
- [ ] 添加下载进度通知

### 长期

- [ ] 支持多服务器批量部署
- [ ] Web UI 管理界面
- [ ] 版本差异对比
- [ ] 自动更新检测

---

**记录人:** Claude (AI Assistant)
**会话时间:** 2026-01-21 22:00 - 23:00
**最终状态:** ✅ 部署成功，Cursor 可正常连接
