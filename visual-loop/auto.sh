#!/usr/bin/env bash
#
# auto.sh - Fully autonomous visual dev loop
# AI writes code, takes screenshots, verifies, iterates
#
# Usage: ./auto.sh "Add version number v0.1.0 to title screen"
# Options:
#   --expect "text"           Quick grep check before vision (faster validation)
#   --verify-code "pat"       Code-only verification (skip vision) - for animations
#   --context-files "a,b"     Manual file list (comma-separated, overrides auto-detect)
#   --no-stash                Don't create git stash checkpoint
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK="${1:-}"
MAX_ITERS="${MAX_ITERS:-5}"
PROJECT_DIR="${PROJECT_DIR:-/home/geni/Documents/vale-village}"
URL="${URL:-http://localhost:5173}"
DEV_CMD="${DEV_CMD:-pnpm dev}"
EXPECT_TEXT=""
VERIFY_CODE=""
CONTEXT_FILES=""
NO_STASH=false

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expect) EXPECT_TEXT="$2"; shift 2 ;;
        --verify-code) VERIFY_CODE="$2"; shift 2 ;;
        --context-files) CONTEXT_FILES="$2"; shift 2 ;;
        --no-stash) NO_STASH=true; shift ;;
        -*) shift ;;
        *) [[ -z "$TASK" ]] && TASK="$1"; shift ;;
    esac
done

[[ -n "$TASK" ]] || { echo "Usage: ./auto.sh \"task description\" [--context-files \"File.tsx,File.css\"] [--expect \"text\"] [--no-stash]"; exit 1; }

# Validate dependencies
if ! command -v codex &>/dev/null; then
    echo "Error: 'codex' command not found."
    echo "Install with: npm install -g @openai/codex"
    exit 1
fi
if ! command -v jq &>/dev/null; then
    echo "Error: 'jq' command not found."
    echo "Install with: sudo apt install jq"
    exit 1
fi

# Colors
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

LOG_DIR="$SCRIPT_DIR/runs/auto_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

log() { echo -e "$1" | tee -a "$LOG_DIR/session.log"; }

# Metrics
START_TIME=$(date +%s)
EDITS_APPLIED=0
EDITS_FAILED=0

cleanup() {
    [[ -n "${DEV_PID:-}" ]] && kill "$DEV_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Git safety: stash changes before starting
create_checkpoint() {
    if [[ "$NO_STASH" == "true" ]]; then
        log "${DIM}Skipping git checkpoint (--no-stash)${RESET}"
        return 0
    fi
    cd "$PROJECT_DIR"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        STASH_NAME="auto-loop-$(date +%Y%m%d_%H%M%S)"
        git stash push -m "$STASH_NAME" --include-untracked >/dev/null 2>&1 || true
        log "${DIM}Created git checkpoint: $STASH_NAME${RESET}"
        echo "$STASH_NAME" > "$LOG_DIR/stash_name"
    fi
}

# Restore from checkpoint on failure
restore_checkpoint() {
    if [[ "$NO_STASH" == "true" ]]; then return 0; fi
    cd "$PROJECT_DIR"
    if [[ -f "$LOG_DIR/stash_name" ]] && git rev-parse --git-dir >/dev/null 2>&1; then
        local stash_name
        stash_name=$(cat "$LOG_DIR/stash_name")
        log "${YELLOW}Restoring from checkpoint: $stash_name${RESET}"
        git checkout . >/dev/null 2>&1 || true
        git stash pop >/dev/null 2>&1 || true
    fi
}

start_dev() {
    log "${DIM}Starting dev server...${RESET}"
    cd "$PROJECT_DIR"
    $DEV_CMD > "$LOG_DIR/dev.log" 2>&1 &
    DEV_PID=$!

    # Wait for server
    for ((w=0; w<60; w++)); do
        if curl -sf "$URL" >/dev/null 2>&1; then
            log "${GREEN}Dev server ready${RESET}"
            return 0
        fi
        sleep 1
    done
    log "${RED}Dev server failed to start${RESET}"
    return 1
}

stop_dev() {
    [[ -n "${DEV_PID:-}" ]] && kill "$DEV_PID" 2>/dev/null || true
    DEV_PID=""
    sleep 2
}

# Detect relevant files from task description
detect_relevant_files() {
    local task="$1"
    local found_files=""

    cd "$PROJECT_DIR"

    # If manual override, use those
    if [[ -n "$CONTEXT_FILES" ]]; then
        IFS=',' read -ra FILES <<< "$CONTEXT_FILES"
        for f in "${FILES[@]}"; do
            f=$(echo "$f" | xargs)  # trim
            # Search for file
            match=$(find src -name "*$f*" -type f 2>/dev/null | head -1)
            [[ -n "$match" ]] && found_files+="$match "
        done
        echo "$found_files" | tr ' ' '\n' | grep -v '^$' | head -4
        return
    fi

    # Extract likely component names from task
    # "title screen" → titlescreen, TitleScreen
    # "button color" → button, Button

    # Method 1: Convert phrases to PascalCase and search
    # "title screen" → TitleScreen
    local pascal=""
    for word in $task; do
        # Skip common words
        [[ "$word" =~ ^(the|a|an|to|in|on|at|for|with|and|or|of|is|add|change|fix|update|make|set)$ ]] && continue
        # Capitalize first letter
        pascal+="$(echo "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
    done

    # Method 2: Extract existing PascalCase words
    local existing_pascal=$(echo "$task" | grep -oE '[A-Z][a-z]+[A-Z][a-z]*' || echo "")

    # Search for files
    for term in $pascal $existing_pascal; do
        [[ -z "$term" ]] && continue
        [[ ${#term} -lt 3 ]] && continue  # Skip short terms

        # Find matching files
        matches=$(find src -type f \( -name "*${term}*" -o -name "*${term,,}*" \) 2>/dev/null | head -2)
        found_files+="$matches "
    done

    # Method 3: Keyword search in file contents
    local keywords=$(echo "$task" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{4,}' | head -5)
    for kw in $keywords; do
        [[ "$kw" =~ ^(title|screen|button|color|text|style|change|update)$ ]] || continue
        matches=$(grep -rl "$kw" src/ui/components/*.tsx src/ui/components/*.css 2>/dev/null | head -2)
        found_files+="$matches "
    done

    # Dedupe and get paired files
    local final_files=""
    for f in $(echo "$found_files" | tr ' ' '\n' | sort -u); do
        [[ -z "$f" ]] && continue
        final_files+="$f "

        # Auto-include paired CSS/TSX
        if [[ "$f" == *.tsx ]]; then
            css="${f%.tsx}.css"
            [[ -f "$css" ]] && final_files+="$css "
        elif [[ "$f" == *.css ]]; then
            tsx="${f%.css}.tsx"
            [[ -f "$tsx" ]] && final_files+="$tsx "
        fi
    done

    # Return unique, limited to 4
    echo "$final_files" | tr ' ' '\n' | grep -v '^$' | sort -u | head -4
}

# Get file contents with line numbers (for context)
get_file_context() {
    local files="$1"
    local context=""

    for f in $files; do
        [[ -f "$PROJECT_DIR/$f" ]] || [[ -f "$f" ]] || continue
        local full_path
        [[ -f "$PROJECT_DIR/$f" ]] && full_path="$PROJECT_DIR/$f" || full_path="$f"

        local rel_path="${full_path#$PROJECT_DIR/}"
        local line_count=$(wc -l < "$full_path")

        context+="═══ $rel_path ($line_count lines) ═══\n"

        # Truncate long files: first 40 + last 15
        if [[ $line_count -gt 60 ]]; then
            context+="$(head -40 "$full_path" | cat -n)\n"
            context+="... [truncated $((line_count - 55)) lines] ...\n"
            context+="$(tail -15 "$full_path" | cat -n)\n"
        else
            context+="$(cat -n "$full_path")\n"
        fi
        context+="\n"
    done

    echo -e "$context"
}

make_changes() {
    local task="$1"
    local feedback="${2:-}"
    local last_analysis="${3:-}"
    local iter_edits_applied=0
    local iter_edits_failed=0

    # Detect and read relevant files
    log "${DIM}Detecting relevant files...${RESET}"
    RELEVANT_FILES=$(detect_relevant_files "$task")

    if [[ -n "$RELEVANT_FILES" ]]; then
        log "${DIM}Found: $(echo $RELEVANT_FILES | tr '\n' ' ')${RESET}"
        FILE_CONTEXT=$(get_file_context "$RELEVANT_FILES")
    else
        log "${YELLOW}⚠ No relevant files detected${RESET}"
        FILE_CONTEXT="No files auto-detected. Common locations:
- src/ui/components/*.tsx - React components
- src/ui/components/*.css - Component styles"
    fi

    # Build rich prompt
    local prompt="You are a developer modifying a React/TypeScript project.

## TASK
$task

## RELEVANT FILES (read carefully - your edits must match this code EXACTLY)
$FILE_CONTEXT

$([[ -n "$feedback" ]] && echo "## PREVIOUS ATTEMPT FAILED
Feedback: $feedback")

$([[ -n "$last_analysis" ]] && echo "## VISUAL ANALYSIS (what the screenshot showed)
$last_analysis")

## OUTPUT FORMAT
Output ONLY valid JSON objects, one per line (no markdown, no explanation):
{\"file\": \"src/path/to/file.tsx\", \"search\": \"exact multiline string from file\", \"replace\": \"replacement string\"}

CRITICAL RULES:
1. Your 'search' string must match the file content EXACTLY (same whitespace, same indentation)
2. Copy the search string directly from the file context above
3. Include enough context in search to be unique (avoid matching multiple places)
4. For CSS changes, include the full property block"

    log "${DIM}Asking AI for code changes...${RESET}"
    EDITS=$(echo "$prompt" | codex exec 2>/dev/null | grep -E '^\{.*\}$' || echo "")

    log "Proposed edits:"
    log "$EDITS"
    echo "$EDITS" > "$LOG_DIR/iter_${i}_edits.json"

    # Apply edits with validation
    # NOTE: Using mapfile instead of pipe to avoid subshell variable scope loss
    mapfile -t EDIT_LINES <<< "$EDITS"
    for line in "${EDIT_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        [[ "$line" != "{"* ]] && continue

        # Validate JSON structure before parsing
        if ! echo "$line" | jq -e '.file and .search' >/dev/null 2>&1; then
            log "${RED}⚠ Invalid JSON edit: ${line:0:50}...${RESET}"
            ((iter_edits_failed++)) || true
            continue
        fi

        FILE=$(echo "$line" | jq -r '.file')
        SEARCH=$(echo "$line" | jq -r '.search')
        REPLACE=$(echo "$line" | jq -r '.replace // ""')

        if [[ -n "$FILE" && -n "$SEARCH" ]]; then
            FULL_PATH="$PROJECT_DIR/$FILE"
            if [[ ! -f "$FULL_PATH" ]]; then
                log "${RED}⚠ File not found: $FILE${RESET}"
                ((iter_edits_failed++)) || true
                continue
            fi
            if [[ ! -r "$FULL_PATH" ]]; then
                log "${RED}⚠ Cannot read file: $FILE (permission denied)${RESET}"
                ((iter_edits_failed++)) || true
                continue
            fi

            # Count matches before edit (use grep -c, handle multiline later)
            MATCH_COUNT=$(grep -cF "$SEARCH" "$FULL_PATH" 2>/dev/null || echo "0")

            if [[ "$MATCH_COUNT" == "0" ]]; then
                log "${RED}⚠ No match found in $FILE${RESET}"
                ((iter_edits_failed++)) || true
                continue
            elif [[ "$MATCH_COUNT" -gt "1" ]]; then
                log "${YELLOW}⚠ Multiple matches ($MATCH_COUNT) in $FILE - applying to first${RESET}"
            fi

            log "${DIM}Editing $FILE...${RESET}"
            # Use perl for multiline replace - escape REPLACE to prevent regex injection
            # Write search/replace to temp files to avoid shell escaping issues
            local tmp_search=$(mktemp)
            local tmp_replace=$(mktemp)
            printf '%s' "$SEARCH" > "$tmp_search"
            printf '%s' "$REPLACE" > "$tmp_replace"

            if perl -i -p0e '
                BEGIN {
                    local $/;
                    open(S, "<", $ARGV[0]) or die; $search = <S>; close S;
                    open(R, "<", $ARGV[1]) or die; $replace = <R>; close R;
                    shift @ARGV; shift @ARGV;
                }
                s/\Q$search\E/$replace/s;
            ' "$tmp_search" "$tmp_replace" "$FULL_PATH" 2>/dev/null; then
                ((iter_edits_applied++)) || true
            else
                log "${RED}⚠ Perl substitution failed in $FILE${RESET}"
                ((iter_edits_failed++)) || true
            fi
            rm -f "$tmp_search" "$tmp_replace"
        fi
    done

    # Git diff check - verify changes were made
    cd "$PROJECT_DIR"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        DIFF_STAT=$(git diff --stat 2>/dev/null || echo "")
        if [[ -n "$DIFF_STAT" ]]; then
            log "${GREEN}✓ Changes detected:${RESET}"
            log "$DIFF_STAT"
        else
            log "${YELLOW}⚠ No git diff detected - edits may have failed${RESET}"
        fi
    fi

    # Update global metrics
    EDITS_APPLIED=$((EDITS_APPLIED + iter_edits_applied))
    EDITS_FAILED=$((EDITS_FAILED + iter_edits_failed))
}

take_screenshot() {
    local output="$1"
    "$SCRIPT_DIR/snap.sh" "$URL" "$output"
}

analyze_screenshot() {
    local shot="$1"
    local task="$2"

    # Use analyze.sh which uses codex with vision
    "$SCRIPT_DIR/analyze.sh" "$shot" "$task"
}

# Quick text check (before expensive vision)
quick_text_check() {
    if [[ -z "$EXPECT_TEXT" ]]; then
        return 1  # No expectation set, skip to vision
    fi
    cd "$PROJECT_DIR"
    if grep -rq "$EXPECT_TEXT" src/ 2>/dev/null; then
        log "${GREEN}✓ Quick check: Found '$EXPECT_TEXT' in source${RESET}"
        return 0
    fi
    log "${DIM}Quick check: '$EXPECT_TEXT' not found yet${RESET}"
    return 1
}

# Code-only verification (for animations, etc. that can't be visually verified)
verify_code_pattern() {
    if [[ -z "$VERIFY_CODE" ]]; then
        return 1  # Not in code-verify mode
    fi
    cd "$PROJECT_DIR"

    # Split pattern by commas for multiple required patterns
    IFS=',' read -ra PATTERNS <<< "$VERIFY_CODE"
    local all_found=true

    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # trim whitespace
        if grep -rqE "$pattern" src/ 2>/dev/null; then
            log "${GREEN}✓ Code check: Found pattern '$pattern'${RESET}"
        else
            log "${RED}✗ Code check: Missing pattern '$pattern'${RESET}"
            all_found=false
        fi
    done

    if [[ "$all_found" == "true" ]]; then
        return 0
    fi
    return 1
}

# Print final metrics
print_metrics() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    log ""
    log "${BOLD}Metrics:${RESET}"
    log "  Duration: ${duration}s"
    log "  Edits applied: $EDITS_APPLIED"
    log "  Edits failed: $EDITS_FAILED"
}

# Main loop
log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
if [[ -n "$VERIFY_CODE" ]]; then
    log "${CYAN}${BOLD}  AUTONOMOUS CODE DEV LOOP${RESET}"
else
    log "${CYAN}${BOLD}  AUTONOMOUS VISUAL DEV LOOP${RESET}"
fi
log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log ""
log "${BOLD}Task:${RESET} $TASK"
log "${BOLD}Project:${RESET} $PROJECT_DIR"
log "${BOLD}Max iterations:${RESET} $MAX_ITERS"
[[ -n "$EXPECT_TEXT" ]] && log "${BOLD}Quick check:${RESET} '$EXPECT_TEXT'"
[[ -n "$VERIFY_CODE" ]] && log "${BOLD}Code verify:${RESET} '$VERIFY_CODE' ${DIM}(skipping vision)${RESET}"
log ""

# Create checkpoint before making any changes
create_checkpoint

FEEDBACK=""
LAST_ANALYSIS=""

for ((i=1; i<=MAX_ITERS; i++)); do
    log "${YELLOW}► Iteration $i / $MAX_ITERS${RESET}"
    log ""

    # Step 1: Make code changes (with context from previous iteration)
    make_changes "$TASK" "$FEEDBACK" "$LAST_ANALYSIS"

    # Step 2: Code-only verification mode (skip dev server + vision)
    if [[ -n "$VERIFY_CODE" ]]; then
        if verify_code_pattern; then
            log ""
            log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log "${GREEN}${BOLD}  ✓ TASK COMPLETE (iteration $i) - code verified${RESET}"
            log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log ""
            log "Session log: $LOG_DIR"
            print_metrics
            exit 0
        fi
        FEEDBACK="Code patterns not found. Required: $VERIFY_CODE"
        log ""
        log "${RED}Issues:${RESET} Required code patterns not found"
        log "${YELLOW}Feedback for next iteration:${RESET} $FEEDBACK"
        log ""
        continue
    fi

    # Step 3: Restart dev server (to pick up changes)
    stop_dev
    start_dev || { log "${RED}Failed to start dev server${RESET}"; restore_checkpoint; exit 1; }

    # Step 4: Quick text check (skip vision if obvious)
    if quick_text_check; then
        log "${DIM}Quick check passed - proceeding to visual verification${RESET}"
    fi

    # Step 5: Take screenshot
    SHOT="$LOG_DIR/iter_${i}.png"
    log "${DIM}Taking screenshot...${RESET}"
    take_screenshot "$SHOT"
    log "Screenshot: $SHOT"

    # Step 6: Analyze
    log "${DIM}Analyzing...${RESET}"
    ANALYSIS=$(analyze_screenshot "$SHOT" "$TASK")
    log "Analysis: $ANALYSIS"
    echo "$ANALYSIS" > "$LOG_DIR/iter_${i}_analysis.json"

    # Save for next iteration context
    LAST_ANALYSIS="$ANALYSIS"

    # Parse result
    PASS=$(echo "$ANALYSIS" | jq -r '.pass // false' 2>/dev/null || echo "false")
    ISSUES=$(echo "$ANALYSIS" | jq -r '.issues // "parse error"' 2>/dev/null || echo "parse error")
    FEEDBACK=$(echo "$ANALYSIS" | jq -r '.next_action // .feedback // ""' 2>/dev/null || echo "")

    if [[ "$PASS" == "true" ]]; then
        log ""
        log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        log "${GREEN}${BOLD}  ✓ TASK COMPLETE (iteration $i)${RESET}"
        log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        log ""
        log "Final screenshot: $SHOT"
        log "Session log: $LOG_DIR"
        print_metrics
        exit 0
    fi

    log ""
    log "${RED}Issues:${RESET} $ISSUES"
    log "${YELLOW}Feedback for next iteration:${RESET} $FEEDBACK"
    log ""
done

log ""
log "${RED}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log "${RED}${BOLD}  ✗ Max iterations reached - task incomplete${RESET}"
log "${RED}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log ""
print_metrics
log "Session log: $LOG_DIR"
log ""
log "${YELLOW}Run 'git checkout .' to restore original files, or check $LOG_DIR for details${RESET}"
exit 1
