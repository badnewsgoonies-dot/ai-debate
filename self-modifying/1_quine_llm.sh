#!/usr/bin/env bash
set -euo pipefail

# PATTERN 1B: LLM-Assisted Quine Evolution
# A script that uses an LLM to evolve itself toward a goal

SCRIPT_PATH="${BASH_SOURCE[0]}"
GOAL="${1:-make this script print 'Hello, World!' before the quine output}"

echo "=== LLM-Assisted Quine Evolution ==="
echo "Goal: $GOAL"
echo ""

# Read current version
CURRENT_CODE=$(cat "$SCRIPT_PATH")

# Ask LLM to evolve the code
echo "Asking Claude to evolve the script..."
NEW_CODE=$(claude -p "Here is a bash script that is trying to evolve:

\`\`\`bash
$CURRENT_CODE
\`\`\`

Goal: $GOAL

Output ONLY the complete modified bash script code, nothing else. Keep the self-reading mechanism intact. The script should still be able to read and modify itself.")

# Safety check: ensure it still contains self-reading logic
if echo "$NEW_CODE" | grep -q 'SCRIPT_PATH\|cat.*BASH_SOURCE'; then
    echo ""
    echo "=== Proposed Evolution ==="
    echo "$NEW_CODE"
    echo ""
    echo -n "Apply this change? [y/N] "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "$NEW_CODE" > "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        echo "Evolution applied! Run again to see the result."
    else
        echo "Evolution rejected."
    fi
else
    echo "ERROR: Evolved code lost self-modification capability. Rejected for safety."
    exit 1
fi
