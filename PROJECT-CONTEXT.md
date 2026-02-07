# 项目信息

## 基本信息
- **项目名称**: Moltbot (Termux Fork)
- **仓库**: github.com/yunze7373/openclaw-termux
- **Workspace**: github.com/yunze7373/openclaw-termux-workspace
- **目标**: 在 Android Termux 环境运行的个人 AI 助手

## 主要特性
- Termux 完全兼容 (Android 原生支持)
- 多节点分布式架构 (Termux + WSL + Mac Mini + Raspberry Pi)
- 集成小鸡语音助手 (XiaoJi v9.3)
- 记忆系统 (Supabase Vector DB + qwen3-embedding)
- 多渠道支持 (Telegram, WhatsApp, WebChat)
- Agent 编排系统 (Codex/Gemini 子任务分发)

## 技术栈
- Node.js 22+ (Termux)
- TypeScript
- Supabase (Vector DB)
- Ollama (本地 embedding)
- Gemini CLI (快速任务)
- Codex CLI (复杂编程任务)

## 部署环境
- 主节点: Android Termux (手机)
- 算力节点: WSL2 (Windows GPU)
- 推理节点: Mac Mini (Ollama)
- 边缘节点: Raspberry Pi 4

## 与上游的关系
- Fork 自: github.com/moltbot/moltbot (upstream)
- 主要改动: Termux 兼容性补丁 + 中文语音 + 记忆系统增强
- 定期 cherry-pick upstream 更新

## 核心差异
- 完全 Termux 适配 (路径、权限、剪贴板、音频)
- 中文语音系统 (Mac TTS + 振动音乐)
- 专属技能 (Voice Notify, Memory Manager, Vibration Music, Netease Music, CDP Browser)
- 分布式 Agent 编排
