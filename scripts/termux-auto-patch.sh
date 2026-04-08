#!/usr/bin/env bash
# termux-auto-patch.sh — Automatically applies Termux compatibility patches
# Reads .progress/termux-patch-library.json and applies missing patches
# Usage: bash scripts/termux-auto-patch.sh [--dry-run] [--patch-id <id>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

DRY_RUN=false
SINGLE_PATCH=""
APPLIED=0; SKIPPED=0; FAILED=0; ERRORS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --patch-id) SINGLE_PATCH="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
log_dry()   { echo -e "${YELLOW}[DRY]${NC}   $*"; }

run_or_dry() {
  if $DRY_RUN; then log_dry "Would run: $*"; return 0; fi
  eval "$@"
}

# ============================================================
# Patch: treeshake-disable
# Ensure treeshake: false is set in tsdown.config.ts
# ============================================================
patch_treeshake_disable() {
  local file="tsdown.config.ts"
  if grep -q 'treeshake.*false' "$file" 2>/dev/null; then
    log_ok "treeshake-disable: already applied"; ((SKIPPED++)); return
  fi
  log_info "treeshake-disable: applying..."
  # Insert treeshake: false after each defineConfig opening or entry block
  run_or_dry "sed -i 's/entry:/treeshake: false,\n    entry:/g' '$file'"
  if grep -q 'treeshake.*false' "$file" 2>/dev/null; then
    log_ok "treeshake-disable: applied"; ((APPLIED++))
  else
    log_fail "treeshake-disable: failed"; ((FAILED++)); ERRORS+=("treeshake-disable")
  fi
}

# ============================================================
# Patch: napi-rs-external
# Ensure @napi-rs/canvas is in externals
# ============================================================
patch_napi_rs_external() {
  local file="tsdown.config.ts"
  if grep -q 'napi-rs/canvas' "$file" 2>/dev/null; then
    log_ok "napi-rs-external: already applied"; ((SKIPPED++)); return
  fi
  log_info "napi-rs-external: applying..."
  # Add to external array — this patch is context-dependent, flag for manual review
  log_warn "napi-rs-external: requires manual review (tsdown.config.ts external arrays vary)"
  log_warn "  Add '@napi-rs/canvas' and '@napi-rs/canvas-android-arm64' to external arrays"
  ((FAILED++)); ERRORS+=("napi-rs-external: manual review needed")
}

# ============================================================
# Patch: pm2-service-manager
# Ensure pm2.ts exists and service.ts has isTermux branch
# ============================================================
patch_pm2_service_manager() {
  if [[ -f "src/daemon/pm2.ts" ]] && grep -q 'isTermux' src/daemon/service.ts 2>/dev/null; then
    log_ok "pm2-service-manager: already applied"; ((SKIPPED++)); return
  fi
  log_info "pm2-service-manager: checking components..."
  
  if [[ ! -f "src/daemon/pm2.ts" ]]; then
    log_warn "pm2-service-manager: src/daemon/pm2.ts missing — must be copied from Termux branch"
    ((FAILED++)); ERRORS+=("pm2-service-manager: pm2.ts missing"); return
  fi
  
  if ! grep -q 'isTermux' src/daemon/service.ts 2>/dev/null; then
    log_warn "pm2-service-manager: service.ts missing isTermux branch — requires manual patch"
    ((FAILED++)); ERRORS+=("pm2-service-manager: service.ts needs isTermux"); return
  fi
  
  log_ok "pm2-service-manager: applied"; ((APPLIED++))
}

# ============================================================
# Patch: ipaddr-require
# Convert ESM import to require() for ipaddr.js
# ============================================================
patch_ipaddr_require() {
  local file="src/shared/net/ip.ts"
  if ! [[ -f "$file" ]]; then log_warn "ipaddr-require: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'require("ipaddr.js")' "$file" 2>/dev/null || grep -q "require('ipaddr.js')" "$file" 2>/dev/null; then
    log_ok "ipaddr-require: already applied"; ((SKIPPED++)); return
  fi
  
  log_info "ipaddr-require: converting ESM import to require()..."
  local dry_flag=""; $DRY_RUN && dry_flag="--dry-run"
  run_or_dry "node '$REPO_ROOT/scripts/termux-require-converter.mjs' '$file' 'ipaddr.js' $dry_flag"
  
  if $DRY_RUN || grep -q 'require("ipaddr.js")' "$file" 2>/dev/null; then
    log_ok "ipaddr-require: applied"; ((APPLIED++))
  else
    log_fail "ipaddr-require: converter failed"
    ((FAILED++)); ERRORS+=("ipaddr-require")
  fi
}

# ============================================================
# Patch: discordjs-voice-require
# Convert ESM import to require() for @discordjs/voice
# ============================================================
patch_discordjs_voice_require() {
  local file="src/discord/voice/manager.ts"
  if ! [[ -f "$file" ]]; then log_warn "discordjs-voice-require: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'require("@discordjs/voice")' "$file" 2>/dev/null || grep -q "require('@discordjs/voice')" "$file" 2>/dev/null; then
    log_ok "discordjs-voice-require: already applied"; ((SKIPPED++)); return
  fi
  
  log_info "discordjs-voice-require: converting ESM import to require()..."
  # This is a destructured import, pattern varies — flag for manual review
  log_warn "discordjs-voice-require: destructured import — requires manual conversion"
  log_warn "  Replace: import { ... } from '@discordjs/voice'"
  log_warn "  With:    const { ... } = require('@discordjs/voice') as any"
  log_warn "  Add:     import type { ... } from '@discordjs/voice' for type-only imports"
  ((FAILED++)); ERRORS+=("discordjs-voice-require: manual conversion needed")
}

# ============================================================
# Patch: playwright-type-aliases
# Add type Dialog = any; type FileChooser = any;
# ============================================================
patch_playwright_type_aliases() {
  local file="src/browser/pw-tools-core.downloads.ts"
  if ! [[ -f "$file" ]]; then log_warn "playwright-type-aliases: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'type Dialog = any' "$file" 2>/dev/null; then
    log_ok "playwright-type-aliases: already applied"; ((SKIPPED++)); return
  fi
  
  log_info "playwright-type-aliases: injecting type aliases..."
  local dry_flag=""; $DRY_RUN && dry_flag="--dry-run"
  run_or_dry "node '$REPO_ROOT/scripts/termux-type-alias-injector.mjs' '$file' 'Dialog,FileChooser' 'playwright' $dry_flag"
  
  if $DRY_RUN || grep -q 'type Dialog = any' "$file" 2>/dev/null; then
    log_ok "playwright-type-aliases: applied"; ((APPLIED++))
  else
    log_fail "playwright-type-aliases: injection failed"
    ((FAILED++)); ERRORS+=("playwright-type-aliases")
  fi
}

# ============================================================
# Patch: chrome-termux-paths
# Add Termux Chromium paths to chrome.executables.ts
# ============================================================
patch_chrome_termux_paths() {
  local file="src/browser/chrome.executables.ts"
  if ! [[ -f "$file" ]]; then log_warn "chrome-termux-paths: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'com.termux' "$file" 2>/dev/null; then
    log_ok "chrome-termux-paths: already applied"; ((SKIPPED++)); return
  fi
  
  log_info "chrome-termux-paths: requires manual addition of Termux paths"
  log_warn "  Add to linux paths: '/data/data/com.termux/files/usr/bin/chromium-browser'"
  ((FAILED++)); ERRORS+=("chrome-termux-paths: manual addition needed")
}

# ============================================================
# Patch: skills-install-termux
# Add BREW_TO_PKG_MAP and Termux detection to skills-install.ts
# ============================================================
patch_skills_install_termux() {
  local file="src/agents/skills-install.ts"
  if ! [[ -f "$file" ]]; then log_warn "skills-install-termux: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'BREW_TO_PKG_MAP' "$file" 2>/dev/null; then
    log_ok "skills-install-termux: already applied"; ((SKIPPED++)); return
  fi
  
  log_info "skills-install-termux: requires manual Termux branch addition"
  log_warn "  Add: BREW_TO_PKG_MAP, isTermux() detection, pkg install fallback"
  log_warn "  Add: MACOS_ONLY_SKILLS skip list"
  ((FAILED++)); ERRORS+=("skills-install-termux: manual addition needed")
}

# ============================================================
# Patch: service-types-inline
# Inline GatewayServiceInstallArgs in service.ts
# ============================================================
patch_service_types_inline() {
  local file="src/daemon/service.ts"
  if ! [[ -f "$file" ]]; then log_warn "service-types-inline: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'GatewayServiceInstallArgs' "$file" 2>/dev/null; then
    log_ok "service-types-inline: already applied"; ((SKIPPED++)); return
  fi
  
  log_warn "service-types-inline: GatewayServiceInstallArgs not found — may need manual inlining"
  ((FAILED++)); ERRORS+=("service-types-inline: needs manual review")
}

# ============================================================
# Patch: web-media-cast
# Add explicit cast in web/media.ts
# ============================================================
patch_web_media_cast() {
  local file="src/web/media.ts"
  if ! [[ -f "$file" ]]; then log_warn "web-media-cast: $file not found"; ((SKIPPED++)); return; fi
  
  if grep -q 'as number | undefined' "$file" 2>/dev/null; then
    log_ok "web-media-cast: already applied"; ((SKIPPED++)); return
  fi
  
  log_warn "web-media-cast: requires manual cast addition"
  ((FAILED++)); ERRORS+=("web-media-cast: manual review needed")
}

# ============================================================
# Patch: termux-tool
# Ensure termux-tool.ts exists
# ============================================================
patch_termux_tool() {
  if [[ -f "src/agents/tools/termux-tool.ts" ]]; then
    log_ok "termux-tool: already present"; ((SKIPPED++)); return
  fi
  log_warn "termux-tool: src/agents/tools/termux-tool.ts missing — copy from Termux branch"
  ((FAILED++)); ERRORS+=("termux-tool: file missing")
}

# ============================================================
# Patch: remove-ignore-scripts
# Remove --ignore-scripts from skills-install.ts
# ============================================================
patch_remove_ignore_scripts() {
  local file="src/agents/skills-install.ts"
  if ! [[ -f "$file" ]]; then log_warn "remove-ignore-scripts: $file not found"; ((SKIPPED++)); return; fi
  
  if ! grep -q 'ignore-scripts' "$file" 2>/dev/null; then
    log_ok "remove-ignore-scripts: already clean"; ((SKIPPED++)); return
  fi
  
  log_info "remove-ignore-scripts: removing --ignore-scripts flags..."
  run_or_dry "sed -i 's/--ignore-scripts //g' '$file'"
  
  if ! grep -q 'ignore-scripts' "$file" 2>/dev/null; then
    log_ok "remove-ignore-scripts: applied"; ((APPLIED++))
  else
    log_fail "remove-ignore-scripts: some occurrences remain"
    ((FAILED++)); ERRORS+=("remove-ignore-scripts: partial")
  fi
}

# ============================================================
# Main execution
# ============================================================
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Termux Auto-Patcher v1.0               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
$DRY_RUN && echo -e "${YELLOW}🔍 DRY RUN MODE — no files will be modified${NC}"
echo ""

ALL_PATCHES=(
  treeshake_disable
  napi_rs_external
  pm2_service_manager
  ipaddr_require
  discordjs_voice_require
  playwright_type_aliases
  chrome_termux_paths
  skills_install_termux
  service_types_inline
  web_media_cast
  termux_tool
  remove_ignore_scripts
)

for patch_fn in "${ALL_PATCHES[@]}"; do
  patch_id="${patch_fn//_/-}"
  if [[ -n "$SINGLE_PATCH" && "$patch_id" != "$SINGLE_PATCH" ]]; then continue; fi
  "patch_${patch_fn}"
done

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "  Applied: ${GREEN}${APPLIED}${NC}  Skipped: ${YELLOW}${SKIPPED}${NC}  Failed: ${RED}${FAILED}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo -e "\n${RED}Issues requiring manual attention:${NC}"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}•${NC} $err"
  done
fi

exit $FAILED
