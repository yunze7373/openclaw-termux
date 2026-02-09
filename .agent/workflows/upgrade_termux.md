---
description: 从官方 OpenClaw 仓库升级 Termux 分支到最新版本（保留 Termux 兼容性）
---

# OpenClaw-Termux 升级工作流

当官方 OpenClaw 发布新版本时，使用此工作流将 Termux 分支同步到最新版，同时保留所有 Termux/Android 定制修改。

> **核心原则：不破坏 Termux 兼容性。**

## 前提条件

- 工作目录：`C:\Users\han\source\repos\yunze7373\openclaw-termux`
- 官方库参考：`\\hanstation\chia\nasdata\openclaw`（或 upstream remote）
- upstream remote 已配置指向 `https://github.com/openclaw/openclaw.git`

---

## Step 1: 查看官方最新版本

// turbo
```bash
git fetch upstream
git ls-remote --tags https://github.com/openclaw/openclaw | tail -5
```

查看 GitHub Releases 获取更新日志：
```
https://github.com/openclaw/openclaw/releases
```

---

## Step 2: 评估本地状态

// turbo
```bash
# 查看当前版本
git log -1 --format="%h %s"

# 本地独有提交数
git log --oneline upstream/main..HEAD | wc -l

# 上游新增提交数
git log --oneline HEAD..upstream/main | wc -l
```

---

## Step 3: 创建备份分支

```bash
git branch backup/pre-<新版本号> main
```

**示例：** `git branch backup/pre-v2026.2.9 main`

> ⚠️ 如遇问题可通过 `git reset --hard backup/pre-<版本号>` 回退。

---

## Step 4: 执行合并

### ⚡ 关键：使用 `--allow-unrelated-histories -X theirs`

由于 Termux 分支历史与 upstream 不共享祖先（unrelated histories），必须使用特殊参数：

```bash
git merge v<新版本标签> --no-ff --allow-unrelated-histories -X theirs -m "merge: upgrade to official v<新版本号>"
```

**参数解释：**
| 参数 | 作用 |
|------|------|
| `--allow-unrelated-histories` | 允许合并无共同祖先的分支 |
| `-X theirs` | 所有冲突自动采用上游版本（之后手动恢复 Termux 补丁） |
| `--no-ff` | 保留合并提交，便于追踪 |

> ❌ **不要用 rebase**——unrelated histories 会导致数百个冲突无法逐一处理。
> ❌ **不要用默认 merge**——会产生大量手动冲突（每个共有文件都会冲突）。

---

## Step 5: 恢复 Termux 定制补丁

合并后 `-X theirs` 会覆盖掉 Termux 在共有文件中的修改，需要手动恢复以下文件：

### 5.1 `.npmrc` — 恢复 sharp 国内镜像

确保 `.npmrc` 包含以下内容：

```ini
allow-build-scripts=@whiskeysockets/baileys,sharp,esbuild,protobufjs,fs-ext,node-pty,@lydell/node-pty,@matrix-org/matrix-sdk-crypto-nodejs

# Termux/Android compatibility: skip native compilation for sharp
# (use wasm fallback or pre-built binaries)
sharp_binary_host=https://npmmirror.com/mirrors/sharp-libvips
sharp_libvips_binary_host=https://npmmirror.com/mirrors/sharp-libvips

ignore-scripts=false
```

### 5.2 `package.json` — 恢复 Termux 元数据

修改以下字段（其他保持上游不动）：

```json
{
  "version": "<新版本号>-termux.1",
  "description": "OpenClaw Termux Fork - Personal AI assistant for Android",
  "repository": {
    "type": "git",
    "url": "https://github.com/yunze7373/openclaw-termux.git"
  }
}
```

### 5.3 `.gitignore` — 追加 Termux 私有规则

在文件末尾追加（如果被覆盖）：

```gitignore
.gemini/
gha-creds-*.json

# ===========================
# Termux 私有仓库专用忽略规则
# ===========================

# --- 归档目录 ---
archive/

# --- 日志文件 ---
*.log
logs/

# --- 个人身份文件 ---
MEMORY.md
SOUL.md
HEARTBEAT.md
TOOLS.md

# --- 敏感凭证 ---
*.pem
*.key
id_rsa*
id_ed25519*
.netrc
.npmrc.local

# --- 临时文件 ---
*.tar.gz
*.orig
*.bak
*.tmp
package-lock.json

# --- 记忆/缓存 ---
memory/
.cache/
.clawdhub/cache/

# Personal workspace files
/AGENTS.md
/CODEX.md
/GEMINI.md
/XIAOJI.md
/PROJECT-CONTEXT.md
```

---

## Step 6: 验证 Termux 独有文件完整性

// turbo
以下文件必须全部存在，如有缺失需从备份分支恢复（`git checkout backup/pre-<版本号> -- <文件路径>`）：

```bash
# 检查 Termux 独有文件
ls -la Install_termux.sh Install_termux_cn.sh ANDROID_FIXES.md ANDROID_FIXES_CN.md README_CN.md VERTEX_AI_SETUP.md moltbot
ls -la scripts/setup-termux.sh scripts/termux-auth-widget.sh scripts/termux-quick-auth.sh scripts/termux-sync-widget.sh
ls -la .clawdhub/lock.json
```

如有缺失：
```bash
git checkout backup/pre-<版本号> -- <缺失文件路径>
```

---

## Step 7: 提交 Termux 补丁

```bash
git add .npmrc package.json .gitignore
git commit -m "chore(termux): restore Termux-specific customizations after v<新版本号> merge

- .npmrc: restore sharp mirror config for Android/Termux
- package.json: set version to <新版本号>-termux.1, restore Termux description and repository
- .gitignore: restore Termux private repo ignore rules"
```

---

## Step 8: 在 Termux 上构建验证

SSH 到 Termux 或在设备上执行：

```bash
# 拉取更新
git pull origin main

# 安装依赖（Termux 上可能需要较长时间）
pnpm install

# 构建
pnpm build

# 测试启动
openclaw --version
openclaw
```

---

## Step 9: 推送到远程

```bash
git push origin main
```

> 如果 push 被拒绝（因历史记录变化），需要 `git push origin main --force-with-lease`。

---

## 快速参考：Termux 独有文件清单

| 类别 | 文件 |
|------|------|
| 安装脚本 | `Install_termux.sh`, `Install_termux_cn.sh` |
| 文档 | `ANDROID_FIXES.md`, `ANDROID_FIXES_CN.md`, `README_CN.md`, `VERTEX_AI_SETUP.md` |
| 配置脚本 | `scripts/setup-termux.sh` |
| 小部件脚本 | `scripts/termux-auth-widget.sh`, `scripts/termux-quick-auth.sh`, `scripts/termux-sync-widget.sh` |
| 其他 | `moltbot`, `.clawdhub/lock.json` |

## 快速参考：需恢复补丁的共有文件

| 文件 | 恢复内容 |
|------|----------|
| `.npmrc` | sharp 国内镜像地址 + `ignore-scripts=false` |
| `package.json` | `version`, `description`, `repository` |
| `.gitignore` | Termux 私有仓库忽略规则块 |

---

## 故障排除

### pnpm install 在 Termux 上失败
```bash
# 清理后重试
rm -rf node_modules
pnpm store prune
pnpm install --no-frozen-lockfile
```

### sharp 编译失败
确认 `.npmrc` 中的镜像配置正确，或尝试：
```bash
npm_config_sharp_binary_host=https://npmmirror.com/mirrors/sharp-libvips pnpm install
```

### 需要回退
```bash
git reset --hard backup/pre-<版本号>
git push origin main --force-with-lease
```
