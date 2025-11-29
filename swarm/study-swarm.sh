#!/bin/bash
# study-swarm.sh - Recursive agent study session
# Agents spawn sub-agents to research, test, and aggregate findings

set -e
TOPIC="${1:-Explain this codebase}"
MAX_DEPTH="${2:-2}"
LOG_DIR="$(dirname "$0")/runs/swarm_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "=== STUDY SWARM ==="
echo "Topic: $TOPIC"
echo "Max depth: $MAX_DEPTH"
echo "Logs: $LOG_DIR"
echo ""

# The recursive agent prompt - each agent can spawn sub-agents
SWARM_PROMPT='You are a research agent in a swarm. You can spawn sub-agents.

RULES:
1. Break complex questions into sub-questions
2. For each sub-question, spawn a sub-agent using: claude -p "sub-question here"
3. Or use: codex exec "task here" for code tasks
4. Aggregate all findings into a final answer
5. Be concise - other agents are waiting

CURRENT DEPTH: $DEPTH / $MAX_DEPTH
If at max depth, do NOT spawn sub-agents - just answer directly.

YOUR TASK: $TASK
'

# Launch primary research agent with Codex (has --full-auto for spawning)
echo "[SWARM] Launching primary agent..."
codex exec --full-auto -m o4-mini "
$SWARM_PROMPT

DEPTH=1
MAX_DEPTH=$MAX_DEPTH
TASK=$TOPIC

Execute this research task. Spawn claude or codex sub-agents as needed.
Return a structured summary of all findings.
" 2>&1 | tee "$LOG_DIR/swarm.log"

echo ""
echo "=== SWARM COMPLETE ==="
echo "Full log: $LOG_DIR/swarm.log"
