#!/data/data/com.termux/files/usr/bin/sh
# 记忆分析面板脚本
# 提供记忆系统统计、分析和可视化功能

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORY_MANAGER="${SCRIPT_DIR}/memory-manager.sh"
LOG_FILE="${WORKSPACE_ROOT}/.cache/memory-analytics.log"

mkdir -p "${WORKSPACE_ROOT}/.cache"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    if [ ! -f "$MEMORY_MANAGER" ]; then
        log "❌ 记忆管理器脚本不存在: $MEMORY_MANAGER"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log "❌ jq 命令不存在"
        return 1
    fi
    
    chmod +x "$MEMORY_MANAGER" 2>/dev/null || true
    
    return 0
}

# 任务1: 总体概况
task_summary() {
    log "生成记忆系统总体概况..."
    
    echo "🧠 记忆系统总体概况"
    echo "======================"
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 基础统计
    echo "📊 基础统计"
    echo "----------"
    "$MEMORY_MANAGER" stats 2>/dev/null | head -20
    
    echo ""
    
    # 最近活动
    echo "🕒 最近活动"
    echo "----------"
    "$MEMORY_MANAGER" list --limit 5 2>/dev/null | jq -r '.[] | "\(if .created_at then .created_at[0:19] else "未知时间" end) - \(.path): \(.content[0:60])..."' 2>/dev/null || echo "无法获取最近活动"
    
    echo ""
    
    # 热门路径
    echo "📁 热门路径"
    echo "----------"
    "$MEMORY_MANAGER" list --limit 10 2>/dev/null | jq -r '.[] | .path' 2>/dev/null | sort | uniq -c | sort -nr | head -5 || echo "无法获取路径统计"
    
    echo ""
    
    # 配置状态
    echo "⚙️ 配置状态"
    echo "----------"
    "$MEMORY_MANAGER" config 2>/dev/null | grep -E "嵌入模型|向量搜索|API密钥" || echo "无法获取配置"
}

# 任务2: 时间线分析
task_timeline() {
    log "生成记忆时间线分析..."
    
    echo "📅 记忆时间线分析"
    echo "======================"
    echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 获取最近30天的记忆
    local recent_memories
    recent_memories=$("$MEMORY_MANAGER" list --limit 50 2>/dev/null || echo "[]")
    
    # 按日期分组
    echo "每日记忆数量统计 (最近30天)"
    echo "------------------------"
    echo "$recent_memories" | jq -r '.[] | .created_at[0:10]' 2>/dev/null | sort | uniq -c | sort -k2 || echo "无法生成时间线"
    
    echo ""
    
    # 时间段分析
    echo "时间段分布"
    echo "----------"
    echo "$recent_memories" | jq -r '.[] | .created_at[11:13] + ":00"' 2>/dev/null | sort | uniq -c | sort -k2 || echo "无法生成时间段分布"
    
    echo ""
    
    # 周活跃趋势
    echo "周活跃趋势"
    echo "----------"
    echo "$recent_memories" | jq -r '.[] | .created_at[0:10]' 2>/dev/null | xargs -I {} date -d {} +%u 2>/dev/null | sort | uniq -c | \
        awk '{days["1"]="周一"; days["2"]="周二"; days["3"]="周三"; days["4"]="周四"; days["5"]="周五"; days["6"]="周六"; days["7"]="周日"; print $1 " - " days[$2]}' || \
        echo "无法生成周趋势"
}

# 任务3: 主题聚类
task_topics() {
    log "生成主题聚类分析..."
    
    echo "🏷️ 主题聚类分析"
    echo "======================"
    echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 获取记忆内容样本
    local sample_memories
    sample_memories=$("$MEMORY_MANAGER" list --limit 20 2>/dev/null || echo "[]")
    
    # 提取关键词（简单版本）
    echo "高频词汇 (前20)"
    echo "---------------"
    echo "$sample_memories" | jq -r '.[] | .content' 2>/dev/null | \
        tr ' ' '\n' | grep -E '^[a-zA-Z]{3,}|^[\u4e00-\u9fa5]{2,}' | \
        sort | uniq -c | sort -nr | head -20 || echo "无法提取高频词汇"
    
    echo ""
    
    # 路径分类
    echo "路径分类统计"
    echo "------------"
    echo "$sample_memories" | jq -r '.[] | .path' 2>/dev/null | \
        awk -F'/' '{print $1}' | sort | uniq -c | sort -nr || echo "无法分类路径"
    
    echo ""
    
    # 元数据分析（如果存在）
    echo "元数据标签统计"
    echo "--------------"
    echo "$sample_memories" | jq -r '.[] | .metadata.tags[]?' 2>/dev/null | \
        sort | uniq -c | sort -nr | head -10 || echo "无标签数据或无法解析"
}

# 任务4: 健康检查
task_health() {
    log "执行记忆系统健康检查..."
    
    echo "🏥 记忆系统健康检查"
    echo "======================"
    echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    local errors=0
    local warnings=0
    
    # 1. 检查记忆管理器可执行性
    echo "1. 记忆管理器状态"
    if [ -x "$MEMORY_MANAGER" ]; then
        echo "   ✅ 脚本可执行"
    else
        echo "   ❌ 脚本不可执行"
        errors=$((errors + 1))
    fi
    
    # 2. 检查配置加载
    echo "2. 配置加载测试"
    if "$MEMORY_MANAGER" config >/dev/null 2>&1; then
        echo "   ✅ 配置加载正常"
    else
        echo "   ❌ 配置加载失败"
        errors=$((errors + 1))
    fi
    
    # 3. 检查数据库连接
    echo "3. 数据库连接测试"
    local db_test
    if db_test=$("$MEMORY_MANAGER" list --limit 1 2>&1); then
        echo "   ✅ 数据库连接正常"
    else
        echo "   ❌ 数据库连接失败"
        echo "   错误信息: $db_test"
        errors=$((errors + 1))
    fi
    
    # 4. 检查向量搜索功能
    echo "4. 向量搜索功能测试"
    local config_output
    config_output=$("$MEMORY_MANAGER" config 2>/dev/null | grep "向量搜索" || true)
    if echo "$config_output" | grep -q "可用"; then
        echo "   ✅ 向量搜索可用"
    else
        echo "   ⚠️  向量搜索不可用 (使用文本模式)"
        warnings=$((warnings + 1))
    fi
    
    # 5. 检查记忆数量
    echo "5. 记忆存储状态"
    local stats_result
    local total_memories=0
    
    # 尝试获取统计信息
    if stats_result=$("$MEMORY_MANAGER" stats 2>&1); then
        # 命令执行成功，尝试解析记忆数量
        # 先尝试从JSON中提取（新格式）
        if total_memories=$(echo "$stats_result" | grep -A2 '"count"' | head -3 | grep '"count"' | grep -o '[0-9]*' 2>/dev/null | head -1); then
            echo "   ✅ 记忆存储正常 (总记忆数: ${total_memories})"
        else
            # 尝试从文本输出中提取（旧格式）
            if total_memories=$(echo "$stats_result" | grep "总记忆数" | grep -o '[0-9]*' 2>/dev/null); then
                echo "   ✅ 记忆存储正常 (总记忆数: ${total_memories})"
            else
                echo "   ✅ 记忆存储正常 (无法解析数量)"
            fi
        fi
    else
        echo "   ⚠️  无法获取记忆统计"
        warnings=$((warnings + 1))
    fi
    
    echo ""
    echo "检查完成:"
    echo "  ✅ 错误数量: $errors"
    echo "  ⚠️  警告数量: $warnings"
    
    if [ $errors -eq 0 ]; then
        echo "🏥 健康状态: ✅ 健康"
    elif [ $errors -le 2 ]; then
        echo "🏥 健康状态: ⚠️  需要注意"
    else
        echo "🏥 健康状态: ❌ 需要修复"
    fi
}

# 任务5: HTML报告生成
task_html_report() {
    log "生成HTML记忆分析报告..."
    
    local report_dir="${WORKSPACE_ROOT}/memory/reports"
    local date_str=$(date '+%Y-%m-%d')
    local time_str=$(date '+%H%M%S')
    local report_file="${report_dir}/memory-report-${date_str}-${time_str}.html"
    
    mkdir -p "$report_dir"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>记忆系统分析报告</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        header { text-align: center; margin-bottom: 40px; border-bottom: 2px solid #4CAF50; padding-bottom: 20px; }
        h1 { color: #333; margin: 0; }
        .subtitle { color: #666; font-size: 18px; margin-top: 10px; }
        .section { margin-bottom: 40px; }
        .section h2 { color: #4CAF50; border-left: 4px solid #4CAF50; padding-left: 15px; margin-top: 30px; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-top: 20px; }
        .stat-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #2196F3; }
        .stat-card h3 { margin-top: 0; color: #333; }
        .stat-value { font-size: 32px; font-weight: bold; color: #2196F3; }
        .health-status { padding: 20px; border-radius: 8px; margin: 20px 0; }
        .healthy { background: #d4edda; border-left: 4px solid #28a745; }
        .warning { background: #fff3cd; border-left: 4px solid #ffc107; }
        .error { background: #f8d7da; border-left: 4px solid #dc3545; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; font-weight: bold; }
        tr:hover { background-color: #f5f5f5; }
        .timestamp { color: #666; font-size: 14px; text-align: right; margin-top: 30px; }
        .chip { display: inline-block; background: #e0e0e0; padding: 4px 12px; border-radius: 16px; margin: 2px; font-size: 14px; }
        .tag-cloud { line-height: 2; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🧠 记忆系统分析报告</h1>
            <div class="subtitle">Moltbot 记忆管理系统状态监控</div>
        </header>
EOF
    
    # 生成时间戳
    cat >> "$report_file" << EOF
        <div class="timestamp">
            报告生成时间: $(date '+%Y-%m-%d %H:%M:%S')
        </div>
        
        <div class="section">
            <h2>📊 系统概览</h2>
            <div class="stats-grid">
EOF
    
    # 获取基础统计（简化版本）
    local total_memories=0
    local recent_activity=""
    local health_status="healthy"
    
    # 尝试获取统计数据
    local stats_output
    if stats_output=$("$MEMORY_MANAGER" stats 2>&1); then
        # 命令执行成功，尝试解析记忆数量
        # 先尝试从JSON中提取count字段（新格式）
        if total_memories=$(echo "$stats_output" | grep -A2 '"count"' | head -3 | grep '"count"' | grep -o '[0-9]*' 2>/dev/null | head -1); then
            : # 成功提取
        else
            # 尝试从文本输出中提取（旧格式）
            total_memories=$(echo "$stats_output" | grep "总记忆数" | grep -o '[0-9]*' 2>/dev/null || echo "0")
        fi
        
        recent_activity=$("$MEMORY_MANAGER" list --limit 3 2>/dev/null | jq -r '.[] | .created_at[0:10]' | sort -r | head -1 || echo "未知")
        health_status="healthy"
    else
        health_status="error"
    fi
    
    cat >> "$report_file" << EOF
                <div class="stat-card">
                    <h3>总记忆数量</h3>
                    <div class="stat-value">${total_memories}</div>
                    <p>条记忆存储在系统中</p>
                </div>
                
                <div class="stat-card">
                    <h3>最近活动</h3>
                    <div class="stat-value">${recent_activity}</div>
                    <p>最后记忆添加日期</p>
                </div>
                
                <div class="stat-card">
                    <h3>运行状态</h3>
                    <div class="stat-value">$(if [ "$health_status" = "healthy" ]; then echo "✅"; else echo "❌"; fi)</div>
                    <p>系统健康状态</p>
                </div>
                
                <div class="stat-card">
                    <h3>报告周期</h3>
                    <div class="stat-value">每日</div>
                    <p>自动生成频率</p>
                </div>
            </div>
        </div>
EOF
    
    # 健康状态部分
    cat >> "$report_file" << EOF
        <div class="section">
            <h2>🏥 健康状态</h2>
            <div class="health-status $(if [ "$health_status" = "healthy" ]; then echo "healthy"; elif [ "$health_status" = "warning" ]; then echo "warning"; else echo "error"; fi)">
                <h3>当前状态: $(if [ "$health_status" = "healthy" ]; then echo "✅ 健康"; elif [ "$health_status" = "warning" ]; then echo "⚠️ 需要注意"; else echo "❌ 需要修复"; fi)</h3>
                <p>系统整体运行状态评估</p>
            </div>
        </div>
EOF
    
    # 最近记忆部分
    cat >> "$report_file" << EOF
        <div class="section">
            <h2>📝 最近记忆</h2>
            <table>
                <thead>
                    <tr>
                        <th>时间</th>
                        <th>路径</th>
                        <th>内容预览</th>
                    </tr>
                </thead>
                <tbody>
EOF
    
    # 获取最近5条记忆
    local recent_memories
    recent_memories=$("$MEMORY_MANAGER" list --limit 5 2>/dev/null || echo "[]")
    
    echo "$recent_memories" | jq -r '.[] | "<tr><td>\(if .created_at then .created_at[0:19] else "未知" end)</td><td>\(.path)</td><td>\(.content[0:50])...</td></tr>"' 2>/dev/null >> "$report_file" || \
        echo "<tr><td colspan='3'>无法加载最近记忆</td></tr>" >> "$report_file"
    
    cat >> "$report_file" << EOF
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>📈 使用建议</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <h3>存储优化</h3>
                    <p>建议使用有意义的路径结构，如: category/topic/item.md</p>
                </div>
                
                <div class="stat-card">
                    <h3>搜索技巧</h3>
                    <p>使用语义搜索获取相关记忆，即使关键词不完全匹配</p>
                </div>
                
                <div class="stat-card">
                    <h3>定期维护</h3>
                    <p>建议每周清理重复和过时记忆</p>
                </div>
                
                <div class="stat-card">
                    <h3>备份策略</h3>
                    <p>重要记忆建议额外备份到本地文件</p>
                </div>
            </div>
        </div>
EOF
    
    cat >> "$report_file" << EOF
        <div class="section">
            <h2>🔧 技术信息</h2>
            <p><strong>系统版本:</strong> 记忆管理系统 v1.0.0</p>
            <p><strong>后端存储:</strong> Supabase + pgvector</p>
            <p><strong>支持模型:</strong> OpenAI, Gemini, DeepSeek, Ollama</p>
            <p><strong>生成工具:</strong> Moltbot 记忆分析面板</p>
        </div>
        
        <div class="timestamp">
            报告结束 - 下次更新: $(date -d '+1 day' '+%Y-%m-%d %H:%M:%S')
        </div>
    </div>
</body>
</html>
EOF
    
    log "✅ HTML报告生成完成: $report_file"
    echo "📄 HTML报告已保存到: $report_file"
    echo "📊 可以在浏览器中打开查看可视化报告"
}

# 任务6: 自动维护
task_maintenance() {
    log "执行自动维护任务..."
    
    echo "🔧 记忆系统自动维护"
    echo "======================"
    echo "维护时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 1. 检查重复记忆（简单版本）
    echo "1. 检查重复记忆"
    local duplicate_check
    duplicate_check=$("$MEMORY_MANAGER" list --limit 100 2>/dev/null | jq -r 'group_by(.path) | map(select(length > 1)) | .[] | sort_by(.created_at) | .[:-1] | .[].id' 2>/dev/null || true)
    
    if [ -n "$duplicate_check" ]; then
        echo "   ⚠️  发现可能的重复记忆"
        echo "$duplicate_check" | head -5 | while read id; do
            echo "     ID: $id"
        done
    else
        echo "   ✅ 未发现明显重复"
    fi
    
    echo ""
    
    # 2. 清理测试记忆
    echo "2. 清理测试记忆"
    local test_memories
    test_memories=$("$MEMORY_MANAGER" list --path "%test%" 2>/dev/null | jq -r '.[] | .id' 2>/dev/null || true)
    
    if [ -n "$test_memories" ]; then
        echo "   🗑️  删除测试记忆"
        echo "$test_memories" | while read id; do
            echo "     删除 ID: $id"
            "$MEMORY_MANAGER" delete "$id" >/dev/null 2>&1 || true
        done
    else
        echo "   ✅ 无测试记忆"
    fi
    
    echo ""
    
    # 3. 生成统计快照
    echo "3. 生成统计快照"
    local snapshot_file="/data/data/com.termux/files/home/.cache/memory-snapshot-$(date +%Y%m%d).json"
    "$MEMORY_MANAGER" list --limit 100 2>/dev/null > "$snapshot_file" 2>/dev/null || true
    
    if [ -s "$snapshot_file" ]; then
        echo "   ✅ 快照保存到: $snapshot_file"
        local snapshot_count=$(jq length "$snapshot_file" 2>/dev/null || echo "0")
        echo "     记录数量: $snapshot_count"
    else
        echo "   ⚠️  快照生成失败"
    fi
    
    echo ""
    echo "维护任务完成"
}

# 主函数
main() {
    local task="${1:-summary}"
    
    log "开始执行记忆分析任务: $task"
    
    # 检查前提条件
    if ! check_prerequisites; then
        log "❌ 前提条件检查失败"
        return 1
    fi
    
    case "$task" in
        summary|overview)
            task_summary
            ;;
        timeline|time)
            task_timeline
            ;;
        topics|tags)
            task_topics
            ;;
        health|check)
            task_health
            ;;
        html|html-report)
            task_html_report
            ;;
        maintenance|auto-maintain)
            task_maintenance
            ;;
        all)
            task_summary
            echo ""
            echo "======================"
            echo ""
            task_health
            echo ""
            echo "======================"
            echo ""
            task_maintenance
            ;;
        *)
            log "未知任务: $task"
            echo "可用任务:"
            echo "  summary       总体概况"
            echo "  timeline      时间线分析"
            echo "  topics        主题聚类"
            echo "  health        健康检查"
            echo "  html          HTML报告"
            echo "  maintenance   自动维护"
            echo "  all           执行所有任务"
            return 1
            ;;
    esac
    
    local result=$?
    if [ $result -eq 0 ]; then
        log "✅ 任务执行成功: $task"
    else
        log "❌ 任务执行失败: $task (退出码: $result)"
    fi
    
    return $result
}

# 执行主函数
main "$@"