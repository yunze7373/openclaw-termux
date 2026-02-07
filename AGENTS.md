# AGENTS.md - OpenClaw Termux 开发团队协作规范

## 🎯 项目概述

**项目**: openclaw-termux - Moltbot 的 Android/Termux 兼容性分支
**仓库**: https://github.com/a12jump/openclaw-termux
**上游**: https://github.com/clawdbot/clawdbot

---

## 🏛️ 团队架构

### 小鸡 (Moltbot) - 协调中枢 / Tech Lead

**职责**:
- 📋 **任务分发**: 从 Notion 读取Pending任务，分发给合适的 Agent
- 🔄 **进度追踪**: 定期检查各 Agent 工作状态，更新 Notion
- 🔧 **轻量修改**: 直接处理简单的代码修改和文档更新
- 📊 **整合汇报**: 向韩哥汇报整体进度，提醒Review任务
- 🚨 **问题处理**: 识别Blocked任务，协调资源解决

**心跳检查清单** (每 30 分钟):
1. 读取 Notion `Moltbot Tasks` 数据库
2. 检查 "Pending" 任务 → 分发
3. 检查 "In Progress" 任务 → 确认状态
4. 检查 "Blocked" 任务 → 通知韩哥
5. 检查 "Review" 任务 → 提醒韩哥

**Notion 数据库 ID**: `300c3533-cc2f-812e-8789-ff7f8de1f31c`

---

## 👥 开发成员

### Codex - Senior Developer

**能力**: 复杂代码重构、Bug 修复、新功能开发
**调用方式**: `sessions_spawn` 或 `exec pty`
**工作目录**: `~/dev/openclaw-termux/` (与小鸡共用)

**任务接收格式**:
```
你是 Codex，OpenClaw Termux 项目的 Senior Developer。

当前任务 (来自 Notion):
- Task ID: OT-XXX
- 标题: XXX
- 分支: feat/xxx
- 详情: XXX

工作目录: ~/dev/openclaw-termux/
Done后:
1. 提交代码: git add -A && git commit -m "feat: xxx"
2. 推送分支: git push origin feat/xxx
3. 回复Done状态
```

---

### Gemini CLI - Fast Developer

**能力**: 快速代码生成、文档编写、数据分析
**调用方式**: `exec gemini`
**工作目录**: `~/dev/openclaw-termux/` (与小鸡共用)

**任务接收格式**:
```bash
gemini -p "任务: XXX
工作目录: ~/dev/openclaw-termux/
要求: XXX"
```

---

### WSL Node - Build Engineer

**能力**: 构建、测试、GPU 计算、官方合并
**调用方式**: `nodes run --node cortex3d-wsl`
**工作目录**: `~/dev/openclaw-termux/`

**任务接收格式**:
```bash
nodes run --node cortex3d-wsl --command "cd ~/dev/openclaw-termux && git pull && pnpm test"
```

---

### Mac Mini - UI/TTS Developer

**能力**: macOS 特性开发、TTS 测试、UI 调试
**调用方式**: `nodes run --node mac-mini` 或 SSH
**工作目录**: `~/dev/openclaw-termux/`

---

### 树莓派 - Edge Tester

**能力**: ARM 平台测试、边缘场景验证
**调用方式**: SSH
**工作目录**: `~/dev/openclaw-termux/`

---

### 韩哥 (Human) - PM / 总指挥

**职责**:
- 🎯 项目方向决策
- ✅ PR 审核与合并
- 📝 需求定义
- 🔑 生产环境部署授权

**通信方式**: Telegram / Web Chat

---

## 📋 Notion 任务管理

### 数据库字段

| 字段 | 说明 |
|------|------|
| Task ID | 唯一标识 (OT-001, OT-002...) |
| 标题 | 任务描述 |
| 状态 | Pending / In Progress / Blocked / Review / Done |
| 负责人 | 小鸡 / Codex / Gemini / WSL / MacMini / 韩哥 |
| 优先级 | P0 紧急 / P1 高 / P2 中 / P3 低 |
| 分支 | Git 分支名 |
| 项目 | openclaw-termux / 其他 |
| 备注 | 进度说明、问题描述 |

### 状态流转

```
Pending → In Progress → Review → Done
              ↓
            Blocked → In Progress
```

---

## 🔄 Git 工作流

### 分支策略

```
main              ────●────●────●────▶  (稳定版本)
                      │    │    │
feat/xxx         ─────┴────┴────┴────▶  (功能分支)
hotfix/xxx       ─────────────────────▶  (紧急修复)
```

### 提交规范

```
<type>(<scope>): <description>

类型: feat / fix / docs / refactor / test / chore
范围: browser / memory / tts / termux / ...
```

### 常用命令

```bash
# 开始新任务
git checkout -b feat/OT-XXX
git pull origin main

# 提交并推送
git add -A
git commit -m "feat(xxx): 描述"
git push origin feat/OT-XXX

# 合并到 main (由韩哥审核后执行)
git checkout main
git merge feat/OT-XXX
git push origin main
```

---

## 🚀 快速开始

1. **查看待办任务**: 访问 Notion 或等待小鸡分发
2. **领取任务**: 更新 Notion 状态为 "In Progress"
3. **创建分支**: `git checkout -b feat/OT-XXX`
4. **Done开发**: 编写代码、测试
5. **提交推送**: `git push origin feat/OT-XXX`
6. **更新状态**: Notion 状态改为 "Review"

---

*最后更新: 2026-02-07*
