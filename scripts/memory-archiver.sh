#!/data/data/com.termux/files/usr/bin/bash
# MEMORY.md Archiving and Cleanup Script
# Solves MEMORY.md infinite growth issue, keeping it within 30000 characters

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR/.."
MEMORY_FILE="$WORKSPACE_ROOT/MEMORY.md"
MEMORY_DIR="$WORKSPACE_ROOT/memory"
ARCHIVE_DIR="$MEMORY_DIR/archives"

# Create directories
mkdir -p "$MEMORY_DIR" "$ARCHIVE_DIR"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check file size
check_file_size() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    local size=$(wc -c < "$file" | awk '{print $1}')
    local lines=$(wc -l < "$file" | awk '{print $1}')
    
    echo "File: $(basename "$file")"
    echo "Size: $size bytes"
    echo "Lines: $lines lines"
    
    if [ $size -gt 30000 ]; then
        log_warning "Exceeds 30000 char limit ($size > 30000)"
        return 1
    else
        log_success "Within limit ($size <= 30000)"
        return 0
    fi
}

# Analyze MEMORY.md structure
analyze_memory_structure() {
    log_info "Analyzing MEMORY.md structure..."
    
    echo "=== Section Distribution ==="
    grep -n "^## " "$MEMORY_FILE" | head -20
    
    echo ""
    echo "=== Date Record Stats ==="
    grep -c "^### [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" "$MEMORY_FILE" || echo "No date tags"
    
    echo ""
    echo "=== Last 5 Date Records ==="
    grep "^### [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" "$MEMORY_FILE" | tail -5
    
    echo ""
    echo "=== Content Type Stats ==="
    local patterns=("New Process Learned" "Issue Diagnosis" "Solution" "Tech Research" "Implementation Plan" "Compatibility Improvement")
    for pattern in "${patterns[@]}"; do
        count=$(grep -c "$pattern" "$MEMORY_FILE" || true)
        echo "  $pattern: $count"
    done
}

# Create MEMORY.md summary version
create_summary_version() {
    local summary_file="$MEMORY_DIR/MEMORY_SUMMARY.md"
    local archive_file="$ARCHIVE_DIR/MEMORY_FULL_$(date +%Y%m%d_%H%M%S).md"
    
    log_info "Creating summary version..."
    
    # 1. Backup full version
    cp "$MEMORY_FILE" "$archive_file"
    log_success "Full version archived to: $(basename "$archive_file")"
    
    # 2. Create summary version (Keep only core learnings)
    cat > "$summary_file" << 'EOF'
# Moltbot Memory - Core Summary

> **NOTE**: This is a summary version of MEMORY.md. Full records are in `memory/archives/`.
> Updated: $(date +%Y-%m-%d)

## 🎯 Core Learnings

### Most Important Technical Insights
1. **Termux Compatibility Methodology**
   - Systematically solve Android/Termux environment issues
   - Cover skills, channels, config, nodes, settings, frontend UI
   - Planned compatibility improvements for every error encountered

2. **Memory System Architecture**
   - MEMORY.md keeps only core summary
   - Detailed records archived to date files
   - Supabase vectorized long-term memory

3. **TTS System Optimization**
   - Identify OnePlus device TTS issues
   - Multi-engine TTS solution (Edge TTS/espeak/gTTS/Local Model)
   - Intelligent routing and fallback scheme

### Key Engineering Principles
1. **Errors are opportunities for improvement** - Systematically record and fix
2. **Configuration over hardcoding** - Centralized env var management
3. **Defensive programming** - Validate inputs, handle exceptions
4. **User-friendly error messages** - Provide solutions

### Ongoing Major Projects
1. **WebChat Media Support** - Image display issue resolution
2. **Frontend UI Mobile Adaptation** - Termux environment optimization
3. **Intelligent TTS Router** - Multi-engine auto-switching
4. **Memory System Perfection** - Auto archiving and cleanup

---

## 📋 How to Find Full Records

### Find Detailed Technical Records:
```bash
# 1. View recent date files
ls -la memory/2026-*.md | tail -5

# 2. Search using memory manager
./memory-manager.sh search "your query"

# 3. View archive files
ls -la memory/archives/
```

### Restore Full Version if Needed:
```bash
# Restore latest full version from archive
cp memory/archives/MEMORY_FULL_LatestDate.md MEMORY.md
```

---

## 🔄 Maintenance Guide

### MEMORY.md Should Contain:
- ✅ Core learnings summary
- ✅ Important engineering principles
- ✅ Key architectural decisions
- ✅ Ongoing project status

### Should NOT Contain:
- ❌ Detailed implementation steps
- ❌ Daily work logs
- ❌ Resolved issue details
- ❌ Testing and debugging process

### Archive Rules:
- Auto-archive MEMORY.md every Friday
- Keep MEMORY.md under 20000 characters
- Save detailed records to date files
EOF
    
    # 3. Replace MEMORY.md with summary version
    mv "$summary_file" "$MEMORY_FILE"
    log_success "MEMORY.md replaced with summary version"
    
    # 4. Verify new file size
    check_file_size "$MEMORY_FILE"
}

# Create today's memory file
create_today_memory() {
    local today=$(date +%Y-%m-%d)
    local today_file="$MEMORY_DIR/$today.md"
    
    if [ -f "$today_file" ]; then
        log_info "Today's memory file exists: $(basename "$today_file")"
        return 0
    fi
    
    log_info "Creating today's memory file..."
    
    cat > "$today_file" << EOF
# $today - Daily Memory Record

## 🎯 Today's Focus
- [ ] MEMORY.md archiving and cleanup
- [ ] TTS system optimization
- [ ] WebChat media support progress

## 📝 Detailed Records

### Timeline
- $(date +%H:%M): Work started

## 🔧 Technical Discoveries

## 🚀 Next Steps

## 📊 Summary

---
*Auto-generated at $(date)*
EOF
    
    log_success "Created today's memory file: $(basename "$today_file")"
}

# Setup auto-archive rules
setup_auto_archive() {
    log_info "Setting up auto-archive rules..."
    
    local cron_script="$SCRIPT_DIR/memory-auto-archive.sh"
    
    cat > "$cron_script" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Auto Memory Archive Script - Runs every Friday

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR/.."

cd "$WORKSPACE_ROOT"

# Check MEMORY.md size
size=$(wc -c < "MEMORY.md" | awk '{print $1}')

if [ $size -gt 25000 ]; then
    echo "[$(date)] MEMORY.md size: $size bytes, triggering auto-archive"
    
    # Run archive script
    ./scripts/memory-archiver.sh --archive-only
    
    echo "[$(date)] Archive complete"
else
    echo "[$(date)] MEMORY.md size: $size bytes, no archive needed"
fi
EOF
    
    chmod +x "$cron_script"
    
    log_success "Created auto-archive script: $(basename "$cron_script")"
    
    echo ""
    echo "📅 Suggested cron config:"
    echo "  # Auto-archive every Friday at 18:00"
    echo "  0 18 * * 5 cd /data/data/com.termux/files/home/clawd && ./scripts/memory-auto-archive.sh"
}

# Main function
main() {
    echo "🔧 MEMORY.md Archiving and Cleanup Tool"
    echo "=========================="
    
    # 1. Check current status
    log_info "1. Checking current status..."
    check_file_size "$MEMORY_FILE"
    
    # 2. Analyze structure
    echo ""
    analyze_memory_structure
    
    # 3. Create today's memory file
    echo ""
    create_today_memory
    
    # 4. Create summary version
    echo ""
    if [ "$1" = "--force" ] || [ "$1" = "--archive-only" ] || ! check_file_size "$MEMORY_FILE" 2>/dev/null; then
        if [ "$1" = "--force" ] || [ "$1" = "--archive-only" ] || [ "$AUTO_CONFIRM" = "true" ]; then
            create_summary_version
        else
            read -p "MEMORY.md exceeds limit, create summary version? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                create_summary_version
            else
                log_warning "User cancelled operation"
                exit 0
            fi
        fi
    else
        log_info "MEMORY.md within limit, no immediate archive needed"
        if [ "$AUTO_CONFIRM" != "true" ]; then
            read -p "Create summary version anyway? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                create_summary_version
            fi
        fi
    fi
    
    # 5. Setup auto-archive
    echo ""
    setup_auto_archive
    
    # 6. Final status
    echo ""
    log_info "Final Status:"
    echo "  MEMORY.md: $(wc -c < "$MEMORY_FILE" | awk '{print $1}') bytes"
    echo "  Today's File: memory/$(date +%Y-%m-%d).md"
    echo "  Archive Dir: memory/archives/"
    
    echo ""
    log_success "Done! New Memory Architecture:"
    echo "  1. MEMORY.md - Core Summary (Keep <30000 chars)"
    echo "  2. memory/YYYY-MM-DD.md - Daily Detailed Records"
    echo "  3. memory/archives/ - Full Version Archives"
    echo "  4. Supabase - Vectorized Long-term Memory"
    
    echo ""
    echo "🚀 Immediate Actions:"
    echo "  1. Add today's new notes to: memory/$(date +%Y-%m-%d).md"
    echo "  2. Remove detailed implementation logs from MEMORY.md"
    echo "  3. Keep only core learnings in MEMORY.md"
}

# Execute main
main "$@"
