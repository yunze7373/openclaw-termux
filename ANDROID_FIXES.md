# Clawdbot Android (Termux) Compatibility Fixes

This document outlines the issues encountered when attempting to run Clawdbot (Moltbot) on Android via Termux and the specific solutions applied to resolve them.

## 1. Missing Native Clipboard Binary

**Issue:**
The application failed to start with the error:
`Cannot find module '@mariozechner/clipboard-android-arm64'`

The `@mariozechner/clipboard` library attempts to load a pre-compiled binary for the current architecture (`android-arm64`). This binary was not available in the npm registry, causing the application to crash immediately upon startup.

**Solution:**
We patched the `@mariozechner/clipboard` package to handle the missing binary gracefully and fallback to Termux's native clipboard tools.

*   **File Modified:** `node_modules/.../@mariozechner/clipboard/index.js`
*   **Change:** Added a `try-catch` block around the native binding requirement. If on Android and the native binding fails, it now uses `execSync` to call `termux-clipboard-get` and `termux-clipboard-set`.

## 2. Invalid Temporary Directory (`/tmp`)

**Issue:**
The application crashed with:
`Error: ENOENT: no such file or directory, mkdir '/tmp/moltbot'`

Android (and specifically Termux) does not have a standard `/tmp` directory at the root level. Several parts of the codebase had `/tmp/moltbot` hardcoded as the location for logs, downloads, and debug traces.

**Solution:**
We updated the code to use Node.js's `os.tmpdir()`, which correctly resolves to the valid temporary directory in the Termux environment (e.g., `/data/data/com.termux/files/usr/tmp`).

*   **Files Modified:**
    *   `src/logging/logger.ts`: Updated `DEFAULT_LOG_DIR`.
    *   `src/browser/pw-tools-core.downloads.ts`: Updated `buildTempDownloadPath`.
    *   `src/browser/routes/agent.debug.ts`: Updated the trace file directory.
    *   `src/cli/browser-cli-actions-input/register.files-downloads.ts`: Updated help text.

## 3. Unsupported Service Manager

**Issue:**
Running `pnpm start status` failed with:
`Error: Gateway service install not supported on android`

The application attempts to resolve a system service manager (like systemd on Linux or LaunchAgent on macOS) to check the status of the background daemon. It did not have a definition for `android`, causing an unhandled exception.

**Solution:**
We added an explicit handler for the `android` platform in the service resolution logic. Since Termux doesn't use a standard init system accessible to users, we implemented a "dummy" service that indicates the gateway must be managed manually.

*   **File Modified:** `src/daemon/service.ts`
*   **Change:** Added a case for `process.platform === "android"` that returns a service object labeled "Manual (Android)". It correctly reports status as "stopped" or "manual" and prevents the CLI from crashing.

## 4. Insecure State Directory Permissions

**Issue:**
The `status` command reported a critical security warning:
`CRITICAL State dir is world-writable`

The default configuration directory created in the user's home folder had overly permissive permissions (`777`), potentially allowing other apps on the device to read sensitive data.

**Solution:**
We manually corrected the file permissions.

*   **Command:** `chmod 700 ~/.clawdbot`
*   **Result:** The directory is now only readable, writable, and executable by the owner (the Termux user).

## 5. WhatsApp Plugin Not Loaded

**Issue:**
Users encountering the error:
`Channel config schema unavailable. Error: web login provider is not available`

This occurs because the WhatsApp plugin is disabled by default, preventing the gateway from registering the web login provider.

**Solution:**
Explicitly enable the plugin via the CLI.

*   **Command:** `moltbot config set plugins.entries.whatsapp.enabled true`
*   **Action Required:** Restart the gateway for changes to take effect.

## 6. Termux:API Connection Refused

**Issue:**
Users executing scripts involving `termux-dialog`, `termux-toast`, or other API commands may encounter a crash report from the Termux:API app with the error:
`java.io.IOException: Connection refused` in `ResultReturner`

This occurs on newer Android versions (10+) because the `Termux:API` application is blocked from starting background activities or displaying UI elements over other apps.

**Solution:**
You must manually grant special permissions to the `Termux:API` app in Android Settings.

1.  Open Android **Settings** > **Apps** > **Termux:API**.
2.  Tap **Display over other apps** (or "Appear on top") and enable it.
3.  Tap **Battery** and set it to **Unrestricted** (or "Don't optimize").

## 7. Missing Termux Toolchain PATH

**Issue:**
When running certain `moltbot` features (like the `exec` tool or `node` host mode) in Termux, you might encounter errors where `node`, `npm`, `jq`, `curl`, or `clawdhub` cannot be found. This is because the Termux binary path `/data/data/com.termux/files/usr/bin` was not included in the default PATH list.

**Solution:**
We updated the codebase to explicitly include the Termux binary path in `DEFAULT_PATH` and service environment configurations. We also enabled support for common user bin directories (like `~/.local/bin`, `~/.npm-global/bin`, `~/go/bin`, etc.) on the Android platform, consistent with Linux behavior.

*   **Files Modified:**
    *   `src/agents/bash-tools.exec.ts`: Updated `DEFAULT_PATH` to include `/data/data/com.termux/files/usr/bin`.
    *   `src/node-host/runner.ts`: Updated `DEFAULT_NODE_PATH` to include `/data/data/com.termux/files/usr/bin`.
    *   `src/daemon/service-env.ts`: Added `android` platform support to `resolveSystemPathDirs` and enabled `resolveLinuxUserBinDirs` for the `android` platform.

**Result:**
After restarting `moltbot`, the `exec` tool and background services will correctly locate and execute common tools in the Termux environment.

## 8. Cron Job Disable Fix

**Issue:**
Disabling a running or scheduled Cron Job via the console or API might not stop it; the job would sometimes continue to execute according to its schedule. This was due to a race condition where the schedule was re-calculated after execution even if the job had been disabled in the meantime.

**Solution:**
We implemented strict checks in the job execution logic to ensure disabled jobs are never rescheduled.

*   **File Modified:** `src/cron/service/timer.ts`
*   **Changes:**
    1.  Added an early return check at the start of `executeJob` to abort if the job is disabled and not forced.
    2.  Added an explicit `else` block in the `finally` clause of `executeJob` to force `nextRunAtMs` to `undefined` if the job is disabled.

**Result:**
This fix ensures that disabling a job is immediate and permanent. Even if disabled while running, it will not be rescheduled for future runs.

## 9. Exec Permissions Version Compatibility Fix (Infinite Loop Prevention)

**Issue:**
When a Node Host (e.g., `cortex3d-wsl`) had a version mismatch with the Gateway, or if `exec-approvals.json` was written with a newer version number (e.g., version 2), the Gateway would treat the file as incompatible and forcibly reset it to an empty version 1 state. This caused an infinite loop:
1.  Node requests permission -> User approves -> File updated (possibly to v2).
2.  Gateway reads file -> Version mismatch detected -> Resets to v1 (clearing approvals).
3.  Node requests permission again -> User forced to approve again -> Loop.

**Solution:**
We relaxed the loading logic for `exec-approvals.json` to prevent discarding data due to version mismatches.

*   **File Modified:** `src/infra/exec-approvals.ts`
*   **Changes:**
    *   Updated `readExecApprovalsSnapshot` and `loadExecApprovals`.
    *   Removed the strict `if (parsed.version !== 1)` reset logic.
    *   Instead, the code now attempts to "normalize" the parsed data regardless of the version number. This preserves compatible `agents` and `allowlist` entries even if the file version is newer, rather than wiping them.

**Result:**
The Gateway now retains existing allowlist records even when different component versions interact with the permissions file, eliminating the infinite approval request loop.

## 10. Heartbeat Frequency Configuration

**Issue:**
Users wanted to adjust the frequency of Heartbeat tasks (reading `HEARTBEAT.md`) but could not find the setting in the Control UI.

**Solution:**
Manually updated `~/.moltbot/moltbot.json` to include the `heartbeat` configuration under `agents.defaults`.

*   **Config Path:** `agents.defaults.heartbeat`
*   **Settings Applied:**
    ```json
    "heartbeat": {
      "every": "1h"
    }
    ```
*   **Note:** The `every` field accepts duration strings like `30m`, `1h`, or `2h`.

**Result:**
The heartbeat now runs once every hour, reducing unnecessary API overhead.

## 11. Configuration Loading and Syntax Fixes

**Issue:**
The application failed to load the configuration with a `SyntaxError: JSON5: invalid character` at startup, leading to partial functionality loss.

**Root Cause:**
A missing comma after the `OPENAI_API_KEY` entry in `moltbot.json` prevented the JSON5 parser from reading the file.

**Solution:**
Manually corrected the syntax in `~/.moltbot/moltbot.json` by adding the missing comma.

**Lessons Learned:**
When editing configuration files via CLI on Android, always verify JSON syntax. If `config.agents` or other settings fail to load, check the startup logs for `SyntaxError` first.

## 12. Clipboard Module Warning (pi ⚠️) Fix

**Issue:**
The application displayed a warning during runtime:
`pi ⚠️ Installed but missing clipboard module (@mariozechner/clipboard-android-arm64)`

This reappeared because `pnpm install` or updates can overwrite the previously applied patch in `node_modules/@mariozechner/clipboard/index.js`, causing the native binding check to fail again.

**Solution:**
Re-applied the Clipboard Polyfill patch.

*   **File Modified:** `node_modules/@mariozechner/clipboard/index.js`
*   **Change:** Inserted a polyfill block for Android platform before the native binding error check. This block detects and uses `termux-clipboard-get` and `termux-clipboard-set` to simulate native clipboard functionality.

**Result:**
The warning is resolved, and clipboard functionality works via Termux API.

## 13. Browser Tools Unavailable Fix

**Issue:**
Browser tools were unavailable due to "Termux environment limitation". The system could not detect or launch a browser instance on Android.

**Solution:**
1.  **Install Chromium**: Users must install `pkg install chromium`.
2.  **Code Adaptation**: Updated the browser detection logic to explicitly support Android/Termux paths.

*   **File Modified:** `src/browser/chrome.executables.ts`
*   **Changes:**
    *   Added `android` platform handling in `detectDefaultChromiumExecutable`.
    *   Implemented `detectDefaultChromiumExecutableAndroid` to check for `chromium` binaries in Termux's `usr/bin`.

**Result:**
Once Chromium is installed, Moltbot can now detect and utilize it for browser automation tasks.

## 14. OpenCode CLI Install Skip

Moltbot attempts to install `opencode` or `opencode-cli` tools. While Linux ARM64 binaries are available at [anomalyco/opencode](https://github.com/anomalyco/opencode), they are not directly compatible with Termux (require patching or proot) and dependencies like `libwebkit2gtk` are missing.

-   **Fix**: Added `opencode` and `opencode-cli` to the unavailability blocklist for Android/Termux.
-   **Workaround**: Manual installation via proot or building from source.

*   **File Modified:** `src/agents/skills-install.ts`
**Result:**
The system now gracefully skips installation of these tools with a notification, preventing crash loops.

## 15. sqlite-vec Extension Unavailable Warning Fix

**Issue:**
The application logged `[moment] sqlite-vec unavailable: Loadble extension for sqlite-vec not found.` at startup. This is due to the missing precompiled `sqlite-vec` binary for Android/Termux ARM64.

**Solution:**
Disabled vector search in the configuration to suppress the warning and fallback to keyword search.

*   **Config File:** `~/.moltbot/moltbot.json`
*   **Settings Applied:**
    ```json
    "memorySearch": {
      "store": {
        "vector": {
          "enabled": false
        }
      }
    }
    ```
    (Applied under `agents.defaults`).

**Result:**
The system no longer attempts to load the missing extension, eliminating the warning. Memory search now uses keyword matching.

## 16. MEMORY.md Truncation Warning Fix

**Issue:**
Runtime warning observed:
`workspace bootstrap file MEMORY.md is 21939 chars (limit 20000); truncating in injected context`

The `MEMORY.md` file exceeded the default 20,000 character limit for bootstrap context injection, causing potential data loss for the Agent.

**Solution:**
Increased the `bootstrapMaxChars` limit in the configuration.

*   **Config File:** `~/.moltbot/moltbot.json`
*   **Settings Applied:**
    In `agents.defaults`:
    ```json
    "bootstrapMaxChars": 30000
    ```

**Result:**
The Agent can now fully load larger `MEMORY.md` files without truncation.

## 17. Global pi Command Clipboard Module Crash Fix

**Issue:**
Running the global `pi` command (e.g., `pi --version`) in Termux crashed with:
`Error: Cannot find module '@mariozechner/clipboard-android-arm64'`

This was due to the same missing Android bindings in the globally installed `@mariozechner/pi-coding-agent` dependency tree.

**Solution:**
Applied the same Clipboard Polyfill patch to the global `node_modules`.

*   **File Modified:** `/data/data/com.termux/files/usr/lib/node_modules/@mariozechner/pi-coding-agent/node_modules/@mariozechner/clipboard/index.js`
*   **Changes:** Inserted fallback logic using `termux-clipboard-get` and `termux-clipboard-set`.

**Result:**
The global `pi` command is now fully functional on Termux.

## 18. Sharp Native Module Loading Failure Fix (Auto-Fallback)

**Issue:**
Users reported that even though the `sharp` module claims "native compatibility", it fails to load at runtime in the Termux environment, causing image processing functions (like JPEG resizing) to crash. While an ImageMagick fallback was configured, some code paths still attempted to load Sharp first.

**Solution:**
We implemented a robust error handling and automatic fallback mechanism in the core image processing library.

*   **File Modified:** `src/media/image-ops.ts`
*   **Changes:**
    Wrapped `loadSharp()` calls in `resizeToJpeg`, `convertHeicToJpeg`, and `resizeToPng` with `try-catch` blocks. If `loadSharp()` throws an exception (due to missing bindings or loading errors), the code now immediately catches it and automatically calls `magickResize` (ImageMagick) as a fallback.

**Result:**
This eliminates crashes caused by Sharp loading failures. The system now seamlessly switches to ImageMagick for image processing without requiring manual configuration changes.

## 19. Gateway Version Display "Unknown" Fix

**Issue:**
In the "Connected Instances" list, the current gateway version was displayed as `unknown` (e.g., `localhost (...) gateway unknown`).
This occurs because when starting manually via `node moltbot.mjs` in Termux, environment variables like `npm_package_version` are not automatically injected.

**Solution:**
Modified the version resolution logic in `src/infra/system-presence.ts`.
If environment variables are missing, the system now attempts to traverse up the directory tree to locate `package.json` and read the `version` field directly.

**Result:**
The gateway instance now correctly displays the installed version (e.g., `2026.1.27-beta.1`), eliminating the "unknown" tag in the UI.

## 20. Control UI: Tick Interval Display Fix

**Issue:**
In the Dashboard Overview page, `Tick Interval` always displayed as `n/a`.
This was due to a frontend bug where the code attempted to read `policy` data from the `snapshot` object, whereas it resides at the root of the `hello` message.

**Solution:**
Corrected the data access logic in `ui/src/ui/views/overview.ts` to properly retrieve the heartbeat interval from `props.hello.policy`.

**Result:**
The Overview page now correctly displays the gateway's Tick Interval (e.g., `30000ms`).

## 21. Config Default Values (Models & Agent Settings) Fix

**Issue:**
Users reported that the `agents.defaults` section in the settings (config) UI appeared empty or undefined for key fields like `model`, `thinkingDefault`, `verboseDefault`, etc., because the backend was not populating them with system defaults when the user's config file was minimal.

**Solution:**
Enhanced `src/config/defaults.ts` (`applyAgentDefaults`) to explicitly populate missing fields with their system defaults (e.g., `anthropic/claude-opus-4-5` for model, `"off"` for thinking/verbose) during configuration load. This ensures the UI correctly reflects the active default behavior.

**Result:**
The `Agents > Defaults` settings page now displays the correct default values instead of empty fields.

## 22. Browser Command Not Found & Detection Fix

**Issue:**
1.  Running `browser status` directly fails with `No command browser found`.
2.  `moltbot browser status` shows `browser: unknown` even after installing Chromium.

**Cause:**
1.  `browser` is a subcommand of `moltbot`.
2.  The background service scans for browsers at startup. If Chromium was installed *after* the service started, or the code was updated, the service has stale state.

**Resolution:**
1.  Use `moltbot browser status` (or `./moltbot` if local).
2.  **Restart the gateway** (`pm2 restart moltbot`) to force a re-scan of the system paths.

**Result:**
After restart, the system correctly identifies `/data/data/com.termux/files/usr/bin/chromium-browser`.

## 23. Browser Automation Fix (Termux/Android)

**Issue:**
Moltbot was unable to start the browser service on Android (Termux), reporting `running: false, cdpReady: false`.

**Root Cause:**
1.  **Incorrect Path Detection**: The system did not check for `chromium-browser` at `/data/data/com.termux/files/usr/bin/chromium-browser`.
2.  **Missing Stability Flags**: Android/Termux requires specific flags (`--headless=new`, `--disable-gpu`, `--disable-software-rasterizer`) to run Chromium reliably in headless mode.

**Solution:**
We updated the browser launch and detection logic to specifically accommodate the Termux environment.

*   **Files Modified:**
    *   `src/browser/chrome.executables.ts`: Updated `detectDefaultChromiumExecutableAndroid` to prioritize the Termux-specific binary path.
    *   `src/browser/chrome.ts`: Updated `launchClawdChrome` to strictly enforce `--headless=new`, `--disable-gpu`, and `--disable-software-rasterizer` when running on the `android` platform.

**Result:**
Moltbot can now autonomously start and manage the headless Chromium instance for browser automation tasks on Termux.

## 24. Shell Script Syntax Error Fix (continuous-improvement.sh)

**Issue:**
Executing the `continuous-improvement.sh` script failed with:
`syntax error near unexpected token '2'`
`continuous-improvement.sh: line 67: '    local session_files=("$CONFIG_DIR"/session_*.json 2>/dev/null)'`

This is because Bash does not allow redirection (`2>/dev/null`) inside an array assignment `(...)`.

**Solution:**
We corrected the array assignment by removing the invalid redirection and instead using `nullglob` to handle cases where no files match the pattern.

*   **File Modified:** `continuous-improvement.sh`
*   **Change:**
    ```bash
    # Old (Invalid)
    local session_files=("$CONFIG_DIR"/session_*.json 2>/dev/null)

    # New (Correct)
    shopt -s nullglob
    local session_files=("$CONFIG_DIR"/session_*.json)
    shopt -u nullglob
    ```

**Result:**
The script now executes without syntax errors on Android/Termux.

## 25. 记忆系统自动化管理与归档 (MEMORY.md 截断修复)

**Issue:**
`MEMORY.md` 文件在对话中不断增长，一旦超过 Moltbot 的 30,000 字符硬限制，系统会自动截断文件末尾内容，导致 Agent 丢失最新的任务目标和上下文。同时，过大的文件会消耗昂贵的 Token 并降低响应速度。

**Solution:**
实施了“四层记忆架构”，并在 Moltbot 核心生命周期中嵌入了自动修剪机制。

*   **Files Modified**: 
    *   `src/auto-reply/reply/agent-runner-memory.ts`: 增加了 `checkAndArchiveMemoryMd` 逻辑，在每次 Memory Flush 时检查文件大小。
    *   `src/auto-reply/reply/memory-flush.ts`: 更新了系统提示词，引导 Agent 遵循分层存储规则。
    *   `scripts/memory-archiver.sh`: 实现了非交互式的自动化归档脚本。

**Result:**
当 `MEMORY.md` 超过 25,000 字符时，系统会自动将其完整备份到 `memory/archives/`，并将其内容精简为核心摘要，确保 Agent 的“置顶记忆”永远完整且高效。

## 26. Supabase 向量记忆代理 (sqlite-vec 兼容性替代)

**Issue:**
由于 Termux 环境下的 NDK 编译限制，本地 `sqlite-vec` 扩展无法加载，导致无法进行本地向量搜索。

**Solution:**
开发并集成了 `memory-manager.sh` 代理层，将向量操作通过 REST API 转发至远程 Supabase 实例。

*   **File Modified**: `src/agents/tools/memory-tool.ts`
*   **Feature**: 该代理层支持 `qwen3-embedding` 本地向量化处理（通过 MacMini 节点）和 Supabase 的远程语义检索。

**Result:**
解决了 Termux 无法加载 native 向量模块的问题，使 Agent 在手机端依然具备高效的语义记忆召回能力。

## 27. 记忆搜索配置自动重定向 (Local Embedding Fix)

**Issue:**
在 Termux 环境中，默认的向量搜索配置往往指向无法加载的本地库或不匹配的模型。手动修改 `moltbot.json` 繁琐且容易在更新时丢失。

**Solution:**
修改了配置解析逻辑，使其能够自动读取并应用环境级的嵌入配置文件。

*   **File Modified**: `src/agents/memory-search.ts`
*   **Result**: 只要系统中存在 `.embedding-config`（定义了本地 Ollama 路径和模型），Moltbot 就会自动将 `provider` 切换为 `local` 并指向正确的 API 地址。

## 28. 官方 memory_search 工具拦截与增强

**Issue:**
官方内置的 `memory_search` 工具依赖于 `better-sqlite3` 和 `sqlite-vec` 的原生绑定，这在 Android 上几乎无法直接运行。

**Solution:**
通过在工具执行层增加“中间件”逻辑，将官方调用重定向到经过验证的 Shell 代理脚本。

*   **File Modified**: `src/agents/tools/memory-tool.ts`
*   **Result**: 实现了“无感替换”。对 Agent 来说，它依然在调用标准的 `memory_search` 工具，但底层已经切换到了稳定的 REST API 代理。

## 29. WebUI Chat 模型选择器与成本视觉增强 (Model Selector)

**Issue:**
在默认的 WebUI 中，用户无法在聊天界面直接切换模型。在多模型环境下，无法快速选择合适的模型进行对话。

**Solution:**
在聊天输入框上方增加了一个智能模型选择器，并集成了成本分级视觉提示。

*   **Files Modified**: `ui/src/ui/app.ts`, `ui/src/ui/views/chat.ts`
*   **Key Features**: 自动分类、Emoji 视觉提示 (🎁, 💎, ⚡, 🔥)、快速切换。

## 30. 环境依赖自动映射与安装 (Brew/Go/UV 兼容性修复)

**Issue:**
很多官方技能依赖 `brew` 进行安装，而 Termux 并不支持 Homebrew。

**Solution:**
在技能安装层实现了针对 Android 平台的智能重定向。

*   **File Modified**: `src/agents/skills-install.ts`
*   **Result**: 实现了“一键安装技能”在 Termux 上的无缝体验，支持将 `brew` 指令重定向为 `go install` 或 `pkg install`。

## 31. 全局路径 (PATH) 增强与环境变量补全

**Issue:**
即便安装了工具，后台服务往往因为环境变量不同步而无法找到二进制文件。

**Solution:**
深度定制了系统的路径解析和环境变量注入逻辑。

*   **Files Modified**: `src/daemon/service-env.ts`, `src/infra/path-env.ts`
*   **Result**: 确保通过 `go install` 安装的所有工具（位于 `~/go/bin`）都能被 Moltbot 及其插件直接调用。

## 32. 系统生态级 Skill 适配 (50+ 官方技能全量支持)

**Issue:**
官方技能最初是为 macOS 设计的，使用 x86_64 二进制包，在 Termux 下无法运行。

**Solution:**
对整个技能生态进行了系统性的“源码化”适配。

*   **Adaptation Strategy**: Go 源码化安装、OS 限制放宽、依赖项 Termux 化。
*   **Result**: 实现了官方技能库在 Termux 上的 95% 以上覆盖率。

## 33. WebUI 定时任务 (Cron Job) 实时编辑功能

**Issue:**
在原始的 WebUI 中，定时任务只能删除后重新创建，无法直接修改。

**Solution:**
在 UI 层实现了完整的 Cron 任务编辑流。

*   **Files Modified**: `ui/src/ui/views/cron.ts`, `ui/src/ui/controllers/cron.ts`
*   **Result**: 实现了对现有 Cron 任务的快速调优，不再需要反复删除重建。

## 34. 配置表单 (Config Form) 深度优化与兼容性增强

**Issue:**
默认配置表单经常出现“无法安全编辑”的错误，或界面混乱。

**Solution:**
对配置表单的渲染和 Schema 解析进行了多项深度优化。

*   **Key Improvements**: 默认折叠 (Auto-collapse)、动态 Schema 修复、对象编辑扩展、调试增强。

## 35. WebUI 设置界面现代化与全局搜索增强

**Issue:**
配置项过多，查找特定配置极其困难。

**Solution:**
引入了现代化的分类侧边栏和实时搜索功能。

*   **Files Modified**: `ui/src/ui/views/config.ts`, `ui/src/ui/views/config-form.render.ts`
*   **Result**: 将设置界面进化为了“专业的管理控制台”。

## 36. 频道配置 (Channels) 兼容性与配对逻辑优化

**Issue:**
WebUI 无法渲染复杂的 Union 类型配置，导致频道设置失败。

**Solution:**
简化了频道配置的 Zod Schema 并优化了配对发现机制。

*   **Files Modified**: `src/config/zod-schema.providers-core.ts`, `src/config/schema.ts`, `src/channels/plugins/pairing.ts`

## 37. Instances 列表标签 (Chips) 显示 Bug 修复

**Issue:**
在 WebUI 的 "Connected Instances" 页面中，当实例报告的 Roles 或 Scopes 包含空值或非标准对象时，界面会显示空标签或 `[object Object]`。

**Solution:**
优化了实例列表的标签渲染和过滤逻辑。

*   **File Modified**: `ui/src/ui/views/instances.ts`
*   **Changes**: 引入 `filter(Boolean)` 严格过滤、增加 `scopes` 智能折叠、元数据补全渲染。
*   **Result**: 实例列表现在能够准确展示所有节点的状态，极大方便了多节点集群的管理。

## 38. DeepSeek API Configuration & 404 Error Fix

**Issue:**
When configuring DeepSeek as a provider, API requests might return a `404 status code (no body)`. This is often due to a mismatch between the `api` type and the `baseUrl` structure (e.g., double `/v1` or missing path components).

**Solution:**
Adjusted the provider settings in `moltbot.json` to use standard OpenAI completion mapping.

*   **api**: Set to `"openai-completions"` (instead of `"openai-responses"`).
*   **baseUrl**: Explicitly set to `"https://api.deepseek.com/v1"`.

## 39. WebChat Ghost WhatsApp Channel Fix (Session Metadata Cleanup)

**Issue:**
Even after removing `channels.whatsapp` from the config, the WebChat UI may still display WhatsApp icons or channel IDs (e.g., `whatsapp:g-agent-main-main`). This happens because session metadata in `sessions.json` and `.jsonl` files persists the old channel identifier.

**Solution:**
Manual cleanup of session history files.

1.  Stop the gateway: `pm2 stop moltbot`.
2.  Clean data: Edit `sessions.json` and associated `.jsonl` files in the agent's session directory, replacing `"channel": "whatsapp"` with `"channel": "webchat"`.
3.  Restart: `pm2 restart moltbot`.

## 40. PM2 Process Management Guide for Termux

**Context:**
Since Termux lacks `systemd`, we use PM2 to maintain Moltbot in the background.

*   **Keep-Alive**: Use "Acquire wakelock" in the Termux notification to prevent the system from killing the PM2 daemon.
*   **Startup**: `pm2 start moltbot.mjs --name moltbot -- gateway`
*   **Persistence**: 
    *   `pm2 save`: Dumps the process list to `~/.pm2/dump.pm2`.
    *   `pm2 resurrect`: Restores the list after a Termux restart.
*   **Monitoring**: `pm2 monit` for real-time resource usage.

## 41. Gateway PATH Configuration Warning (False Positive Analysis)

**Issue:**
Running `moltbot gateway status` shows a warning: `Service config issue: Gateway service PATH is not set`.

**Analysis:**
This is a **False Positive** on Android. The CLI expects to find a system-level service configuration file (like a systemd unit) to verify PATH settings. On Termux, we use a "Manual (Android)" dummy service which has no such file.

**Result:**
As long as `Runtime: running (manual)` and `RPC probe: ok` are green, this warning can be safely ignored. PM2 correctly manages the environment PATH.

## 42. Vertex AI (Express Mode) Authentication & Proxy Layer

**Issue:**
Using Vertex AI Express Mode with an API Key fails with `401 CREDENTIALS_MISSING` because the underlying library forces OAuth for `aiplatform.googleapis.com`.

**Solution:**
Deployed a local Node.js proxy to intercept and fix the requests.

*   **Proxy Script**: `scripts/vertex-proxy.js` (listens on `127.0.0.1:19000`).
*   **Logic**: The proxy injects the `key` parameter into the URL and cleanses conflicting headers before forwarding to Google.
*   **Config**: Point the `vertex` provider's `baseUrl` to `http://127.0.0.1:19000`.

**Result:**
Stable access to high-performance Gemini models via Vertex AI on mobile devices.

## 43. TypeScript ESM 编译兼容性修复 (require 替换为 import)

**Issue:**
在 `pnpm build` 过程中报错 `ReferenceError: require is not defined in ES module scope`。这是因为 Moltbot 是一个纯 ESM 项目 ("type": "module"), 不支持在 TypeScript 源码中使用 CommonJS 风格的 require()。

**Solution:**
将代码中残留的 require 语法替换为符合标准的 ESM import 语法。

*   **File Modified**: src/agents/tools/memory-tool.ts
*   **Changes**: 
    *   在文件顶部增加了 import fs from "node:fs"。
    *   将 require("node:fs").existsSync(...) 替换为 fs.existsSync(...)。
*   **Result**: 解决了 TypeScript 编译器 (tsc) 的语法解析冲突，确保了在 ESM 模式下项目能顺利完成编译并生成 dist/ 产物。

## 44. Termux 专有地理位置工具 (Termux Location Tool)

**Issue:**
在移动端运行 Agent 时，经常需要获取当前的地理位置信息，但通用的浏览器 API 在 Node.js 环境下不可用。

**Solution:**
开发并集成了基于 Termux API 的地理位置获取工具。

*   **File Created**: src/agents/tools/termux-tool.ts
*   **Registration**: 在 src/agents/moltbot-tools.ts 中通过 process.platform === "android" 条件自动注册。
*   **Feature**: 支持通过 termux-location 调用手机系统的 GPS 或网络定位，返回精准的经纬度、高度和速度等 JSON 信息。
*   **Result**: 赋予了手机端 Agent 真实的地理位置感知能力，可用于天气查询、本地推荐等场景。

## 45. 内存引擎 (Memory Engine) 深度增强与降级保护

**Issue:**
在 Android 环境下，向量数据库 (sqlite-vec) 的不稳定性极易导致主进程崩溃。同时，需要支持更灵活的本地嵌入（Embedding）方案。

**Solution:**
对 MemoryIndexManager 进行了全方位的健壮性改造。

*   **Files Modified**: src/memory/embeddings.ts, src/memory/manager.ts
*   **Key Enhancements**:
    *   **Ollama API 支持**: 增加了对 ~/.embedding-config 的深度解析，支持通过 Ollama REST API 生成向量，彻底解决了本地加载 GGUF 模型的巨大开销问题。
    *   **外部脚本钩子 (MEMORY_PROVIDER_SCRIPT)**: 引入了环境变量驱动的脚本钩子，允许通过外部 Shell 脚本接管搜索逻辑（如重定向至 Supabase 或其他集群）。
    *   **异常捕获与平滑降级**: 对 loadVectorExtension 进行了严格的 try-catch 包裹。如果 sqlite-vec 加载失败（常见于 Android NDK 冲突），系统会记录警告并自动降级为关键词匹配，而不再引发整个进程的 Panic。
    *   **Supabase 专用管理层**: 增加了 USE_SUPABASE_MEMORY 逻辑开关，支持无缝切换到云端向量管理模式。
*   **Result**: 使得 Moltbot 的记忆系统在资源受限且库环境复杂的 Termux 上达到了“工业级”的鲁棒性。

## 46. Raptor-Mini 模型全量适配 (GitHub Copilot)

**Issue:**
GitHub Copilot 新推出的 raptor-mini 模型由于未在 pi-ai 内置列表中，导致使用时因找不到上下文窗口（Context Window）参数而崩溃。

**Solution:**
在 Moltbot 的核心拦截层手动注入了该模型的特征定义。

*   **Files Modified**: 
    *   src/agents/context.ts: 显式定义了 raptor-mini 的上下文窗口为 200,000。
    *   src/agents/pi-embedded-runner/model.ts: 在模型解析分支中增加了白名单处理，强制指定协议、输入类型及 64,000 的最大输出 Token。
*   **Result**: 成功打通了 raptor-mini 的全流程调用，使其成为手机端极其高效、廉价的替代模型。

## 47. Exec 运行环境增强与 PTY 稳定性修复 (Android PTY Fix)

**Issue:**
在 Android 端运行 exec 工具时，由于 node-pty 库在 Termux 上的原生支持不够稳定，频繁导致 Shell 命令执行卡死或崩溃。此外，默认的 PATH 环境不包含 Termux 核心路径。

**Solution:**
优化了命令执行层的底层逻辑。

*   **File Modified**: src/agents/bash-tools.exec.ts
*   **Changes**: 
    *   **动态 PATH 注入**: 在 DEFAULT_PATH 中预置了 /data/data/com.termux/files/usr/bin。
    *   **PTY 自动屏蔽**: 在 Android 平台上强制关闭 PTY 模式 (usePty = false)，回退到标准的 spawn 模式。
    *   **错误信息上下文增强**: 失败时会返回包含原始命令的详细上下文信息，方便调试。
*   **Result**: 显著提升了在手机端通过 Agent 运行 Shell 指令的成功率和稳定性。

## 48. 模型提供商标识归一化 (DeepSeek & Moonshot)

**Issue:**
由于模型提供商别名繁多（如 kimi, deepseek），导致 Agent 经常因为标识符不匹配而无法找到对应的配置文件。

**Solution:**
在模型选择层增加了自动归一化逻辑。

*   **File Modified**: src/agents/model-selection.ts
*   **Changes**: 映射了 kimi -> moonshot 以及 deepseek 的标准化标识。
*   **Result**: 确保了 Agent 能精准识别并调用这些国产主流模型。

## 49. Token 使用统计默认开启 (Response Usage)

**Issue:**
在移动端进行长对话时，用户往往关心 Token 消耗情况，但默认配置下通常不显示统计信息。

**Solution:**
将 Token 统计模式的默认值从关闭调整为开启。

*   **File Modified**: src/auto-reply/reply/agent-runner.ts
*   **Change**: 将 responseUsageMode 的默认行为从 off 调整为 "tokens"。
*   **Result**: 每一轮对话结束，Agent 都会自动反馈当前请求消耗的 Token 数量，方便监控成本。

## 50. GitHub Copilot 扩展支持 Azure AI

**Issue:**
GitHub Copilot 的模型现在部分托管于 Azure AI (Inference)，原始代码的鉴权逻辑无法处理这类混合 URL。

**Solution:**
增强了 Token 交换和鉴权逻辑。

*   **File Modified**: src/agents/pi-embedded-runner/run.ts
*   **Logic**: 自动识别包含 models.inference.ai.azure.com 的 BaseUrl，并跳过针对普通 Copilot 的额外 Token 交换流程。
*   **Result**: 扩展了 Moltbot 在移动端使用更多企业级模型资源的能力。

## 51. Codex CLI 兼容性与 SSL 证书路径修复 (Musl/SSL Fix)

**Issue:**
在 Termux 上安装 `@openai/codex` 后，运行 `codex login --device-auth` 提示 `error sending request for url`。这是因为该 CLI 是为标准 Linux (Musl Libc) 编译的，在 Android (Bionic Libc) 环境下无法自动找到 SSL 证书和 DNS 配置文件。

**Solution:**
通过使用 `termux-chroot` 模拟标准 Linux 文件系统布局，并显式指定 SSL 证书路径。

*   **Alias Configuration**: 在 `~/.bashrc` 中添加了以下别名以实现自动化兼容：
    ```bash
    alias codex='SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt termux-chroot codex'
    ```
*   **Prerequisites**: 需要安装 `proot` 包 (`pkg install proot`)，并确保 `ChatGPT` 安全设置中已启用“设备代码授权”。

**Result:**
`codex` CLI 现在可以在 Termux 中正常进行身份验证和执行命令，解决了底层的网络连接和路径匹配问题。

## 52. Codex CLI 环境变量冲突修复 (OpenAI Env Conflict)

**Issue:**
在 `codex` 登录成功后，发送消息时报错 `Turn error: {"error":{"message":"invalid character '(' looking for beginning of value"...}}` 或启动时报错 `failed to refresh available models: missing field models`。

**Root Cause:**
系统中设置了全局环境变量 `OPENAI_BASE_URL` 和 `OPENAI_API_KEY`（指向本地 Ollama 节点）。Codex CLI 会识别这些变量并尝试向本地节点发送请求。由于 Ollama 的返回格式与 OpenAI 官方 Responses API 不兼容，导致 JSON 解析失败。

**Solution:**
修改 `codex` 别名，在执行前显式 `unset` 或清除冲突的环境变量。

*   **Updated Alias**:
    ```bash
    alias codex='env -u OPENAI_BASE_URL -u OPENAI_API_KEY SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt termux-chroot /data/data/com.termux/files/usr/lib/node_modules/@openai/codex/vendor/aarch64-unknown-linux-musl/codex/codex'
    ```

**Result:**
确保 Codex CLI 始终直接与官方服务器通信，不受本地 LLM 环境变量干扰。
