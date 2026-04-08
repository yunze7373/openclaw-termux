# Termux Upgrade Checklist

> Step-by-step checklist for upgrading openclaw-termux from upstream openclaw/openclaw.
> Use alongside `docs/TERMUX-UPGRADE-GUIDE.md` for detailed error patterns.

## Pre-Merge Validation

- [ ] **Fetch upstream**: `git fetch upstream`
- [ ] **Review upstream changes**: `git log --oneline upstream/main..HEAD` (understand what's new)
- [ ] **Check for conflicts**: `git diff upstream/main...HEAD --name-only` — review files that overlap with Termux patches
- [ ] **Backup current branch**: `git branch backup-$(date +%Y%m%d)` before rebasing

## Merge/Rebase

- [ ] **Rebase onto upstream**: `git rebase upstream/main`
- [ ] **Resolve conflicts** — prioritize Termux patches (see conflict resolution guide below)

## Build System Fixes (Apply After Merge)

- [ ] **treeshake: false** — Verify `tsdown.config.ts` still has `treeshake: false` for all entries
  ```bash
  grep 'treeshake' tsdown.config.ts
  # Expected: treeshake: false in every entry
  ```
- [ ] **@napi-rs/canvas external** — Verify native modules are externalized
  ```bash
  grep 'napi-rs' tsdown.config.ts
  ```
- [ ] **Build succeeds**: `pnpm build` completes without errors

## Type Fix Patterns (Common TS Errors After Merge)

### TS2305 — Module has no exported member
- [ ] **Playwright types** — Check `src/browser/pw-tools-core.downloads.ts` still has:
  ```ts
  type Dialog = any;
  type FileChooser = any;
  ```

### TS2339 — Property does not exist
- [ ] Check if upstream changed interfaces used in `src/daemon/service.ts`
- [ ] Check if `src/agents/bash-tools.exec.ts` options changed

### ESM Import Failures
- [ ] **ipaddr.js** — `src/shared/net/ip.ts` uses `require("ipaddr.js")` (not ESM import)
- [ ] **@discordjs/voice** — `src/discord/voice/manager.ts` uses `require("@discordjs/voice")`

## Service Manager

- [ ] **pm2.ts exists**: `src/daemon/pm2.ts` present and compiles
- [ ] **service.ts routing**: `src/daemon/service.ts` has `isTermux()` / `platform === "android"` branch before Linux check

## Skills Installer

- [ ] **BREW_TO_PKG_MAP** present in `src/agents/skills-install.ts`
- [ ] **MACOS_ONLY_SKILLS** skip list present
- [ ] **No --ignore-scripts** in global install commands

## Browser/Chrome

- [ ] **Termux Chromium paths** in `src/browser/chrome.executables.ts`
- [ ] **Android → Linux platform mapping** for executable detection

## Post-Merge Validation

- [ ] `pnpm install` — no errors
- [ ] `pnpm build` — builds successfully
- [ ] `pnpm tsgo` — type-check passes (or only pre-existing errors)
- [ ] Basic smoke test: `node dist/openclaw.mjs --version`

## Device Testing (Termux)

- [ ] Transfer built package to Termux device
- [ ] `npm install -g` succeeds
- [ ] `openclaw --version` works
- [ ] `openclaw gateway start` runs (PM2 lifecycle)
- [ ] `openclaw config set` works
- [ ] Basic agent interaction succeeds

## Automated Validation

- [ ] Run `bash scripts/termux-patch-verify.sh` (checks all patches from patch library)

## Conflict Resolution Guide

| File | Resolution |
|------|-----------|
| `tsdown.config.ts` | Keep Termux `treeshake: false` + merge upstream entry changes |
| `src/daemon/service.ts` | Accept both sides, ensure PM2 branch comes before Linux |
| `src/agents/skills-install.ts` | Large rewrite — manual merge likely needed |
| `src/shared/net/ip.ts` | Keep `require()` pattern, merge upstream logic changes |
| `src/browser/chrome.executables.ts` | Keep Termux paths, merge upstream browser changes |
| `package.json` | Keep Termux version suffix, accept upstream dep updates |
