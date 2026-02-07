# OpenClaw Termux Upgrade Project Plan
# v2026.1.27-termux-stable → v2026.2.6+
# 目标: 1天内完成功能拉齐

## 📊 项目概览
- **总变更量**: 797 commits
- **新功能**: 55 个
- **修复**: 275 个  
- **优先级**: Termux 兼容性 > 核心功能 > 文档

## 🎯 任务分配策略

### Agent 能力矩阵
| Agent | 强项 | 适合任务 |
|-------|------|----------|
| Codex | 复杂代码重构 | 核心代码合并、冲突解决 |
| Gemini | 快速处理、文档 | 文档更新、简单修复 |
| WSL | GPU/Docker | 构建测试、全量测试 |
| 小鸡(我) | 监督协调 | 任务分配、验证、Bug修复 |

### 验证环境
- **主开发**: ~/dev/openclaw-termux (Termux 手机)
- **验证环境**: ssh op8 (空白 Termux)
- **算力支持**: WSL (cortex3d-wsl)

---

## 📋 任务清单 (按优先级)

### P0: 核心稳定性修复 (必须)
| ID | 任务 | Commit | Agent | 状态 |
|----|------|--------|-------|------|
| P0-1 | Cron 调度可靠性修复 | d90cac990 | Codex | 🔄 进行中 (解决冲突) |
| P0-2 | Gateway 认证修复 | a459e237e | Codex | 待开始 |
| P0-3 | Session 锁释放 | ec0728b35 | Codex | 待开始 |
| P0-4 | Memory input_type 修复 | e78ae48e6 | Codex | 待开始 |
| P0-5 | resolveUserPath 空值保护 | 421644940 | Codex | 待开始 |

### P1: 重要新功能 (高优先级)
| ID | 任务 | Commit | Agent | 状态 |
|----|------|--------|-------|------|
| P1-1 | Voyage AI 原生支持 | 6965a2cc9 | Codex | 待开始 |
| P1-2 | xAI Grok 支持 | db31c0ccc | Codex | 待开始 |
| P1-3 | 百度千帆支持 | 88ffad1c4 | Codex | 待开始 |
| P1-4 | Claude Opus 4.6 | eb80b9acb | Codex | 待开始 |
| P1-5 | Cron delivery 模式增强 | 511c656cb+ | Codex | 待开始 |
| P1-6 | QR Code 技能 | ad13c265b | Gemini | 待开始 |
| P1-7 | Cloudflare AI Gateway | 5b0851ebd | Codex | 待开始 |
| P1-8 | per-channel responsePrefix | 5d82c8231 | Gemini | 待开始 |

### P2: UI/UX 改进 (中优先级)
| ID | 任务 | Commit | Agent | 状态 |
|----|------|--------|-------|------|
| P2-1 | Agents Dashboard UI | 64849e81f | Codex | 待开始 |
| P2-2 | 新消息指示器样式 | efb4a34be | Gemini | 待开始 |
| P2-3 | Dashboard 链接修复 | c5194d814 | Gemini | 待开始 |
| P2-4 | Discord set-presence | 5af322f71 | Gemini | 待开始 |

### P3: 文档更新 (低优先级)
| ID | 任务 | Commit | Agent | 状态 |
|----|------|--------|-------|------|
| P3-1 | 故障排查指南 | 9a3f62cb8 | Gemini | 待开始 |
| P3-2 | HEARTBEAT/MEMORY 引导 | a4d5c7f67 | Gemini | 待开始 |
| P3-3 | iMessage TCC 指南 | 93bf75279 | Gemini | 待开始 |

---

## 🔄 执行阶段

### 阶段 1: 准备 (00:45 - 01:00)
- [x] 任务计划制定
- [ ] op8 验证环境准备
- [ ] 创建 upgrade 分支
- [ ] 设置 Cron 监督任务

### 阶段 2: P0 核心修复 (01:00 - 04:00)
- [ ] Cherry-pick P0 修复
- [ ] Termux 兼容性验证
- [ ] 在 op8 上测试

### 阶段 3: P1 新功能 (04:00 - 12:00)
- [ ] 逐个合并新功能
- [ ] 适配 Termux 特殊路径
- [ ] 功能验证

### 阶段 4: P2/P3 改进 (12:00 - 20:00)
- [ ] UI 改进
- [ ] 文档更新
- [ ] 全量回归测试

### 阶段 5: 发布 (20:00 - 24:00)
- [ ] 在 op8 全量验证
- [ ] 合并到 main
- [ ] 打标签 v2026.2.6-termux

---

## 📝 监督规则

### Cron 监督频率: 30分钟/次
1. 检查当前任务进度
2. 查看 Agent 输出日志
3. 识别卡住/失败的任务
4. 重新分配给其他 Agent
5. 记录问题到 `.learnings/ERRORS.md`

### Agent 故障切换
- Codex 失败 2 次 → 交给 Gemini
- Gemini 失败 2 次 → 手动处理
- 任何安全问题 → 立即停止并通知

### 验证检查清单
- [ ] Gateway 启动正常
- [ ] Cron 任务执行正常
- [ ] Memory 存储/搜索正常
- [ ] 所有渠道连接正常
- [ ] 无新增 console 错误
