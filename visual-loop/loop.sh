#!/usr/bin/env bash
#
# loop.sh - Visual feedback loop
# Runs dev server, takes screenshots, AI analyzes, iterates
#
# Usage: ./loop.sh "Add a red button to the header"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK="${1:-}"
MAX_ITERATIONS="${MAX_ITERATIONS:-5}"
PROJECT_DIR="${PROJECT_DIR:-/home/geni/Documents/vale-village}"
URL="${URL:-http://localhost:5173}"

[[ -n "$TASK" ]] || { echo "Usage: ./loop.sh \"task description\""; exit 1; }

# Colors
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

LOG_DIR="$SCRIPT_DIR/runs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

log() { echo -e "$1" | tee -a "$LOG_DIR/session.log"; }

log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log "${CYAN}${BOLD}  VISUAL FEEDBACK LOOP${RESET}"
log "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log ""
log "${BOLD}Task:${RESET} $TASK"
log "${BOLD}Max iterations:${RESET} $MAX_ITERATIONS"
log ""

# Check if dev server is running
if ! curl -sf "$URL" >/dev/null 2>&1; then
    log "${YELLOW}Dev server not running. Start it first: pnpm dev${RESET}"
    exit 1
fi

for ((i=1; i<=MAX_ITERATIONS; i++)); do
    log "${YELLOW}► Iteration $i / $MAX_ITERATIONS${RESET}"
    log ""

    # Take screenshot
    log "${DIM}Taking screenshot...${RESET}"
    SHOT="$LOG_DIR/iter_${i}.png"
    "$SCRIPT_DIR/snap.sh" "$URL" "$SHOT"
    log "Screenshot: $SHOT"

    # Analyze
    log "${DIM}Analyzing...${RESET}"
    ANALYSIS=$("$SCRIPT_DIR/analyze.sh" "$SHOT" "$TASK" 2>&1)
    log "Analysis: $ANALYSIS"
    echo "$ANALYSIS" > "$LOG_DIR/iter_${i}_analysis.json"

    # Parse result
    PASS=$(echo "$ANALYSIS" | jq -r '.pass // false' 2>/dev/null || echo "false")
    ISSUES=$(echo "$ANALYSIS" | jq -r '.issues // "parse error"' 2>/dev/null || echo "parse error")
    NEXT=$(echo "$ANALYSIS" | jq -r '.next_action // "unknown"' 2>/dev/null || echo "unknown")

    if [[ "$PASS" == "true" ]]; then
        log ""
        log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        log "${GREEN}${BOLD}  ✓ TASK COMPLETE${RESET}"
        log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        log ""
        log "Final screenshot: $SHOT"
        log "Session log: $LOG_DIR"
        exit 0
    fi

    log ""
    log "${RED}Issues:${RESET} $ISSUES"
    log "${YELLOW}Next:${RESET} $NEXT"
    log ""

    # If not the last iteration, prompt for action
    if [[ $i -lt $MAX_ITERATIONS ]]; then
        log "${DIM}Waiting for you to make changes... Press Enter when ready for next iteration.${RESET}"
        read -r
    fi
done

log ""
log "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log "${YELLOW}${BOLD}  Max iterations reached - manual review needed${RESET}"
log "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
log ""
log "Session log: $LOG_DIR"
exit 1
