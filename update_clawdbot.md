# OpenClaw Termux 升级计划

## 版本信息

| 项目 | 版本 |
|------|------|
| 官方 OpenClaw | v2026.2.22 |
| OpenClaw-Termux (当前) | 2026.2.22-termux.1 | ✅ 已完成 |
| 目标版本 | 2026.2.22-termux.1 |

## 官方 v2026.2.22 主要变更

### 新增功能
- Mistral provider 支持 (含 memory embeddings 和 voice)
- 内置自动更新器 (默认关闭)
- CLI 新增 `openclaw update --dry-run` 预览功能
- Synology Chat 频道插件
- 多个语言的 FTS 搜索改进 (西班牙语、葡萄牙语、日语、韩语、阿拉伯语)

### Breaking Changes
- tool-failure 回复默认隐藏详细错误 (需 `/verbose on` 查看)
- CLI onboarding 默认 `session.dmScope` 改为 `per-channel-peer`
- 频道 streaming 配置统一为 `channels.<channel>.streaming`
- 移除 Gateway device-auth 签名 v1

### 重要修复
- Discord Voice: `@discordjs/opus` 改为可选依赖
- Docker: 修复 `docker-setup.sh` 预创建 identity 目录
- Cron: 多个改进和修复
- Telegram: webhook 和 polling 改进
- Gateway: 配对和重启修复

## Termux 兼容性要求

需要保留以下 Termux 特定修改：

### 1. 路径兼容性 (service-env.ts)
- Termux 特定路径: `/data/data/com.termux/files/usr/bin`
- Termux Go 二进制: `${home}/go/bin`

### 2. 运行时兼容性
- PTY 支持检测
- 临时目录使用 `os.tmpdir()`
- 日志目录适配

### 3. Android 检测
- `process.platform === "android"` 检测
- Termux 环境变量检测

## 升级步骤

### 步骤 1: 同步官方代码
```bash
# 确保本地官方仓库最新
cd ../openclaw
git fetch upstream
git merge upstream/main
```

### 步骤 2: 合并到 Termux 分支
```bash
cd ../openclaw-termux
git checkout update-termux-attempt-3
git merge ../openclaw
```

### 步骤 3: 解决冲突
检查并解决以下文件的冲突：
- `src/agents/bash-tools.exec-runtime.ts`
- `src/daemon/service-env.ts`
- `package.json` / `package.termux.json`

### 步骤 4: 恢复 Termux 兼容性
确保以下修改被保留：
1. `service-env.ts` - Termux 路径处理
2. `bash-tools.exec-runtime.ts` - Android 检测
3. 任何 Termux 特定的运行时调整

### 步骤 5: 更新版本号
- `package.json`: `2026.2.22-termux.1`
- `package.termux.json`: `2026.2.22-termux.1`

### 步骤 6: 创建 Release 提交
```bash
git add -A
git commit -m "chore(release): 2026.2.22-termux.1 — sync with official openclaw v2026.2.22"
```

## 升级状态

**⚠️ 需要修复** - 2026-02-23

### 合并提交
- `7ab70b077` - Merge: sync with official openclaw v2026.2.22

### Termux 兼容性保留确认
- [x] `src/daemon/service-env.ts` - Termux 路径处理 ✅
- [x] `src/agents/bash-tools.exec-runtime.ts` - Android 检测 ✅
- [x] `src/agents/bash-tools.exec.ts` - PTY 检测 ✅
- [x] `src/node-host/runner.ts` - Android 支持 ✅
- [x] `src/platform/android/notify.ts` - Android 通知 ✅

### ⚠️ Termux Memory 兼容性丢失 (已修复 ✅)

在合并过程中，以下 v2026.2.9-termux.1 中的 Termux 特定 Memory 修改已**恢复**：

| 文件 | 恢复的修改 | 状态 |
|------|----------|------|
| `src/memory/embeddings.ts` | Ollama embeddings 支持 (`~/.embedding-config`) | ✅ 已恢复 |
| `src/agents/tools/memory-tool.ts` | Supabase memory-manager.sh 集成 | ✅ 已恢复 |
| `src/cli/memory-cli.ts` | Termux 错误修复建议 | ✅ 已恢复 |
| `src/auto-reply/reply/memory-flush.ts` | 4层内存架构提示 | ✅ 已恢复 |

## 待检查项

- [x] 官方 CHANGELOG 更新 - 已同步
- [x] 新增的 provider 配置 - Mistral provider 已存在 (11个相关文件)
- [ ] 新增的 Synology Chat 频道 - **官方尚未发布此功能** (CHANGELOG中有但代码中未找到)
- [x] Discord Voice 依赖变更 - 已实现 fallback 逻辑 (opusscript 作为备用)
- [x] Cron 相关更新 - Cron 代码已同步 (143+ 相关文件)
- [x] Gateway 认证变更 - device-auth v2 已实现 (nonce 支持)

## 风险评估

### 高风险
- ~~Gateway device-auth v1 移除可能影响现有配对设备~~ - 已验证支持 v2

### 中风险
- streaming 配置统一可能导致现有配置迁移
- dmScope 默认值变更

### 低风险
- 新增功能通常是可选的

---

创建时间: 2026-02-23
更新时间: 2026-02-23
