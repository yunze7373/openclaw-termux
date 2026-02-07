#!/data/data/com.termux/files/usr/bin/bash
# Moltbot 记忆管理系统 (REST API 版)
# 统一管理向量数据库和记忆文件

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$WORKSPACE_ROOT/.memory-config"
EMBEDDING_CONFIG="$HOME/.embedding-config"
ANALYTICS_SCRIPT="${SCRIPT_DIR}/memory-analytics.sh"

# 如果当前目录没有配置文件，尝试从 ~/clawd 加载
if [ ! -f "$CONFIG_FILE" ] && [ -f "$HOME/clawd/.memory-config" ]; then
    CONFIG_FILE="$HOME/clawd/.memory-config"
fi

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✓ $1${NC}" >&2; }
log_error() { echo -e "${RED}✗ $1${NC}" >&2; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}" >&2; }

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_info "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
    
    if [ -f "$EMBEDDING_CONFIG" ]; then
        log_info "加载嵌入配置文件: $EMBEDDING_CONFIG"
        source "$EMBEDDING_CONFIG"
    fi
    
    # Supabase 配置映射
    SUPABASE_URL="${SUPABASE_URL:-}"
    SUPABASE_KEY="${SUPABASE_SERVICE_KEY:-$SUPABASE_ANON_KEY}"
    TABLE_NAME="${MEMORY_TABLE:-memory_vectors}"
    
    if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ]; then
        log_error "未找到 SUPABASE_URL 或 SUPABASE_SERVICE_KEY"
        exit 1
    fi
    
    # 设置嵌入模型
    EMBEDDING_MODEL="${EMBEDDING_MODEL:-local}"
}

# 检查依赖
check_deps() {
    local missing=0
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "缺少依赖: $cmd"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# 生成嵌入向量
generate_embedding() {
    local text="$1"
    local model="$EMBEDDING_MODEL"
    
    # 只支持本地部署的 qwen3-embedding 模型
    if [ "$model" = "local" ]; then
        # 使用本地 MacMini 上的 Ollama (通过 ZeroTier 或局域网)
        # 根据 .embedding-config，地址是 http://192.168.31.45:11434/
        local base_url="${OLLAMA_BASE_URL%/*}" # 去掉末尾的 /v1
        local payload=$(jq -n --arg prompt "$text" '{"model": "qwen3-embedding", "prompt": $prompt}')
        local output=$(curl -s "${base_url}/api/embeddings" -d "$payload")
        echo "$output" | jq -c '.embedding'
    else
        log_error "不支持的嵌入模型: $model"\n        return 1
        log_error "仅支持 local 模型 (使用 qwen3-embedding)"
        return 1
    fi
}

# 存储记忆 (Upsert)
store_memory() {
    local path="$1"
    local content="$2"
    local metadata="$3"
    
    if [ -z "$path" ] || [ -z "$content" ]; then
        log_error "用法: store <path> <content> [metadata]"
        return 1
    fi
    
    # 确保 metadata 是有效的 JSON
    if [ -z "$metadata" ] || [ "$metadata" == "null" ]; then
        metadata="{}"
    fi
    
    local embedding=$(generate_embedding "$content")
    if [ -z "$embedding" ] || [ "$embedding" == "null" ]; then
        log_error "生成嵌入失败"
        return 1
    fi
    
    # 构造 JSON
    # 使用 --arg 并用 fromjson 转换，避免 --argjson 处理大字符串时的潜在问题
    local json=$(jq -n \
        --arg path "$path" \
        --arg content "$content" \
        --arg metadata_str "$metadata" \
        --arg embedding_str "$embedding" \
        '{path: $path, content: $content, metadata: ($metadata_str | fromjson), embedding: ($embedding_str | fromjson)}')
        
    log_info "正在存储到 Supabase..."
    
    # 使用 PostgREST Upsert (ON CONFLICT (path) DO UPDATE)
    # 需要在请求头添加 Prefer: resolution=merge-duplicates 或使用 POST + On Conflict
    # 在 Supabase 中，Upsert 通常通过 POST 并带上特定的 Header 或使用 RPC
    
    local response=$(curl -s -X POST "${SUPABASE_URL}/rest/v1/${TABLE_NAME}" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" \
        -H "Content-Type: application/json" \
        -H "Prefer: resolution=merge-duplicates" \
        -d "$json")
        
    if [[ "$response" == *"error"* ]]; then
        log_error "存储失败: $response"
        return 1
    else
        log_success "记忆已成功存储/更新: $path"
    fi
}

# 搜索记忆
search_memory() {
    local query="$1"
    shift
    local limit=5
    local threshold=0.5
    local text_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --limit) limit="$2"; shift 2 ;;
            --threshold) threshold="$2"; shift 2 ;;
            --text-only) text_only=true; shift ;;
            *) shift ;;
        esac
    done
    
    if [ "$text_only" = true ]; then
        curl -s -G "${SUPABASE_URL}/rest/v1/${TABLE_NAME}" \
            -H "apikey: ${SUPABASE_KEY}" \
            -H "Authorization: Bearer ${SUPABASE_KEY}" \
            --data-urlencode "or=(content.ilike.*${query}*,path.ilike.*${query}*)" \
            --data-urlencode "limit=${limit}" | jq .
    else
        local embedding=$(generate_embedding "$query")
        if [ -z "$embedding" ] || [ "$embedding" == "null" ]; then
            log_error "生成查询向量失败"
            return 1
        fi
        
        # 调用 RPC 函数 match_memory_vectors
        local params=$(jq -n \
            --argjson embedding "$embedding" \
            --argjson threshold "$threshold" \
            --argjson limit "$limit" \
            '{query_embedding: $embedding, match_threshold: $threshold, match_count: $limit}')
            
        curl -s -X POST "${SUPABASE_URL}/rest/v1/rpc/match_memory_vectors" \
            -H "apikey: ${SUPABASE_KEY}" \
            -H "Authorization: Bearer ${SUPABASE_KEY}" \
            -H "Content-Type: application/json" \
            -d "$params" | jq .
    fi
}

# 列出记忆
list_memories() {
    local limit=20
    local offset=0
    local path_filter=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --limit) limit="$2"; shift 2 ;;
            --offset) offset="$2"; shift 2 ;;
            --path) path_filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    local url="${SUPABASE_URL}/rest/v1/${TABLE_NAME}?select=id,path,content,metadata,created_at,updated_at&order=id.desc&limit=${limit}&offset=${offset}"
    
    if [ -n "$path_filter" ]; then
        # 转换 SQL LIKE 为 PostgREST filter
        local filter=$(echo "$path_filter" | sed 's/%/*/g')
        url="${url}&path=like.${filter}"
    fi
    
    curl -s -X GET "$url" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" | jq .
}

# 获取统计
get_stats() {
    log_info "记忆系统统计 (REST)"
    
    # 获取总数 (通过 Header)
    local total=$(curl -s -I -X GET "${SUPABASE_URL}/rest/v1/${TABLE_NAME}?select=id" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" \
        -H "Prefer: count=exact" | grep -i "content-range" | awk -F'/' '{print $2}' | tr -d '\r')
        
    echo "{\"success\": true, \"result\": [{\"count\": ${total:-0}}]}"
}

# 自动诊断/健康检查
task_health() {
    if [ -f "$ANALYTICS_SCRIPT" ]; then
        bash "$ANALYTICS_SCRIPT" health
    else
        log_error "找不到分析脚本: $ANALYTICS_SCRIPT"
        return 1
    fi
}

# 主逻辑
load_config
check_deps

case "$1" in
    store)
        shift
        store_memory "$@"
        ;;
    search)
        shift
        search_memory "$@"
        ;;
    list)
        shift
        list_memories "$@"
        ;;
    stats)
        get_stats
        ;;
    health)
        task_health
        ;;
    config)
        log_info "当前配置:"
        # 脱敏 URL: 仅保留协议和后缀，遮盖项目 ID
        MASKED_URL=$(echo "$SUPABASE_URL" | sed -E 's/https?:\/\/([^\.]+)\.(.+)/https:\/\/********\.\2/')
        echo "URL: $MASKED_URL"
        echo "Table: $TABLE_NAME"
        echo "Model: $EMBEDDING_MODEL"
        echo "向量搜索: 可用 (使用 $EMBEDDING_MODEL 模型)"
        ;;
    help|--help|-h)
        echo "用法: memory-manager.sh <store|search|list|stats|health|config|help>"
        ;;
    *)
        log_error "未知命令: $1"
        exit 1
        ;;
esac
