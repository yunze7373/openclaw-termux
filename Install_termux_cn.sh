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
    print_substep "检查系统包更新..."
    local UPGRADABLE
    UPGRADABLE=$(pkg update -y 2>&1 | grep -c "can be upgraded" 2>/dev/null || true)
    UPGRADABLE=${UPGRADABLE:-0}
    UPGRADABLE=${UPGRADABLE//[^0-9]/}  # 移除非数字字符
    if [[ -z "$UPGRADABLE" ]] || [[ "$UPGRADABLE" -eq 0 ]]; then
        UPGRADABLE=0
    fi
    if [[ "$UPGRADABLE" -gt 0 ]]; then
        print_warn "检测到 $UPGRADABLE 个可升级的包，正在升级..."
        pkg upgrade -y > /dev/null 2>&1 || {
            print_error "系统包升级失败"
            exit 1
        }
        print_success "系统包已升级"
    else
        print_success "系统包已是最新"
    fi
    
    print_substep "安装基础工具..."
    pkg install -y nodejs-lts git openssh curl wget jq > /dev/null 2>&1
    print_success "nodejs-lts, git, curl, jq"
    
    if ! check_command pnpm; then
        print_substep "安装 pnpm..."
        npm install -g pnpm > /dev/null 2>&1
    fi
    print_success "pnpm"
    
    if ! check_command pm2; then
        print_substep "安装 pm2..."
        npm install -g pm2 > /dev/null 2>&1
    fi
    print_success "pm2"
}

install_linux_deps() {
    print_substep "安装 Linux 依赖..."
    
    if check_command apt-get; then
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y nodejs npm git curl jq > /dev/null 2>&1
    elif check_command dnf; then
        sudo dnf install -y nodejs npm git curl jq > /dev/null 2>&1
    elif check_command pacman; then
        sudo pacman -Sy --noconfirm nodejs npm git curl jq > /dev/null 2>&1
    else
        print_warn "无法检测包管理器，请手动安装: nodejs npm git curl jq"
    fi
    
    if ! check_command pnpm; then
        npm install -g pnpm > /dev/null 2>&1
    fi
    print_success "依赖安装完成"
}

install_macos_deps() {
    print_substep "安装 macOS 依赖..."
    
    if ! check_command brew; then
        print_error "请先安装 Homebrew: https://brew.sh"
        exit 1
    fi
    
    brew install node git jq > /dev/null 2>&1
    
    if ! check_command pnpm; then
        npm install -g pnpm > /dev/null 2>&1
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
// Exclude native bindings that cannot be bundled on Android\/Termux\
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
  // Skip canvas loading on Termux (Android) due to native binding incompatibility\
  if (process.env.TERMUX_VERSION || process.platform === "android") {\
    throw new Error("Canvas module not available on Android\/Termux");\
  }\

            }' "$PROJECT_ROOT/src/media/input-files.ts"

            PATCHED=$((PATCHED + 1))
        fi
    fi

    if [[ $PATCHED -gt 0 ]]; then
        print_success "已应用 $PATCHED 个 Termux 兼容性补丁"
    else
        print_success "Termux 兼容性补丁已就位"
    fi
}

# ============================================================================
# 项目构建
# ============================================================================

build_project() {
    cd "$PROJECT_ROOT"
    
    if [[ "$PLATFORM" == "termux" ]]; then
        export npm_config_sharp_binary_host="https://npmmirror.com/mirrors/sharp-libvips"
        export npm_config_sharp_libvips_binary_host="https://npmmirror.com/mirrors/sharp-libvips"
        git config core.hooksPath /dev/null 2>/dev/null || true
    fi
    # 创建临时日志文件用于捕获错误
    local BUILD_LOG="$PROJECT_ROOT/.build.log"
    
    # npm 依赖安装（带旋转动画，捕获错误到日志）
    start_spinner "安装 npm 依赖 (这可能需要 3-5 分钟)..."
    
    # 暂时禁用 errexit 以便自行处理错误
    set +e
    
    if [[ "$PLATFORM" == "termux" ]]; then
        pnpm install --no-frozen-lockfile --ignore-scripts < /dev/null > "$BUILD_LOG" 2>&1
        local pnpm_exit=$?
        
        if [[ $pnpm_exit -eq 0 ]]; then
            # 手动运行兼容的 postinstall 脚本
            node node_modules/.pnpm/esbuild*/node_modules/esbuild/install.js 2>/dev/null || true
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
        pnpm install --frozen-lockfile > "$BUILD_LOG" 2>&1 || pnpm install > "$BUILD_LOG" 2>&1
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
    start_spinner "编译 TypeScript (这可能需要 1-2 分钟)..."
    if [[ "$PLATFORM" == "termux" ]]; then
        # 解析 tsdown 命令: pnpm exec → 全局 → 直接 node 执行
        local TSDOWN_CMD=""
        if pnpm exec tsdown --version > /dev/null 2>&1; then
            TSDOWN_CMD="pnpm exec tsdown"
        elif command -v tsdown &> /dev/null; then
            TSDOWN_CMD="tsdown"
        else
            # 自动安装全局 tsdown
            npm install -g tsdown > /dev/null 2>&1 || true
            if command -v tsdown &> /dev/null; then
                TSDOWN_CMD="tsdown"
            else
                # 最后回退: 直接用 node 执行
                local TSDOWN_ENTRY=$(find node_modules/.pnpm -path '*/tsdown/dist/run.mjs' 2>/dev/null | head -1)
                if [[ -n "$TSDOWN_ENTRY" ]]; then
                    TSDOWN_CMD="node $TSDOWN_ENTRY"
                fi
            fi
        fi
        
        if [[ -z "$TSDOWN_CMD" ]]; then
            stop_spinner "false" "找不到 tsdown 命令"
            echo ""
            echo -e "${YELLOW}提示: 请手动安装 tsdown: npm install -g tsdown${NC}"
            exit 1
        fi
        
        if $TSDOWN_CMD > "$BUILD_LOG" 2>&1 && \
           pnpm exec tsc -p tsconfig.plugin-sdk.dts.json >> "$BUILD_LOG" 2>&1 && \
           node --import tsx scripts/write-plugin-sdk-entry-dts.ts >> "$BUILD_LOG" 2>&1 && \
           node --import tsx scripts/canvas-a2ui-copy.ts >> "$BUILD_LOG" 2>&1 && \
           node --import tsx scripts/copy-hook-metadata.ts >> "$BUILD_LOG" 2>&1 && \
           node --import tsx scripts/write-build-info.ts >> "$BUILD_LOG" 2>&1 && \
           node --import tsx scripts/write-cli-compat.ts >> "$BUILD_LOG" 2>&1; then
            stop_spinner "true" "TypeScript 编译完成"
            rm -f "$BUILD_LOG"
        else
            stop_spinner "false" "TypeScript 编译失败"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ 错误日志 ━━━━━━━━━━━━━${NC}"
            tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}提示: 完整日志保存在: $BUILD_LOG${NC}"
            exit 1
        fi
    else
        if pnpm build > "$BUILD_LOG" 2>&1; then
            stop_spinner "true" "TypeScript 编译完成"
            rm -f "$BUILD_LOG"
        else
            stop_spinner "false" "构建失败"
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━ 错误日志 ━━━━━━━━━━━━━${NC}"
            tail -n 30 "$BUILD_LOG" 2>/dev/null || cat "$BUILD_LOG" 2>/dev/null
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${YELLOW}提示: 完整日志保存在: $BUILD_LOG${NC}"
            exit 1
        fi
    fi
    
    # UI 构建（带旋转动画）
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
            print_substep "配置 PM2 服务..."

            # 1. 停止并删除旧服务
            pm2 stop openclaw-gateway > /dev/null 2>&1 || true
            pm2 delete openclaw-gateway > /dev/null 2>&1 || true
            sleep 1  # 等待删除完成

            # 2. 从配置文件中读取 token（如果存在）
            local GATEWAY_TOKEN=""
            if [[ -f "$PROJECT_ROOT/openclaw.json" ]]; then
                # 尝试从网关配置部分读取 token
                GATEWAY_TOKEN=$(jq -r '.gateway.auth.token // empty' "$PROJECT_ROOT/openclaw.json" 2>/dev/null || \
                    grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_ROOT/openclaw.json" 2>/dev/null | \
                    sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
            fi

            # 3. 启动新服务，传递必要的环境变量
            local PM2_ENV=""
            if [[ -n "$GATEWAY_TOKEN" ]]; then
                PM2_ENV="--env OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN"
            fi

            # 4. 使用 --force 确保 pm2 使用最新配置
            pm2 start "$OPENCLAW_BIN" \
                --name openclaw-gateway \
                --interpreter node \
                $PM2_ENV \
                --force \
                -- gateway start > /dev/null 2>&1

            # 5. 保存 PM2 进程列表（用于开机自启）
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
            
            print_step "验证安装"
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
            git fetch origin > /dev/null 2>&1
            git reset --hard origin/main > /dev/null 2>&1
            print_success "代码已更新"
            
            print_step "构建项目"
            patch_termux_compat
            build_project
            
            # 修复 sqlite-vec (Termux 需要)
            if [[ "$PLATFORM" == "termux" && -f "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" ]]; then
                bash "$PROJECT_ROOT/scripts/fix-sqlite-vec.sh" > /dev/null 2>&1 || true
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
