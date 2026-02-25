#!/usr/bin/env bash
#
# OpenClaw Termux 一键部署脚本
# 用法: ./Install_termux_cn.sh [--full | --update | --help]
#
# 功能:
#   - 检测并安装必要依赖 (Node.js, pnpm, git 等)
#   - 设置环境变量 (PATH, NODE_OPTIONS, TERMUX_VERSION 等)
#   - 安装 npm 依赖并构建项目
#   - 创建命令行入口点 (openclaw)
#   - 配置 pm2 服务 (可选)
#
# 作者: OpenClaw Team
# 版本: 2.0.0

# 注意: 我们故意不使用 "set -e" 因为我们需要自定义错误处理
# 以便在构建步骤失败时正确显示错误信息

# ============================================================================
# 配置
# ============================================================================

# 脚本现在在项目根目录，SCRIPT_DIR 就是 PROJECT_ROOT
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_BIN="$PROJECT_ROOT/openclaw.mjs"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# 步骤计数
CURRENT_STEP=0
TOTAL_STEPS=6

# ============================================================================
# UI 函数
# ============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}             OpenClaw Termux 一键部署脚本                     ${NC}${CYAN}║${NC}"
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
    echo -e "${BOLD}${GREEN}🎉 部署完成!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# 旋转动画，用于长时间任务
SPINNER_PID=""
SPINNER_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
export START_TIME=0

start_spinner() {
    local msg="$1"
    export START_TIME=$(date +%s)
    
    (
        local i=0
        local char_count=${#SPINNER_CHARS}
        local start_ts="$START_TIME"  # 在子shell中捕获
        
        while true; do
            local char="${SPINNER_CHARS:$i:1}"
            local now=$(date +%s)
            local elapsed=$(( now - start_ts ))
            
            # 每10秒增加一个点 (最多5个)
            local dot_count=$(( elapsed / 10 ))
            if [[ $dot_count -gt 5 ]]; then dot_count=5; fi
            local dots=""
            for ((d=0; d<dot_count; d++)); do dots+="."; done
            
            # 格式化经过时间
            local mins=$(( elapsed / 60 ))
            local secs=$(( elapsed % 60 ))
            local time_str
            if [[ $mins -gt 0 ]]; then
                time_str="${mins}分${secs}秒"
            else
                time_str="${secs}秒"
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
    
    # 计算最终经过时间
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    local time_str
    if [[ $mins -gt 0 ]]; then
        time_str="${mins}分${secs}秒"
    else
        time_str="${secs}秒"
    fi
    
    # 清除行
    printf "\r%100s\r" ""
    
    if [[ "$success" == "true" ]]; then
        echo -e "   ${GREEN}✓${NC} $msg ${DIM}(${time_str})${NC}"
    else
        echo -e "   ${RED}✗${NC} $msg ${DIM}(${time_str})${NC}"
    fi
}

# ============================================================================
# 环境检测
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
# 依赖检查与安装
# ============================================================================

install_termux_deps() {
    print_substep "清理包管理器锁..."
    # 杀死任何可能持有锁的 apt 进程
    pkill -f "apt|pkg" 2>/dev/null || true
    sleep 1
    
    # 移除陈旧的锁文件
    rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock-frontend 2>/dev/null || true
    rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock 2>/dev/null || true
    sleep 1
    
    print_substep "等待包管理器就绪..."
    local wait_count=0
    local max_attempts=15
    
    # 等待包管理器锁可用
    while [[ $wait_count -lt $max_attempts ]]; do
        if flock -n /data/data/com.termux/files/usr/var/lib/apt/lock -c "echo ok" &>/dev/null 2>&1; then
            print_success "包管理器已准备好"
            break
        fi
        wait_count=$((wait_count + 1))
        if [[ $wait_count -eq 5 ]]; then
            print_warn "包管理器仍被锁定，强制清理..."
            pkill -9 -f "apt|pkg" 2>/dev/null || true
            rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock* 2>/dev/null || true
            sleep 2
        else
            sleep 2
        fi
    done
    
    # 更新包列表 (带重试)
    print_substep "更新包列表 (尝试 1/3)..."
    local update_attempt=1
    while [[ $update_attempt -le 3 ]]; do
        if pkg update -y 2>&1 | tail -2; then
            break
        fi
        update_attempt=$((update_attempt + 1))
        if [[ $update_attempt -le 3 ]]; then
            print_warn "更新失败，重试 (尝试 $update_attempt/3)..."
            sleep 3
        fi
    done
    
    # 检查可升级的包
    local UPGRADABLE
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | wc -l || echo 0)
    UPGRADABLE=$((UPGRADABLE - 1))  # 减去表头行
    
    if [[ "$UPGRADABLE" -gt 0 ]]; then
        print_warn "检测到 $UPGRADABLE 个可升级的包，正在升级..."
        print_substep "这可能需要几分钟时间，具体取决于包的大小..."
        
        # 显示实时升级进度 (带重试)
        local upgrade_attempt=1
        while [[ $upgrade_attempt -le 3 ]]; do
            if pkg upgrade -y 2>&1 | grep -E "^(Processing|Unpacking|Setting up|Preparing|Configuring|^[a-zA-Z0-9])" | while read line; do
                print_substep "   $line"
            done; then
                print_success "系统包已升级"
                break
            fi
            upgrade_attempt=$((upgrade_attempt + 1))
            if [[ $upgrade_attempt -le 3 ]]; then
                print_warn "升级失败，5秒后重试 (尝试 $upgrade_attempt/3)..."
                sleep 5
            elif [[ $upgrade_attempt -gt 3 ]]; then
                print_warn "升级失败 3 次，继续安装..."
            fi
        done
    else
        print_success "系统包已是最新"
    fi
    
    print_substep "安装基础工具 (nodejs-lts, git, openssh, build-essential 等)..."
    print_substep "这可能需要几分钟时间，请耐心等待..."
    
    # 带重试暄安装，以确保可靠性
    local install_attempt=1
    while [[ $install_attempt -le 2 ]]; do
        if ! pkg install -y --fix-broken nodejs-lts git openssh curl wget jq python golang rust build-essential mpv proot tailscale cloudflared 2>&1 | while read line; do
            # 显示进度行，但限制频率以避免过度输出
            if [[ "$line" =~ ^(Processing|Unpacking|Setting up|Reading|Building|Get:|Hit:|Ign:|^[a-z0-9\-]+:) ]]; then
                print_substep "   $line"
            fi
        done; then
            if [[ $install_attempt -lt 2 ]]; then
                print_warn "安装失败，重试 (尝试 $((install_attempt + 1))/2)..."
                pkill -f "apt|pkg" 2>/dev/null || true
                sleep 3
                install_attempt=$((install_attempt + 1))
            else
                print_error "基础工具安装失败 2 次"
                exit 1
            fi
        else
            break
        fi
    done
    print_success "nodejs-lts, git, curl, jq 及其他工具"
    
    if ! check_command pnpm; then
        print_substep "全局安装 pnpm..."
        if ! npm install -g pnpm 2>&1 | tail -3; then
            print_error "pnpm 安装失败"
            exit 1
        fi
    fi
    print_success "pnpm"
    
    if ! check_command pm2; then
        print_substep "全局安装 pm2..."
        # pm2 安装带有超时保护和进度反馈
        local pm2_attempt=0
        while [[ $pm2_attempt -lt 2 ]]; do
            # 显示实时进度，不缓冲输出
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
                    print_warn "pm2 安装超时 (120s)，清理进程并重试..."
                    pkill -9 npm 2>/dev/null || true
                    pkill -9 node 2>/dev/null || true
                    sleep 3
                elif [[ $pm2_attempt -lt 1 ]]; then
                    print_warn "pm2 安装失败 (exit code: $npm_exit)，尝试 $((pm2_attempt + 2))/2..."
                    pkill -9 npm 2>/dev/null || true
                    sleep 2
                else
                    print_error "pm2 全局安装失败 2 次，请检查网络连接"
                    exit 1
                fi
            fi
            pm2_attempt=$((pm2_attempt + 1))
        done
    fi
    print_success "pm2"
}

install_linux_deps() {
    print_substep "检测包管理器并更新系统..."
    
    if check_command apt-get; then
        print_substep "   检测到 apt-get 包管理器..."
        print_substep "   运行 apt-get update..."
        if ! sudo apt-get update 2>&1 | tail -5; then
            print_error "apt-get update 失败"
            exit 1
        fi
        print_substep "   使用 apt-get 安装 (nodejs npm git curl jq)..."
        if ! sudo apt-get install -y nodejs npm git curl jq 2>&1 | tail -5; then
            print_error "apt-get 安装失败"
            exit 1
        fi
    elif check_command dnf; then
        print_substep "   检测到 dnf 包管理器..."
        print_substep "   使用 dnf 安装 (nodejs npm git curl jq)..."
        if ! sudo dnf install -y nodejs npm git curl jq 2>&1 | tail -5; then
            print_error "dnf 安装失败"
            exit 1
        fi
    elif check_command pacman; then
        print_substep "   检测到 pacman 包管理器..."
        print_substep "   使用 pacman 安装 (nodejs npm git curl jq)..."
        if ! sudo pacman -Sy --noconfirm nodejs npm git curl jq 2>&1 | tail -5; then
            print_error "pacman 安装失败"
            exit 1
        fi
    else
        print_warn "无法检测包管理器，请手动安装: nodejs npm git curl jq"
    fi
    
    if ! check_command pnpm; then
        print_substep "全局安装 pnpm..."
        npm install -g pnpm 2>&1 | tail -3
    fi
    print_success "依赖安装完成"
}

install_macos_deps() {
    print_substep "通过 Homebrew 安装 macOS 依赖..."
    
    if ! check_command brew; then
        print_error "请先安装 Homebrew: https://brew.sh"
        exit 1
    fi
    
    print_substep "   使用 Homebrew 安装 (node git jq)..."
    if ! brew install node git jq 2>&1 | tail -5; then
        print_error "Homebrew 安装失败"
        exit 1
    fi
    
    if ! check_command pnpm; then
        print_substep "全局安装 pnpm..."
        npm install -g pnpm 2>&1 | tail -3
    fi
    print_success "依赖安装完成"
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
            print_error "不支持的平台: $PLATFORM"
            exit 1
            ;;
    esac
}

# ============================================================================
# 环境变量设置
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
        print_success "环境变量已配置 ($PROFILE_FILE)"
        return
    fi
    
    print_substep "写入环境变量到 $PROFILE_FILE..."
    
    cat >> "$PROFILE_FILE" << 'EOF'

# ============================================================================
# OpenClaw 环境配置 (由 Install_termux_cn.sh 自动生成)
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
    
    print_success "环境变量已写入"
    source "$PROFILE_FILE" 2>/dev/null || true
}

# ============================================================================
# Termux 兼容性补丁
# ============================================================================

patch_termux_compat() {
    # 仅在 Termux 平台执行
    [[ "$PLATFORM" != "termux" ]] && return 0

    local PATCHED=0

    # 补丁 1: tsdown.config.ts - 排除 canvas 原生绑定
    if [[ -f "$PROJECT_ROOT/tsdown.config.ts" ]]; then
        if ! grep -q '@napi-rs/canvas' "$PROJECT_ROOT/tsdown.config.ts" 2>/dev/null; then
            # 在 env 定义后插入 external 数组
            sed -i '/^const env = {/,/^};/ {
                /^};/a\
\
const external = ["@napi-rs/canvas", "@napi-rs/canvas-android-arm64"];
            }' "$PROJECT_ROOT/tsdown.config.ts"

            # 在每个配置条目中添加 external
            sed -i '/^    env,$/a\    external,' "$PROJECT_ROOT/tsdown.config.ts"

            PATCHED=$((PATCHED + 1))
        fi
    fi

    # 补丁 2: src/media/input-files.ts - 跳过 Termux 上的 canvas 加载
    if [[ -f "$PROJECT_ROOT/src/media/input-files.ts" ]]; then
        if ! grep -q 'TERMUX_VERSION' "$PROJECT_ROOT/src/media/input-files.ts" 2>/dev/null; then
            sed -i '/async function loadCanvasModule/,/^}/ {
                /async function loadCanvasModule/a\
  if (process.env.TERMUX_VERSION || process.platform === "android") {\
    throw new Error("Canvas module not available on Android/Termux");\
  }\

            }' "$PROJECT_ROOT/src/media/input-files.ts"

            PATCHED=$((PATCHED + 1))
        fi
    fi

    # 补丁 3: playwright-core stub 将在 pnpm install 之后注入
    # (见 build_project -> stub_playwright_core)
    # 注意：不在这里创建 stub，因为 pnpm install 会覆盖它

    if [[ $PATCHED -gt 0 ]]; then
        print_success "已应用 $PATCHED 个 Termux 兼容性补丁"
    else
        print_success "Termux 兼容性补丁已就位"
    fi
}

# ============================================================================
# playwright-core stub (必须在 pnpm install 之后运行!)
# ============================================================================

stub_playwright_core() {
    # 仅在 Termux 平台执行
    [[ "$PLATFORM" != "termux" ]] && return 0

    # playwright-core 在 Android 上会抛出 "Unsupported platform: android" 崩溃
    # 我们替换真实包为 stub，让 require("playwright-core") 返回空对象

    local PW_STUB_JS='// Stub for playwright-core on Termux/Android
// The real playwright-core throws: "Error: Unsupported platform: android"
// This stub allows the app to load without crashing
module.exports = {
  chromium: null,
  firefox: null,
  webkit: null,
  devices: {},
  errors: {},
  selectors: {},
  _addSelectorsTag: function() {},
};'

    local PW_STUB_PKG='{
  "name": "playwright-core",
  "version": "0.0.0-termux-stub",
  "main": "index.js",
  "description": "Stub for playwright-core on Termux/Android"
}'

    # 1. 替换 pnpm .pnpm store 中的真实 playwright-core（实际文件位置）
    local pnpm_pw_dirs
    pnpm_pw_dirs=$(find "$PROJECT_ROOT/node_modules/.pnpm" -maxdepth 1 -type d -name 'playwright-core@*' 2>/dev/null || true)
    for pw_dir in $pnpm_pw_dirs; do
        local real_dir="$pw_dir/node_modules/playwright-core"
        if [[ -d "$real_dir" ]]; then
            # 替换真实文件为 stub
            rm -rf "$real_dir/lib" "$real_dir/types" 2>/dev/null || true
            echo "$PW_STUB_JS" > "$real_dir/index.js"
            # 保留原始 package.json 中的 name/version 以满足 pnpm 校验
            if [[ -f "$real_dir/package.json" ]]; then
                # 用 node 修改 main 字段指向我们的 stub
                node -e "
                    const fs = require('fs');
                    const p = JSON.parse(fs.readFileSync('$real_dir/package.json', 'utf8'));
                    p.main = 'index.js';
                    fs.writeFileSync('$real_dir/package.json', JSON.stringify(p, null, 2));
                " 2>/dev/null || echo "$PW_STUB_PKG" > "$real_dir/package.json"
            fi
        fi
    done

    # 2. 替换/创建顶层 node_modules/playwright-core（symlink 或 directory）
    local top_pw="$PROJECT_ROOT/node_modules/playwright-core"
    # 如果是 symlink（pnpm 默认），先删除 symlink
    if [[ -L "$top_pw" ]]; then
        rm -f "$top_pw"
    elif [[ -d "$top_pw" ]]; then
        rm -rf "$top_pw"
    fi
    mkdir -p "$top_pw"
    echo "$PW_STUB_PKG" > "$top_pw/package.json"
    echo "$PW_STUB_JS" > "$top_pw/index.js"

    # 3. 如果有 .pnpm store 中的 deep nested playwright-core，也处理
    find "$PROJECT_ROOT/node_modules/.pnpm" -path "*/node_modules/playwright-core/lib/server/registry/index.js" -type f 2>/dev/null | while read -r registry_file; do
        # 替换 registry/index.js 中的平台检查，直接导出空
        echo "module.exports = {};" > "$registry_file" 2>/dev/null || true
    done
}

# ============================================================================
# 项目构建
# ============================================================================

build_project() {
    cd "$PROJECT_ROOT"
    
    if [[ "$PLATFORM" == "termux" ]]; then
        # 修复可能的 dpkg 中断问题（带超时防止无限卡住）
        print_substep "检查 dpkg 锁定状态..."
        
        # 如果 dpkg 锁被持有，等待片刻
        local dpkg_wait_count=0
        local max_dpkg_wait=10  # 最多等待10秒
        
        while [[ $dpkg_wait_count -lt $max_dpkg_wait ]]; do
            if ! flock -n 9 <> /data/data/com.termux/files/usr/var/lib/dpkg/lock-frontend 2>/dev/null; then
                # 锁被持有，等待
                sleep 1
                dpkg_wait_count=$((dpkg_wait_count + 1))
            else
                break
            fi
        done
        
        # 尝试配置 dpkg，但不阻塞超过5秒
        if timeout 5 dpkg --configure -a > /dev/null 2>&1; then
            print_success "dpkg 配置已检查"
        else
            print_warn "dpkg 锁定或配置超时，跳过 (已在依赖安装时处理)"
        fi
        sleep 1
        
        export npm_config_sharp_binary_host="https://npmmirror.com/mirrors/sharp-libvips"
        export npm_config_sharp_libvips_binary_host="https://npmmirror.com/mirrors/sharp-libvips"
        git config core.hooksPath /dev/null 2>/dev/null || true
    fi
    # 创建临时日志文件用于捕获错误
    local BUILD_LOG="$PROJECT_ROOT/.build.log"
    
    # npm 依赖安装（带旋转动画，捕获错误到日志）
    print_substep "使用 pnpm 安装 npm 依赖..."
    start_spinner "这可能需要 3-5 分钟，具体取决于平台..."
    
    # 暂时禁用 errexit 以便自行处理错误
    set +e
    
    if [[ "$PLATFORM" == "termux" ]]; then
        # Skip native builds on Termux to avoid compilation errors
        print_substep "使用 --ignore-scripts 跳过原生依赖编译..."
        pnpm install --no-frozen-lockfile --ignore-scripts < /dev/null 2>&1 | tee "$BUILD_LOG" | grep -E "(ERR!|WARN|added|removed|moved)" | while read line; do
            # 可选：实时显示警告/错误
            if [[ "$line" =~ ERR! ]] || [[ "$line" =~ WARN ]]; then
                echo -e "   ${YELLOW}$line${NC}"
            fi
        done &
        local pnpm_pid=$!
        wait $pnpm_pid
        local pnpm_exit=$?
        
        if [[ $pnpm_exit -eq 0 ]]; then
            # 手动运行兼容的 postinstall 脚本
            print_substep "运行 postinstall 脚本..."
            node node_modules/.pnpm/esbuild*/node_modules/esbuild/install.js 2>/dev/null || true
            # 关键: pnpm install 会覆盖之前的 stub，必须在安装后重新注入
            stub_playwright_core
            stop_spinner "true" "npm 依赖安装完成"
            rm -f "$BUILD_LOG"
        else
            stop_spinner "false" "pnpm install 失败 (退出码: $pnpm_exit)"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ 错误日志 ━━━━━━━━━━━━━${NC}"
            if [[ -f "$BUILD_LOG" ]]; then
                tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            else
                echo "未找到构建日志: $BUILD_LOG"
            fi
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}提示: 完整日志保存在: $BUILD_LOG${NC}"
            echo -e "${YELLOW}尝试手动运行: pnpm install --no-frozen-lockfile${NC}"
            set -e
            exit 1
        fi
    else
        print_substep "尝试标准锁定文件安装 (更快)..."
        (pnpm install --frozen-lockfile 2>&1 | tee "$BUILD_LOG") || (
            print_substep "标准锁定文件安装失败，尝试灵活安装..."
            pnpm install 2>&1 | tee "$BUILD_LOG"
        )
        local pnpm_exit=$?
        
        if [[ $pnpm_exit -eq 0 ]]; then
            stop_spinner "true" "npm 依赖安装完成"
            rm -f "$BUILD_LOG"
        else
            stop_spinner "false" "pnpm install 失败 (退出码: $pnpm_exit)"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ 错误日志 ━━━━━━━━━━━━━${NC}"
            if [[ -f "$BUILD_LOG" ]]; then
                tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            else
                echo "未找到构建日志: $BUILD_LOG"
            fi
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}提示: 完整日志保存在: $BUILD_LOG${NC}"
            exit 1
        fi
    fi
    
    # TypeScript 编译（带旋转动画）
    print_substep "启动 TypeScript 编译..."
    start_spinner "编译 TypeScript (这可能需要 1-2 分钟)..."
    if [[ "$PLATFORM" == "termux" ]]; then
        # Termux: 尝试标准构建，如果失败则使用加速编译
        print_substep "   运行 pnpm build (主要构建)..."
        if ! pnpm build > "$BUILD_LOG" 2>&1; then
            # 检查是否是 rolldown/canvas:a2ui:bundle 失败（CPU 指令不兼容）
            if grep -qE "Illegal instruction|SIGILL|Invalid machine instruction|rolldown" "$BUILD_LOG" 2>/dev/null; then
                # rolldown (Rust 二进制) 在此 CPU 上不可用
                # 回退：使用 esbuild（Go 二进制，有 ARM 预构建，不会 SIGILL）
                stop_spinner "false" "本地编译不可用 (rolldown CPU 不兼容)"
                print_substep "   使用 esbuild 作为备用编译器..."
                start_spinner "安装 esbuild 并编译 (ARM 兼容)..."
                
                # 确保 esbuild 可用（有 ARM 预构建二进制）
                if ! command -v esbuild &>/dev/null && ! npx --yes esbuild --version &>/dev/null 2>&1; then
                    npm install -g esbuild > /dev/null 2>&1 || true
                fi
                local ESBUILD_CMD="npx --yes esbuild"
                if command -v esbuild &>/dev/null; then
                    ESBUILD_CMD="esbuild"
                fi
                
                # esbuild 编译各入口点（--packages=external 保留 node_modules 引用）
                local ESBUILD_FLAGS="--bundle --platform=node --format=esm --packages=external --define:process.env.NODE_ENV='\"production\"' --external:@napi-rs/canvas --external:@napi-rs/canvas-android-arm64 --external:playwright-core"
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
                    # plugin-sdk 入口
                    # shellcheck disable=SC2086
                    $ESBUILD_CMD src/plugin-sdk/index.ts src/plugin-sdk/account-id.ts $ESBUILD_FLAGS --outdir=dist/plugin-sdk >> "$BUILD_LOG" 2>&1 || ESBUILD_OK=false
                fi
                
                if $ESBUILD_OK; then
                    # hooks 入口
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
                    # post-build 脚本（write-build-info 等，纯 Node.js 可运行）
                    node --import tsx scripts/write-build-info.ts >> "$BUILD_LOG" 2>&1 || true
                    node --import tsx scripts/write-cli-compat.ts >> "$BUILD_LOG" 2>&1 || true
                    node --import tsx scripts/copy-hook-metadata.ts >> "$BUILD_LOG" 2>&1 || true
                    stop_spinner "true" "esbuild 编译完成 (ARM 兼容备用方案)"
                else
                    stop_spinner "false" "esbuild 编译也失败"
                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━ 构建失败详情 ━━━━━━━━━━━━━${NC}"
                    tail -n 20 "$BUILD_LOG" 2>/dev/null
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    exit 1
                fi
            else
                # 其他构建错误
                stop_spinner "false" "pnpm build 失败"
                echo ""
                echo -e "${RED}━━━━━━━━━━━━━ 错误日志 ━━━━━━━━━━━━━${NC}"
                tail -n 40 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
                echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                exit 1
            fi
        else
            print_substep "   修复 Termux 兼容性问题..."
            if ! (pnpm exec tsc 2>&1 | tee -a "$BUILD_LOG" && \
                  pnpm exec tsc -p tsconfig.plugin-sdk.dts.json >> "$BUILD_LOG" 2>&1 && \
                  node --import tsx scripts/write-build-info.ts >> "$BUILD_LOG" 2>&1); then
                # 继续进行，即使有警告
                print_substep "   编译有部分警告但继续进行..."
            fi
        fi
        
        stop_spinner "true" "TypeScript 编译完成"
        rm -f "$BUILD_LOG"
    else
        print_substep "   运行 pnpm build..."
        if ! pnpm build > "$BUILD_LOG" 2>&1; then
            stop_spinner "false" "构建失败"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ 错误日志 ━━━━━━━━━━━━━${NC}"
            tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}提示: 完整日志保存在: $BUILD_LOG${NC}"
            exit 1
        fi
        stop_spinner "true" "TypeScript 编译完成"
        rm -f "$BUILD_LOG"
    fi
    
    # UI 构建（带旋转动画）
    print_substep "构建 UI 组件..."
    start_spinner "构建 UI..."
    if pnpm ui:build > "$BUILD_LOG" 2>&1; then
        stop_spinner "true" "UI 构建完成"
        rm -f "$BUILD_LOG"
    else
        stop_spinner "true" "UI 构建跳过 (可选组件)"
        rm -f "$BUILD_LOG"
    fi
}

# ============================================================================
# 创建命令行入口
# ============================================================================

create_cli_entries() {
    local BIN_DIR
    if [[ "$PLATFORM" == "termux" ]]; then
        BIN_DIR="$PREFIX/bin"
    else
        BIN_DIR="$HOME/.local/bin"
        mkdir -p "$BIN_DIR"
    fi
    
    ln -sf "$OPENCLAW_BIN" "$BIN_DIR/openclaw"
    chmod +x "$OPENCLAW_BIN"
    
    print_success "命令行入口: $BIN_DIR/openclaw"
}

# ============================================================================
# 服务配置
# ============================================================================

setup_service() {
    if [[ "$PLATFORM" == "termux" ]]; then
        if check_command pm2; then
            pm2 delete openclaw-gateway > /dev/null 2>&1 || true
            # Termux: 直接启动 Node.js 脚本，确保参数正确传递
            # 使用 openclaw.mjs 而不是链接的 OPENCLAW_BIN，以确保 PM2 正确处理参数
            # 重要：使用 'gateway run' 而不是 'gateway start'（start是PM2管理命令，不会实际执行服务）
            # Export env vars so pm2 child process inherits them for Termux detection
            export TERMUX=1
            export TERMUX_VERSION="${TERMUX_VERSION:-termux}"
            export ANDROID_ROOT="${ANDROID_ROOT:-/system}"
            pm2 start node \
                --name openclaw-gateway \
                --cwd "$PROJECT_ROOT" \
                --merge-logs \
                --time \
                -- "$PROJECT_ROOT/openclaw.mjs" gateway run
            pm2 save > /dev/null 2>&1
            print_success "PM2 服务已配置"
        else
            print_warn "pm2 未安装，跳过服务配置"
        fi
    else
        print_substep "运行 'openclaw gateway install' 配置系统服务"
    fi
}

# ============================================================================
# 验证安装
# ============================================================================

verify_installation() {
    if check_command openclaw; then
        local VERSION
        VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
        print_success "openclaw 版本: $VERSION"
    else
        print_error "openclaw 命令未找到"
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
            GATEWAY_METHOD="手动"
        fi
    fi
    
    if [[ "$GATEWAY_RUNNING" == "true" ]]; then
        print_success "Gateway 状态: 运行中 (通过 $GATEWAY_METHOD 管理)"
    else
        print_warn "Gateway 未运行"
    fi
}

# ============================================================================
# 后续步骤
# ============================================================================

print_next_steps() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                     ✓ 安装完成!                              ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 检查 gateway 是否已经在运行
    local GATEWAY_RUNNING=false
    if check_command pm2; then
        if pm2 list 2>/dev/null | grep -q "openclaw-gateway.*online"; then
            GATEWAY_RUNNING=true
        fi
    fi
    
    if [[ "$GATEWAY_RUNNING" == "true" ]]; then
        echo -e "${GREEN}✓ Gateway 已通过 PM2 自动启动${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}下一步: 配置 API 密钥${NC}"
        echo -e "   openclaw onboard --install-daemon"
        echo -e "   ${DIM}引导程序将帮助您配置 API 密钥和模型${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}验证安装:${NC}"
        echo -e "   openclaw doctor                          ${DIM}# 检查配置${NC}"
        echo -e "   pm2 logs openclaw-gateway                ${DIM}# 查看服务日志${NC}"
    else
        echo -e "${BOLD}${YELLOW}步骤 1: 应用环境变量${NC}"
        echo -e "   source ~/.bashrc    ${DIM}# 或 ~/.zshrc${NC}"
        echo ""
        echo -e "${BOLD}${YELLOW}步骤 2: 运行配置向导${NC}"
        echo -e "   openclaw onboard --install-daemon"
        echo -e "   ${DIM}引导程序将帮助您配置 API 密钥和模型${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}PM2 服务命令:${NC}"
    echo -e "   pm2 list                      ${DIM}# 查看进程列表${NC}"
    echo -e "   pm2 start openclaw-gateway    ${DIM}# 后台启动${NC}"
    echo -e "   pm2 logs openclaw-gateway     ${DIM}# 查看日志${NC}"
    echo -e "   pm2 restart openclaw-gateway  ${DIM}# 重启服务${NC}"
    echo -e "   pm2 stop openclaw-gateway     ${DIM}# 停止服务${NC}"
    echo ""
    echo -e "${BOLD}手动控制 (前台运行，调试用):${NC}"
    echo -e "   openclaw gateway start        ${DIM}# 启动${NC}"
    echo -e "   openclaw gateway stop         ${DIM}# 停止${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${DIM}文档: https://docs.openclaw.ai${NC}"
    echo -e "${DIM}GitHub: https://github.com/yunze7373/openclaw-termux${NC}"
    echo ""
    echo ""
}

uninstall_openclaw() {
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}          卸载 OPENCLAW TERMUX          ${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}这将删除以下内容:${NC}"
    echo -e "  • PM2 服务 (openclaw-gateway)"
    echo -e "  • 命令行入口 ($PREFIX/bin/openclaw)"
    echo -e "  • 配置文件和 Agents (~/.openclaw)"
    echo -e "  • 项目仓库 ($PROJECT_ROOT)"
    echo ""
    
    read -p "确定要继续吗? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "卸载已取消."
        exit 0
    fi
    echo ""

    # 停止并删除 PM2 服务
    if check_command pm2; then
        print_step "正在移除服务"
        pm2 stop openclaw-gateway > /dev/null 2>&1 || true
        pm2 delete openclaw-gateway > /dev/null 2>&1 || true
        pm2 save > /dev/null 2>&1 || true
        print_success "服务已停止并移除"
    fi

    # 移除符号链接
    local BIN_DIR
    if [[ "$PLATFORM" == "termux" ]]; then
        BIN_DIR="$PREFIX/bin"
    else
        BIN_DIR="$HOME/.local/bin"
    fi
    
    if [[ -f "$BIN_DIR/openclaw" ]]; then
        rm -f "$BIN_DIR/openclaw"
        print_success "已移除命令行入口: $BIN_DIR/openclaw"
    fi

    # 移除配置
    if [[ -d "$HOME/.openclaw" ]]; then
        rm -rf "$HOME/.openclaw"
        print_success "已移除配置文件: ~/.openclaw"
    fi

    # 移除项目目录
    if [[ -d "$PROJECT_ROOT" ]]; then
        print_step "正在移除仓库"
        # 安全检查
        if [[ "$PROJECT_ROOT" == "$HOME" ]]; then
            print_error "项目根目录是 HOME, 为了安全跳过删除!"
        else
            rm -rf "$PROJECT_ROOT"
            print_success "已移除项目仓库: $PROJECT_ROOT"
        fi
    fi

    echo ""
    print_success "卸载完成."
    echo ""
    echo -e "${DIM}提示: 依赖环境 (nodejs, pnpm, pm2) 已保留.${NC}"
    echo -e "${DIM}如需移除它们, 请运行: pkg uninstall nodejs python git${NC}"
    echo ""
}

# ============================================================================
# 主函数
# ============================================================================

show_help() {
    cat << EOF
OpenClaw Termux 一键部署脚本

用法: $0 [选项]

选项:
  --full      完整安装 (依赖 + 构建 + 服务)
  --update    仅更新 (拉取最新代码 + 重新构建)
  --deps      仅安装依赖
  --build     仅构建项目
  --service   仅配置服务
  --uninstall 卸载 OpenClaw
  --help      显示帮助信息

示例:
  $0 --full     # 首次安装
  $0 --update   # 更新到最新版本
  $0 --uninstall # 卸载全部
EOF
}

main() {
    local MODE="${1:-full}"
    
    case "$MODE" in
        --help|-h)
            show_help
            exit 0
            ;;
        --full|full)
            print_header
            PLATFORM=$(detect_platform)
            
            print_step "检测平台"
            print_success "检测到: $PLATFORM"
            
            print_step "安装依赖"
            install_dependencies
            
            print_step "配置环境变量"
            setup_environment
            
            print_step "构建项目"
            patch_termux_compat
            build_project
            
            # 修复 sqlite-vec (Termux 需要)
            if [[ "$PLATFORM" == "termux" && -f "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" ]]; then
                print_step "修复 sqlite-vec"
                bash "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" || print_warn "sqlite-vec 修复跳过"
            else
                TOTAL_STEPS=$((TOTAL_STEPS - 1))
            fi
            
            print_step "创建入口 & 配置服务"
            create_cli_entries
            setup_service
            
            # 验证安装（作为第 6 步的后续，不显示为独立步骤）
            echo ""
            print_substep "验证安装..."
            verify_installation
            
            print_footer
            print_next_steps
            ;;
        --update|update)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=4
            
            print_step "检测平台"
            print_success "检测到: $PLATFORM"
            
            print_step "拉取最新代码"
            cd "$PROJECT_ROOT"
            
            # 清理本地修改和未跟踪的文件
            print_substep "清理工作目录..."
            git fetch origin > /dev/null 2>&1 || print_warn "git fetch 失败，继续..."
            git stash > /dev/null 2>&1 || true
            git clean -fd > /dev/null 2>&1 || true
            git checkout -- . > /dev/null 2>&1 || true
            
            # 确保在 main 分支且完全同步
            print_substep "切换到 main 分支..."
            git checkout main > /dev/null 2>&1 || { print_error "无法切换到 main 分支"; exit 1; }
            git reset --hard origin/main > /dev/null 2>&1 || { print_error "无法同步 main 分支"; exit 1; }
            
            print_success "代码已更新"
            
            print_step "构建项目"
            patch_termux_compat
            build_project
            
            # 修复 sqlite-vec (Termux 需要)
            if [[ "$PLATFORM" == "termux" && -f "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" ]]; then
                bash "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" > /dev/null 2>&1 || true
            fi
            
            # 重启服务前，确保 dist 存在
            if [[ ! -f "$PROJECT_ROOT/dist/entry.js" && ! -f "$PROJECT_ROOT/dist/entry.mjs" ]]; then
                print_warn "dist 目录不完整，重新编译..."
                build_project
            fi
            
            # 重启服务 (如果正在运行)
            if check_command pm2 && pm2 list 2>/dev/null | grep -q "openclaw-gateway"; then
                print_substep "重启 pm2 服务..."
                pm2 restart openclaw-gateway > /dev/null 2>&1
                print_success "服务已重启"
            fi
            
            print_step "验证安装"
            verify_installation
            
            print_footer
            print_next_steps
            ;;
        --deps|deps)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=2
            
            print_step "检测平台"
            print_success "检测到: $PLATFORM"
            
            print_step "安装依赖"
            install_dependencies
            setup_environment
            
            print_footer
            ;;
        --build|build)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=2
            
            print_step "检测平台"
            print_success "检测到: $PLATFORM"
            
            print_step "构建项目"
            patch_termux_compat
            build_project
            create_cli_entries
            
            print_footer
            ;;
        --service|service)
            print_header
            PLATFORM=$(detect_platform)
            TOTAL_STEPS=1
            
            print_step "配置服务"
            setup_service
            
            print_footer
            ;;
        --uninstall|uninstall)
            print_header
            PLATFORM=$(detect_platform)
            uninstall_openclaw
            ;;
        *)
            print_error "未知选项: $MODE"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
