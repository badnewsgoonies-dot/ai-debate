#!/bin/bash
# parallel-swarm.sh - Spawn multiple agents in parallel, aggregate results
# Each agent can spawn its own sub-agents

TOPIC="${1:-Analyze this codebase}"
LOG_DIR="$(dirname "$0")/runs/parallel_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "=== PARALLEL SWARM ==="
echo "Topic: $TOPIC"
echo ""

# Spawn 3 specialist agents in parallel
echo "[DISPATCH] Spawning specialist agents..."

# Agent 1: Code Structure Analyst (uses Codex for code reading)
codex exec --full-auto -m o4-mini "
You are a CODE STRUCTURE agent. Analyze the codebase structure.
- List key directories and their purposes
- Identify main entry points
- You may spawn: claude -p 'question' for clarification
Return structured findings.
" > "$LOG_DIR/structure.txt" 2>&1 &
PID1=$!

# Agent 2: Dependency Analyst (uses Claude for reasoning)
claude -p "
You are a DEPENDENCY agent analyzing: $TOPIC
- What external dependencies exist?
- What are the key integrations?
Be concise.
" > "$LOG_DIR/deps.txt" 2>&1 &
PID2=$!

# Agent 3: Test/Quality Analyst (uses Codex for running things)
codex exec --full-auto -m o4-mini "
You are a QUALITY agent. Check code quality.
- Run any linters/tests if available
- Identify potential issues
- You may spawn sub-agents for deep dives
Return findings.
" > "$LOG_DIR/quality.txt" 2>&1 &
PID3=$!

echo "[SWARM] Agents dispatched (PIDs: $PID1, $PID2, $PID3)"
echo "[SWARM] Waiting for results..."

wait $PID1 $PID2 $PID3

echo ""
echo "=== AGGREGATING RESULTS ==="

# Final aggregator agent combines all findings
claude -p "
You are the AGGREGATOR. Combine these specialist reports into a unified summary:

=== STRUCTURE REPORT ===
$(cat "$LOG_DIR/structure.txt")

=== DEPENDENCY REPORT ===
$(cat "$LOG_DIR/deps.txt")

=== QUALITY REPORT ===
$(cat "$LOG_DIR/quality.txt")

Provide a cohesive summary with key insights and recommendations.
" | tee "$LOG_DIR/final.txt"

echo ""
echo "=== SWARM COMPLETE ==="
echo "Reports in: $LOG_DIR/"
