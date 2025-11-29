#!/bin/bash
# prompt-evolver.sh - Evolutionary prompt optimization
# Pattern: Population → Score → Select → Mutate → Repeat
#
# Usage: ./prompt-evolver.sh "task description" "test_command" [generations]

set -euo pipefail

TASK="${1:-Classify sentiment as positive or negative}"
TEST_CMD="${2:-echo 'test passed'}"  # Command that scores a prompt (should output a number)
GENERATIONS="${3:-5}"
POP_SIZE=4
TOP_K=2

RUN_DIR="$(dirname "$0")/../runs/evolver_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

echo "=== PROMPT EVOLVER ==="
echo "Task: $TASK"
echo "Generations: $GENERATIONS"
echo "Population: $POP_SIZE, Select top: $TOP_K"
echo "Logs: $RUN_DIR"
echo ""

# Initialize population with Claude
echo "[Gen 0] Initializing population..."
POPULATION=$(claude -p "
Generate $POP_SIZE different prompt variations for this task:
$TASK

Return as a numbered list (1. 2. 3. 4.) with just the prompts, no explanations.
Each should be a complete instruction that could be given to an AI.
")

echo "$POPULATION" > "$RUN_DIR/gen_0_population.txt"
echo "$POPULATION"
echo ""

# Evolution loop
for GEN in $(seq 1 $GENERATIONS); do
    echo "[Gen $GEN] Evaluating and evolving..."

    # Score each prompt (simplified - in real use, run actual tests)
    SCORED=$(codex exec -m gpt-5.1-codex-max -c reasoning.effort=medium --sandbox danger-full-access "
You have these prompt candidates:
$POPULATION

For each prompt, estimate a quality score 1-100 based on:
- Clarity (is it unambiguous?)
- Completeness (does it specify format, constraints?)
- Effectiveness (would it get good results?)

Return format:
PROMPT: [the prompt]
SCORE: [number]
---
(repeat for each)
" 2>&1)

    echo "$SCORED" > "$RUN_DIR/gen_${GEN}_scored.txt"

    # Select top performers and generate mutations with Claude
    EVOLVED=$(claude -p "
Here are scored prompts:
$SCORED

Take the top $TOP_K scoring prompts and:
1. Keep them as-is
2. Create $((POP_SIZE - TOP_K)) mutations by:
   - Combining best elements from top prompts
   - Adding specificity or constraints
   - Rephrasing for clarity

Return $POP_SIZE prompts as a numbered list (1. 2. 3. 4.)
Just the prompts, no scores or explanations.
")

    POPULATION="$EVOLVED"
    echo "$POPULATION" > "$RUN_DIR/gen_${GEN}_population.txt"

    echo "  Top prompts evolved:"
    echo "$POPULATION" | head -8
    echo ""
done

echo "=== EVOLUTION COMPLETE ==="
echo ""
echo "Final population:"
echo "$POPULATION"
echo ""
echo "Best prompt (first in final population):"
echo "$POPULATION" | head -2
echo ""
echo "Full history: $RUN_DIR/"
