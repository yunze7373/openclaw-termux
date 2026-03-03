# Clawdbot Android (Termux) 兼容性修复文档

本文档整理了在 Android Termux 环境下运行 Clawdbot (Moltbot) 时遇到的问题及其具体解决方案。

## 1. 缺失原生剪贴板二进制文件 (Native Clipboard Binary)

**问题描述：**
应用启动时报错：
`Cannot find module '@mariozechner/clipboard-android-arm64'`

`@mariozechner/clipboard` 库尝试根据当前架构（`android-arm64`）加载预编译的二进制文件。由于 npm 仓库中缺少该平台的二进制包，导致应用在启动阶段直接崩溃。

**解决方案：**
我们对 `@mariozechner/clipboard` 包进行了补丁处理，使其在缺失原生绑定时能够平滑降级，转而使用 Termux 自带的剪贴板工具。

*   **修改文件：** `node_modules/.../@mariozechner/clipboard/index.js`
*   **具体改动：** 在加载原生绑定的代码外层添加了 `try-catch` 逻辑。在 Android 平台上，如果原生绑定加载失败，将通过 `child_process.execSync` 调用 Termux 的 `termux-clipboard-get` 和 `termux-clipboard-set` 命令来实现剪贴板功能。

## 2. 无效的临时目录 (`/tmp`)

**问题描述：**
应用崩溃并提示：
`Error: ENOENT: no such file or directory, mkdir '/tmp/moltbot'`

Android（尤其是 Termux）在根目录下没有标准的 `/tmp` 目录。代码库中多处硬编码了 `/tmp/moltbot` 作为日志、下载文件和调试追踪（trace）的存放位置。

**解决方案：**
将硬编码的路径修改为动态获取 Node.js 的 `os.tmpdir()`。在 Termux 环境中，这会正确指向有效的临时目录（例如 `/data/data/com.termux/files/usr/tmp`）。

*   **修改涉及文件：**
    *   `src/logging/logger.ts`: 更新了 `DEFAULT_LOG_DIR`。
    *   `src/browser/pw-tools-core.downloads.ts`: 更新了 `buildTempDownloadPath` 函数。
    *   `src/browser/routes/agent.debug.ts`: 更新了浏览器追踪文件的存放目录。
    *   `src/cli/browser-cli-actions-input/register.files-downloads.ts`: 更新了相关命令的帮助提示文本。

## 3. 不支持的服务管理器 (Service Manager)

**问题描述：**
执行 `pnpm start status` 时报错：
`Error: Gateway service install not supported on android`

应用会尝试识别系统服务管理器（如 Linux 的 systemd 或 macOS 的 LaunchAgent）来检查后台守护进程的状态。由于缺少对 `android` 平台的定义，导致抛出未处理的异常。

**解决方案：**
在服务解析逻辑中增加了对 `android` 平台的显式支持。由于 Termux 环境下用户无法直接使用标准系统级服务管理，我们实现了一个“手动管理”的虚拟服务模式。

*   **修改文件：** `src/daemon/service.ts`
*   **具体改动：** 增加了 `process.platform === "android"` 的判断分支，返回一个标记为 "Manual (Android)" 的服务对象。该对象会正确返回“未安装”或“手动运行”的状态，从而避免 CLI 崩溃。

## 4. 状态目录权限安全隐患

**问题描述：**
`status` 命令报告了一个严重的安全警告：
`CRITICAL State dir is world-writable`

在用户家目录下默认创建的配置目录（`~/.clawdbot`）权限过于宽松（`777`），这可能导致设备上的其他应用读取到敏感的配置数据。

**解决方案：**
手动修正了目录权限。

*   **执行命令：** `chmod 700 ~/.clawdbot`
*   **修复结果：** 现在该目录仅限当前 Termux 用户读写和执行，提高了安全性。

## 5. WhatsApp 插件未自动加载

**问题描述：**
用户在尝试登录或配置 WhatsApp 频道时报错：
`Channel config schema unavailable. Error: web login provider is not available`

这是因为 WhatsApp 插件默认处于禁用状态，导致网关无法识别相关的登录方法。

**解决方案：**
通过 CLI 显式启用该插件。

*   **执行命令：** `moltbot config set plugins.entries.whatsapp.enabled true`
*   **后续操作：** 需重启网关才能生效。

## 6. Termux:API 连接被拒绝 (Connection Refused)

**问题描述：**
用户在执行包含 `termux-dialog`、`termux-toast` 或其他 API 命令的脚本时，Termux:API 应用可能会崩溃并报告错误：
`java.io.IOException: Connection refused` at `ResultReturner`

此问题常见于较新版本的 Android (10+)，原因是 `Termux:API` 应用被系统限制，无法在后台启动或在其他应用之上显示界面。

**解决方案：**
需要在 Android 系统设置中手动授予 `Termux:API` 应用特殊权限。

1.  打开 Android **设置 (Settings)** > **应用 (Apps)** > **Termux:API**。
2.  点击 **显示在其他应用上层 (Display over other apps)** 并开启。
3.  点击 **电池 (Battery)** 并设置为 **无限制 (Unrestricted)**。

## 7. DeepSeek API 配置与 404 错误

**问题描述：**
配置 DeepSeek 模型提供商时，API 请求返回 `404 status code (no body)`。

这通常是由于 `baseUrl` 与 `api` 类型不匹配导致的路径构造错误：
*   如果使用 `api: "openai-responses"`，内部客户端可能会错误地处理 `baseUrl`（导致双重 `/v1` 或其他路径错误）。
*   如果 `baseUrl` 缺少 `/v1`，某些客户端实现可能无法正确追加路径。

**解决方案：**
在 `~/.moltbot/moltbot.json` 中，将 DeepSeek 提供商的配置调整为使用标准的 OpenAI 完成接口模式：

1.  **api**: 设置为 `"openai-completions"`（而不是 `"openai-responses"`）。
2.  **baseUrl**: 明确设置为 `"https://api.deepseek.com/v1"`。

示例配置：
```json
"deepseek": {
  "baseUrl": "https://api.deepseek.com/v1",
  "apiKey": "sk-...",
  "api": "openai-completions",
  "models": [...] 
}
```

## 8. WebChat 前端显示已移除的 WhatsApp 频道

**问题描述：**
即使在配置文件中移除了 `channels.whatsapp`，WebChat 前端界面仍然显示 `whatsapp:g-agent-main-main` 或 WhatsApp 图标。

这是因为会话元数据（存储在 `sessions.json` 和 `.jsonl` 历史文件中）持久化了之前的频道信息 (`channel: "whatsapp"`)，前端 UI 会优先读取这些历史记录来渲染界面。

**解决方案：**
需要手动清理会话数据中的频道标记：

1.  **停止服务**：`pm2 stop moltbot`
2.  **清理数据**：编辑 `~/.moltbot/agents/main/sessions/sessions.json` 和所有 `.jsonl` 文件，将 `"channel": "whatsapp"` 替换为 `"channel": "webchat"`（或删除该字段）。
3.  **重启服务**：`pm2 restart moltbot`

## 9. PM2 进程管理指南 (后台运行原理)

在 Android Termux 环境中，由于缺乏 Linux 标准的 `systemd` 或 `init` 服务管理系统，我们使用 **PM2** (Process Manager 2) 来托管和维持 Moltbot 网关的后台运行。

### 核心原理
PM2 是一个守护进程管理器，它在用户空间运行。
1.  **守护进程 (Daemon)**: 当你第一次执行 `pm2` 命令时，它会在后台启动一个 `PM2 God Daemon` 进程。这个进程负责孵化、监控并重启你的应用。
2.  **Keep-Alive**: 如果 Moltbot 崩溃，PM2 会自动尝试重启它。
3.  **Android 限制**: PM2 仅在 Termux 处于活动状态（或持有 Wake Lock）时运行。如果 Android 系统杀死了 Termux 后台进程，PM2 也会随之停止。建议在 Termux 通知栏中点击 "Acquire wakelock" 以防止被系统杀后台。

### 常用管理命令

#### 1. 启动服务 (Start)
启动 Moltbot 网关 Standard 命令：
```bash
pm2 start moltbot.mjs --name moltbot -- gateway
```
*   `moltbot.mjs`: 入口文件。
*   `--name moltbot`: 给进程起个名字叫 "moltbot"，方便后续管理。
*   `--`: 这是一个分隔符，后面的参数会传给脚本，而不是传给 PM2。
*   `gateway`: 传递给 moltbot 的子命令，告诉它启动网关模式。

#### 2. 查看状态 (List & Monit)
查看所有运行中的进程：
```bash
pm2 list
```
查看 CPU/内存占用仪表盘：
```bash
pm2 monit
```

#### 3. 查看日志 (Logs)
这是排查问题最重要的命令：
```bash
# 查看所有日志（实时滚动）
pm2 logs

# 仅查看 moltbot 的日志，并显示最近 100 行
pm2 logs moltbot --lines 100
```

#### 4. 重启服务 (Restart)
当你修改了配置文件 (`moltbot.json`) 或更新了代码后，必须重启才能生效：
```bash
pm2 restart moltbot
```
*提示：这会平滑重启进程，通常不会导致长时间的断连。*

#### 5. 停止与删除 (Stop & Delete)
停止运行但保留配置（仍在列表中）：
```bash
pm2 stop moltbot
```
彻底从 PM2 列表中移除（下次需要重新使用 `start` 命令启动）：
```bash
pm2 delete moltbot
```

### 持久化与恢复 (Persistence)
虽然 PM2 无法在 Android 重启后自动自启（除非配置 `Termux:Boot`），但你可以保存当前的运行列表，以便下次快速恢复。

1.  **保存当前列表** (Save):
    ```bash
pm2 save
```
    这会将当前运行的进程列表转储到 `~/.pm2/dump.pm2` 文件中。

2.  **恢复列表** (Resurrect):
    如果 Termux 完全关闭或手机重启，重新进入 Termux 后：
    ```bash
pm2 resurrect
```
    这会读取转储文件并一次性复活所有进程。

## 10. Gateway PATH 配置警告 (False Positive)

**问题描述：**
运行 `moltbot gateway status` 时，可能会看到以下警告：
```text
Service: Manual (Android) (inactive)
Service config issue: Gateway service PATH is not set; the daemon should use a minimal PATH.
```

**原因解释：**
这是一个**误报 (False Positive)**。
Clawdbot CLI 设计用于检查系统级服务（如 `systemd` 或 `launchd`）的配置文件是否正确设置了环境变量（PATH）。在 Android Termux 上，我们无法安装系统级服务，而是通过 `src/daemon/service.ts` 返回了一个虚拟的 "Manual (Android)" 服务状态。由于这个虚拟服务没有实际的配置文件供 CLI 读取，CLI 的检查逻辑会认为“未设置 PATH”并发出警告。

**是否需要修复：**
**不需要。** 只要 `Runtime: running (manual)` 和 `RPC probe: ok` 显示正常（这表明网关进程实际上正在运行且可访问），您就可以安全地忽略关于 "Service config issue" 的警告。此时 PM2 正在接管环境管理，它会自动继承正确的 Termux PATH。

## 11. Termux 工具链 PATH 缺失修复

**问题描述：**
在 Termux 环境下，执行 `moltbot` 的某些功能（如 `exec` 工具或 `node` 托管模式）时，可能会遇到找不到 `node`, `npm`, `jq`, `curl` 或 `clawdhub` 的错误。这是因为 Termux 的二进制路径 `/data/data/com.termux/files/usr/bin` 未包含在默认的 PATH 列表中。

**解决方案：**
我们修改了以下文件，显式地将 Termux 的二进制路径添加到 `DEFAULT_PATH` 和服务环境配置中。同时，我们启用了对 Android 平台上常见用户 bin 目录（如 `~/.local/bin`, `~/.npm-global/bin`, `~/go/bin` 等）的支持，与 Linux 行为保持一致。

*   **修改文件：**
    *   `src/agents/bash-tools.exec.ts`: 更新 `DEFAULT_PATH` 包含 `/data/data/com.termux/files/usr/bin`。
    *   `src/node-host/runner.ts`: 更新 `DEFAULT_NODE_PATH` 包含 `/data/data/com.termux/files/usr/bin`。
    *   `src/daemon/service-env.ts`: 在 `resolveSystemPathDirs` 函数中添加 `android` 平台支持，并为 `android` 平台启用了 `resolveLinuxUserBinDirs`。

**修复效果：**
重启 `moltbot` 后，`exec` 工具和后台服务将能够正确找到并执行 Termux 环境中的常用工具。

## 12. 定时任务 (Cron Job) 禁用不生效修复

**问题描述：**
用户在控制台或通过 API 禁用 (disable) 了一个正在运行或计划中的定时任务 (Cron Job) 后，该任务可能并未停止，而是继续按照原定计划执行。这通常发生在任务执行过程中被禁用，导致调度状态未能正确清除。

**解决方案：**
我们对定时任务执行逻辑进行了严格的防御性编程，确保任务在禁用状态下绝对不会被重新调度。

*   **修改文件：** `src/cron/service/timer.ts`
*   **具体改动：**
    1.  在任务执行函数 `executeJob` 的开头增加了检查，如果任务已被禁用且非强制执行，直接返回。
    2.  在 `executeJob` 的 `finally` 块中增加显式的 `else` 分支：如果任务被禁用，强制将下一次运行时间 (`nextRunAtMs`) 设置为 `undefined`。

**修复效果：**
此修复消除了禁用操作与任务执行之间的竞态条件。无论任务处于何种状态，一旦被禁用，它将在本次执行结束后彻底停止，不再产生新的调度。

## 13. Exec 权限文件版本兼容性修复 (防止重置死循环)

**问题描述：**
当 Node Host（如 `cortex3d-wsl`）与 Gateway 版本不一致，或 `exec-approvals.json` 文件被写入了较新的版本号（如 version 2）时，Gateway 会认为文件格式不兼容并将其强制重置为空的 version 1 状态。这会导致以下死循环：
1.  Node 请求权限 -> 用户批准 -> 文件更新为 v2（或包含新字段）。
2.  Gateway 读取文件 -> 发现版本不匹配 -> 重置为 v1（清空批准记录）。
3.  Node 再次请求权限 -> 用户被迫再次批准 -> 循环。

**解决方案：**
我们放宽了 `exec-approvals.json` 的加载逻辑，不再因版本号不匹配而直接丢弃所有数据。

*   **修改文件：** `src/infra/exec-approvals.ts`
*   **具体改动：**
    *   修改 `readExecApprovalsSnapshot` 和 `loadExecApprovals` 函数。
    *   移除 `if (parsed.version !== 1)` 的强制重置逻辑。
    *   改为尝试对读取到的数据进行“归一化” (normalize)。这意味着即使版本号是 2，我们也会尽可能保留其中兼容的 `agents` 和 `allowlist` 数据，而不是直接清空。

**修复效果：**
现在即使不同版本的组件同时修改权限文件，Gateway 也会保留已有的白名单记录，避免了反复请求权限的死循环。

## 14. 心跳任务 (Heartbeat) 频率配置

**问题描述：**
用户希望修改心跳任务（读取 `HEARTBEAT.md` 并执行任务）的执行频率，但在控制台 UI 中未能找到相关设置。

**解决方案：**
手动修改 `~/.moltbot/moltbot.json` 配置文件，在 `agents.defaults` 中增加 `heartbeat` 配置。

*   **修改位置：** `agents.defaults.heartbeat`
*   **具体配置：**
    ```json
    "heartbeat": {
      "every": "1h"
    }
    ```
*   **配置说明：** `every` 字段接受时长字符串（如 `30m`, `1h`, `2h`）。

**效果：**
心跳任务现在将每 1 小时执行一次，减少了对 API 的调用频率。

## 15. 配置文件加载与语法错误修复

**问题描述：**
`moltbot` 启动时报错 `SyntaxError: JSON5: invalid character '"' at 12:7`，导致配置无法正确加载，Agent 功能受限。

**原因分析：**
在手动或通过工具编辑 `moltbot.json` 时，`OPENAI_API_KEY` 字段后缺失了逗号，导致 JSON5 解析失败。

**解决方案：**
修正了 `~/.moltbot/moltbot.json` 中的语法错误，补全了缺失的逗号。

**经验教训：**
在 Android 环境下通过命令行编辑 JSON 文件时，务必确保语法的严谨性。如果发现 `config.agents` 或其他配置项未生效，应优先检查日志中的 `SyntaxError`。

## 16. 剪贴板模块缺失警告 (pi ⚠️) 修复

**问题描述：**
应用运行时出现警告：
`pi ⚠️ Installed but missing clipboard module (@mariozechner/clipboard-android-arm64)`

这是因为 `pnpm install` 或更新操作可能会覆盖之前对 `node_modules/@mariozechner/clipboard/index.js` 应用的补丁，导致原生绑定检查再次失败。

**解决方案：**
重新应用了剪贴板模块的 Polyfill 补丁。

*   **修改文件：** `node_modules/@mariozechner/clipboard/index.js`
*   **具体改动：** 在加载原生绑定的代码外层添加了 `try-catch` 逻辑。在 Android 平台上，如果原生绑定加载失败，将通过 `child_process.execSync` 调用 Termux 的 `termux-clipboard-get` 和 `termux-clipboard-set` 命令来实现剪贴板功能。

**修复效果：**
警告信息消失，剪贴板功能通过 Termux API 正常工作。

## 17. 浏览器工具 (Browser Tools) 不可用修复

**问题描述：**
Moltbot 提示浏览器工具不可用或“Environment limitation”。这是因为 Chromium 浏览器未被检测到或无法在 Termux 环境下启动。

**解决方案：**
1.  **安装 Chromium**: 用户需手动安装 `pkg install chromium`。
2.  **代码适配**: 我们修改了浏览器检测逻辑，使其在 Android 平台上能够识别 Termux 安装的 Chromium 二进制文件。

*   **修改文件：** `src/browser/chrome.executables.ts`
*   **具体改动：**
    *   在 `detectDefaultChromiumExecutable` 函数中增加了对 `android` 平台的处理。
    *   新增 `detectDefaultChromiumExecutableAndroid` 函数，专门检测 `/data/data/com.termux/files/usr/bin/chromium` 和 `chromium-browser`。

**修复效果：**
安装 Chromium 后，Moltbot 能够正确识别并调用浏览器进行自动化任务（需要配合 X11/Wayland 或 headless 模式）。

## 18. OpenCode CLI 安装跳过

Moltbot 可能会尝试安装 `opencode` 或 `opencode-cli` 工具。虽然 [anomalyco/opencode](https://github.com/anomalyco/opencode) 提供了 Linux ARM64 二进制文件，但它们与 Termux 不直接兼容（需要 pathcing 或 proot），且缺少 `libwebkit2gtk` 等依赖项。

-   **修复**: 已将 `opencode` 和 `opencode-cli` 添加到 Android/Termux 平台的不可用黑名单中。
-   **变通方法**: 通过 proot 手动安装或从源码构建。

*   **修改文件：** `src/agents/skills-install.ts`
**效果：**
当系统尝试安装这些工具时，它将直接跳过并显示不可用，而不是报错。这允许相关的 Agent 继续运行（尽管可能会缺少某些功能）。

## 19. sqlite-vec 扩展不可用警告修复

**问题描述：**
应用运行时提示 `[moment] sqlite-vec unavailable: Loadble extension for sqlite-vec not found.`。这是因为 `sqlite-vec` 向量搜索扩展缺少适用于 Android/Termux ARM64 架构的预编译二进制文件。

**解决方案：**
在配置文件中禁用向量搜索功能（回退到纯文本搜索），以消除警告并防止加载错误。

*   **修改配置文件：** `~/.moltbot/moltbot.json`
*   **具体配置：**
    在 `agents.defaults` 下添加或更新 `memorySearch` 配置：
    ```json
    "memorySearch": {
      "store": {
        "vector": {
          "enabled": false
        }
      }
    }
    ```

**效果：**
系统将不再尝试加载 `sqlite-vec` 扩展，消除了相关的启动警告。记忆搜索将降级使用关键词匹配。

## 20. MEMORY.md 截断警告修复 (bootstrapMaxChars)

**问题描述：**
应用运行时出现警告：
`workspace bootstrap file MEMORY.md is 21939 chars (limit 20000); truncating in injected context`

这是因为 `MEMORY.md` 文件的大小超过了默认的上下文注入限制（20,000 字符），导致部分记忆内容被截断，可能影响 Agent 的表现。

**解决方案：**
在配置文件中增加 `bootstrapMaxChars` 参数，提高注入限制。

*   **修改配置文件：** `~/.moltbot/moltbot.json`
*   **具体配置：**
    在 `agents.defaults` 下添加：
    ```json
    "bootstrapMaxChars": 30000
    ```
    （或设置为更大的值，视 `MEMORY.md` 实际大小而定）。

**效果：**
Agent 能够完整读取较大的 `MEMORY.md` 文件，不再出现截断警告。

## 21. 全局 pi 命令剪贴板模块崩溃修复

**问题描述：**
在 Termux 中运行全局 `pi` 命令（如 `pi --version`）时崩溃，报错：
`Error: Cannot find module '@mariozechner/clipboard-android-arm64'`

这是因为全局安装的 `@mariozechner/pi-coding-agent` 所依赖的剪贴板模块也存在 Android 平台绑定缺失的问题。

**解决方案：**
对全局 `node_modules` 中的剪贴板模块应用同样的 Polyfill 补丁。

*   **修改文件：** `/data/data/com.termux/files/usr/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/clipboard/index.js`
*   **具体改动：** 插入针对 Termux 的 `termux-clipboard-get/set` 回退逻辑。

**修复效果：**
全局 `pi` 命令现在可以正常运行，不再崩溃。

## 22. Sharp 模块原生加载失败修复 (ImageMagick 自动回退)

**问题描述：**
用户报告称，在 Termux 环境下，即使 `sharp` 模块显示为“原生兼容”，但在实际运行时仍无法加载，导致图像处理功能（如 JPEG 缩放、PNG 转换）崩溃。虽然配置了 ImageMagick 作为降级方案，但部分代码路径仍尝试优先加载 Sharp。

**解决方案：**
我们在图像处理核心库中增加了更激进的错误捕获和自动回退机制。

*   **修改文件：** `src/media/image-ops.ts`
*   **具体改动：**
    在 `resizeToJpeg`, `convertHeicToJpeg`, `resizeToPng` 等核心函数中，将 `loadSharp()` 调用包裹在 `try-catch` 块中。
    如果 `loadSharp()` 抛出异常（无论是因为缺少原生绑定还是加载失败），代码将立即捕获该异常并自动调用 `magickResize` (ImageMagick) 作为后备方案。

**修复效果：**
消除了由于 Sharp 加载失败导致的崩溃。系统现在能够平滑地切换到 ImageMagick 进行图像处理，无需用户手动更改环境变量或配置文件。

## 23. 网关版本显示未知 (Unknown) 修复

**问题描述：**
在 "Connected Instances" 列表中，当前网关的版本号显示为 `unknown`（例如 `localhost (...) gateway unknown`）。
这是因为在 Termux 中通过 `node moltbot.mjs` 手动启动时，`process.env.npm_package_version` 等环境变量未被自动注入。

**解决方案：**
修改了 `src/infra/system-presence.ts` 中的版本获取逻辑。
如果环境变量缺失，系统现在会尝试向上遍历目录查找 `package.json` 并读取其中的 `version` 字段。

**修复效果：**
网关实例现在能正确显示当前安装的版本号（如 `2026.1.27-beta.1`），消除了界面上的 "unknown" 标记。

## 24. Control UI: Tick Interval 显示修复

**问题描述：**
在 Dashboard 的 Overview 页面中，`Tick Interval` 始终显示为 `n/a`。
这是因为前端代码错误地尝试从 `snapshot` 对象中读取 `policy` 数据，而实际上 `policy` 位于 `hello` 消息的根层级。

**解决方案：**
修正了 `ui/src/ui/views/overview.ts` 中的数据读取逻辑，现在正确地从 `props.hello.policy` 中获取心跳间隔 (Tick Interval)。

**修复效果：**
Overview 页面现在能正确显示网关的 Tick Interval（例如 `30000ms`）。

## 25. 配置默认值 (模型与代理设置) 加载修复

**问题描述：**
用户反馈称 `agents.defaults` 配置页面（Control UI）中的许多设置项（如默认模型、思考模式、详细模式等）没有显示默认值，而是显示为空或未定义。这是因为当用户配置文件中未显式设置这些项时，后端没有自动填充系统默认值。

**解决方案：**
修改了 `src/config/defaults.ts` 中的 `applyAgentDefaults` 函数。现在，如果配置文件中缺失 `model`, `thinkingDefault`, `verboseDefault`, `elevatedDefault` 等关键字段，系统会自动注入内置的默认值（例如 `anthropic/claude-opus-4-5`）。

**修复效果：**
Control UI 的 "Agents > Defaults" 设置页现在能正确显示系统当前的默认配置，而非空白。

## 26. Browser Command Not Found 误区澄清与检测修复

**问题描述：**
1.  用户安装了 Chromium 后，尝试在终端直接运行 `browser status`，遇到报错 `No command browser found`。
2.  运行 `moltbot browser status` 时，显示 `browser: unknown`，即未检测到浏览器。

**原因解释：**
1.  `browser` 是 `moltbot` 的子命令，不是独立命令。
2.  Moltbot 的后台服务（Gateway）在启动时会扫描系统路径。如果在服务启动**之后**才安装 Chromium，或者我们刚刚更新了检测代码，**后台服务需要重启**才能加载新的配置和路径。

**解决方案：**
1.  使用正确的命令：`./moltbot browser status` 或 `moltbot browser status`。
2.  **重启服务**：执行以下命令重启后台进程，使其重新扫描浏览器路径：
    ```bash
    pm2 restart moltbot
    ```

**结果：**
重启后，`moltbot browser status` 将正确显示 `detectedPath: .../chromium-browser`，Agent 即可正常调用浏览器。

## 27. 常用技能在 Android/Termux 下的安装与运行支持 (Go/Node)

**问题描述：**
在 Android/Termux 环境下尝试安装 `camsnap`, `gifgrep`, `goplaces`, `summarize`, `openhue`, `ordercli`, `sag`, `songsee` 等技能时，系统通常会提示 `Skipped: '...' is not available on Android/Termux`。这是因为这些技能默认仅提供 `brew` 安装方式，且在安装脚本中被显式禁用了。

**解决方案：**
1.  **扩展安装方式**：
    *   为 `camsnap`, `gifgrep`, `goplaces`, `openhue`, `ordercli`, `sag`, `songsee` 增加了 `go install` 安装方式。
    *   为 `summarize` 增加了 `node` (npm) 安装方式。
2.  **解除黑名单**：在 `src/agents/skills-install.ts` 中将上述技能从 Android 平台的不可用列表中移除。
3.  **完善服务路径**：在 `src/daemon/service-env.ts` 中将 `~/go/bin` 添加到服务运行环境的 PATH 中，确保系统能正确识别 Go 安装的工具。

**修复效果：**
用户现在可以在 Termux 中通过控制台 UI 或 CLI 成功安装并运行这些技能。
*   安装示例：`moltbot skills install camsnap go` 或 `moltbot skills install summarize npm`。

**注意**：部分工具可能需要额外系统依赖（如 `camsnap` 需要 `ffmpeg`，`sag` 需要 `mpv`），请根据提示执行 `pkg install <pkg>`。

## 28. 脚本语法错误修复 (continuous-improvement.sh)

**问题描述：**
在执行 `continuous-improvement.sh` 脚本时报错：
`syntax error near unexpected token '2'`
`continuous-improvement.sh: line 67: '    local session_files=("$CONFIG_DIR"/session_*.json 2>/dev/null)'`

这是因为在 Bash 中，不允许在数组赋值语句 `(...)` 内部直接进行重定向（`2>/dev/null`）。

**解决方案：**
修正了数组赋值语句，移除了非法的重定向，改用 `nullglob` 选项来优雅地处理 pattern 匹配不到文件的情况。

*   **修改文件：** `continuous-improvement.sh`
*   **具体改动：**
    ```bash
    # 旧代码（非法语法）
    local session_files=("$CONFIG_DIR"/session_*.json 2>/dev/null)

    # 新代码（修正后）
    shopt -s nullglob
    local session_files=("$CONFIG_DIR"/session_*.json)
    shopt -u nullglob
    ```

**修复效果：**
脚本现在可以在 Android/Termux 环境下正常运行，不再报语法错误。

## 29. Vertex AI (Express Mode) 鉴权与代理修复

**问题描述：**
在 Termux 环境下使用 Vertex AI (Express Mode) 的 API Key 时，Moltbot 报错 `401 CREDENTIALS_MISSING`。这是因为 Moltbot 底层库在识别到 `aiplatform.googleapis.com` 域名时，会强制要求 OAuth 认证而忽略 API Key。

**解决方案：**
部署了一个本地代理转发器 (`vertex-proxy`)，将请求从本地 `127.0.0.1:19000` 转发至 Google，并在转发过程中强制注入 API Key 参数并清洗干扰请求头。

*   **修改涉及文件：**
    *   `scripts/vertex-proxy.js`: 新增代理脚本。
    *   `~/.moltbot/moltbot.json`: 将 `vertex` 提供商的 `baseUrl` 指向本地代理。
*   **详细配置说明：** 参见 [VERTEX_AI_SETUP.md](./VERTEX_AI_SETUP.md)。

**效果：**
用户可以稳定使用 Vertex AI 的高性能模型（如 `gemini-3-pro-preview`），且支持在 Web UI 中随时在 Vertex、AI Studio 和 DeepSeek 之间无缝切换。

## 运行状态总结
目前应用已可以正常启动。您可以使用以下命令：

```bash
cd clawdbot
pnpm start status
pnpm start gateway --port 18789
```

**注意：** 由于缺乏系统级的后台服务管理器，建议在独立的终端会话中运行 Gateway，或者使用 `nohup` 等工具使其在后台持续运行。