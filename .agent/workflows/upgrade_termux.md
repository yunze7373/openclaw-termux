---
description: 从官方 OpenClaw 升级 Termux 分支到最新版本并发布 Release（完整自动化工作流）
---

# OpenClaw-Termux 升级 + 发布工作流

当官方 OpenClaw 发布新版本时，Agent 按此工作流自动完成：检查版本 → 合并 → 修补 → 修复兼容性 → 提交 → 推送 → 发布 Release。

> **核心原则：不破坏 Termux 兼容性，所有步骤可由 Agent 自动执行。**

---

## 前置信息

| 项目 | 值 |
|------|-----|
| 工作目录 | `C:\Users\han\source\repos\yunze7373\openclaw-termux` |
| 官方仓库参考 | `\\hanstation\chia\nasdata\openclaw` |
| upstream remote | `https://github.com/openclaw/openclaw.git` |
| GitHub 仓库 | `yunze7373/openclaw-termux` |
| gh 默认仓库 | 需确认已设置 `gh repo set-default yunze7373/openclaw-termux` |

---

## Step 1: 确认官方最新版本

// turbo
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git fetch upstream --tags
```

// turbo
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git tag -l "v*" --sort=-version:refname | head -5
```

同时查看官方 GitHub Releases 页面获取更新日志：
- 使用 `read_url_content` 工具读取 `https://github.com/openclaw/openclaw/releases`
- 记录新版本号为 `<NEW_VERSION>`（例如 `v2026.2.9`）

// turbo
确认当前本地版本：
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
node -e "console.log(require('./package.json').version)"
```

**决策点：** 如果本地版本已是最新，通知用户不需要升级并结束。

---

## Step 2: 创建备份分支

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git branch backup/pre-<NEW_VERSION> main
```

**示例：** `git branch backup/pre-v2026.2.9 main`

---

## Step 3: 执行合并（关键步骤）

### ⚡ 必须使用 `--allow-unrelated-histories -X theirs`

Termux 分支与 upstream 没有共同祖先，所以：
- ❌ 不能用普通 merge（会产生数百个冲突）
- ❌ 不能用 rebase（同理）
- ✅ 必须用 `-X theirs` 策略自动采用上游所有变更

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git merge <NEW_VERSION> --no-ff --allow-unrelated-histories -X theirs -m "merge: upgrade to official <NEW_VERSION>"
```

**示例：**
```bash
git merge v2026.2.9 --no-ff --allow-unrelated-histories -X theirs -m "merge: upgrade to official v2026.2.9"
```

如果合并失败，先 `git merge --abort` 再排查原因。

---

## Step 4: 恢复 Termux 定制补丁

`-X theirs` 会覆盖共有文件中的 Termux 修改，必须手动恢复：

### 4.1 `.npmrc` — 恢复 sharp 国内镜像

用 `view_file` 查看当前 `.npmrc`，确保包含以下内容（如缺失则补上）：

```ini
allow-build-scripts=@whiskeysockets/baileys,sharp,esbuild,protobufjs,fs-ext,node-pty,@lydell/node-pty,@matrix-org/matrix-sdk-crypto-nodejs

# Termux/Android: sharp pre-built binaries mirror
sharp_binary_host=https://npmmirror.com/mirrors/sharp-libvips
sharp_libvips_binary_host=https://npmmirror.com/mirrors/sharp-libvips

ignore-scripts=false
```

### 4.2 `package.json` — 恢复 Termux 元数据

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

**示例：** 如果 `<NEW_VERSION>` 为 `v2026.2.9`，则 version 设为 `"2026.2.9-termux.1"`。

### 4.3 `.gitignore` — 追加 Termux 私有规则

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

### 4.4 `README.md` — 从备份恢复 Termux 版 README

`README.md` 是完全不同的内容（Termux 版有功能对比表、Android 硬件能力、安装说明等），必须从备份恢复：

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git checkout backup/pre-<NEW_VERSION> -- README.md
```

---

## Step 5: 检查并修复 Termux 兼容性问题

### 5.1 /tmp 硬编码检查

// turbo
搜索运行时代码（非 test 文件）中的硬编码 `/tmp`：
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
grep -rn '"/tmp/' src/ --include="*.ts" | grep -v ".test.ts"
```

**已知需修复位置：**
- `src/logging/logger.ts` 第 ~13 行 `DEFAULT_LOG_DIR = "/tmp/openclaw"`
  - 修复为：`export const DEFAULT_LOG_DIR = path.join(os.tmpdir(), "openclaw");`
  - 需添加 `import os from "node:os";`

对找到的每个硬编码 `/tmp`，都应改为 `os.tmpdir()` 或 `path.join(os.tmpdir(), ...)` 确保 Termux 兼容。

### 5.2 Termux 独有文件完整性

// turbo
验证以下 12 个文件全部存在：
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
ls Install_termux.sh Install_termux_cn.sh ANDROID_FIXES.md ANDROID_FIXES_CN.md README_CN.md VERTEX_AI_SETUP.md moltbot .clawdhub/lock.json scripts/setup-termux.sh scripts/termux-auth-widget.sh scripts/termux-quick-auth.sh scripts/termux-sync-widget.sh
```

如有缺失，从备份恢复：
```bash
git checkout backup/pre-<NEW_VERSION> -- <缺失文件路径>
```

### 5.3 Workspace 包依赖一致性检查 ⚠️

**关键问题：** 如果主包名改过（例如 `openclaw` → `openclaw-android`），务必检查所有 extensions 和 packages 中的 workspace 引用是否同步。

// turbo
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux

# 查看主包名
node -e "console.log(require('./package.json').name)"

# 检查 extensions 中的引用
grep -r '"openclaw' extensions/*/package.json | head -10

# 检查 packages 中的引用
grep -r '"openclaw' packages/*/package.json
```

**预期结果：** 所有引用都应该与主包名一致。例如：
- 如果主包是 `"openclaw"`，所有引用应该是 `"openclaw": "workspace:*"`
- 如果主包是 `"openclaw-android"`，所有引用应该是 `"openclaw-android": "workspace:*"`

**如有不匹配：**

```bash
# 批量替换（PowerShell 示例）
$files = @(Get-ChildItem -Path extensions -Filter "package.json" -Recurse; Get-ChildItem -Path packages -Filter "package.json" -Recurse)
foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    # 替换旧包名为新包名
    $newContent = $content -replace '"openclaw":\s*"workspace:\*"', '"openclaw-android": "workspace:*"'
    Set-Content -Path $file.FullName -Value $newContent
}

# 提交这个修复
git add extensions/*/package.json packages/*/package.json
git commit -m "fix(workspace): sync package name references to <ACTUAL_PACKAGE_NAME>"
```

---

## Step 6: 提交所有变更

将 Step 4 + Step 5 的修改作为一个提交：

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git add .npmrc package.json .gitignore README.md src/logging/logger.ts
```

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git commit -m "chore(termux): restore Termux-specific customizations after <NEW_VERSION> merge

- .npmrc: restore sharp mirror config for Android/Termux
- package.json: set version to <VERSION>-termux.1, restore Termux description and repository
- .gitignore: restore Termux private repo ignore rules
- src/logging/logger.ts: use os.tmpdir() instead of hardcoded /tmp
- README.md: restore Termux-specific README"
```

---

## Step 7: 压缩为单个版本提交

将合并产生的所有提交压缩为一个干净的版本提交（像官方一样清晰）：

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git reset --soft origin/main
```

然后重新提交，commit message 需包含完整更新摘要（从 Step 1 收集的 Release Notes 中整理）：

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git commit -m "chore(release): <NEW_VERSION>-termux.1 — sync with official openclaw <NEW_VERSION>

Merged upstream openclaw <NEW_VERSION> with all Termux/Android customizations preserved.

New upstream features:
- <从官方 Release Notes 中列出主要新功能>

Key fixes:
- <从官方 Release Notes 中列出重要修复>

Termux customizations retained:
- .npmrc: sharp mirror config for Android
- package.json: Termux version/description/repository
- .gitignore: Termux private repo ignore rules
- src/logging/logger.ts: os.tmpdir() for Termux /tmp compat"
```

---

## Step 8: 推送到 GitHub

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git push origin main
```

如果被拒绝：
```bash
git push origin main --force-with-lease
```

---

## Step 9: 创建 Git Tag

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git tag -a <NEW_VERSION>-termux.1 -m "OpenClaw Termux <NEW_VERSION>-termux.1"
```

```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
git push origin <NEW_VERSION>-termux.1
```

---

## Step 10: 发布 GitHub Release

### 10.1 确保 gh 默认仓库已设置

// turbo
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
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
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
gh release create <NEW_VERSION>-termux.1 --title "OpenClaw Termux <NEW_VERSION_WITHOUT_V>" --notes-file RELEASE_NOTES.md
```

### 10.4 清理临时文件

// turbo
```bash
cd C:\Users\han\source\repos\yunze7373\openclaw-termux
del RELEASE_NOTES.md
```

---

## Step 11: 通知用户

升级完成后，通知用户以下信息：
1. Release 链接：`https://github.com/yunze7373/openclaw-termux/releases/tag/<NEW_VERSION>-termux.1`
2. Termux 上更新方法：`./Install_termux_cn.sh --update`
3. 备份分支名：`backup/pre-<NEW_VERSION>`

---

## 故障排除

### 合并失败
```bash
git merge --abort
# 检查 upstream tag 是否存在
git tag -l "<NEW_VERSION>"
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
git reset --hard backup/pre-<NEW_VERSION>
git push origin main --force-with-lease
```

### gh release 挂起
不要在 `--notes` 里使用特殊字符（反引号等），改用 `--notes-file` 方式。

### gh 没有设置默认仓库
```bash
gh repo set-default yunze7373/openclaw-termux
```
