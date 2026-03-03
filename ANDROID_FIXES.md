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

## 25. Automated Memory Management & Archiving (MEMORY.md Truncation Fix)

**Issue:**
The `MEMORY.md` file keeps growing during conversations. Once it exceeds Moltbot's 30,000 character hard limit, the system automatically truncates the end of the file, causing the Agent to lose the latest task goals and context. Meanwhile, excessively large files consume expensive tokens and slow down response speeds.

**Solution:**
Implemented a "Four-Tier Memory Architecture" and embedded an automatic pruning mechanism within Moltbot's core lifecycle.

*   **Files Modified**: 
    *   `src/auto-reply/reply/agent-runner-memory.ts`: Added `checkAndArchiveMemoryMd` logic to check file size during every Memory Flush.
    *   `src/auto-reply/reply/memory-flush.ts`: Updated system prompts to guide the Agent to follow tiered storage rules.
    *   `scripts/memory-archiver.sh`: Implemented a non-interactive automated archiving script.

**Result:**
When `MEMORY.md` exceeds 25,000 characters, the system automatically backs it up fully to `memory/archives/` and streamlines its content to a core summary, ensuring the Agent's "pinned memory" remains complete and efficient.

## 26. Supabase Vector Memory Proxy (sqlite-vec Compatibility Replacement)

**Issue:**
Due to NDK compilation limitations in the Termux environment, the local `sqlite-vec` extension cannot be loaded, preventing local vector searches.

**Solution:**
Developed and integrated a `memory-manager.sh` proxy layer to forward vector operations to a remote Supabase instance via REST API.

*   **File Modified**: `src/agents/tools/memory-tool.ts`
*   **Feature**: This proxy layer supports `qwen3-embedding` local vectorization (via MacMini node) and Supabase's remote semantic retrieval.

**Result:**
Resolved the issue of Termux being unable to load native vector modules, enabling the Agent to maintain efficient semantic memory recall capabilities on mobile devices.

## 27. Memory Search Config Auto-Redirection (Local Embedding Fix)

**Issue:**
In the Termux environment, default vector search configurations often point to unloadable local libraries or mismatched models. Manually modifying `moltbot.json` is tedious and prone to being lost during updates.

**Solution:**
Modified the configuration parsing logic to automatically read and apply environment-level embedding configurations.

*   **File Modified**: `src/agents/memory-search.ts`
*   **Result**: As long as `.embedding-config` exists in the system (defining local Ollama path and model), Moltbot automatically switches the `provider` to `local` and points to the correct API address.

## 28. Official memory_search Tool Interception & Enhancement

**Issue:**
The official built-in `memory_search` tool relies on native bindings for `better-sqlite3` and `sqlite-vec`, which are nearly impossible to run directly on Android.

**Solution:**
Added "middleware" logic at the tool execution layer to redirect official calls to a verified Shell proxy script.

*   **File Modified**: `src/agents/tools/memory-tool.ts`
*   **Result**: Achieved "seamless replacement". To the Agent, it is still calling the standard `memory_search` tool, but the underlying implementation has switched to a stable REST API proxy.

## 29. WebUI Chat Model Selector & Cost Visual Enhancement (Model Selector)

**Issue:**
In the default WebUI, users cannot switch models directly in the chat interface. In a multi-model environment, it is impossible to quickly select the appropriate model for conversation.

**Solution:**
Added a smart model selector above the chat input box and integrated cost-tiered visual cues.

*   **Files Modified**: `ui/src/ui/app.ts`, `ui/src/ui/views/chat.ts`
*   **Key Features**: Auto-classification, Emoji visual cues (🎁, 💎, ⚡, 🔥), quick switching.

## 30. Environment Dependency Auto-Mapping & Installation (Brew/Go/UV Compatibility Fix)

**Issue:**
Many official skills rely on `brew` for installation, but Termux does not support Homebrew.

**Solution:**
Implemented intelligent redirection for the Android platform at the skill installation layer.

*   **File Modified**: `src/agents/skills-install.ts`
*   **Result**: Achieved a seamless "one-click skill installation" experience on Termux, supporting redirection of `brew` commands to `go install` or `pkg install`.

## 31. Global Path (PATH) Enhancement & Env Var Injection

**Issue:**
Even after installing tools, background services often failed to find binaries due to asynchronous environment variables.

**Solution:**
Deeply customized the system's path resolution and environment variable injection logic.

*   **Files Modified**: `src/daemon/service-env.ts`, `src/infra/path-env.ts`
*   **Result**: Ensures that all tools installed via `go install` (located in `~/go/bin`) can be directly invoked by Moltbot and its plugins.

## 32. Ecosystem-wide Skill Adaptation (50+ Official Skills Supported)

**Issue:**
Official skills were originally designed for macOS using x86_64 binaries, rendering them inoperable on Termux.

**Solution:**
Performed a systematic "source-based" adaptation of the entire skill ecosystem.

*   **Adaptation Strategy**: Source-based Go installation, relaxed OS restrictions, Termux dependency mapping.
*   **Result**: Achieved over 95% coverage of the official skill library on Termux.

## 33. WebUI Cron Job Real-time Editing

**Issue:**
In the original WebUI, cron jobs could only be deleted and recreated, not modified directly.

**Solution:**
Implemented a full Cron task editing flow in the UI layer.

*   **Files Modified**: `ui/src/ui/views/cron.ts`, `ui/src/ui/controllers/cron.ts`
*   **Result**: Enabled rapid tuning of existing Cron tasks without the need for repeated deletion and recreation.

## 34. Config Form Optimization & Compatibility Enhancement

**Issue:**
The default configuration form often displayed "Unable to safely edit" errors or was cluttered.

**Solution:**
Performed deep optimizations on config form rendering and Schema parsing.

*   **Key Improvements**: Auto-collapse defaults, dynamic Schema repair, extended object editing, enhanced debugging.

## 35. WebUI Settings Modernization & Global Search

**Issue:**
With too many configuration items, finding specific settings was extremely difficult.

**Solution:**
Introduced a modern sidebar with categories and real-time search functionality.

*   **Files Modified**: `ui/src/ui/views/config.ts`, `ui/src/ui/views/config-form.render.ts`
*   **Result**: Evolved the settings interface into a "Professional Management Console".

## 36. Channels Configuration Compatibility & Pairing Logic Optimization

**Issue:**
WebUI failed to render complex Union type configurations, causing channel setup failures.

**Solution:**
Simplified the Zod Schema for channel configurations and optimized the pairing discovery mechanism.

*   **Files Modified**: `src/config/zod-schema.providers-core.ts`, `src/config/schema.ts`, `src/channels/plugins/pairing.ts`

## 37. Instances List Chips Display Bug Fix

**Issue:**
In the WebUI "Connected Instances" page, when instances reported Roles or Scopes containing empty values or non-standard objects, the interface displayed empty tags or `[object Object]`.

**Solution:**
Optimized tag rendering and filtering logic for the instance list.

*   **File Modified**: `ui/src/ui/views/instances.ts`
*   **Changes**: Introduced `filter(Boolean)` strict filtering, smart folding for `scopes`, and metadata completion rendering.
*   **Result**: The instance list now accurately displays the status of all nodes, greatly facilitating multi-node cluster management.

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

## 43. TypeScript ESM Compilation Compatibility (Replace require with import)

**Issue:**
During `pnpm build`, an error `ReferenceError: require is not defined in ES module scope` occurred. This is because Moltbot is a pure ESM project ("type": "module") and does not support CommonJS-style `require()` in TypeScript source.

**Solution:**
Replaced residual `require` syntax with standard ESM `import` syntax.

*   **File Modified**: `src/agents/tools/memory-tool.ts`
*   **Changes**: 
    *   Added `import fs from "node:fs"` at the top of the file.
    *   Replaced `require("node:fs").existsSync(...)` with `fs.existsSync(...)`.
*   **Result**: Resolved TypeScript compiler (tsc) syntax conflicts, ensuring the project compiles and generates `dist/` artifacts correctly in ESM mode.

## 44. Termux Location Tool (Termux Location Tool)

**Issue:**
When running the Agent on mobile, it often needs to access current geolocation information, but generic browser APIs are unavailable in the Node.js environment.

**Solution:**
Developed and integrated a geolocation tool based on Termux API.

*   **File Created**: `src/agents/tools/termux-tool.ts`
*   **Registration**: Automatically registered in `src/agents/moltbot-tools.ts` via `process.platform === "android"` condition.
*   **Feature**: Supports calling the phone's GPS or network location via `termux-location`, returning precise JSON data including latitude, longitude, altitude, and speed.
*   **Result**: Empowered the mobile Agent with real geolocation awareness, useful for weather queries, local recommendations, etc.

## 45. Memory Engine Deep Enhancement & Fallback Protection

**Issue:**
In the Android environment, the instability of the vector database (`sqlite-vec`) easily caused main process crashes. Also needed to support more flexible local Embedding schemes.

**Solution:**
Completely revamped `MemoryIndexManager` for robustness.

*   **Files Modified**: `src/memory/embeddings.ts`, `src/memory/manager.ts`
*   **Key Enhancements**:
    *   **Ollama API Support**: Added deep parsing of `~/.embedding-config`, supporting vector generation via Ollama REST API, completely solving the massive overhead of loading GGUF models locally.
    *   **External Script Hook (MEMORY_PROVIDER_SCRIPT)**: Introduced an environment variable-driven script hook, allowing external Shell scripts to take over search logic (e.g., redirecting to Supabase or other clusters).
    *   **Exception Catching & Smooth Fallback**: Strictly wrapped `loadVectorExtension` in try-catch. If `sqlite-vec` fails to load (common with Android NDK conflicts), the system logs a warning and automatically downgrades to keyword matching instead of panicking the entire process.
    *   **Supabase Management Layer**: Added `USE_SUPABASE_MEMORY` logic switch to support seamless switching to cloud-based vector management.
*   **Result**: Achieved "industrial-grade" robustness for Moltbot's memory system on the resource-constrained and environmentally complex Termux.

## 46. Raptor-Mini Model Full Adaptation (GitHub Copilot)

**Issue:**
The newly introduced `raptor-mini` model in GitHub Copilot was not in the built-in list of `pi-ai`, causing crashes due to missing `Context Window` parameters.

**Solution:**
Manually injected the feature definition for this model in Moltbot's core interception layer.

*   **Files Modified**: 
    *   `src/agents/context.ts`: Explicitly defined `raptor-mini` context window as 200,000.
    *   `src/agents/pi-embedded-runner/model.ts`: Added whitelist processing in the model parsing branch, forcing specification of protocol, input type, and max output tokens of 64,000.
*   **Result**: Successfully enabled full workflow invocation for `raptor-mini`, making it an extremely efficient and cheap alternative model on mobile.

## 47. Exec Runtime Enhancement & PTY Stability Fix (Android PTY Fix)

**Issue:**
When running `exec` tools on Android, the `node-pty` library's native support on Termux was unstable, causing frequent shell command freezes or crashes. Additionally, the default PATH environment did not include Termux core paths.

**Solution:**
Optimized the underlying logic of the command execution layer.

*   **File Modified**: `src/agents/bash-tools.exec.ts`
*   **Changes**: 
    *   **Dynamic PATH Injection**: Pre-populated `/data/data/com.termux/files/usr/bin` in `DEFAULT_PATH`.
    *   **PTY Auto-Disable**: Forced PTY mode off (`usePty = false`) on Android platform, falling back to standard `spawn` mode.
    *   **Contextual Error Info**: Enhanced failure messages with the original command context for easier debugging.
*   **Result**: Significantly improved the success rate and stability of running Shell commands via Agent on mobile.

## 48. Model Provider ID Normalization (DeepSeek & Moonshot)

**Issue:**
Due to numerous model provider aliases (e.g., kimi, deepseek), the Agent often failed to find corresponding config files due to mismatched identifiers.

**Solution:**
Added automatic normalization logic in the model selection layer.

*   **File Modified**: `src/agents/model-selection.ts`
*   **Changes**: Mapped `kimi` -> `moonshot` and standardized `deepseek` identifiers.
*   **Result**: Ensured the Agent can accurately identify and invoke these mainstream domestic models.

## 49. Token Usage Stats Default On (Response Usage)

**Issue:**
During long conversations on mobile, users often care about Token consumption, but the default configuration usually hid this information.

**Solution:**
Changed default Token statistics mode from off to on.

*   **File Modified**: `src/auto-reply/reply/agent-runner.ts`
*   **Change**: Changed `responseUsageMode` default behavior from `off` to `"tokens"`.
*   **Result**: Upon completion of each dialogue turn, the Agent automatically reports the Token count consumed by the current request, facilitating cost monitoring.

## 50. GitHub Copilot Azure AI Support

**Issue:**
GitHub Copilot models are now partially hosted on Azure AI (Inference), and the original code's auth logic could not handle such hybrid URLs.

**Solution:**
Enhanced Token exchange and authentication logic.

*   **File Modified**: `src/agents/pi-embedded-runner/run.ts`
*   **Logic**: Automatically identifies BaseUrls containing `models.inference.ai.azure.com` and skips the extra Token exchange process for ordinary Copilot.
*   **Result**: Extended Moltbot's capability to use more enterprise-grade model resources on mobile.

## 51. Codex CLI Compatibility & SSL Cert Path Fix (Musl/SSL Fix)

**Issue:**
After installing `@openai/codex` on Termux, running `codex login --device-auth` failed with `error sending request for url`. This is because the CLI is compiled for standard Linux (Musl Libc) and cannot automatically find SSL certificates and DNS configs in the Android (Bionic Libc) environment.

**Solution:**
Simulated standard Linux file system layout using `termux-chroot` and explicitly specified the SSL certificate path.

*   **Alias Configuration**: Added the following alias in `~/.bashrc` for automated compatibility:
    ```bash
    alias codex='SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt termux-chroot codex'
    ```
*   **Prerequisites**: Requires `proot` package (`pkg install proot`) and "Device Code Authorization" enabled in `ChatGPT` security settings.

**Result:**
`codex` CLI can now authenticate and execute commands normally in Termux, resolving underlying network connection and path matching issues.

## 52. Codex CLI Environment Variable Conflict Fix (OpenAI Env Conflict)

**Issue:**
After successful `codex` login, sending messages failed with `Turn error: {"error":{"message":"invalid character '(' looking for beginning of value"...}}` or startup failed with `failed to refresh available models: missing field models`.

**Root Cause:**
Global environment variables `OPENAI_BASE_URL` and `OPENAI_API_KEY` (pointing to local Ollama node) were set. Codex CLI picks these up and attempts to request the local node. Since Ollama's return format is incompatible with OpenAI Official Responses API, JSON parsing failed.

**Solution:**
Modified the `codex` alias to explicitly `unset` or clear conflicting environment variables before execution.

*   **Updated Alias**:
    ```bash
    alias codex='env -u OPENAI_BASE_URL -u OPENAI_API_KEY SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt termux-chroot /data/data/com.termux/files/usr/lib/node_modules/@openai/codex/vendor/aarch64-unknown-linux-musl/codex/codex'
    ```

**Result:**
Ensures Codex CLI always communicates directly with official servers, unaffected by local LLM environment variables.

## 53. Skills Installation Termux Compatibility Layer

**Issue:**
Running `openclaw onboard --install-daemon` to install skills results in numerous failures:
- `E: Unable to locate package steipete/tap` - macOS-only brew taps
- `ERR_PNPM_NO_GLOBAL_BIN_DIR` - PNPM_HOME not set for global installs
- `E: Unable to locate package 1password-cli` - packages not in Termux repos

**Solution:**
Added a comprehensive Termux compatibility layer in `skills-install.ts`:

*   **File Modified:** `src/agents/skills-install.ts`
*   **Key Changes:**
    1.  **`isTermux` helper**: Unified detection via `TERMUX_VERSION` or `process.platform === "android"`.
    2.  **`BREW_TO_PKG_MAP`**: Maps common brew formulas to Termux pkg names (e.g., `go` → `golang`, `node` → `nodejs-lts`).
    3.  **`isMacOSOnlyFormula()`**: Detects brew taps (formulas with `/`) and gracefully skips them with a clear error message.
    4.  **PNPM_HOME injection**: Automatically sets `PNPM_HOME` environment variable for node global installs.
    5.  **GOPATH/GOBIN injection**: Automatically sets Go paths for Termux go installs.

**Result:**
- macOS-only skills are skipped with descriptive messages instead of cryptic `apt` errors.
- Node global installs (clawhub, mcporter, oracle) now succeed with proper PNPM_HOME.
- Go-based skills properly install to `~/go/bin`.
- Future skills from ClawdHub will automatically benefit from these compatibility mappings.
