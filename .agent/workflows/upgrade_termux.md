---
description: 从官方 OpenClaw 升级 Termux 分支到最新版本并发布 Release（完整自动化工作流）
---

# OpenClaw-Termux 升级 + 发布工作流

当官方 OpenClaw 发布新版本时，Agent 按此工作流自动完成：检查版本 → 合并 → 修补 → 修复兼容性 → 提交 → 推送 → 发布 Release。

> **核心原则：不破坏 Termux 兼容性，所有步骤可由 Agent 自动执行。**

---

## 前置信息

| 项目 | 值 |
|------|------|
| 工作目录 (Drive Letter) | `Y:\repos\yunze7373\openclaw-termux` |
| 工作目录 (UNC) | `\\hanstation\chia\source\repos\yunze7373\openclaw-termux` |
| 官方仓库参考 | `\\hanstation\chia\nasdata\openclaw` (aka `X:\openclaw`) |
| upstream remote | `https://github.com/openclaw/openclaw.git` |
| GitHub 仓库 | `yunze7373/openclaw-termux` |
| gh 默认仓库 | 需确认已设置 `gh repo set-default yunze7373/openclaw-termux` |
| git 注意事项 | NAS (UNC/Drive Letter) 上的 git 操作非常慢，commit 可能要 5+ 分钟 |

---

## Termux 分支定制清单（升级后必须全部保留）

升级的核心任务是：采用上游所有变更，然后恢复以下定制。

### A. Termux 独有文件（上游不存在，从备份恢复）

| 文件 | 说明 |
|------|------|
| `Install_termux.sh` | 英文安装脚本 |
| `Install_termux_cn.sh` | 中文安装脚本（含国内镜像） |
| `scripts/setup-termux.sh` | Termux 环境初始化 |
| `scripts/termux-auth-widget.sh` | 认证 Widget |
| `scripts/termux-quick-auth.sh` | 快速认证脚本 |
| `scripts/termux-sync-widget.sh` | 同步 Widget |
| `ANDROID_FIXES.md` | Android 兼容性修复文档 |
| `ANDROID_FIXES_CN.md` | Android 兼容性修复文档（中文） |
| `README_CN.md` | 中文 README |
| `VERTEX_AI_SETUP.md` | Vertex AI 配置文档 |
| `docs/platforms/termux.md` | 平台文档 |
| `assets/termux-dashboard.png` | 截图资源 |
| `assets/termux-dashboard_cn.png` | 截图资源（中文） |
| `moltbot` | 启动器脚本 |
| `.clawdhub/lock.json` | 锁定文件 |

### B. 元数据文件补丁（合并后字段级修复）

| 文件 | 修改内容 |
|------|----------|
| `.npmrc` | 添加 `sharp_binary_host` / `sharp_libvips_binary_host` 镜像 |
| `package.json` | `version` → `X.Y.Z-termux.1`，`description` / `repository` |
| `.gitignore` | 追加 Termux 私有仓库忽略规则块 |
| `README.md` | 完全替换为 Termux 版 README（从备份恢复） |

### C. 源码补丁（合并后代码级修复）

| 文件 | 补丁 | 状态 |
|------|------|------|
| `src/gateway/server.impl.ts` | 导入 `OpenClawSchema`，自动清理无效 config key | Termux 专有 |
| `src/memory/manager-supabase.ts` | Supabase 内存管理器（Termux 独有文件） | Termux 专有 |
| `src/logging/logger.ts` | `/tmp` → `os.tmpdir()` | ✅ 已被上游 v2026.2.12 采纳，不再需要 |

### D. 构建时补丁（Install 脚本内处理，不入 git）

| 补丁 | 处理方式 |
|------|----------|
| `tsdown.config.ts` 排除 `@napi-rs/canvas` | Install 脚本在构建前自动 sed 修补 |
| `src/media/input-files.ts` 去除 canvas 依赖 | Install 脚本在构建前自动 sed 修补 |

---

## Step 1: 确认官方最新版本

// turbo
```bash
git -C Y:\repos\yunze7373\openclaw-termux fetch upstream --tags
```

// turbo
```bash
git -C Y:\repos\yunze7373\openclaw-termux tag -l "v*" --sort=-version:refname | head -5
```

同时查看官方 GitHub Releases 页面获取更新日志：
- 使用 `read_url_content` 工具读取 `https://github.com/openclaw/openclaw/releases`
- 记录新版本号为 `<NEW_VERSION>`（例如 `v2026.2.14`）

// turbo
确认当前本地版本：
```bash
git -C Y:\repos\yunze7373\openclaw-termux log --oneline -1 HEAD
```

**决策点：** 如果本地版本已是最新，通知用户不需要升级并结束。

---

## Step 2: 创建备份分支

```bash
git -C Y:\repos\yunze7373\openclaw-termux branch backup/pre-<NEW_VERSION>
```

**示例：** `git -C Y:\repos\yunze7373\openclaw-termux branch backup/pre-v2026.2.14`

---

## Step 3: 执行合并（关键步骤）

### ⚡ 必须使用 `--allow-unrelated-histories -X theirs`

Termux 分支与 upstream 没有共同祖先，所以：
- ❌ 不能用普通 merge（会产生数百个冲突）
- ❌ 不能用 rebase（同理）
- ✅ 必须用 `-X theirs` 策略自动采用上游所有变更

```bash
git -C Y:\repos\yunze7373\openclaw-termux merge <NEW_VERSION> --no-ff --allow-unrelated-histories -X theirs -m "merge: upgrade to official <NEW_VERSION>"
```

**示例：**
```bash
git -C Y:\repos\yunze7373\openclaw-termux merge v2026.2.14 --no-ff --allow-unrelated-histories -X theirs -m "merge: upgrade to official v2026.2.14"
```

如果合并失败，先 `git -C Y:\repos\yunze7373\openclaw-termux merge --abort` 再排查原因。

---

## Step 4: 恢复 Termux 定制补丁

`-X theirs` 会覆盖共有文件中的 Termux 修改，必须手动恢复：

### 4.1 恢复 Termux 独有文件（A 类）

从备份分支恢复所有 Termux 独有文件：

```bash
git -C Y:\repos\yunze7373\openclaw-termux checkout backup/pre-<NEW_VERSION> -- Install_termux.sh Install_termux_cn.sh scripts/setup-termux.sh scripts/termux-auth-widget.sh scripts/termux-quick-auth.sh scripts/termux-sync-widget.sh ANDROID_FIXES.md ANDROID_FIXES_CN.md README_CN.md VERTEX_AI_SETUP.md docs/platforms/termux.md assets/termux-dashboard.png assets/termux-dashboard_cn.png moltbot .clawdhub/lock.json
```

### 4.2 恢复 README.md

README.md 是完全不同的内容（Termux 版有功能对比表、Android 硬件能力、安装说明等），必须从备份恢复：

```bash
git -C Y:\repos\yunze7373\openclaw-termux checkout backup/pre-<NEW_VERSION> -- README.md
```

### 4.3 `.npmrc` — 恢复 sharp 国内镜像

用 `view_file` 查看当前 `.npmrc`，确保包含以下内容（如缺失则补上）：

```ini
allow-build-scripts=@whiskeysockets/baileys,sharp,esbuild,protobufjs,fs-ext,node-pty,@lydell/node-pty,@matrix-org/matrix-sdk-crypto-nodejs

# Termux/Android: sharp pre-built binaries mirror
sharp_binary_host=https://npmmirror.com/mirrors/sharp-libvips
sharp_libvips_binary_host=https://npmmirror.com/mirrors/sharp-libvips

ignore-scripts=false
```

### 4.4 `package.json` — 恢复 Termux 元数据

修改以下三个字段（其余保持上游不变）：

```json
{
  "version": "<NEW_VERSION_WITHOUT_V>-termux.1",
  "description": "OpenClaw Termux Fork - Personal AI assistant for Android",
  "repository": {
    "type": "git",
    "url": "https://github.com/yunze7373/openclaw-termux.git"
  }
}
```

**示例：** 如果 `<NEW_VERSION>` 为 `v2026.2.14`，则 version 设为 `"2026.2.14-termux.1"`。

### 4.5 `.gitignore` — 追加 Termux 私有规则

检查文件末尾是否有 `# Termux 私有仓库专用忽略规则` 块。如缺失，在末尾追加：

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

## Step 5: 源码补丁（C 类）

### 5.1 `src/gateway/server.impl.ts` — 自动清理无效 config key

在 `configSnapshot = await readConfigFileSnapshot();` 之后（约第 192 行附近），插入以下代码块：

1. 在文件顶部 import 块中新增 `OpenClawSchema`：
   ```typescript
   import {
     // ... existing imports ...
     OpenClawSchema,
     writeConfigFile,
   } from "../config/config.js";
   ```

2. 在 `configSnapshot = await readConfigFileSnapshot();` 后，`if (configSnapshot.exists && !configSnapshot.valid)` 前插入：
   ```typescript
   // Auto-strip unrecognized config keys (e.g. stale or manually-added keys like "web_search")
   // instead of crashing the gateway.  This mirrors `openclaw doctor --fix` behaviour.
   if (configSnapshot.exists && configSnapshot.config) {
     const parseResult = OpenClawSchema.safeParse(configSnapshot.config);
     if (!parseResult.success) {
       const unrecognizedKeys: string[] = [];
       const cleaned = structuredClone(configSnapshot.config);
       for (const issue of parseResult.error.issues) {
         if (issue.code === "unrecognized_keys") {
           const uIssue = issue as typeof issue & { keys: PropertyKey[] };
           const parentPath = issue.path.filter(
             (p: PropertyKey): p is string | number => typeof p !== "symbol",
           );
           let target: unknown = cleaned;
           for (const part of parentPath) {
             if (target && typeof target === "object" && !Array.isArray(target)) {
               target = (target as Record<string, unknown>)[String(part)];
             } else if (Array.isArray(target) && typeof part === "number") {
               target = target[part];
             } else {
               target = undefined;
             }
           }
           if (target && typeof target === "object" && !Array.isArray(target)) {
             const record = target as Record<string, unknown>;
             for (const key of uIssue.keys) {
               if (typeof key === "string" && key in record) {
                 delete record[key];
                 const keyPath = parentPath.length > 0 ? `${parentPath.join(".")}.${key}` : key;
                 unrecognizedKeys.push(keyPath);
               }
             }
           }
         }
       }
       if (unrecognizedKeys.length > 0) {
         await writeConfigFile(cleaned);
         log.warn(
           `gateway: auto-removed unrecognized config keys:\n${unrecognizedKeys
             .map((k) => `- ${k}`)
             .join("\n")}`,
         );
         configSnapshot = await readConfigFileSnapshot();
       }
     }
   }
   ```

### 5.2 `src/memory/manager-supabase.ts` — Supabase 内存管理器

这是 Termux 独有文件。从备份恢复：
```bash
git -C Y:\repos\yunze7373\openclaw-termux checkout backup/pre-<NEW_VERSION> -- src/memory/manager-supabase.ts
```

### 5.3 `/tmp` 硬编码检查（验证性步骤）

从 v2026.2.12 起，上游已使用 `os.tmpdir()` fallback。验证一下：

// turbo
```bash
git -C Y:\repos\yunze7373\openclaw-termux grep -rn '"/tmp/' src/ -- '*.ts' ':!*.test.ts'
```

如果仍有残留硬编码 `/tmp`，用 `os.tmpdir()` 替换。

---

## Step 6: 提交所有变更

将 Step 4 + Step 5 的修改作为一个提交：

```bash
git -C Y:\repos\yunze7373\openclaw-termux add -A
```

```bash
git -C Y:\repos\yunze7373\openclaw-termux commit -m "chore(termux): restore Termux-specific customizations after <NEW_VERSION> merge"
```

---

## Step 7: 压缩为单个版本提交

将合并产生的所有提交压缩为一个干净的版本提交：

```bash
git -C Y:\repos\yunze7373\openclaw-termux reset --soft origin/main
```

然后重新提交，commit message 需包含完整更新摘要（从 Step 1 收集的 Release Notes 中整理）：

```bash
git -C Y:\repos\yunze7373\openclaw-termux commit -m "chore(release): <NEW_VERSION>-termux.1 — sync with official openclaw <NEW_VERSION>"
```

> 注意：如果 commit message 包含多行内容，请使用 `--file` 方式代替 `-m`，先将 message 写入临时文件再提交，以避免 PowerShell 多行字符串解析问题。

---

## Step 8: 推送到 GitHub

```bash
git -C Y:\repos\yunze7373\openclaw-termux push origin main
```

如果被拒绝：
```bash
git -C Y:\repos\yunze7373\openclaw-termux push origin main --force-with-lease
```

---

## Step 9: 创建 Git Tag

```bash
git -C Y:\repos\yunze7373\openclaw-termux tag -a <NEW_VERSION>-termux.1 -m "OpenClaw Termux <NEW_VERSION>-termux.1"
```

```bash
git -C Y:\repos\yunze7373\openclaw-termux push origin <NEW_VERSION>-termux.1
```

---

## Step 10: 发布 GitHub Release

### 10.1 确保 gh 默认仓库已设置

// turbo
```bash
gh repo set-default yunze7373/openclaw-termux
```

### 10.2 创建 Release Notes 文件

在项目根目录创建临时文件 `RELEASE_NOTES.md`，内容如下（中文，使用 emoji 分节）：

```markdown
## 同步官方 OpenClaw <NEW_VERSION>

### 🆕 上游新增功能
- **功能名** — 简要描述
- ...

### 🔧 上游重要修复
- 修复描述
- ...

### 📱 Termux 专属修复
- **fix**: 具体修复内容
- 保留所有 Termux/Android 定制

### 📦 升级方法
\```bash
./Install_termux_cn.sh --update
\```
```

### 10.3 发布 Release

```bash
cd Y:\repos\yunze7373\openclaw-termux
gh release create <NEW_VERSION>-termux.1 --title "OpenClaw Termux <NEW_VERSION_WITHOUT_V>" --notes-file RELEASE_NOTES.md
```

### 10.4 清理临时文件

// turbo
```bash
del Y:\repos\yunze7373\openclaw-termux\RELEASE_NOTES.md
```

---

## Step 11: 通知用户

升级完成后，通知用户以下信息：
1. Release 链接：`https://github.com/yunze7373/openclaw-termux/releases/tag/<NEW_VERSION>-termux.1`
2. Termux 上更新方法：`./Install_termux_cn.sh --update`
3. 备份分支名：`backup/pre-<NEW_VERSION>`

---

## 故障排除

### Git 操作太慢
NAS 上的 git 操作（特别是 commit）可能需要 5+ 分钟。使用 `git -C <path>` 代替 `cd <path>; git ...`，并耐心等待。对于非常慢的操作，可以尝试在本地 clone 后操作。

### 合并失败
```bash
git -C Y:\repos\yunze7373\openclaw-termux merge --abort
# 检查 upstream tag 是否存在
git -C Y:\repos\yunze7373\openclaw-termux tag -l "<NEW_VERSION>"
```

### pnpm install 在 Termux 上失败
```bash
rm -rf node_modules
pnpm store prune
pnpm install --no-frozen-lockfile
```

### sharp 编译失败
确认 `.npmrc` 中的镜像配置正确。

### 需要回退
```bash
git -C Y:\repos\yunze7373\openclaw-termux reset --hard backup/pre-<NEW_VERSION>
git -C Y:\repos\yunze7373\openclaw-termux push origin main --force-with-lease
```

### gh release 挂起
不要在 `--notes` 里使用特殊字符（反引号等），改用 `--notes-file` 方式。

### gh 没有设置默认仓库
```bash
gh repo set-default yunze7373/openclaw-termux
```

### PowerShell 多行 commit message
PowerShell 多行字符串在 git commit 中可能导致挂起。解决方法：
```powershell
# 将 message 写入文件
Set-Content -Path C:\Users\yunze\Desktop\commit_msg.txt -Value @"
chore(release): v2026.2.14-termux.1

Merged upstream openclaw v2026.2.14 with Termux customizations.
"@
# 使用文件提交
git -C Y:\repos\yunze7373\openclaw-termux commit --file C:\Users\yunze\Desktop\commit_msg.txt
```
