# Upstream Sync Analysis Report
**Date**: 2026-04-08
**Upstream**: `openclaw/openclaw` @ `7f19676439`
**Current Branch**: `upgrade-termux-v2026.3.8` @ `3dd2737c2f`

## Upstream Changes in Patched Files

| File | Status | Impact |
|------|--------|--------|
| `tsdown.config.ts` | **Modified** (236 lines) | Must re-verify treeshake: false + napi-rs externals |
| `src/daemon/service.ts` | **Modified** (335 lines) | Must re-apply pm2/isTermux branch |
| `src/daemon/pm2.ts` | **Deleted upstream** (388 lines) | File is Termux-only — keep without merge |
| `src/shared/net/ip.ts` | **Modified** (62 lines) | Must re-apply require() conversion |
| `src/browser/pw-tools-core.downloads.ts` | **Deleted upstream** (288 lines) | File may have been refactored — investigate |
| `src/browser/chrome.executables.ts` | **Deleted upstream** (629 lines) | File may have been refactored — investigate |
| `src/agents/skills-install.ts` | **Modified** (834 lines) | Major refactor — must re-apply BREW_TO_PKG_MAP |

## Key Observations

1. **3 files deleted upstream** — `pm2.ts` (ours only), `pw-tools-core.downloads.ts`, `chrome.executables.ts`
2. **4 files significantly modified** — all have Termux patches that need re-application
3. **Total delta**: 657 additions, 2115 deletions — substantial upstream refactoring

## Recommended Sync Strategy

1. Create a clean sync branch: `git checkout -b sync-upstream-$(date +%Y%m%d) upstream/main`
2. Run `scripts/termux-auto-patch.sh --dry-run` to identify needed patches
3. Apply automated patches where possible
4. Manually resolve deleted file conflicts (investigate upstream refactoring)
5. Run `scripts/termux-patch-verify.sh` for validation
6. Run build + `scripts/termux-smoke-tests.sh`
7. Merge back to main branch

## Blocked?

No — but actual sync should be done with user confirmation due to destructive branch operations.
The tooling is ready and tested.
