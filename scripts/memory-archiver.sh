#!/data/data/com.termux/files/usr/bin/bash
# MEMORY.md归档和清理脚本
# 解决MEMORY.md无限增长问题，保持在30000字符限制内

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR/.."
MEMORY_FILE="$WORKSPACE_ROOT/MEMORY.md"
MEMORY_DIR="$WORKSPACE_ROOT/memory"
ARCHIVE_DIR="$MEMORY_DIR/archives"

# 创建目录
mkdir -p "$MEMORY_DIR" "$ARCHIVE_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[信息]${NC} $1"; }
log_success() { echo -e "${GREEN}[成功]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
log_error() { echo -e "${RED}[错误]${NC} $1"; }

# 检查文件大小
check_file_size() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "文件不存在: $file"
        return 1
    fi
    
    local size=$(wc -c < "$file" | awk '{print $1}')
    local lines=$(wc -l < "$file" | awk '{print $1}')
    
    echo "文件: $(basename "$file")"
    echo "大小: $size 字节"
    echo "行数: $lines 行"
    
    if [ $size -gt 30000 ]; then
        log_warning "超过30000字符限制 ($size > 30000)"
        return 1
    else
        log_success "在限制内 ($size <= 30000)"
        return 0
    fi
}

# 分析MEMORY.md结构
analyze_memory_structure() {
    log_info "分析MEMORY.md结构..."
    
    echo "=== 章节分布 ==="
    grep -n "^## " "$MEMORY_FILE" | head -20
    
    echo ""
    echo "=== 日期记录统计 ==="
    grep -c "^### [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" "$MEMORY_FILE" || echo "无日期标记"
    
    echo ""
    echo "=== 最近5个日期记录 ==="
    grep "^### [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" "$MEMORY_FILE" | tail -5
    
    echo ""
    echo "=== 内容类型统计 ==="
    local patterns=("学到的新流程" "问题诊断" "解决方案" "技术调研" "实施计划" "兼容性改进")
    for pattern in "${patterns[@]}"; do
        count=$(grep -c "$pattern" "$MEMORY_FILE" || true)
        echo "  $pattern: $count"
    done
}

# 创建MEMORY.md摘要版本
create_summary_version() {
    local summary_file="$MEMORY_DIR/MEMORY_SUMMARY.md"
    local archive_file="$ARCHIVE_DIR/MEMORY_FULL_$(date +%Y%m%d_%H%M%S).md"
    
    log_info "创建摘要版本..."
    
    # 1. 备份完整版本
    cp "$MEMORY_FILE" "$archive_file"
    log_success "完整版本归档到: $(basename "$archive_file")"
    
    # 2. 创建摘要版本 (只保留核心学习经验)
    cat > "$summary_file" << 'EOF'
# Moltbot 记忆 - 核心摘要

> **注意**: 这是MEMORY.md的摘要版本，完整记录在 `memory/archives/` 目录中
> 更新日期: $(date +%Y-%m-%d)

## 🎯 核心学习经验

### 最重要的技术洞察
1. **Termux兼容性改进方法论**
   - 系统性地解决Android/Termux环境问题
   - 覆盖skills, channels, 配置, nodes, settings, 前端UI
   - 有计划地对每一个出错的地方进行兼容改进

2. **记忆系统架构**
   - MEMORY.md只保留核心摘要
   - 详细记录归档到日期文件
   - Supabase向量化长期记忆

3. **TTS系统优化**
   - 识别OnePlus设备TTS问题
   - 多引擎TTS解决方案 (Edge TTS/espeak/gTTS/本地模型)
   - 智能路由和降级方案

### 关键工程原则
1. **错误是改进的机会** - 系统化记录和修复
2. **配置优于硬编码** - 环境变量集中管理
3. **防御性编程** - 验证输入，处理异常
4. **用户友好的错误信息** - 提供解决方案

### 正在进行的重大项目
1. **WebChat媒体支持** - 图片显示问题解决
2. **前端UI移动适配** - Termux环境优化
3. **智能TTS路由器** - 多引擎自动切换
4. **记忆系统完善** - 自动归档和清理

---

## 📋 如何查找完整记录

### 查找详细技术记录:
```bash
# 1. 查看最近日期文件
ls -la memory/2026-*.md | tail -5

# 2. 使用记忆管理系统搜索
./memory-manager.sh search "你的查询"

# 3. 查看归档文件
ls -la memory/archives/
```

### 需要时还原完整版本:
```bash
# 从归档恢复最新完整版本
cp memory/archives/MEMORY_FULL_最新日期.md MEMORY.md
```

---

## 🔄 维护指南

### MEMORY.md应该包含:
- ✅ 核心学习经验摘要
- ✅ 重要工程原则
- ✅ 关键架构决策
- ✅ 正在进行的项目状态

### 不应该包含:
- ❌ 详细技术实施步骤
- ❌ 每日工作记录
- ❌ 已解决的问题细节
- ❌ 测试和调试过程

### 归档规则:
- 每周五自动归档MEMORY.md
- 保持MEMORY.md在20000字符以内
- 详细记录保存到日期文件
EOF
    
    # 3. 替换MEMORY.md为摘要版本
    mv "$summary_file" "$MEMORY_FILE"
    log_success "MEMORY.md已替换为摘要版本"
    
    # 4. 验证新文件大小
    check_file_size "$MEMORY_FILE"
}

# 创建今日记忆文件
create_today_memory() {
    local today=$(date +%Y-%m-%d)
    local today_file="$MEMORY_DIR/$today.md"
    
    if [ -f "$today_file" ]; then
        log_info "今日记忆文件已存在: $(basename "$today_file")"
        return 0
    fi
    
    log_info "创建今日记忆文件..."
    
    cat > "$today_file" << EOF
# $today - 每日记忆记录

## 🎯 今日焦点
- [ ] MEMORY.md归档和清理
- [ ] TTS系统优化
- [ ] WebChat媒体支持进展

## 📝 详细记录

### 时间线
- $(date +%H:%M): 开始工作

## 🔧 技术发现

## 🚀 下一步计划

## 📊 总结

---
*自动生成于 $(date)*
EOF
    
    log_success "创建今日记忆文件: $(basename "$today_file")"
}

# 建立自动归档规则
setup_auto_archive() {
    log_info "设置自动归档规则..."
    
    local cron_script="$SCRIPT_DIR/memory-auto-archive.sh"
    
    cat > "$cron_script" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# 自动记忆归档脚本 - 每周五运行

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR/.."

cd "$WORKSPACE_ROOT"

# 检查MEMORY.md大小
size=$(wc -c < "MEMORY.md" | awk '{print $1}')

if [ $size -gt 25000 ]; then
    echo "[$(date)] MEMORY.md大小: $size 字节，触发自动归档"
    
    # 运行归档脚本
    ./scripts/memory-archiver.sh --archive-only
    
    echo "[$(date)] 归档完成"
else
    echo "[$(date)] MEMORY.md大小: $size 字节，无需归档"
fi
EOF
    
    chmod +x "$cron_script"
    
    log_success "创建自动归档脚本: $(basename "$cron_script")"
    
    echo ""
    echo "📅 建议cron配置:"
    echo "  # 每周五18:00自动归档"
    echo "  0 18 * * 5 cd /data/data/com.termux/files/home/clawd && ./scripts/memory-auto-archive.sh"
}

# 主函数
main() {
    echo "🔧 MEMORY.md归档和清理工具"
    echo "=========================="
    
    # 1. 检查当前状态
    log_info "1. 检查当前状态..."
    check_file_size "$MEMORY_FILE"
    
    # 2. 分析结构
    echo ""
    analyze_memory_structure
    
    # 3. 创建今日记忆文件
    echo ""
    create_today_memory
    
    # 4. 创建摘要版本
    echo ""
    if [ "$1" = "--force" ] || [ "$1" = "--archive-only" ] || ! check_file_size "$MEMORY_FILE" 2>/dev/null; then
        if [ "$1" = "--force" ] || [ "$1" = "--archive-only" ] || [ "$AUTO_CONFIRM" = "true" ]; then
            create_summary_version
        else
            read -p "MEMORY.md超过限制，是否创建摘要版本？ (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                create_summary_version
            else
                log_warning "用户取消操作"
                exit 0
            fi
        fi
    else
        log_info "MEMORY.md在限制内，无需立即归档"
        if [ "$AUTO_CONFIRM" != "true" ]; then
            read -p "是否仍要创建摘要版本？ (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                create_summary_version
            fi
        fi
    fi
    
    # 5. 设置自动归档
    echo ""
    setup_auto_archive
    
    # 6. 最终状态
    echo ""
    log_info "最终状态:"
    echo "  MEMORY.md: $(wc -c < "$MEMORY_FILE" | awk '{print $1}') 字节"
    echo "  今日文件: memory/$(date +%Y-%m-%d).md"
    echo "  归档目录: memory/archives/"
    
    echo ""
    log_success "完成！新的记忆架构:"
    echo "  1. MEMORY.md - 核心摘要 (保持<30000字符)"
    echo "  2. memory/YYYY-MM-DD.md - 每日详细记录"
    echo "  3. memory/archives/ - 完整版本归档"
    echo "  4. Supabase - 向量化长期记忆"
    
    echo ""
    echo "🚀 立即操作:"
    echo "  1. 将今天的新记录添加到: memory/$(date +%Y-%m-%d).md"
    echo "  2. 从MEMORY.md中移除详细实施记录"
    echo "  3. 只保留核心学习经验在MEMORY.md中"
}

# 执行主函数
main "$@"