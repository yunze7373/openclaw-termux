# Termux 升级指南

本文档记录了 openclaw-termux 从 v2026.2.9-termux.1 升级到 v2026.3.2-termux.1 过程中遇到的所有问题及其解决方案，供下次升级时参考。

## 升级流程

### 1. Git 升级操作

```bash
cd ~/openclaw-termux

# 添加 upstream 远程（如果还没有）
git remote add upstream https://github.com/openclaw/openclaw.git 2>/dev/null || true

# 获取 upstream 最新代码
git fetch upstream

# 创建升级分支
git checkout -b upgrade-termux

# 合并上游代码（使用 --no-edit 避免冲突）
git merge upstream/main --no-edit

# 或者直接 rebase
# git rebase upstream/main
```

### 2. 解决 TypeScript 类型错误

升级后运行 `pnpm build`，根据错误逐一修复。以下是常见错误类型及其解决方案：

---

## 常见错误及解决方案

### 错误类型 1： discriminated union 类型访问错误

**错误示例：**
```typescript
src/telegram/bot-native-commands.ts: error TS2339: Property 'reason' does not exist on type 'BaseAccessCheckResult'.
```

**原因：** TypeScript 无法在 `if (!baseAccess.allowed)` 之后正确窄化 `baseAccess.reason` 的类型。

**解决方案：** 将属性提取到 const 变量：
```typescript
// 修复前
if (!baseAccess.allowed) {
  if (baseAccess.reason === "group-disabled") {
    return await sendAuthMessage("This group is disabled.");
  }
}

// 修复后
if (!baseAccess.allowed) {
  const reason = baseAccess.reason;
  if (reason === "group-disabled") {
    return await sendAuthMessage("This group is disabled.");
  }
}
```

---

### 错误类型 2：ReadJsonBodyResult 类型访问错误

**错误示例：**
```typescript
src/telegram/webhook.ts: error TS2339: Property 'code' does not exist on type 'ReadJsonBodyResult'.
```

**解决方案：** 同样需要提取到 const 变量：
```typescript
// 修复前
if (!body.ok) {
  if (body.code === "PAYLOAD_TOO_LARGE") {
    // ...
  }
}

// 修复后
if (!body.ok) {
  const code = body.code;
  const error = body.error;
  if (code === "PAYLOAD_TOO_LARGE") {
    // ...
  }
}
```

---

### 错误类型 3：不存在的属性/导入

**错误示例：**
```typescript
src/agents/pi-tools.ts: error TS2339: Property 'safeBinTrustedDirs' does not exist on type 'PiToolsConfig'.
```

**原因：** 上游版本移除了某些属性或方法。

**解决方案：** 删除不存在的属性：
```typescript
// 删除这些属性
safeBinTrustedDirs?: string[];
safeBinProfiles?: Record<string, unknown>;
currentChannelId?: string;
currentThreadTs?: string;
accountId?: string;
notifyOnExitEmptySuccess?: boolean;
```

---

### 错误类型 4：可选依赖模块未找到

**错误示例：**
```typescript
src/discord/monitor/gateway-plugin.ts: error TS2307: Cannot find module 'https-proxy-agent'.
src/discord/voice/manager.ts: error TS2307: Cannot find module '@discordjs/voice'.
src/shared/net/ip.ts: error TS2307: Cannot find module 'ipaddr.js'.
```

**原因：** 这些是可选依赖，Termux 设备上可能未安装。

**解决方案：** 使用 `require()` 替代 ES 导入，并添加类型断言：
```typescript
// 修复前
import { HttpsProxyAgent } from "https-proxy-agent";

// 修复后
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { HttpsProxyAgent } = require("https-proxy-agent") as typeof import("https-proxy-agent");
```

**注意：** 确保 `require()` 调用在 `createRequire` 声明之后：
```typescript
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);

// eslint-disable-next-line @typescript-eslint/no-require-imports
const { AudioPlayerStatus, EndBehaviorType } = require("@discordjs/voice") as typeof import("@discordjs/voice");
```

---

### 错误类型 5：ipaddr.js 命名空间类型错误

**错误示例：**
```typescript
src/shared/net/ip.ts: error TS2503: Cannot find namespace 'ipaddr'.
```

**解决方案：** 使用类型导入配合 require()：
```typescript
/* eslint-disable @typescript-eslint/no-require-imports */
const ipaddr = require("ipaddr.js") as typeof import("ipaddr.js");

import type { IPv4, IPv6 } from "ipaddr.js";

export type ParsedIpAddress = IPv4 | IPv6;
type Ipv4Range = ReturnType<IPv4["range"]>;
type Ipv6Range = ReturnType<IPv6["range"]>;
```

然后将所有 `ipaddr.IPv4` 和 `ipaddr.IPv6` 类型引用替换为 `IPv4` 和 `IPv6`。

---

### 错误类型 6：Playwright 类型错误

**错误示例：**
```typescript
src/browser/pw-tools-core.downloads.ts: error TS2305: Module '"playwright-core"' has no exported member 'Dialog'.
src/browser/pw-tools-core.downloads.ts: error TS2305: Module '"playwright-core"' has no exported member 'FileChooser'.
```

**原因：** playwright-core@1.58.2 的类型导出方式特殊，Termux 设备上的 TypeScript 无法正确解析。

**最终解决方案：** 使用 `any` 类型别名：
```typescript
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import type { Page } from "playwright-core";
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Dialog = any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type FileChooser = any;
```

---

### 错误类型 7：隐式 any 类型

**错误示例：**
```typescript
src/browser/pw-tools-core.storage.ts: error TS7031: Binding element 'kind' implicitly has an 'any' type.
```

**解决方案：** 添加显式类型注解：
```typescript
// 修复前
await page.evaluate(
  ({ kind }) => {
    // ...
  },
  { kind: opts.kind },
);

// 修复后
await page.evaluate(
  ({ kind }: { kind: StorageKind }) => {
    // ...
  },
  { kind: opts.kind },
);
```

---

### 错误类型 8：maxBytesOroptions 类型断言错误

**错误示例：**
```typescript
src/web/media.ts: error TS2322: Type 'number | undefined' is not assignable to type 'number'.
```

**解决方案：** 添加类型断言：
```typescript
// 修复前
maxBytes: params.maxBytesOrOptions,

// 修复后
maxBytes: params.maxBytesOrOptions as number | undefined,
```

---

### 错误类型 9：Browser 类型断言错误

**错误示例：**
```typescript
src/browser/pw-session.ts: error TS2352: Conversion of type 'Promise<Browser>' to type 'Browser' may be a mistake.
```

**解决方案：** 添加正确的类型断言：
```typescript
const browser = await withNoProxyForCdpUrl(endpoint, () =>
  chromium.connectOverCDP(endpoint, { timeout, headers }),
) as Browser;
```

---

### 错误类型 10：回调参数类型注解

**错误示例：**
```typescript
src/browser/pw-tools-core.interactions.ts: error TS7006: Parameter 'labels' implicitly has an 'any' type.
```

**解决方案：** 添加显式类型注解：
```typescript
await page.evaluate((labels: Array<{ selector: string; text: string }>) => {
  // ...
}, labels);
```

---

### 错误类型 11：transport 属性不存在

**错误示例：**
```typescript
src/agents/pi-embedded-runner/extra-params.ts: error TS2353: Object literal may only specify known properties.
```

**原因：** 上游类型定义移除了 `transport` 属性。

**解决方案：** 删除该属性：
```typescript
// 删除 transport 属性
```

---

## 构建脚本调整

### 跳过 plugin-sdk:dts 构建

如果 `build:plugin-sdk:dts` 步骤失败，可以在 `package.json` 中修改 build 脚本：

```json
{
  "scripts": {
    "build": "pnpm canvas:a2ui:bundle && tsdown && node --import tsx scripts/write-plugin-sdk-entry-dts.ts && node --import tsx scripts/canvas-a2ui-copy.ts && node --import tsx scripts/copy-hook-metadata.ts && node --import tsx scripts/copy-export-html-templates.ts && node --import tsx scripts/write-build-info.ts && node --import tsx scripts/write-cli-startup-metadata.ts && node --import tsx scripts/write-cli-compat.ts"
  }
}
```

移除 `build:plugin-sdk:dts` 步骤。

同时更新 `tsconfig.plugin-sdk.dts.json`：

```json
{
  "compilerOptions": {
    "skipLibCheck": true,
    "skipDefaultLibCheck": true
  },
  "exclude": [
    "node_modules",
    "dist",
    "src/**/*.test.ts",
    "src/discord/**",
    "src/shared/net/ip.ts"
  ]
}
```

---

## Termux 设备更新步骤

升级完成后，在 Termux 设备上运行：

```bash
cd ~/openclaw-termux

# 获取远程标签
git fetch origin --tags

# 删除旧标签
git tag -d v2026.3.2-termux.1 2>/dev/null || true

# 获取新标签
git fetch origin tag v2026.3.2-termux.1

# 切换到新版本
git checkout -f v2026.3.2-termux.1

# 清理未跟踪文件
git clean -fd

# 安装依赖
pnpm install

# 构建
pnpm build

# 启动
openclaw start
```

---

## 推送流程

修复完成后，提交并推送：

```bash
# 提交所有修复
git add -A
git commit -m "fix(termux): resolve TypeScript build errors for v2026.3.2 upgrade"

# 推送到远程
git push origin main --force

# 更新标签
git tag -d v2026.3.2-termux.1
git tag v2026.3.2-termux.1
git push origin v2026.3.2-termux.1 --force
```

---

## 检查清单

升级完成后，确认以下事项：

- [ ] `pnpm build` 成功完成，无 TypeScript 错误
- [ ] main 分支已推送到远程
- [ ] 版本标签已推送到远程
- [ ] Termux 设备可以正常拉取和构建
- [ ] 应用可以正常启动运行

---

## 版本历史

| 版本 | 日期 | 备注 |
|------|------|------|
| v2026.2.9-termux.1 | 2026-02-09 | 基准版本 |
| v2026.3.2-termux.1 | 2026-03-04 | 升级到上游 v2026.3.2 |

---

## 有用的命令

```bash
# 查看当前版本
git describe --tags --always

# 查看远程标签
git ls-remote origin refs/tags/*

# 查看构建日志
cat .build.log

# 清理并重新构建
git clean -fd && pnpm install && pnpm build
```
