#!/usr/bin/env bash
#
# orchestrate.sh - AI-to-AI task orchestration
# Reads task_list.json, executes each via auto.sh, tracks progress
#
# Usage: ./orchestrate.sh [--dry-run] [--start-from N] [--stream NAME]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_FILE="${TASK_FILE:-$SCRIPT_DIR/task_list.json}"
PROGRESS_FILE="$SCRIPT_DIR/.orchestrate_progress"
PROJECT_DIR="${PROJECT_DIR:-/home/geni/Documents/vale-village}"

# Options
DRY_RUN=false
START_FROM=0
STREAM=""
HUMAN_REVIEW=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --start-from) START_FROM="$2"; shift 2 ;;
        --stream) STREAM="$2"; shift 2 ;;
        --review) HUMAN_REVIEW=true; shift ;;
        -h|--help)
            echo "Usage: ./orchestrate.sh [--dry-run] [--start-from N] [--stream NAME] [--review]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Show tasks without executing"
            echo "  --start-from N Skip first N tasks"
            echo "  --stream NAME  Only run tasks in this stream (visual, content, core)"
            echo "  --review       Pause for human review after each task"
            exit 0
            ;;
        *) shift ;;
    esac
done

# Colors
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

LOG_DIR="$SCRIPT_DIR/runs/orchestrate_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

log() { echo -e "$1" | tee -a "$LOG_DIR/orchestrate.log"; }

# Load or initialize progress
load_progress() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        COMPLETED=$(cat "$PROGRESS_FILE" | jq -r '.completed // []' 2>/dev/null || echo "[]")
        FAILED=$(cat "$PROGRESS_FILE" | jq -r '.failed // []' 2>/dev/null || echo "[]")
    else
        COMPLETED="[]"
        FAILED="[]"
    fi
}

save_progress() {
    local task_id="$1"
    local status="$2"

    # Use jq --arg to safely escape task_id (prevents JSON injection)
    if [[ "$status" == "completed" ]]; then
        COMPLETED=$(echo "$COMPLETED" | jq --arg tid "$task_id" '. + [$tid]') || {
            log "${RED}Failed to update progress for $task_id${RESET}"
            return 1
        }
    else
        FAILED=$(echo "$FAILED" | jq --arg tid "$task_id" '. + [$tid]') || {
            log "${RED}Failed to update progress for $task_id${RESET}"
            return 1
        }
    fi

    # Atomic write: write to temp file then move
    echo "{\"completed\": $COMPLETED, \"failed\": $FAILED}" > "$PROGRESS_FILE.tmp"
    mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
}

is_completed() {
    local task_id="$1"
    # Use jq --arg for safe comparison
    echo "$COMPLETED" | jq -e --arg tid "$task_id" 'index($tid)' >/dev/null 2>&1
}

# Check if task_list.json exists
if [[ ! -f "$TASK_FILE" ]]; then
    log "${RED}Error: $TASK_FILE not found${RESET}"
    log ""
    log "Generate it first with:"
    log "  ./generate_tasks.sh"
    log ""
    log "Or create manually with format:"
    log '  [{"id": "task-1", "task": "description", "stream": "visual", "context_files": "File.tsx"}]'
    exit 1
fi

# Load tasks
TASKS=$(cat "$TASK_FILE")
TASK_COUNT=$(echo "$TASKS" | jq 'length')

log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log "${CYAN}${BOLD}  AI ORCHESTRATION ENGINE${RESET}"
log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log ""
log "${BOLD}Task file:${RESET} $TASK_FILE"
log "${BOLD}Total tasks:${RESET} $TASK_COUNT"
[[ -n "$STREAM" ]] && log "${BOLD}Stream filter:${RESET} $STREAM"
[[ "$DRY_RUN" == "true" ]] && log "${YELLOW}DRY RUN MODE${RESET}"
log ""

load_progress
COMPLETED_COUNT=$(echo "$COMPLETED" | jq 'length')
FAILED_COUNT=$(echo "$FAILED" | jq 'length')
log "${BOLD}Progress:${RESET} $COMPLETED_COUNT completed, $FAILED_COUNT failed"
log ""

# Process tasks
CURRENT=0
SUCCEEDED=0
SKIPPED=0

for row in $(echo "$TASKS" | jq -r '.[] | @base64'); do
    _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

    TASK_ID=$(_jq '.id // empty')
    [[ -z "$TASK_ID" ]] && TASK_ID="task-$CURRENT"
    TASK_DESC=$(_jq '.task')
    TASK_STREAM=$(_jq '.stream // "general"')
    CONTEXT_FILES=$(_jq '.context_files // ""')
    VERIFY_CODE=$(_jq '.verify_code // ""')
    EXPECT=$(_jq '.expect // ""')

    ((CURRENT++)) || true

    # Skip if before start point
    if [[ $CURRENT -le $START_FROM ]]; then
        continue
    fi

    # Skip if stream filter doesn't match
    if [[ -n "$STREAM" && "$TASK_STREAM" != "$STREAM" ]]; then
        continue
    fi

    # Skip if already completed
    if is_completed "$TASK_ID"; then
        log "${DIM}[$CURRENT/$TASK_COUNT] $TASK_ID - already completed${RESET}"
        ((SKIPPED++)) || true
        continue
    fi

    log "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    log "${BOLD}[$CURRENT/$TASK_COUNT] $TASK_ID${RESET}"
    log "${DIM}Stream: $TASK_STREAM${RESET}"
    log ""
    log "$TASK_DESC"
    log ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log "${DIM}[dry-run] Would execute: auto.sh \"$TASK_DESC\"${RESET}"
        [[ -n "$CONTEXT_FILES" ]] && log "${DIM}  --context-files \"$CONTEXT_FILES\"${RESET}"
        [[ -n "$VERIFY_CODE" ]] && log "${DIM}  --verify-code \"$VERIFY_CODE\"${RESET}"
        [[ -n "$EXPECT" ]] && log "${DIM}  --expect \"$EXPECT\"${RESET}"
        continue
    fi

    # Human review checkpoint
    if [[ "$HUMAN_REVIEW" == "true" ]]; then
        log ""
        log "${YELLOW}Human review required. Press ENTER to proceed, 's' to skip, 'q' to quit:${RESET}"
        read -r response
        case "$response" in
            s|S) log "${DIM}Skipped by human${RESET}"; continue ;;
            q|Q) log "${YELLOW}Stopped by human${RESET}"; exit 0 ;;
        esac
    fi

    # Build auto.sh command
    CMD="$SCRIPT_DIR/auto.sh \"$TASK_DESC\""
    [[ -n "$CONTEXT_FILES" ]] && CMD+=" --context-files \"$CONTEXT_FILES\""
    [[ -n "$VERIFY_CODE" ]] && CMD+=" --verify-code \"$VERIFY_CODE\""
    [[ -n "$EXPECT" ]] && CMD+=" --expect \"$EXPECT\""
    CMD+=" --no-stash"  # Orchestrator manages checkpoints

    log "${DIM}Executing: $CMD${RESET}"
    log ""

    # Execute with timeout (10 min per task)
    TASK_LOG="$LOG_DIR/${TASK_ID}.log"
    if timeout 600 bash -c "$CMD" > "$TASK_LOG" 2>&1; then
        log "${GREEN}✓ Task completed${RESET}"
        save_progress "$TASK_ID" "completed"
        ((SUCCEEDED++)) || true

        # Verify before commit: typecheck + tests
        cd "$PROJECT_DIR"

        # TypeScript compilation check
        log "${DIM}Running typecheck...${RESET}"
        if ! pnpm typecheck >/dev/null 2>&1; then
            log "${RED}✗ TypeScript errors - reverting changes${RESET}"
            git checkout . 2>/dev/null || true
            save_progress "$TASK_ID" "failed"
            ((SUCCEEDED--)) || true
            continue
        fi
        log "${GREEN}✓ Typecheck passed${RESET}"

        # Run tests (if test command exists)
        if [[ -f "package.json" ]] && grep -q '"test"' package.json 2>/dev/null; then
            log "${DIM}Running tests...${RESET}"
            if ! timeout 120 pnpm test >/dev/null 2>&1; then
                log "${RED}✗ Tests failed - reverting changes${RESET}"
                git checkout . 2>/dev/null || true
                save_progress "$TASK_ID" "failed"
                ((SUCCEEDED--)) || true
                continue
            fi
            log "${GREEN}✓ Tests passed${RESET}"
        fi

        # Commit after successful verification
        if git rev-parse --git-dir >/dev/null 2>&1; then
            DIFF=$(git diff --stat 2>/dev/null || echo "")
            if [[ -n "$DIFF" ]]; then
                git add -A
                # Use heredoc for safe commit message
                git commit -m "$(cat <<EOF
feat: $TASK_DESC

Orchestrated by AI pipeline.
Task ID: $TASK_ID
Verified: typecheck ✓, tests ✓

🤖 Generated with Claude Code
EOF
)" >/dev/null 2>&1 || true
                log "${DIM}Changes committed${RESET}"
            fi
        fi
    else
        EXIT_CODE=$?
        log "${RED}✗ Task failed (exit $EXIT_CODE)${RESET}"
        log "${DIM}See: $TASK_LOG${RESET}"
        save_progress "$TASK_ID" "failed"

        # On failure, revert changes
        cd "$PROJECT_DIR"
        git checkout . 2>/dev/null || true
        log "${DIM}Changes reverted${RESET}"
    fi

    log ""
done

# Summary
log ""
log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log "${CYAN}${BOLD}  ORCHESTRATION COMPLETE${RESET}"
log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log ""
log "${BOLD}Results:${RESET}"
log "  Succeeded: $SUCCEEDED"
log "  Skipped:   $SKIPPED"
log "  Failed:    $(echo "$FAILED" | jq 'length')"
log ""
log "Session log: $LOG_DIR"
log "Progress file: $PROGRESS_FILE"
