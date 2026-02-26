# Cursor Server 部署脚本 - 问题修复记录

**日期:** 2026-01-26
**问题:** cursor-deploy 命令不起作用

---

## 发现的问题

### 问题 1: 脚本未安装到 PATH

**症状:**
```bash
cursor-deploy -v 2.3.41 -c xxx
# command not found
```

**原因:** 脚本只创建了文档文件，没有复制到 `~/.local/bin/`

**修复:**
```bash
cp ~/Documents/cursor-deploy/scripts/deploy-cursor-server.sh ~/.local/bin/cursor-deploy
chmod +x ~/.local/bin/cursor-deploy
```

---

### 问题 2: 脚本"卡住"不继续

**症状:**
```bash
cursor-deploy -v 2.3.41 -c testcommit
# 显示 "即将部署 Cursor Server 2.3.41" 后没有反应
```

**原因:** 脚本等待用户输入确认 (`read -p "确认继续? [y/N]:"`)

**修复:** 添加 `--yes` / `-y` 参数跳过确认

```bash
# 新增选项
-y, --yes    跳过确认提示（自动化脚本推荐）

# 使用方法
cursor-deploy -v 2.3.41 -c xxx -y
```

---

### 问题 3: mihomo 检测时机问题

**原因:** `detect_mihomo_port()` 在参数解析之前执行，效率低

**修复:** 移动 mihomo 检测到参数解析之后

```bash
# 参数解析后配置
if [ -z "$PROXY_URL" ] && [ "$NO_PROXY" != "true" ]; then
    PROXY_URL="$(detect_mihomo_port)"
fi
```

---

### 问题 4: 命名不一致

**原因:** 文档中混用 `cursor-server-deploy` 和 `deploy-cursor-server.sh`

**修复:** 统一命名为 `cursor-deploy`

```bash
# 文件夹重命名
~/Documents/cursor-server-deploy/ → ~/Documents/cursor-deploy/

# 脚本名称
~/.local/bin/cursor-deploy
```

---

## 更新内容

### 脚本更新

| 项目 | 变更 |
|------|------|
| 新增参数 | `-y, --yes` 跳过确认提示 |
| 优化逻辑 | mihomo 检测移到参数解析后 |
| 新增变量 | `SKIP_CONFIRM="false"` |

### 文档更新

1. **README.md**
   - 更新命名引用
   - 添加 `-y` 参数示例

2. **USAGE_GUIDE.md**
   - 更新基本用法表格
   - 新增故障排除条目（问题 1: 脚本"卡住"）
   - 添加 `--yes` 参数说明

3. **文件结构**
   ```
   ~/Documents/cursor-deploy/
   ├── README.md
   ├── scripts/
   │   ├── deploy-cursor-server.sh    (源文件)
   │   └── cursor-deploy.backup.*     (备份)
   ├── guides/
   │   └── USAGE_GUIDE.md
   └── logs/
       ├── SESSION_LOG_2026-01-21.md
       └── SESSION_LOG_FIXES_2026-01-26.md
   ```

---

## 使用方法（修复后）

### 交互式部署

```bash
cursor-deploy
# 按提示输入版本和 commit
# 看到确认提示时输入 y
```

### 自动化部署（推荐）

```bash
# 完全自动化，无需确认
cursor-deploy -v 2.3.41 -c 2ca326e0d1ce10956aea33d54c0e2d8c13c58a30 -y
```

### 版本管理

```bash
# 查看已安装版本
cursor-deploy --list

# 回滚到上一版本
cursor-deploy --rollback
```

---

## 验证

```bash
# 检查脚本存在
ls -la ~/.local/bin/cursor-deploy

# 查看帮助
cursor-deploy --help

# 测试参数解析（不会实际部署）
echo "n" | cursor-deploy -v 2.3.41 -c testcommit
# 应该看到 "操作已取消"
```

---

**修复时间:** 2026-01-26
**修复人:** Claude (AI Assistant)
**状态:** ✅ 已完成并验证
