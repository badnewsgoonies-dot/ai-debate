#!/usr/bin/env bash
#
# analyze.sh - Send screenshot to AI for analysis
# Usage: ./analyze.sh screenshot.png "task description"
# Uses: codex (with gpt-5.1 vision)
#
set -euo pipefail

SCREENSHOT="${1:-}"
TASK="${2:-Check if the UI looks correct}"

[[ -f "$SCREENSHOT" ]] || { echo "Error: Screenshot not found: $SCREENSHOT"; exit 1; }

PROMPT="You are a visual QA bot.

TASK: $TASK

Analyze this screenshot and return ONLY valid JSON (no markdown, no explanation):
{\"pass\": true or false, \"issues\": \"description of any problems or none\", \"next_action\": \"what to do next or done\"}

Be strict. If the task is not fully complete, fail it."

# Use codex with image
echo "$PROMPT" | codex exec -i "$SCREENSHOT" 2>/dev/null | grep -E '^\{.*\}$' | head -1
