#!/usr/bin/env bash
# termux-compat-analyzer.sh — Pre-merge compatibility analyzer
# Compares upstream changes against known Termux patch points to predict issues
# Usage: bash scripts/termux-compat-analyzer.sh [upstream-ref]

set -euo pipefail

UPSTREAM_REF="${1:-upstream/main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

red()    { printf '\033[31m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
bold()   { printf '\033[1m%s\033[0m' "$1"; }

ISSUES=0
WARNINGS=0

issue() { ISSUES=$((ISSUES + 1)); echo "  $(red "❌ ISSUE"): $1"; }
warn()  { WARNINGS=$((WARNINGS + 1)); echo "  $(yellow "⚠️  WARN"): $1"; }
ok()    { echo "  $(green "✅ OK"): $1"; }

echo "🔍 Termux Compatibility Analyzer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Comparing HEAD against: $UPSTREAM_REF"
echo ""

# Get files changed in upstream since our fork point
MERGE_BASE=$(git merge-base HEAD "$UPSTREAM_REF" 2>/dev/null || echo "")
if [ -z "$MERGE_BASE" ]; then
  echo "$(red "ERROR"): Cannot find merge base between HEAD and $UPSTREAM_REF"
  echo "Run: git fetch upstream"
  exit 1
fi

UPSTREAM_CHANGED=$(git diff "$MERGE_BASE".."$UPSTREAM_REF" --name-only 2>/dev/null)

# === Known Termux patch files ===
PATCHED_FILES=(
  "tsdown.config.ts"
  "src/daemon/service.ts"
  "src/shared/net/ip.ts"
  "src/discord/voice/manager.ts"
  "src/browser/pw-tools-core.downloads.ts"
  "src/browser/chrome.executables.ts"
  "src/agents/skills-install.ts"
  "src/agents/bash-tools.exec.ts"
  "src/web/media.ts"
  "src/agents/pi-embedded-runner/extra-params.ts"
  "src/agents/pi-tools.ts"
  "src/browser/pw-session.ts"
  "src/browser/pw-tools-core.interactions.ts"
  "src/browser/pw-tools-core.storage.ts"
  "src/telegram/bot-native-commands.ts"
  "src/telegram/webhook.ts"
  "src/discord/monitor/gateway-plugin.ts"
  "package.json"
  ".npmrc"
)

# Check 1: Patched files changed upstream
echo "$(bold "1. Patched File Conflicts")"
CONFLICT_FILES=()
for f in "${PATCHED_FILES[@]}"; do
  if echo "$UPSTREAM_CHANGED" | grep -q "^${f}$"; then
    CONFLICT_FILES+=("$f")
    warn "Upstream changed patched file: $f"
  fi
done
if [ ${#CONFLICT_FILES[@]} -eq 0 ]; then
  ok "No patched files changed upstream"
fi
echo ""

# Check 2: service-types.ts changes (we inlined these)
echo "$(bold "2. Service Types (Inlined)")"
if echo "$UPSTREAM_CHANGED" | grep -q "src/daemon/service-types.ts"; then
  issue "Upstream changed service-types.ts — we inlined these types in service.ts, manual merge needed"
elif echo "$UPSTREAM_CHANGED" | grep -q "src/daemon/"; then
  warn "Upstream changed daemon/ files — check service.ts compatibility"
else
  ok "No daemon type changes"
fi
echo ""

# Check 3: New ESM-only imports that may need require() pattern
echo "$(bold "3. New Import Patterns")"
NEW_FILES=$(git diff "$MERGE_BASE".."$UPSTREAM_REF" --name-only --diff-filter=A 2>/dev/null | grep '\.ts$' || true)
if [ -n "$NEW_FILES" ]; then
  # Check for native/optional module imports in new files
  NATIVE_IMPORTS=$(echo "$NEW_FILES" | xargs -I{} git show "$UPSTREAM_REF:{}" 2>/dev/null | grep -l 'from "@napi-rs\|from "better-sqlite3\|from "@discordjs/voice' 2>/dev/null || true)
  if [ -n "$NATIVE_IMPORTS" ]; then
    warn "New files import native modules — may need require() pattern for Termux"
  else
    ok "No new native module imports detected"
  fi
else
  ok "No new TypeScript files added upstream"
fi
echo ""

# Check 4: Build config changes
echo "$(bold "4. Build Configuration")"
if echo "$UPSTREAM_CHANGED" | grep -q "tsdown.config.ts"; then
  issue "tsdown.config.ts changed upstream — ensure treeshake: false is preserved"
fi
if echo "$UPSTREAM_CHANGED" | grep -q "tsconfig"; then
  warn "tsconfig changed upstream — verify Termux compatibility"
fi
if echo "$UPSTREAM_CHANGED" | grep -q "package.json"; then
  warn "package.json changed — check for new native dependencies"
fi
if ! echo "$UPSTREAM_CHANGED" | grep -qE "tsdown|tsconfig|package.json"; then
  ok "No build config changes"
fi
echo ""

# Check 5: Playwright/browser changes
echo "$(bold "5. Browser/Playwright")"
BROWSER_CHANGES=$(echo "$UPSTREAM_CHANGED" | grep "^src/browser/" || true)
if [ -n "$BROWSER_CHANGES" ]; then
  warn "Browser files changed upstream:"
  echo "$BROWSER_CHANGES" | while read -r f; do echo "    - $f"; done
  echo "    Check Dialog/FileChooser type aliases and Termux Chromium paths"
else
  ok "No browser changes"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $(red "$ISSUES issues"), $(yellow "$WARNINGS warnings")"
echo ""

if [ "$ISSUES" -gt 0 ]; then
  echo "$(red "⚠️  Manual intervention likely needed before merge!")"
  echo ""
  echo "Recommended steps:"
  echo "  1. Review each ISSUE above"
  echo "  2. Prepare conflict resolution plan"
  echo "  3. Run: git rebase $UPSTREAM_REF (resolve conflicts per docs/TERMUX-UPGRADE-CHECKLIST.md)"
  echo "  4. Run: bash scripts/termux-patch-verify.sh"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "$(yellow "⚡ Merge should be straightforward but review warnings")"
  exit 0
else
  echo "$(green "✅ Clean merge expected — no Termux patch conflicts!")"
  exit 0
fi
