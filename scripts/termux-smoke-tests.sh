#!/usr/bin/env bash
# termux-smoke-tests.sh — Basic smoke tests for Termux runtime
# Run after build to verify core functionality works on Termux/Android
# Usage: bash scripts/termux-smoke-tests.sh [dist-dir]

set -euo pipefail

DIST_DIR="${1:-dist}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
SKIP=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }

pass() { PASS=$((PASS + 1)); printf "  %-45s %s\n" "$1" "$(green "PASS")"; }
fail() { FAIL=$((FAIL + 1)); printf "  %-45s %s\n" "$1" "$(red "FAIL")"; }
skip() { SKIP=$((SKIP + 1)); printf "  %-45s %s\n" "$1" "$(yellow "SKIP")"; }

echo "🧪 Termux Smoke Tests"
echo "━━━━━━━━━━━━━━━━━━━━━"
echo ""

# === 1. Build Output ===
echo "📦 Build Output"
if [ -f "$DIST_DIR/openclaw.mjs" ]; then
  pass "dist/openclaw.mjs exists"
else
  fail "dist/openclaw.mjs missing — run pnpm build first"
fi

# Check for __exportAll (tree-shaking artifact that crashes on Termux)
if [ -f "$DIST_DIR/openclaw.mjs" ]; then
  if grep -q '__exportAll' "$DIST_DIR/openclaw.mjs" 2>/dev/null; then
    fail "dist/openclaw.mjs contains __exportAll (tree-shaking not disabled!)"
  else
    pass "No __exportAll in build output"
  fi
fi
echo ""

# === 2. Node.js Runtime ===
echo "⚙️  Node.js Runtime"
NODE_VERSION=$(node --version 2>/dev/null || echo "none")
if [ "$NODE_VERSION" != "none" ]; then
  pass "Node.js available: $NODE_VERSION"
  # Check version >= 22
  MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')
  if [ "$MAJOR" -ge 22 ]; then
    pass "Node.js >= 22"
  else
    fail "Node.js $NODE_VERSION < 22 (need 22+)"
  fi
else
  fail "Node.js not found"
fi
echo ""

# === 3. CLI Execution ===
echo "🖥️  CLI Execution"
if [ -f "$DIST_DIR/openclaw.mjs" ]; then
  VERSION_OUTPUT=$(node "$DIST_DIR/openclaw.mjs" --version 2>&1 || echo "ERROR")
  if echo "$VERSION_OUTPUT" | grep -qE '[0-9]+\.[0-9]+'; then
    pass "openclaw --version: $VERSION_OUTPUT"
  else
    fail "openclaw --version failed: $VERSION_OUTPUT"
  fi

  HELP_OUTPUT=$(node "$DIST_DIR/openclaw.mjs" --help 2>&1 || echo "ERROR")
  if echo "$HELP_OUTPUT" | grep -qi "gateway\|config\|agent"; then
    pass "openclaw --help shows commands"
  else
    fail "openclaw --help output unexpected"
  fi
else
  skip "CLI tests (no build output)"
fi
echo ""

# === 4. Platform Detection ===
echo "🤖 Platform Detection"
PLATFORM=$(node -e "console.log(process.platform)" 2>/dev/null || echo "unknown")
pass "process.platform: $PLATFORM"

if [ "$PLATFORM" = "android" ] || [ -n "${TERMUX_VERSION:-}" ]; then
  pass "Termux environment detected"

  # Check PM2
  if command -v pm2 >/dev/null 2>&1; then
    pass "pm2 available: $(pm2 --version 2>/dev/null || echo 'unknown')"
  else
    yellow "  pm2 not installed (optional: npm i -g pm2)"
  fi
else
  skip "Termux-specific tests (not on Termux)"
fi
echo ""

# === 5. Key Dependencies ===
echo "📚 Key Dependencies"
if [ -d "node_modules" ]; then
  for dep in playwright-core typescript; do
    if [ -d "node_modules/$dep" ]; then
      pass "$dep installed"
    else
      skip "$dep not installed (optional)"
    fi
  done
else
  skip "node_modules not present"
fi
echo ""

# === Summary ===
echo "━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL + SKIP))
echo "Results: $(green "$PASS passed") / $(red "$FAIL failed") / $(yellow "$SKIP skipped") (total: $TOTAL)"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  red "❌ $FAIL tests failed!"
  exit 1
else
  echo ""
  green "✅ All smoke tests passed!"
  exit 0
fi
