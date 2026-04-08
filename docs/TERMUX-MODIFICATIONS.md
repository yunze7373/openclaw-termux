# Termux/Android Modifications Reference

> Auto-generated audit of all changes between `upstream/main` and this fork.
> Last updated: 2026-04-08

## Summary

This fork modifies ~28 source files and adds ~22 new files to make OpenClaw run on Termux/Android. Changes fall into **7 categories**.

---

## 1. Build Configuration — Tree-shaking Disabled

**Why**: tsdown/rolldown's tree-shaking generates `__exportAll` helper functions that crash on Termux/Android Node.js runtime.

| File | Change |
|------|--------|
| `tsdown.config.ts` | `treeshake: false` for all entries; added `external` list for `@napi-rs/canvas*`; suppressed `PLUGIN_TIMINGS` noise |

## 2. Service Manager — PM2 Instead of systemd/launchd

**Why**: Termux has no systemd. PM2 is used as the process manager.

| File | Change |
|------|--------|
| `src/daemon/pm2.ts` | **NEW** — Full PM2 lifecycle: install, uninstall, stop, restart, status, runtime query |
| `src/daemon/service.ts` | Added `pm2` branch in `resolveGatewayService()` for `platform === "android"` or `isTermux()`; inlined service type definitions (removed `service-types.js` import); wrapped all platform handlers in async closures for type compatibility |

## 3. Optional/Native Module Imports — `require()` + `type` Imports

**Why**: Some ESM imports fail on Termux due to missing native bindings or platform detection issues. Pattern: use `require()` for runtime + `import type` for types.

| File | Change |
|------|--------|
| `src/shared/net/ip.ts` | `import ipaddr` → `const ipaddr = require("ipaddr.js")`; separate `import type { IPv4, IPv6 }` |
| `src/discord/voice/manager.ts` | `import { ... } from "@discordjs/voice"` → `const { ... } = require("@discordjs/voice")`; separate `import type` |

## 4. Playwright/Browser Type Fixes

**Why**: Playwright types (`Dialog`, `FileChooser`) cause TS2305 errors on Termux builds. Using `any` type aliases avoids the issue.

| File | Change |
|------|--------|
| `src/browser/pw-tools-core.downloads.ts` | Added `type Dialog = any; type FileChooser = any`; explicit type annotations on `.then()` callbacks |
| `src/browser/chrome.executables.ts` | Added Termux Chromium paths (`/data/data/com.termux/files/usr/bin/chromium*`); map `"android"` platform to `"linux"` for executable detection |
| `src/browser/pw-tools-core.interactions.ts` | Type annotation fixes (implicit `any`) |
| `src/browser/pw-tools-core.storage.ts` | Type annotation fixes |
| `src/browser/pw-session.ts` | Minor adjustments for Termux compatibility |

## 5. Skills/Package Installation — Termux `pkg` Support

**Why**: Termux uses `pkg` instead of `brew`. Skills that install via `brew` need mapping.

| File | Change |
|------|--------|
| `src/agents/skills-install.ts` | Major rewrite: added `isTermux` detection, `BREW_TO_PKG_MAP` (brew→pkg formula mapping), `MACOS_ONLY_SKILLS` skip list, `isMacOSOnlyFormula()`, Termux PNPM_HOME resolution, `pip` installer support, inlined `formatInstallFailureMessage`, removed `--ignore-scripts` from global installs, added direct fetch+stream download for skill tarballs |

## 6. Type Narrowing & Cast Fixes

**Why**: Stricter TS or discriminated union patterns that break on Termux runtime.

| File | Change |
|------|--------|
| `src/web/media.ts` | Added explicit cast `as number \| undefined` for `maxBytesOrOptions` |
| `src/agents/pi-embedded-runner/extra-params.ts` | Removed `transport` parameter handling (simplified) |
| `src/agents/bash-tools.exec.ts` | Removed fields: `safeBinTrustedDirs`, `safeBinProfiles`, `currentChannelId`, `currentThreadTs`, `accountId`, `notifyOnExitEmptySuccess` (upstream API changes adapted) |
| `src/agents/pi-tools.ts` | Upstream API adaptation |
| `src/telegram/bot-native-commands.ts` | Minor type fixes |
| `src/telegram/webhook.ts` | Minor type fixes |
| `src/discord/monitor/gateway-plugin.ts` | Minor type fixes |

## 7. New Termux-Specific Files

| File | Purpose |
|------|---------|
| `src/agents/tools/termux-tool.ts` | Termux-specific agent tool |
| `src/daemon/pm2.ts` | PM2 process manager (see §2) |
| `Install_termux.sh` | English installation script for Termux |
| `Install_termux_cn.sh` | Chinese installation script for Termux |
| `scripts/setup-termux.sh` | Termux environment setup |
| `scripts/fix-sqlite-vec.sh` | SQLite-vec native module fix |
| `ANDROID_FIXES.md` | Detailed Android fix documentation (EN) |
| `ANDROID_FIXES_CN.md` | Detailed Android fix documentation (CN) |
| `README_CN.md` | Chinese README |
| `VERTEX_AI_SETUP.md` | Vertex AI setup guide |
| `docs/TERMUX-UPGRADE-GUIDE.md` | Upgrade guide for syncing upstream |
| `docs/WORKFLOW-MODIFICATIONS.md` | Workflow/CI modifications |
| `docs/architecture/TAKEOVER_PLAN.md` | Takeover plan |

## 8. CI/Workflow & Config Simplifications

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Heavily simplified (removed macOS/Windows matrix, sandbox tests) |
| `.github/workflows/auto-response.yml` | Simplified |
| `.github/workflows/labeler.yml` | Simplified |
| `.github/workflows/install-smoke.yml` | Adapted for Termux |
| `.github/workflows/cleanup.yml` | **NEW** — cleanup workflow |
| `.github/workflows/docker-release.yml` | Renamed to `.disabled` |
| `.gitignore` | Termux-specific ignores |
| `.npmrc` | Adjusted for Termux builds |
| `package.json` | Version `2026.3.8-termux.1`, dependency adjustments |
| `tsconfig.plugin-sdk.dts.json` | Adjusted paths |

## 9. Removed Files (Not Applicable to Termux)

- Android native app (`apps/android/`) — entire directory removed (Termux runs Node.js directly, not the native Android app)
- macOS/iOS apps (`apps/ios/`, `apps/macos/`) — removed
- Various GitHub templates, workflows, and CI configs not relevant to Termux
- `VISION.md`, `.mailmap`, `.pi/extensions/` — removed

---

## Quick Reference: Fix Patterns

| Pattern | When Needed | Example |
|---------|-------------|---------|
| `treeshake: false` | Always (build config) | `tsdown.config.ts` |
| `const x = require("mod")` + `import type` | Optional native ESM modules | `ipaddr.js`, `@discordjs/voice` |
| `type X = any` for Playwright types | Always (type stubs) | `Dialog`, `FileChooser` |
| `platform === "android"` guard | Service manager, browser detection | `service.ts`, `chrome.executables.ts` |
| `BREW_TO_PKG_MAP` lookup | Skill installation on Termux | `skills-install.ts` |
| Explicit type casts | Various TS strict mode fixes | `as number \| undefined` |
