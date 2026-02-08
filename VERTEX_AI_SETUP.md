# Moltbot Vertex AI (Express Mode) 配置报告

本文档总结了在 Termux 环境下为 Moltbot 配置 Vertex AI 的现状、原理及维护说明。

## 1. 核心架构：本地代理模式

由于 Moltbot 底层库对 Vertex AI 域名的鉴权限制，我们采用了**本地代理转发**方案。

*   **代理地址**: `http://127.0.0.1:19000`
*   **转发目标**: `https://aiplatform.googleapis.com/v1/publishers/google`
*   **功能**: 自动在所有请求中注入 `VERTEX_API_KEY` (使用 `?key=...` 参数)，并清洗可能导致 401 错误的干扰请求头。

## 2. 提供者 (Providers) 现状

| 提供者 | 标识符 (Prefix) | 鉴权 Key | 连接方式 | 特点 |
| :--- | :--- | :--- | :--- | :--- |
| **Vertex AI** | `vertex/` | `VERTEX_API_KEY` | 经由本地代理 | **主力使用**。使用 Google Cloud 赠金，额度高且稳定。 |
| **AI Studio** | `gemini/` | `GEMINI_API_KEY` | 直连 Google | **备用**。配置简单，但免费层级极易限流 (429)。 |
| **DeepSeek** | `deepseek/` | `DEEPSEEK_API_KEY` | 直连 DeepSeek | **独立运行**。不受代理影响，随时可切回。 |

## 3. 自动化与自启动 (PM2)

目前 `moltbot` 和 `vertex-proxy` 均由 **PM2** 管理。

*   **查看状态**: `pm2 list`
*   **自启动保障**: 只要执行过 `pm2 save`，下次启动 PM2 时，网关和代理会**同时启动**。
*   **切换逻辑**: 
    *   当选择 `vertex/...` 模型时，Moltbot 自动连接本地代理。
    *   当选择 `deepseek/...` 或 `gemini/...` 时，Moltbot **自动恢复直连模式**，不经过代理。

## 4. 维护与 Key 更新

Key 统一存储在 `~/.moltbot/moltbot.json` 的 `env.vars` 中：

*   **更新 Vertex Key**: 修改 `VERTEX_API_KEY` 的值。
*   **同步操作**: 更新 `env.vars` 后，建议运行 `node scripts/final-key-sync.js` 确保 Provider 内部的硬编码部分也同步更新（虽然代理会自动读取 env，但部分内部校验仍需同步）。
*   **重启命令**: `pm2 restart all`

## 5. 常见问题 (Q&A)

**Q: 为什么会有 429 错误？**
A: 这是 Google 服务端对预览版模型（如 Gemini 3 Pro）的频率限制。
**解决**: 切换到 `vertex/gemini-2.5-flash`，该模型的配额非常充足。

**Q: 为什么不直接调用 Vertex？**
A: 库限制。Moltbot 在检测到 Vertex 域名时会强制要求 OAuth 认证，通过本地代理转发可以“欺骗”库，从而支持使用简单的 API Key。
