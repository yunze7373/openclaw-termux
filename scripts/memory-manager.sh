#!/data/data/com.termux/files/usr/bin/bash
# Moltbot Memory Management System (REST API Version)
# Unified management of vector database and memory files

# Path Configuration
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$WORKSPACE_ROOT/.memory-config"
EMBEDDING_CONFIG="$HOME/.embedding-config"
ANALYTICS_SCRIPT="${SCRIPT_DIR}/memory-analytics.sh"

# If config file doesn't exist in current dir, try loading from ~/clawd
if [ ! -f "$CONFIG_FILE" ] && [ -f "$HOME/clawd/.memory-config" ]; then
    CONFIG_FILE="$HOME/clawd/.memory-config"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✓ $1${NC}" >&2; }
log_error() { echo -e "${RED}✗ $1${NC}" >&2; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}" >&2; }

# Load Config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Loading config: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
    
    if [ -f "$EMBEDDING_CONFIG" ]; then
        log_info "Loading embedding config: $EMBEDDING_CONFIG"
        source "$EMBEDDING_CONFIG"
    fi
    
    # Supabase Config Mapping
    SUPABASE_URL="${SUPABASE_URL:-}"
    SUPABASE_KEY="${SUPABASE_SERVICE_KEY:-$SUPABASE_ANON_KEY}"
    TABLE_NAME="${MEMORY_TABLE:-memory_vectors}"
    
    if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ]; then
        log_error "Missing SUPABASE_URL or SUPABASE_SERVICE_KEY"
        exit 1
    fi
    
    # Set Embedding Model
    EMBEDDING_MODEL="${EMBEDDING_MODEL:-local}"
}

# Check Dependencies
check_deps() {
    local missing=0
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Missing dependency: $cmd"
            missing=1
        fi
    done
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# Generate Embedding Vector
generate_embedding() {
    local text="$1"
    local model="$EMBEDDING_MODEL"
    
    # Only supports locally deployed qwen3-embedding model
    if [ "$model" = "local" ]; then
        # Use Ollama on local MacMini (via ZeroTier or LAN)
        # Based on .embedding-config, e.g. http://<IP>:11434/
        local base_url="${OLLAMA_BASE_URL%/*}" # Remove trailing /v1
        local payload=$(jq -n --arg prompt "$text" '{"model": "qwen3-embedding", "prompt": $prompt}')
        local output=$(curl -s "${base_url}/api/embeddings" -d "$payload")
        echo "$output" | jq -c '.embedding'
    else
        log_error "Unsupported embedding model: $model"
        return 1
    fi
}

# Store Memory (Upsert)
store_memory() {
    local path="$1"
    local content="$2"
    local metadata="$3"
    
    if [ -z "$path" ] || [ -z "$content" ]; then
        log_error "Usage: store <path> <content> [metadata]"
        return 1
    fi
    
    # Ensure metadata is valid JSON
    if [ -z "$metadata" ] || [ "$metadata" == "null" ]; then
        metadata="{}"
    fi
    
    local embedding=$(generate_embedding "$content")
    if [ -z "$embedding" ] || [ "$embedding" == "null" ]; then
        log_error "Failed to generate embedding"
        return 1
    fi
    
    # Construct JSON
    # Use --arg and fromjson to avoid potential issues with --argjson on large strings
    local json=$(jq -n \
        --arg path "$path" \
        --arg content "$content" \
        --arg metadata_str "$metadata" \
        --arg embedding_str "$embedding" \
        '{path: $path, content: $content, metadata: ($metadata_str | fromjson), embedding: ($embedding_str | fromjson)}')
        
    log_info "Storing to Supabase..."
    
    # Use PostgREST Upsert (ON CONFLICT (path) DO UPDATE)
    # Requires Prefer: resolution=merge-duplicates or using POST + On Conflict
    
    local response=$(curl -s -X POST "${SUPABASE_URL}/rest/v1/${TABLE_NAME}" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" \
        -H "Content-Type: application/json" \
        -H "Prefer: resolution=merge-duplicates" \
        -d "$json")
        
    if [[ "$response" == *"error"* ]]; then
        log_error "Storage failed: $response"
        return 1
    else
        log_success "Memory successfully stored/updated: $path"
    fi
}

# Search Memory
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
            log_error "Failed to generate query embedding"
            return 1
        fi
        
        # Call RPC function match_memory_vectors
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

# List Memories
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
        # Convert SQL LIKE to PostgREST filter
        local filter=$(echo "$path_filter" | sed 's/%/*/g')
        url="${url}&path=like.${filter}"
    fi
    
    curl -s -X GET "$url" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" | jq .
}

# Get Stats
get_stats() {
    log_info "Memory System Stats (REST)"
    
    # Get total count (via Header)
    local total=$(curl -s -I -X GET "${SUPABASE_URL}/rest/v1/${TABLE_NAME}?select=id" \
        -H "apikey: ${SUPABASE_KEY}" \
        -H "Authorization: Bearer ${SUPABASE_KEY}" \
        -H "Prefer: count=exact" | grep -i "content-range" | awk -F'/' '{print $2}' | tr -d '\r')
        
    echo "{\"success\": true, \"result\": [{\"count\": ${total:-0}}]}"
}

# Auto Diagnostic/Health Check
task_health() {
    if [ -f "$ANALYTICS_SCRIPT" ]; then
        bash "$ANALYTICS_SCRIPT" health
    else
        log_error "Analytics script not found: $ANALYTICS_SCRIPT"
        return 1
    fi
}

# Main Logic
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
        log_info "Current Config:"
        # Masked URL: Keep protocol and suffix, mask project ID
        MASKED_URL=$(echo "$SUPABASE_URL" | sed -E 's/https?:\/\/([^\.]+)\.(.+)/https:\/\/********\.\2/')
        echo "URL: $MASKED_URL"
        echo "Table: $TABLE_NAME"
        echo "Model: $EMBEDDING_MODEL"
        echo "Vector Search: Available (Using $EMBEDDING_MODEL model)"
        ;;
    help|--help|-h)
        echo "Usage: memory-manager.sh <store|search|list|stats|health|config|help>"
        ;;
    *)
        log_error "Unknown command: $1"
        exit 1
        ;;
esac
