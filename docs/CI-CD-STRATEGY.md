# CI/CD Strategy for openclaw-termux

> How CI and automation work for this Termux fork.

## Overview

This fork maintains a simplified CI pipeline focused on Termux/Android compatibility rather than the full upstream multi-platform matrix.

## Workflows

### Active Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push/PR to main | Build + type-check + basic tests (Linux only, no macOS/Windows matrix) |
| `install-smoke.yml` | Push/PR | Verifies `npm install` works cleanly |
| `upstream-watch.yml` | Daily cron + manual | Checks for upstream changes, creates issue if patched files affected |
| `cleanup.yml` | On demand | Repository cleanup tasks |

### Disabled Workflows

| Workflow | Reason |
|----------|--------|
| `docker-release.yml.disabled` | Docker releases not needed for Termux fork |

### Removed Upstream Workflows

| Workflow | Reason |
|----------|--------|
| `sandbox-common-smoke.yml` | Sandbox not applicable to Termux |
| Full macOS/Windows CI matrix | Not relevant for Android target |

## Automation Scripts

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `scripts/termux-patch-verify.sh` | Validates all Termux patches are applied | After merge/rebase from upstream |
| `scripts/termux-compat-analyzer.sh` | Pre-merge conflict predictor | Before merging upstream changes |
| `scripts/termux-smoke-tests.sh` | Runtime smoke tests | After build, especially on device |

## Upgrade Workflow

```
1. upstream-watch.yml detects changes → creates GitHub issue
2. Developer runs: bash scripts/termux-compat-analyzer.sh
3. Developer rebases: git rebase upstream/main
4. Resolve conflicts per docs/TERMUX-UPGRADE-CHECKLIST.md
5. Verify patches: bash scripts/termux-patch-verify.sh
6. Build: pnpm build
7. Smoke test: bash scripts/termux-smoke-tests.sh
8. Device test on Termux
9. Push to main
```

## Release Strategy

- Version format: `YYYY.M.D-termux.N` (e.g., `2026.3.8-termux.1`)
- Releases are cut manually when upstream sync + validation complete
- No npm publish (local/git install only)
- No macOS app packaging

## Key Differences from Upstream CI

1. **Single platform**: Linux only (no macOS/Windows matrix)
2. **No sandbox tests**: Termux doesn't use Docker sandbox
3. **No app packaging**: No macOS/iOS/Android native app builds
4. **Upstream watch**: Additional workflow to track upstream changes
5. **Patch verification**: Additional validation step in CI for Termux-specific patches
