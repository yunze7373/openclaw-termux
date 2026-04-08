# Phase 2 Briefing: Automated Upstream Sync & Testing

## Context

Phase 1 (Documentation & Patch Systematization) is complete. We now have:
- Full modification audit (`docs/TERMUX-MODIFICATIONS.md`) — 28 modified + 22 new files, 12 patch categories
- Structured patch library (`.progress/termux-patch-library.json`) — 12 patch definitions with validation
- Upgrade checklist (`docs/TERMUX-UPGRADE-CHECKLIST.md`) — step-by-step guide
- Pre-merge analyzer (`scripts/termux-compat-analyzer.sh`) — conflict predictor
- Patch verification (`scripts/termux-patch-verify.sh`) — 10 automated checks, all passing
- Smoke tests (`scripts/termux-smoke-tests.sh`) — runtime validation
- Upstream watch workflow (`.github/workflows/upstream-watch.yml`) — daily monitoring
- CI/CD strategy documentation (`docs/CI-CD-STRATEGY.md`)

## Phase 2 Goals

### 2A: Automated Patch Application
- Build `scripts/termux-auto-patch.sh` that reads `termux-patch-library.json` and applies missing patches automatically
- Handle common merge patterns: require() conversion, type aliases, platform guards
- Reduce manual intervention during upstream sync from ~2 hours to ~15 minutes

### 2B: CI Integration
- Add patch verification step to `ci.yml` (run `termux-patch-verify.sh` in CI)
- Add smoke test step to CI (build + `termux-smoke-tests.sh`)
- Add compat analyzer as PR check for upstream sync PRs

### 2C: Test Coverage
- Add Termux-specific unit tests for `src/daemon/pm2.ts`
- Add tests for `src/agents/skills-install.ts` (Termux branch)
- Add tests for platform detection logic in `src/daemon/service.ts`

### 2D: Real Upstream Sync
- Perform actual upstream sync to validate the full workflow
- Document any new issues discovered
- Update patch library with any new patches needed

## Success Criteria
- Upstream sync can be completed with < 30 minutes of manual work
- CI catches all Termux compatibility regressions
- All 12+ patches are automatically verified on every push
