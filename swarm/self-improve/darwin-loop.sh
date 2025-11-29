#!/bin/bash
# darwin-loop.sh - Self-modifying code via test-driven evolution
# Pattern: Edit → Test → Keep if better, Rollback if worse
#
# Usage: ./darwin-loop.sh "file_to_improve" "test_command" [max_iterations]

set -euo pipefail

TARGET_FILE="${1:-}"
TEST_CMD="${2:-echo 0}"  # Should output a numeric score (higher = better)
MAX_ITER="${3:-5}"

if [ -z "$TARGET_FILE" ] || [ ! -f "$TARGET_FILE" ]; then
    echo "Usage: ./darwin-loop.sh <file_to_improve> <test_command> [max_iterations]"
    echo "Example: ./darwin-loop.sh ./my_script.py 'python test.py'"
    exit 1
fi

RUN_DIR="$(dirname "$0")/../runs/darwin_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

echo "=== DARWIN LOOP ==="
echo "Target: $TARGET_FILE"
echo "Test: $TEST_CMD"
echo "Max iterations: $MAX_ITER"
echo "Logs: $RUN_DIR"
echo ""

# Backup original
cp "$TARGET_FILE" "$RUN_DIR/original_$(basename "$TARGET_FILE")"

# Get baseline score
echo "[Baseline] Running initial test..."
BEST_SCORE=$(eval "$TEST_CMD" 2>&1 | grep -oE '[0-9]+' | tail -1 || echo "0")
echo "  Initial score: $BEST_SCORE"
echo ""

BEST_CODE=$(cat "$TARGET_FILE")

for ITER in $(seq 1 $MAX_ITER); do
    echo "[Iteration $ITER/$MAX_ITER]"

    # Ask Claude to analyze and suggest improvement
    CURRENT_CODE=$(cat "$TARGET_FILE")

    SUGGESTION=$(claude -p "
Analyze this code and suggest ONE specific improvement to increase its quality/performance.
The code is tested with: $TEST_CMD
Current score: $BEST_SCORE

CODE:
$CURRENT_CODE

Return ONLY a unified diff (--- a/file, +++ b/file format) or say 'NO_IMPROVEMENT' if optimal.
Keep changes minimal and focused.
")

    echo "$SUGGESTION" > "$RUN_DIR/iter_${ITER}_suggestion.txt"

    if echo "$SUGGESTION" | grep -q "NO_IMPROVEMENT"; then
        echo "  Claude says no more improvements possible."
        break
    fi

    # Apply the suggestion via Codex (has file access)
    echo "  Applying suggested change..."

    APPLY_RESULT=$(codex exec -m gpt-5.1-codex-max -c reasoning.effort=medium --sandbox danger-full-access "
Apply this diff to $TARGET_FILE:
$SUGGESTION

If it's not a valid diff, interpret it as instructions and make the change.
Show the change you made.
" 2>&1)

    echo "$APPLY_RESULT" > "$RUN_DIR/iter_${ITER}_apply.log"

    # Test new version
    echo "  Testing modified version..."
    NEW_SCORE=$(eval "$TEST_CMD" 2>&1 | grep -oE '[0-9]+' | tail -1 || echo "0")
    echo "  New score: $NEW_SCORE (was: $BEST_SCORE)"

    # Keep or rollback
    if [ "$NEW_SCORE" -gt "$BEST_SCORE" ]; then
        echo "  ✓ Improvement! Keeping change."
        BEST_SCORE="$NEW_SCORE"
        BEST_CODE=$(cat "$TARGET_FILE")
        cp "$TARGET_FILE" "$RUN_DIR/iter_${ITER}_improved.txt"
    else
        echo "  ✗ No improvement. Rolling back."
        echo "$BEST_CODE" > "$TARGET_FILE"
    fi

    echo ""
done

echo "=== DARWIN LOOP COMPLETE ==="
echo "Final score: $BEST_SCORE"
echo "History: $RUN_DIR/"

# Restore best version
echo "$BEST_CODE" > "$TARGET_FILE"
echo "Best version saved to: $TARGET_FILE"
