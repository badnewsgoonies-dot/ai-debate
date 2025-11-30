#!/usr/bin/env bash
#
# prompt-evolver.sh - Iterative prompt refinement via codex + claude scorer
# Usage: ./prompt-evolver.sh "Goal (what prompt should achieve)" ["Starting prompt text"]
#

set -euo pipefail

TASK="${1:-}"
BASE_PROMPT="${2:-${BASE_PROMPT:-}}"
ROUNDS="${ROUNDS:-3}"
VARIANTS="${VARIANTS:-4}"

if [[ -z "$TASK" ]]; then
    echo "Usage: $0 \"goal/task\" [\"starting prompt text\"]" >&2
    echo "Env overrides: ROUNDS (default 3), VARIANTS (default 4), BASE_PROMPT" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/runs/prompt_evolver_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "=== PROMPT EVOLVER ==="
echo "Goal: $TASK"
[[ -n "$BASE_PROMPT" ]] && echo "Starting prompt provided."
echo "Rounds: $ROUNDS | Variants per round: $VARIANTS"
echo "Logs: $LOG_DIR"
echo ""

PROMPT=$(cat <<EOF
You are the PROMPT EVOLVER orchestrator (codex with tools enabled).
Objective: craft the strongest prompt to achieve: "$TASK"
Starting prompt (may be empty): "$BASE_PROMPT"
Rounds: $ROUNDS | Variants per round: $VARIANTS
Log directory: $LOG_DIR

Method (repeat up to ROUNDS):
1) Baseline: If no starting prompt, draft a concise baseline tailored to the goal.
2) Generate VARIANTS mutations of the current best prompt (diverse edits, not synonyms).
3) Score each variant by calling "claude -p" as an impartial grader. Score 1-10 on: clarity, coverage of goal, safety/guardrails, brevity/controllability. Write a short rationale.
4) Save variants + scores to "$LOG_DIR/round_<n>.txt" (one file per round).
5) Select the best-scoring prompt (tie-break: brevity then safety). Use it as the parent for the next round.

Constraints:
- Keep loops bounded (ROUNDS) and variants limited (VARIANTS).
- Avoid destructive shell actions; default to read-only operations.
- Keep outputs concise and ASCII.

Final deliverables (print to stdout and save):
- Best prompt (print plainly) and why it won.
- Quick next-tweak suggestion if time allowed.
- Save the final prompt to "$LOG_DIR/best_prompt.txt" and a brief summary to "$LOG_DIR/summary.txt".
EOF
)

LOG_DIR="$LOG_DIR" TASK="$TASK" BASE_PROMPT="$BASE_PROMPT" ROUNDS="$ROUNDS" VARIANTS="$VARIANTS" codex exec \
    --full-auto \
    -m gpt-5.1-codex-max \
    -c reasoning.effort=xhigh \
    --sandbox danger-full-access \
    "$PROMPT" | tee "$LOG_DIR/prompt_evolver.log"

echo ""
echo "=== PROMPT EVOLVER COMPLETE ==="
echo "Full log: $LOG_DIR/prompt_evolver.log"
