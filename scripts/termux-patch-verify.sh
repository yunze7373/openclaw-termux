#!/usr/bin/env bash
# termux-patch-verify.sh — Validates all Termux patches are correctly applied
# Reads from .progress/termux-patch-library.json and checks each patch
# Exit 0 = all good, Exit 1 = issues found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
WARN=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }

check() {
  local id="$1" desc="$2" cmd="$3" expect="$4"
  printf "  %-35s " "$id"
  if eval "$cmd" >/dev/null 2>&1; then
    green "✅ $desc"
    PASS=$((PASS + 1))
  else
    red "❌ $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "🔍 Termux Patch Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# === Build Configuration ===
echo "📦 Build Configuration"
check "treeshake-disable" \
  "treeshake: false in tsdown.config.ts" \
  "grep -q 'treeshake.*false' tsdown.config.ts" \
  "found"

check "napi-rs-external" \
  "@napi-rs/canvas externalized" \
  "grep -q 'napi-rs/canvas' tsdown.config.ts" \
  "found"

echo ""

# === Service Manager ===
echo "🔧 Service Manager (PM2)"
check "pm2-file-exists" \
  "src/daemon/pm2.ts exists" \
  "test -f src/daemon/pm2.ts" \
  "exists"

check "pm2-service-branch" \
  "isTermux() in service.ts" \
  "grep -q 'isTermux' src/daemon/service.ts" \
  "found"

echo ""

# === Optional Imports (require pattern) ===
echo "📥 Optional Imports (require pattern)"
check "ipaddr-require" \
  "ipaddr.js uses require()" \
  "grep -q 'require(\"ipaddr.js\")' src/shared/net/ip.ts" \
  "found"

check "discordjs-voice-require" \
  "@discordjs/voice uses require()" \
  "grep -q 'require(\"@discordjs/voice\")' src/discord/voice/manager.ts" \
  "found"

echo ""

# === Type Fixes ===
echo "🏷️  Type Fixes"
check "playwright-dialog-alias" \
  "Dialog type alias in pw-tools-core.downloads.ts" \
  "grep -q 'type Dialog = any' src/browser/pw-tools-core.downloads.ts" \
  "found"

check "playwright-filechooser-alias" \
  "FileChooser type alias" \
  "grep -q 'type FileChooser = any' src/browser/pw-tools-core.downloads.ts" \
  "found"

echo ""

# === Paths ===
echo "📂 Platform Paths"
check "chrome-termux-paths" \
  "Termux Chromium paths in chrome.executables.ts" \
  "grep -q 'com.termux' src/browser/chrome.executables.ts" \
  "found"

echo ""

# === Package Manager ===
echo "📦 Skills Installer"
check "brew-to-pkg-map" \
  "BREW_TO_PKG_MAP in skills-install.ts" \
  "grep -q 'BREW_TO_PKG_MAP' src/agents/skills-install.ts" \
  "found"

check "macos-only-skills" \
  "MACOS_ONLY_SKILLS skip list" \
  "grep -q 'MACOS_ONLY_SKILLS' src/agents/skills-install.ts" \
  "found"

check "no-ignore-scripts" \
  "No --ignore-scripts in global installs" \
  "! grep -q '\-\-ignore-scripts' src/agents/skills-install.ts" \
  "not found (good)"

echo ""

# === Termux-specific files ===
echo "📄 Termux-Specific Files"
check "termux-tool" \
  "termux-tool.ts exists" \
  "test -f src/agents/tools/termux-tool.ts" \
  "exists"

check "install-script-en" \
  "Install_termux.sh exists" \
  "test -f Install_termux.sh" \
  "exists"

check "install-script-cn" \
  "Install_termux_cn.sh exists" \
  "test -f Install_termux_cn.sh" \
  "exists"

check "android-fixes-doc" \
  "ANDROID_FIXES.md exists" \
  "test -f ANDROID_FIXES.md" \
  "exists"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $(green "$PASS passed"), $(red "$FAIL failed"), $(yellow "$WARN warnings")"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  red "⚠️  $FAIL patches need attention!"
  exit 1
else
  echo ""
  green "✅ All Termux patches verified!"
  exit 0
fi
