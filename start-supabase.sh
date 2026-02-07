#!/data/data/com.termux/files/usr/bin/bash

# 加载配置
CONFIG_DIR="$HOME/clawd"
ROOT_CONFIG="$HOME/.embedding-config"
PROJECT_CONFIG="$CONFIG_DIR/.embedding-config"

# 优先读取项目配置，如果不存在则读取根配置
if [ -f "$PROJECT_CONFIG" ]; then
    echo "Loading project config: $PROJECT_CONFIG"
    source "$PROJECT_CONFIG"
elif [ -f "$ROOT_CONFIG" ]; then
    echo "Loading root config: $ROOT_CONFIG"
    source "$ROOT_CONFIG"
fi

# 确保关键变量已设置
if [ -z "$OLLAMA_BASE_URL" ]; then
    echo "ERROR: OLLAMA_BASE_URL not found in config."
    exit 1
fi

# 设置 Supabase 拦截所需的环境变量
export USE_SUPABASE_MEMORY="true"
export MEMORY_TABLE="memory_vectors"

# 如果配置里没有 Supabase Key，尝试从 .env 文件或用户输入中获取
# 这里假设用户已经设置了 SUPABASE_URL 和 SUPABASE_KEY (或者 SERVICE_KEY)
# 为了方便，我们尝试从 clawd/moltbot-supabase-memory-config.env 加载作为默认值
SUPABASE_ENV="$CONFIG_DIR/moltbot-supabase-memory-config.env"
if [ -f "$SUPABASE_ENV" ]; then
    echo "Loading Supabase config: $SUPABASE_ENV"
    # 导出文件中的变量
    set -a
    source "$SUPABASE_ENV"
    set +a
    
    # 映射变量名以匹配 Moltbot
    # 优先使用 Service Key (如果用户手动在环境里设置了)，否则使用 Anon Key
    if [ -z "$SUPABASE_SERVICE_KEY" ] && [ -z "$SUPABASE_KEY" ]; then
         export SUPABASE_KEY="$SUPABASE_ANON_KEY"
    fi
fi

# 验证 Supabase 配置
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ]; then
    echo "ERROR: Missing Supabase credentials. Please set SUPABASE_URL and SUPABASE_KEY."
    exit 1
fi

echo "🚀 Starting Moltbot with Supabase Memory Interceptor..."
echo "   Embedding Model: $OLLAMA_EMBEDDING_MODEL ($EMBEDDING_DIMENSIONS dims)"
echo "   Supabase URL: $SUPABASE_URL"
echo "   Table: $MEMORY_TABLE"

# 启动
pnpm start
