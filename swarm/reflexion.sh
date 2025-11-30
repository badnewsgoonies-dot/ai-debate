#!/usr/bin/env bash
#
# reflexion.sh - Iterative attempt + self-critique loop (codex orchestrator)
# Usage: ./reflexion.sh "Investigate X" [max_iterations]
#

set -euo pipefail

TASK="${1:-}"
MAX_ITERATIONS="${2:-${MAX_ITERATIONS:-5}}"

if [[ -z "$TASK" ]]; then
    echo "Usage: $0 \"task to study\" [max_iterations]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/runs/reflexion_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "=== REFLEXION LOOP ==="
echo "Task: $TASK"
echo "Max iterations: $MAX_ITERATIONS"
echo "Logs: $LOG_DIR"
echo ""

PROMPT=$(cat <<EOF
You are running a Reflexion-style loop as the orchestrator (codex with tools).
Goal: $TASK
Max iterations: $MAX_ITERATIONS
Log directory: $LOG_DIR

Rules:
- Use up to MAX_ITERATIONS loops of (attempt → critique → improve).
- For critique, call "claude -p" with the previous attempt to get pointed feedback.
- After each attempt, save concise notes to "\$LOG_DIR/iter_<n>.txt" (attempt, critique, next move).
- Stop early if the task is satisfied; otherwise continue until the cap.
- Keep output concise; include final answer plus next steps.
- Avoid destructive actions; prefer read-only inspection unless strictly needed.
- Use bash best practices already present in this repo (quoted vars, set -euo pipefail).

Deliverables:
- Final printed summary with: what was tried, best solution, and recommended next action.
- Persist intermediate notes in the log dir for traceability.
EOF
)

LOG_DIR="$LOG_DIR" TASK="$TASK" MAX_ITERATIONS="$MAX_ITERATIONS" codex exec \
    --full-auto \
    -m gpt-5.1-codex-max \
    -c reasoning.effort=xhigh \
    --sandbox danger-full-access \
    "$PROMPT" | tee "$LOG_DIR/reflexion.log"

echo ""
echo "=== REFLEXION COMPLETE ==="
echo "Full log: $LOG_DIR/reflexion.log"
