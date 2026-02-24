#!/usr/bin/env bash
#
# OpenClaw Termux One-Click Deploy Script
# Usage: ./Install_termux.sh [--full | --update | --help]
#
# Features:
#   - Detect and install dependencies (Node.js, pnpm, git, etc.)
#   - Set up environment variables (PATH, NODE_OPTIONS, TERMUX_VERSION, etc.)
#   - Install npm packages and build project
#   - Create CLI entry point (openclaw)
#   - Configure pm2 service (optional)
#
# Author: OpenClaw Team
# Version: 2.0.0

# Note: We intentionally do NOT use "set -e" because we need custom error handling
# for build steps with proper error message display.

# ============================================================================
# Configuration
# ============================================================================

# Script is now in project root, so SCRIPT_DIR is PROJECT_ROOT
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_BIN="$PROJECT_ROOT/openclaw.mjs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Step counter
CURRENT_STEP=0
TOTAL_STEPS=6

# ============================================================================
# UI Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}           OpenClaw Termux One-Click Deploy                   ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}📦 [$CURRENT_STEP/$TOTAL_STEPS] $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_substep() {
    echo -e "   ${DIM}▸${NC} $1"
}

print_success() {
    echo -e "   ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "   ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "   ${RED}✗${NC} $1"
}

print_footer() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}🎉 Deployment Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Spinner animation for long-running tasks
SPINNER_PID=""
SPINNER_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
export START_TIME=0

start_spinner() {
    local msg="$1"
    export START_TIME=$(date +%s)
    
    (
        local i=0
        local char_count=${#SPINNER_CHARS}
        local start_ts="$START_TIME"  # Capture in subshell
        
        while true; do
            local char="${SPINNER_CHARS:$i:1}"
            local now=$(date +%s)
            local elapsed=$(( now - start_ts ))
            
            # Add dots every 10 seconds (max 5 dots)
            local dot_count=$(( elapsed / 10 ))
            if [[ $dot_count -gt 5 ]]; then dot_count=5; fi
            local dots=""
            for ((d=0; d<dot_count; d++)); do dots+="."; done
            
            # Format elapsed time
            local mins=$(( elapsed / 60 ))
            local secs=$(( elapsed % 60 ))
            local time_str
            if [[ $mins -gt 0 ]]; then
                time_str="${mins}m${secs}s"
            else
                time_str="${secs}s"
            fi
            
            printf "\r   ${CYAN}%s${NC} %s ${DIM}[%s]${NC}%s   " "$char" "$msg" "$time_str" "$dots"
            i=$(( (i + 1) % char_count ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    local success="$1"
    local msg="$2"
    
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
    fi
    
    # Calculate final elapsed time
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    local time_str
    if [[ $mins -gt 0 ]]; then
        time_str="${mins}m${secs}s"
    else
        time_str="${secs}s"
    fi
    
    # Clear the line
    printf "\r%100s\r" ""
    
    if [[ "$success" == "true" ]]; then
        echo -e "   ${GREEN}✓${NC} $msg ${DIM}(${time_str})${NC}"
    else
        echo -e "   ${RED}✗${NC} $msg ${DIM}(${time_str})${NC}"
    fi
}

# Run command with spinner
run_with_spinner() {
    local msg="$1"
    shift
    
    start_spinner "$msg"
    local output
    if output=$("$@" 2>&1); then
        stop_spinner "true" "$msg"
        return 0
    else
        stop_spinner "false" "$msg - FAILED"
        echo -e "   ${DIM}Error: $output${NC}" | head -5
        return 1
    fi
}

# ============================================================================
# Platform Detection
# ============================================================================

detect_platform() {
    if [[ -n "${TERMUX_VERSION:-}" ]]; then
        echo "termux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif [[ "$(uname)" == "Linux" ]]; then
        if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
            echo "raspberrypi"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

check_command() {
    command -v "$1" &> /dev/null
}

# ============================================================================
# Dependency Installation
# ============================================================================

install_termux_deps() {
    print_substep "Cleaning up package manager locks..."
    # Kill any stray apt processes that might hold locks
    pkill -f "apt|pkg" 2>/dev/null || true
    sleep 1
    
    # Remove stale lock files
    rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock-frontend 2>/dev/null || true
    rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock 2>/dev/null || true
    sleep 1
    
    print_substep "Waiting for package manager to be ready..."
    local wait_count=0
    local max_attempts=15
    
    # Wait for package manager lock to be available
    while [[ $wait_count -lt $max_attempts ]]; do
        if flock -n /data/data/com.termux/files/usr/var/lib/apt/lock -c "echo ok" &>/dev/null 2>&1; then
            print_success "Package manager ready"
            break
        fi
        wait_count=$((wait_count + 1))
        if [[ $wait_count -eq 5 ]]; then
            print_warn "Package manager still locked, force cleaning..."
            pkill -9 -f "apt|pkg" 2>/dev/null || true
            rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock* 2>/dev/null || true
            sleep 2
        else
            sleep 2
        fi
    done
    
    # Update package lists with retries
    print_substep "Updating package lists (attempt 1/3)..."
    local update_attempt=1
    while [[ $update_attempt -le 3 ]]; do
        if pkg update -y 2>&1 | tail -2; then
            break
        fi
        update_attempt=$((update_attempt + 1))
        if [[ $update_attempt -le 3 ]]; then
            print_warn "Update failed, retrying (attempt $update_attempt/3)..."
            sleep 3
        fi
    done
    
    # Check for upgradable packages
    local UPGRADABLE
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | wc -l || echo 0)
    UPGRADABLE=$((UPGRADABLE - 1))  # subtract header line
    
    if [[ "$UPGRADABLE" -gt 0 ]]; then
        print_warn "Found $UPGRADABLE upgradable packages, upgrading..."
        print_substep "This may take several minutes depending on package size..."
        
        # Show real-time upgrade progress with retries
        local upgrade_attempt=1
        while [[ $upgrade_attempt -le 3 ]]; do
            if pkg upgrade -y 2>&1 | grep -E "^(Processing|Unpacking|Setting up|Preparing|Configuring|^[a-zA-Z0-9])" | while read line; do
                print_substep "   $line"
            done; then
                print_success "System packages upgraded"
                break
            fi
            upgrade_attempt=$((upgrade_attempt + 1))
            if [[ $upgrade_attempt -le 3 ]]; then
                print_warn "Upgrade failed, retrying (attempt $upgrade_attempt/3) in 5 seconds..."
                sleep 5
            elif [[ $upgrade_attempt -gt 3 ]]; then
                print_warn "Upgrade failed after 3 attempts, continuing with installation..."
            fi
        done
    else
        print_success "System packages up to date"
    fi
    
    print_substep "Installing base tools (nodejs-lts, git, openssh, build-essential, etc.)..."
    print_substep "This may take several minutes on first install..."
    
    # Install with retries for reliability
    local install_attempt=1
    while [[ $install_attempt -le 2 ]]; do
        if ! pkg install -y --fix-broken nodejs-lts git openssh curl wget jq python golang rust build-essential mpv proot tailscale cloudflared 2>&1 | while read line; do
            # Show progress lines but limit frequency to avoid clutter
            if [[ "$line" =~ ^(Processing|Unpacking|Setting up|Reading|Building|Get:|Hit:|Ign:|^[a-z0-9\-]+:) ]]; then
                print_substep "   $line"
            fi
        done; then
            if [[ $install_attempt -lt 2 ]]; then
                print_warn "Installation failed, retrying (attempt $((install_attempt + 1))/2)..."
                pkill -f "apt|pkg" 2>/dev/null || true
                sleep 3
                install_attempt=$((install_attempt + 1))
            else
                print_error "Base tools installation failed after 2 attempts"
                exit 1
            fi
        else
            break
        fi
    done
    print_success "nodejs-lts, git, curl, jq, and other tools"
    
    if ! check_command pnpm; then
        print_substep "Installing pnpm globally..."
        if ! npm install -g pnpm 2>&1 | tail -3; then
            print_error "pnpm installation failed"
            exit 1
        fi
    fi
    print_success "pnpm"
    
    if ! check_command pm2; then
        print_substep "Installing pm2 globally..."
        # pm2 install with timeout protection and progress feedback
        local pm2_attempt=0
        while [[ $pm2_attempt -lt 2 ]]; do
            # Show real-time progress without buffering
            if timeout 120 npm install -g pm2 \
                --registry https://registry.npmmirror.com \
                --fetch-timeout 60000 \
                --fetch-retry-mintimeout 10000 \
                --fetch-retry-maxtimeout 60000 \
                --fetch-retries 5 2>&1; then
                break
            else
                local npm_exit=$?
                if [[ $npm_exit -eq 124 ]]; then
                    print_warn "pm2 installation timeout (120s), killing processes and retrying..."
                    pkill -9 npm 2>/dev/null || true
                    pkill -9 node 2>/dev/null || true
                    sleep 3
                elif [[ $pm2_attempt -lt 1 ]]; then
                    print_warn "pm2 installation failed (exit code: $npm_exit), attempt $((pm2_attempt + 2))/2..."
                    pkill -9 npm 2>/dev/null || true
                    sleep 2
                else
                    print_error "pm2 global installation failed 2 times, please check your network connection"
                    exit 1
                fi
            fi
            pm2_attempt=$((pm2_attempt + 1))
        done
    fi
    print_success "pm2"
}

install_linux_deps() {
    print_substep "Detecting package manager and updating system..."
    
    if check_command apt-get; then
        print_substep "   Using apt-get package manager..."
        print_substep "   Running apt-get update..."
        if ! sudo apt-get update 2>&1 | tail -5; then
            print_error "apt-get update failed"
            exit 1
        fi
        print_substep "   Installing with apt-get (nodejs npm git curl jq)..."
        if ! sudo apt-get install -y nodejs npm git curl jq 2>&1 | tail -5; then
            print_error "apt-get install failed"
            exit 1
        fi
    elif check_command dnf; then
        print_substep "   Using dnf package manager..."
        print_substep "   Installing with dnf (nodejs npm git curl jq)..."
        if ! sudo dnf install -y nodejs npm git curl jq 2>&1 | tail -5; then
            print_error "dnf install failed"
            exit 1
        fi
    elif check_command pacman; then
        print_substep "   Using pacman package manager..."
        print_substep "   Installing with pacman (nodejs npm git curl jq)..."
        if ! sudo pacman -Sy --noconfirm nodejs npm git curl jq 2>&1 | tail -5; then
            print_error "pacman install failed"
            exit 1
        fi
    else
        print_warn "Cannot detect package manager, please install manually: nodejs npm git curl jq"
    fi
    
    if ! check_command pnpm; then
        print_substep "Installing pnpm globally..."
        npm install -g pnpm 2>&1 | tail -3
    fi
    print_success "Dependencies installed"
}

install_macos_deps() {
    print_substep "Installing macOS dependencies via Homebrew..."
    
    if ! check_command brew; then
        print_error "Please install Homebrew first: https://brew.sh"
        exit 1
    fi
    
    print_substep "   Installing with Homebrew (node git jq)..."
    if ! brew install node git jq 2>&1 | tail -5; then
        print_error "Homebrew install failed"
        exit 1
    fi
    
    if ! check_command pnpm; then
        print_substep "Installing pnpm globally..."
        npm install -g pnpm 2>&1 | tail -3
    fi
    print_success "Dependencies installed"
}

install_dependencies() {
    case "$PLATFORM" in
        termux)
            install_termux_deps
            ;;
        linux|raspberrypi)
            install_linux_deps
            ;;
        macos)
            install_macos_deps
            ;;
        *)
            print_error "Unsupported platform: $PLATFORM"
            exit 1
            ;;
    esac
}

# ============================================================================
# Environment Setup
# ============================================================================

setup_environment() {
    local PROFILE_FILE
    if [[ -f "$HOME/.zshrc" ]]; then
        PROFILE_FILE="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        PROFILE_FILE="$HOME/.bashrc"
    else
        PROFILE_FILE="$HOME/.profile"
    fi
    
    if grep -q "OPENCLAW_PATH_BOOTSTRAPPED" "$PROFILE_FILE" 2>/dev/null; then
        print_success "Environment already configured ($PROFILE_FILE)"
        return
    fi
    
    print_substep "Writing environment variables to $PROFILE_FILE..."
    
    cat >> "$PROFILE_FILE" << 'EOF'

# ============================================================================
# OpenClaw Environment (auto-generated by Install_termux.sh)
# ============================================================================

export OPENCLAW_PATH_BOOTSTRAPPED=1
export NODE_OPTIONS="--max-old-space-size=4096"

if [[ -n "${TERMUX_VERSION:-}" ]]; then
    export PATH="$PREFIX/bin:$PATH"
    export TMPDIR="$PREFIX/tmp"
    export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
    export NODE_EXTRA_CA_CERTS="$PREFIX/etc/tls/cert.pem"
fi

export PATH="$HOME/.local/bin:$PATH"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
EOF
    
    print_success "Environment variables written"
    source "$PROFILE_FILE" 2>/dev/null || true
}

# ============================================================================
# Termux Compatibility Patches
# ============================================================================

patch_termux_compat() {
    # Only run on Termux platform
    [[ "$PLATFORM" != "termux" ]] && return 0

    local PATCHED=0

    # Patch 1: tsdown.config.ts - exclude canvas native bindings from bundling
    if [[ -f "$PROJECT_ROOT/tsdown.config.ts" ]]; then
        if ! grep -q '@napi-rs/canvas' "$PROJECT_ROOT/tsdown.config.ts" 2>/dev/null; then
            # Insert external array after env definition
            sed -i '/^const env = {/,/^};/ {
                /^};/a\
\
// Exclude native bindings that cannot be bundled on Android\/Termux\
const external = ["@napi-rs/canvas", "@napi-rs/canvas-android-arm64"];
            }' "$PROJECT_ROOT/tsdown.config.ts"

            # Add external to each config entry
            sed -i '/^    env,$/a\    external,' "$PROJECT_ROOT/tsdown.config.ts"

            PATCHED=$((PATCHED + 1))
        fi
    fi

    # Patch 2: src/media/input-files.ts - skip canvas loading on Termux
    if [[ -f "$PROJECT_ROOT/src/media/input-files.ts" ]]; then
        if ! grep -q 'TERMUX_VERSION' "$PROJECT_ROOT/src/media/input-files.ts" 2>/dev/null; then
            sed -i '/async function loadCanvasModule/,/^}/ {
                /async function loadCanvasModule/a\
  // Skip canvas loading on Termux (Android) due to native binding incompatibility\
  if (process.env.TERMUX_VERSION || process.platform === "android") {\
    throw new Error("Canvas module not available on Android\/Termux");\
  }\

            }' "$PROJECT_ROOT/src/media/input-files.ts"

            PATCHED=$((PATCHED + 1))
        fi
    fi

    if [[ $PATCHED -gt 0 ]]; then
        print_success "Applied $PATCHED Termux compatibility patches"
    else
        print_success "Termux compatibility patches already in place"
    fi
}

# ============================================================================
# Project Build
# ============================================================================

build_project() {
    cd "$PROJECT_ROOT"
    
    if [[ "$PLATFORM" == "termux" ]]; then
        # Fix possible dpkg interrupt issues (with timeout to prevent hanging)
        print_substep "Checking dpkg lock status..."
        
        # If dpkg lock is held, wait a moment
        local dpkg_wait_count=0
        local max_dpkg_wait=10  # Wait max 10 seconds
        
        while [[ $dpkg_wait_count -lt $max_dpkg_wait ]]; do
            if ! flock -n 9 <> /data/data/com.termux/files/usr/var/lib/dpkg/lock-frontend 2>/dev/null; then
                # Lock is held, wait
                sleep 1
                dpkg_wait_count=$((dpkg_wait_count + 1))
            else
                break
            fi
        done
        
        # Try to configure dpkg, but don't block longer than 5 seconds
        if timeout 5 dpkg --configure -a > /dev/null 2>&1; then
            print_success "dpkg configuration checked"
        else
            print_warn "dpkg lock or configure timeout, skipping (already handled during deps install)"
        fi
        sleep 1
        
        export npm_config_sharp_binary_host="https://npmmirror.com/mirrors/sharp-libvips"
        export npm_config_sharp_libvips_binary_host="https://npmmirror.com/mirrors/sharp-libvips"
        git config core.hooksPath /dev/null 2>/dev/null || true
    fi
    
    # Create temp log file for error capture
    local BUILD_LOG="$PROJECT_ROOT/.build.log"
    fi
    
    # npm dependencies with spinner (capture errors to log file)
    print_substep "Installing npm dependencies with pnpm..."
    start_spinner "This may take 3-5 minutes depending on platform..."
    
    # Temporarily disable errexit to handle errors ourselves
    set +e
    
    if [[ "$PLATFORM" == "termux" ]]; then
        # Skip native builds on Termux to avoid compilation errors
        print_substep "Skipping native builds with --ignore-scripts..."
        pnpm install --no-frozen-lockfile --ignore-scripts < /dev/null 2>&1 | tee "$BUILD_LOG" | grep -E "(ERR!|WARN|added|removed|moved)" | while read line; do
            # Optionally show warnings/errors in real-time
            if [[ "$line" =~ ERR! ]] || [[ "$line" =~ WARN ]]; then
                echo -e "   ${YELLOW}$line${NC}"
            fi
        done &
        local pnpm_pid=$!
        wait $pnpm_pid
        local pnpm_exit=$?
        
        if [[ $pnpm_exit -eq 0 ]]; then
            # Run compatible postinstall scripts
            print_substep "Running postinstall scripts..."
            node node_modules/.pnpm/esbuild*/node_modules/esbuild/install.js 2>/dev/null || true
            stop_spinner "true" "npm dependencies installed"
            rm -f "$BUILD_LOG"
        else
            stop_spinner "false" "pnpm install failed (exit code: $pnpm_exit)"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ ERROR LOG ━━━━━━━━━━━━━${NC}"
            # Show last 30 lines of error
            if [[ -f "$BUILD_LOG" ]]; then
                tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            else
                echo "No build log found at $BUILD_LOG"
            fi
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}Tip: Full log saved at: $BUILD_LOG${NC}"
            echo -e "${YELLOW}Try running manually: pnpm install --no-frozen-lockfile${NC}"
            set -e  # Re-enable before exit
            exit 1
        fi
    else
        print_substep "Trying frozen lockfile first (faster)..."
        (pnpm install --frozen-lockfile 2>&1 | tee "$BUILD_LOG") || (
            print_substep "Frozen lockfile failed, trying flexible install..."
            pnpm install 2>&1 | tee "$BUILD_LOG"
        )
        local pnpm_exit=$?
        
        if [[ $pnpm_exit -eq 0 ]]; then
            stop_spinner "true" "npm dependencies installed"
            rm -f "$BUILD_LOG"
        else
            stop_spinner "false" "pnpm install failed (exit code: $pnpm_exit)"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ ERROR LOG ━━━━━━━━━━━━━${NC}"
            if [[ -f "$BUILD_LOG" ]]; then
                tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            else
                echo "No build log found at $BUILD_LOG"
            fi
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}Tip: Full log saved at: $BUILD_LOG${NC}"
            set -e  # Re-enable before exit
            exit 1
        fi
    fi
    
    # TypeScript compilation with spinner
    print_substep "Starting TypeScript compilation..."
    start_spinner "Compiling TypeScript (this may take 1-2 minutes)..."
    if [[ "$PLATFORM" == "termux" ]]; then
        # Resolve tsdown command: pnpm exec → global → direct node execution
        local TSDOWN_CMD=""
        if pnpm exec tsdown --version > /dev/null 2>&1; then
            TSDOWN_CMD="pnpm exec tsdown"
        elif command -v tsdown &> /dev/null; then
            TSDOWN_CMD="tsdown"
        else
            # Auto-install global tsdown
            print_substep "   Installing tsdown..."
            npm install -g tsdown > /dev/null 2>&1 || true
            if command -v tsdown &> /dev/null; then
                TSDOWN_CMD="tsdown"
            else
                # Last resort: direct node execution
                local TSDOWN_ENTRY=$(find node_modules/.pnpm -path '*/tsdown/dist/run.mjs' 2>/dev/null | head -1)
                if [[ -n "$TSDOWN_ENTRY" ]]; then
                    TSDOWN_CMD="node $TSDOWN_ENTRY"
                fi
            fi
        fi
        
        if [[ -z "$TSDOWN_CMD" ]]; then
            stop_spinner "false" "tsdown command not found"
            echo ""
            echo -e "${YELLOW}Tip: Install tsdown manually: npm install -g tsdown${NC}"
            exit 1
        fi
        
        print_substep "   Running tsdown (main build)..."
        if ! $TSDOWN_CMD > "$BUILD_LOG" 2>&1; then
            # Check if it's a SIGILL / rolldown CPU incompatibility
            if grep -qE "Illegal instruction|SIGILL|Invalid machine instruction|rolldown" "$BUILD_LOG" 2>/dev/null; then
                # rolldown (Rust binary) is incompatible with this CPU
                # Fallback: use esbuild (Go binary with ARM prebuilts, no SIGILL)
                stop_spinner "false" "tsdown/rolldown CPU incompatible (SIGILL)"
                print_substep "   Falling back to esbuild (ARM-compatible)..."
                start_spinner "Installing esbuild and compiling (ARM-compatible)..."
                
                # Ensure esbuild is available (prebuilt Go binary for ARM)
                if ! command -v esbuild &>/dev/null && ! npx --yes esbuild --version &>/dev/null 2>&1; then
                    npm install -g esbuild > /dev/null 2>&1 || true
                fi
                local ESBUILD_CMD="npx --yes esbuild"
                if command -v esbuild &>/dev/null; then
                    ESBUILD_CMD="esbuild"
                fi
                
                # Build all entry points without rolldown (--packages=external keeps node_modules refs)
                local ESBUILD_FLAGS="--bundle --platform=node --format=esm --packages=external --define:process.env.NODE_ENV='\"production\"' --external:@napi-rs/canvas --external:@napi-rs/canvas-android-arm64"
                local ESBUILD_OK=true
                
                mkdir -p dist dist/infra dist/cli dist/plugin-sdk dist/hooks
                
                for entry in src/index.ts src/entry.ts src/infra/warning-filter.ts src/cli/daemon-cli.ts src/extensionAPI.ts; do
                    local outfile="dist/${entry#src/}"
                    outfile="${outfile%.ts}.js"
                    mkdir -p "$(dirname "$outfile")"
                    # shellcheck disable=SC2086
                    if ! $ESBUILD_CMD "$entry" $ESBUILD_FLAGS --outfile="$outfile" >> "$BUILD_LOG" 2>&1; then
                        ESBUILD_OK=false; break
                    fi
                done
                
                if $ESBUILD_OK; then
                    # shellcheck disable=SC2086
                    $ESBUILD_CMD src/plugin-sdk/index.ts src/plugin-sdk/account-id.ts $ESBUILD_FLAGS --outdir=dist/plugin-sdk >> "$BUILD_LOG" 2>&1 || ESBUILD_OK=false
                fi
                
                if $ESBUILD_OK; then
                    find src/hooks/bundled -name 'handler.ts' 2>/dev/null | while IFS= read -r hfile; do
                        local hout="dist/${hfile#src/}"
                        hout="${hout%.ts}.js"
                        mkdir -p "$(dirname "$hout")"
                        # shellcheck disable=SC2086
                        $ESBUILD_CMD "$hfile" $ESBUILD_FLAGS --outfile="$hout" >> "$BUILD_LOG" 2>&1 || true
                    done
                    # shellcheck disable=SC2086
                    $ESBUILD_CMD src/hooks/llm-slug-generator.ts $ESBUILD_FLAGS --outfile=dist/hooks/llm-slug-generator.js >> "$BUILD_LOG" 2>&1 || true
                fi
                
                if $ESBUILD_OK; then
                    node --import tsx scripts/write-build-info.ts >> "$BUILD_LOG" 2>&1 || true
                    node --import tsx scripts/write-cli-compat.ts >> "$BUILD_LOG" 2>&1 || true
                    node --import tsx scripts/copy-hook-metadata.ts >> "$BUILD_LOG" 2>&1 || true
                    stop_spinner "true" "esbuild compilation complete (ARM-compatible fallback)"
                else
                    stop_spinner "false" "esbuild also failed"
                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━ ERROR LOG ━━━━━━━━━━━━━${NC}"
                    tail -n 20 "$BUILD_LOG" 2>/dev/null
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    exit 1
                fi
            else
                stop_spinner "false" "tsdown failed"
                echo ""
                echo -e "${RED}━━━━━━━━━━━━━ ERROR LOG ━━━━━━━━━━━━━${NC}"
                tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
                echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                exit 1
            fi
        fi
        
        print_substep "   Compiling TypeScript declaration files..."
        if ! pnpm exec tsc -p tsconfig.plugin-sdk.dts.json >> "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "tsc dts compilation failed"
            exit 1
        fi
        
        print_substep "   Generating plugin SDK..."
        if ! node --import tsx scripts/write-plugin-sdk-entry-dts.ts >> "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "plugin SDK generation failed"
            exit 1
        fi
        
        print_substep "   Copying A2UI assets..."
        if ! node --import tsx scripts/canvas-a2ui-copy.ts >> "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "A2UI copy failed"
            exit 1
        fi
        
        print_substep "   Copying hook metadata..."
        if ! node --import tsx scripts/copy-hook-metadata.ts >> "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "hook metadata copy failed"
            exit 1
        fi
        
        print_substep "   Writing build info..."
        if ! node --import tsx scripts/write-build-info.ts >> "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "build info generation failed"
            exit 1
        fi
        
        print_substep "   Writing CLI compatibility info..."
        if ! node --import tsx scripts/write-cli-compat.ts >> "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "CLI compat generation failed"
            exit 1
        fi
        
        stop_spinner "true" "TypeScript compilation complete"
        rm -f "$BUILD_LOG"
    else
        # Non-Termux platforms
        print_substep "   Running pnpm build..."
        if ! pnpm build > "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "TypeScript compilation failed"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ ERROR LOG ━━━━━━━━━━━━━${NC}"
            tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}Tip: Full log saved at: $BUILD_LOG${NC}"
            exit 1
        fi
        stop_spinner "true" "TypeScript compilation complete"
        rm -f "$BUILD_LOG"
    fi
    
    # UI build with spinner
    print_substep "Building UI components..."
    start_spinner "Building UI..."
    if pnpm ui:build > "$BUILD_LOG" 2>&1; then
        stop_spinner "true" "UI build complete"
        rm -f "$BUILD_LOG"
    else
        stop_spinner "true" "UI build skipped (optional component)"
        rm -f "$BUILD_LOG"
    fi
}

# ============================================================================
# CLI Entry Creation
# ============================================================================

create_cli_entries() {
    local BIN_DIR
    if [[ "$PLATFORM" == "termux" ]]; then
        BIN_DIR="$PREFIX/bin"
        
        # Create shims for coding agents that require standard Linux paths
        # This will wrap the npm-installed binaries
        LOCAL_BIN="$HOME/.local/bin"
        mkdir -p "$LOCAL_BIN"
        
        for agent in codex claude; do
            # We assume npm installs the real binary to $PREFIX/bin/$agent which is a symlink to JS
            # But we want our wrapper to be picked up first.
            # $HOME/.local/bin is usually before $PREFIX/bin in PATH (set in setup_environment)
            
            cat > "$LOCAL_BIN/$agent" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
# Use termux-chroot to simulate standard Linux paths for the node process
# We invoke the original npm binary from PREFIX/bin
exec termux-chroot $PREFIX/bin/$agent "\$@"
EOF
            chmod +x "$LOCAL_BIN/$agent"
            print_substep "Created wrapper: $agent -> termux-chroot"
        done
        
    else
        BIN_DIR="$HOME/.local/bin"
        mkdir -p "$BIN_DIR"
    fi
    
    ln -sf "$OPENCLAW_BIN" "$BIN_DIR/openclaw"
    chmod +x "$OPENCLAW_BIN"
    
    print_success "CLI entry: $BIN_DIR/openclaw"
}

# ============================================================================
# Service Configuration
# ============================================================================

setup_service() {
    if [[ "$PLATFORM" == "termux" ]]; then
        if check_command pm2; then
            pm2 delete openclaw-gateway > /dev/null 2>&1 || true
            pm2 start "$OPENCLAW_BIN" --name openclaw-gateway --interpreter node -- gateway start > /dev/null 2>&1
            pm2 save > /dev/null 2>&1
            print_success "PM2 service configured"
        else
            print_warn "pm2 not installed, skipping service configuration"
        fi
    else
        print_substep "Run 'openclaw gateway install' to configure system service"
    fi
}

# ============================================================================
# Installation Verification
# ============================================================================

verify_installation() {
    if check_command openclaw; then
        local VERSION
        VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
        print_success "openclaw version: $VERSION"
    else
        print_error "openclaw command not found"
        return 1
    fi
    
    local GATEWAY_RUNNING=false
    local GATEWAY_METHOD=""
    
    if check_command pm2; then
        if pm2 list 2>/dev/null | grep -q "openclaw-gateway.*online"; then
            GATEWAY_RUNNING=true
            GATEWAY_METHOD="PM2"
        fi
    fi
    
    if [[ "$GATEWAY_RUNNING" == "false" ]]; then
        if timeout 10 openclaw gateway status 2>/dev/null | grep -q "running"; then
            GATEWAY_RUNNING=true
            GATEWAY_METHOD="manual"
        fi
    fi
    
    if [[ "$GATEWAY_RUNNING" == "true" ]]; then
        print_success "Gateway status: running (managed by $GATEWAY_METHOD)"
    else
        print_warn "Gateway not running"
    fi
}

# ============================================================================
# Next Steps
# ============================================================================

print_next_steps() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                   ✓ Installation Complete!                   ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check if gateway is already running
    local GATEWAY_RUNNING=false
    if check_command pm2; then
        if pm2 list 2>/dev/null | grep -q "openclaw-gateway.*online"; then
            GATEWAY_RUNNING=true
        fi
    fi
    
    if [[ "$GATEWAY_RUNNING" == "true" ]]; then
        echo -e "${GREEN}✓ Gateway is already running via PM2${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}Next Step: Configure your API keys${NC}"
        echo -e "   openclaw onboard --install-daemon"
        echo -e "   ${DIM}This wizard will guide you through API key and model setup${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}Verify Installation:${NC}"
        echo -e "   openclaw doctor                          ${DIM}# Check configuration${NC}"
        echo -e "   pm2 logs openclaw-gateway                ${DIM}# View service logs${NC}"
    else
        echo -e "${BOLD}${YELLOW}Step 1: Apply Environment${NC}"
        echo -e "   source ~/.bashrc    ${DIM}# or ~/.zshrc${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}Step 2: Run Setup Wizard${NC}"
        echo -e "   openclaw onboard --install-daemon"
        echo -e "   ${DIM}This wizard will guide you through API key and model setup${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}PM2 Service Commands:${NC}"
    echo -e "   pm2 list                      ${DIM}# List running processes${NC}"
    echo -e "   pm2 start openclaw-gateway    ${DIM}# Start in background${NC}"
    echo -e "   pm2 logs openclaw-gateway     ${DIM}# View logs${NC}"
    echo -e "   pm2 restart openclaw-gateway  ${DIM}# Restart service${NC}"
    echo -e "   pm2 stop openclaw-gateway     ${DIM}# Stop service${NC}"
    echo ""
    echo -e "${BOLD}Manual Control (Foreground, for debugging):${NC}"
    echo -e "   openclaw gateway start        ${DIM}# Start${NC}"
    echo -e "   openclaw gateway stop         ${DIM}# Stop${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${DIM}Documentation: https://docs.openclaw.ai${NC}"
    echo -e "${DIM}GitHub: https://github.com/yunze7373/openclaw-termux${NC}"
    echo ""
    echo ""
}

uninstall_openclaw() {
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}       UNINSTALL OPENCLAW TERMUX       ${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}This will remove:${NC}"
    echo -e "  • PM2 service (openclaw-gateway)"
    echo -e "  • CLI entry ($PREFIX/bin/openclaw)"
    echo -e "  • Configuration & Agents (~/.openclaw)"
    echo -e "  • Project Repository ($PROJECT_ROOT)"
    echo ""
    
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
    echo ""

    # Stop and delete PM2 service
    if check_command pm2; then
        print_step "Removing Service"
        pm2 stop openclaw-gateway > /dev/null 2>&1 || true
        pm2 delete openclaw-gateway > /dev/null 2>&1 || true
        pm2 save > /dev/null 2>&1 || true
        print_success "Service stopped and removed"
    fi

    # Remove symlink
    local BIN_DIR
    if [[ "$PLATFORM" == "termux" ]]; then
        BIN_DIR="$PREFIX/bin"
    else
        BIN_DIR="$HOME/.local/bin"
    fi
    
    if [[ -f "$BIN_DIR/openclaw" ]]; then
        rm -f "$BIN_DIR/openclaw"
        print_success "Removed CLI entry: $BIN_DIR/openclaw"
    fi

    # Remove configuration
    if [[ -d "$HOME/.openclaw" ]]; then
        rm -rf "$HOME/.openclaw"
        print_success "Removed configuration: ~/.openclaw"
    fi

    # Remove project directory
    if [[ -d "$PROJECT_ROOT" ]]; then
        print_step "Removing Repository"
        # Verify we are not deleting $HOME (safety check)
        if [[ "$PROJECT_ROOT" == "$HOME" ]]; then
            print_error "Project root is HOME, skipping deletion!"
        else
            rm -rf "$PROJECT_ROOT"
            print_success "Removed repository: $PROJECT_ROOT"
        fi
    fi

    echo ""
    print_success "Uninstallation complete."
    echo ""
    echo -e "${DIM}Note: Dependencies (nodejs, pnpm, pm2) were kept.${NC}"
    echo -e "${DIM}To remove them, run: pkg uninstall nodejs python git${NC}"
    echo ""
}

# ============================================================================
# Main Function
# ============================================================================

show_help() {
    cat << EOF
OpenClaw Termux One-Click Deploy Script

Usage: $0 [option]

Options:
  --full      Full install (dependencies + build + service)
  --update    Update only (pull latest code + rebuild)
  --deps      Install dependencies only
  --build     Build project only
  --service   Configure service only
  --uninstall Uninstall OpenClaw
  --help      Show this help message

Examples:
  $0 --full     # First-time installation
  $0 --update   # Update to latest version
  $0 --uninstall # Remove everything
EOF
}

main() {
    export PATH="$HOME/.cargo/bin:$PATH"
    local MODE="${1:-full}"
    
    case "$MODE" in
        --help|-h)
            show_help
            exit 0
            ;;
        --full|full)
            print_header
            PLATFORM=$(detect_platform)
            
            print_step "Detecting Platform"
            print_success "Detected: $PLATFORM"
            
            print_step "Installing Dependencies"
            install_dependencies
            
            print_step "Configuring Environment"
            setup_environment
            
            print_step "Building Project"
            patch_termux_compat
            build_project
            
            # Fix sqlite-vec (Termux only)
            if [[ "$PLATFORM" == "termux" && -f "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" ]]; then
                print_step "Fixing sqlite-vec"
                bash "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" || print_warn "sqlite-vec fix skipped"
            else
                TOTAL_STEPS=$((TOTAL_STEPS - 1))
            fi
            
            print_step "Creating CLI & Configuring Service"
            create_cli_entries
            setup_service
            
            print_step "Verifying Installation"
            verify_installation
            
            print_footer
            print_next_steps
            ;;
        --update|update)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=4
            
            print_step "Detecting Platform"
            print_success "Detected: $PLATFORM"
            
            print_step "Pulling Latest Code"
            cd "$PROJECT_ROOT"
            git fetch origin > /dev/null 2>&1
            git reset --hard origin/main > /dev/null 2>&1
            print_success "Code updated"
            
            print_step "Building Project"
            patch_termux_compat
            build_project
            
            # Fix sqlite-vec (Termux only)
            if [[ "$PLATFORM" == "termux" && -f "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" ]]; then
                bash "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" > /dev/null 2>&1 || true
            fi
            
            # Restart service if running
            if check_command pm2 && pm2 list 2>/dev/null | grep -q "openclaw-gateway"; then
                print_substep "Restarting pm2 service..."
                pm2 restart openclaw-gateway > /dev/null 2>&1
                print_success "Service restarted"
            fi
            
            print_step "Verifying Installation"
            verify_installation
            
            print_footer
            print_next_steps
            ;;
        --deps|deps)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=2
            
            print_step "Detecting Platform"
            print_success "Detected: $PLATFORM"
            
            print_step "Installing Dependencies"
            install_dependencies
            setup_environment
            
            print_footer
            ;;
        --build|build)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=2
            
            print_step "Detecting Platform"
            print_success "Detected: $PLATFORM"
            
            print_step "Building Project"
            patch_termux_compat
            build_project
            create_cli_entries
            
            print_footer
            ;;
        --service|service)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=1
            
            print_step "Configuring Service"
            setup_service
            
            print_footer
            ;;
        --uninstall|uninstall)
            print_header
            PLATFORM=$(detect_platform)
            uninstall_openclaw
            ;;
        *)
            print_error "Unknown option: $MODE"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
