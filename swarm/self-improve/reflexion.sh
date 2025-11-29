#!/bin/bash
# reflexion.sh - Error-driven self-improvement loop
# Pattern: Run → Fail → Reflect → Retry with insight
#
# Usage: ./reflexion.sh "command to run" [max_attempts]

set -euo pipefail

COMMAND="${1:-echo 'No command provided'}"
MAX_ATTEMPTS="${2:-5}"
RUN_DIR="$(dirname "$0")/../runs/reflexion_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

echo "=== REFLEXION LOOP ==="
echo "Command: $COMMAND"
echo "Max attempts: $MAX_ATTEMPTS"
echo "Logs: $RUN_DIR"
echo ""

REFLECTIONS=""
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "[Attempt $ATTEMPT/$MAX_ATTEMPTS]"

    # Build context with past reflections
    if [ -n "$REFLECTIONS" ]; then
        CONTEXT="Previous attempts failed. Learnings so far:
$REFLECTIONS

Apply these insights when executing."
    else
        CONTEXT=""
    fi

    # Run the command via Codex (orchestrator with tools)
    echo "  Running command..."
    OUTPUT=$(codex exec -m gpt-5.1-codex-max -c reasoning.effort=high --sandbox danger-full-access "
$CONTEXT

Execute this command and report success/failure:
$COMMAND

If it fails, explain what went wrong concisely.
" 2>&1) || true

    echo "$OUTPUT" > "$RUN_DIR/attempt_${ATTEMPT}.log"

    # Check for success indicators
    if echo "$OUTPUT" | grep -qiE "success|passed|completed|done|worked"; then
        echo "  ✓ Success on attempt $ATTEMPT!"
        echo "$OUTPUT" | tail -20
        echo ""
        echo "=== REFLEXION COMPLETE ==="
        exit 0
    fi

    # Failed - get reflection from Claude (reasoning brain)
    echo "  ✗ Failed. Getting reflection..."

    REFLECTION=$(claude -p "
You are a debugging assistant. Analyze this failed attempt and provide a brief (2-3 line) insight for the next attempt.

Command: $COMMAND
Output: $OUTPUT

What should we try differently? Be specific and actionable.
" 2>&1)

    echo "$REFLECTION" > "$RUN_DIR/reflection_${ATTEMPT}.log"
    REFLECTIONS="${REFLECTIONS}
Attempt $ATTEMPT: $REFLECTION"

    echo "  Reflection: $(echo "$REFLECTION" | head -2)"
    echo ""

    sleep 1
done

echo "=== MAX ATTEMPTS REACHED ==="
echo "All reflections saved to: $RUN_DIR"
echo "Last output:"
echo "$OUTPUT" | tail -10
exit 1
