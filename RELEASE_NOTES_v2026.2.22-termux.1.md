# 🚀 OpenClaw Termux 2026.2.22

稳定版发布，包含 PM2 服务管理完整修复和 Termux/Android 部署优化。

## ✨ 本版本亮点

### 🔧 核心修复
- **PM2 Service Management**: 修复 `gateway start` vs `gateway run` 命令混淆，解决服务持续重启问题 (#fixes 191+ restarts)
- **Git Branch Sync**: 自动处理分支发散和脏工作目录，--update 时确保切换到 main 分支
- **TypeScript Compilation**: 简化 Termux 编译流程，移除不稳定的 tsdown
- **Package Lock Handling**: 改进 dpkg 锁检测和 pkg upgrade 处理

### 📱 Termux/Android 优化
- Node.js 24.13.0 支持和验证
- pnpm 包管理器完整集成
- Android root 文件系统兼容性修复
- `/tmp` 目录硬编码替换为 `os.tmpdir()`

### 🛠️ 安装脚本改进
- `./Install_termux_cn.sh --full` - 完整首次安装（依赖 + 构建 + PM2 服务）
- `./Install_termux_cn.sh --update` - 增量更新，自动清理并同步 main 分支
- improved progress output 和 error handling

## 📦 升级指南

### 自动更新
```bash
cd ~/dev/openclaw-termux
./Install_termux_cn.sh --update
```

### 首次安装 (Termux)
```bash
curl -fsSL https://raw.githubusercontent.com/yunze7373/openclaw-termux/main/Install_termux_cn.sh | bash -s -- --full
```

## 🔐 安全性
- CWE-319: WebSocket plaintext 连接限制为 loopback 地址，远程需使用 Tailscale + wss://
- 所有数据库、配置文件、日志统一使用 `~/.openclaw/` 中心化管理
- 敏感凭证从不存储在代码中

## 📋 已知问题与解决方案

| 问题                | 解决方案                                                                |
| ------------------- | ----------------------------------------------------------------------- |
| PM2 unknown in PATH | 安装：`npm install -g pm2`                                              |
| pnpm install 超时   | 使用国内镜像：`pnpm config set registry https://registry.npmmirror.com` |
| sharp 编译失败      | `.npmrc` 已配置镜像；确保是 ARM64 设备                                  |
| Gateway 无法启动    | 运行 `openclaw doctor` 诊断，检查 `pm2 logs openclaw-gateway`           |

## 🔗 资源
- 📖 文档: https://docs.openclaw.ai
- 🐛 反馈: https://github.com/yunze7373/openclaw-termux/issues
- 📱 Android 设备要求: ARM64, Android 9+, 4GB+ RAM 推荐

---

**发布日期**: 2026-02-24  
**提交**: `5a505e3d` (main)  
**维护者**: @yunze7373

## 版本历史
- **2026.2.22** (current) - PM2 service fixes + installation script improvements
- **2026.2.21** and earlier - Previous releases
