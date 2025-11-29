#!/bin/bash
# hybrid-swarm.sh - Multi-provider agent swarm
# Uses Claude (Anthropic) + Codex (OpenAI) + Copilot (GitHub)

TOPIC="${1:-Analyze this problem}"
LOG_DIR="$(dirname "$0")/runs/hybrid_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "=== HYBRID SWARM ==="
echo "Topic: $TOPIC"
echo "Providers: Claude + Codex + Copilot"
echo ""

# Spawn 3 agents from different providers in parallel
echo "[DISPATCH] Spawning multi-provider agents..."

# Agent 1: Claude (Anthropic) - Deep reasoning
claude -p "
You are CLAUDE AGENT in a multi-AI swarm.
Task: $TOPIC

Focus on: Deep reasoning, nuance, edge cases, potential pitfalls.
Be concise but thorough. Return structured findings.
" > "$LOG_DIR/claude.txt" 2>&1 &
PID1=$!

# Agent 2: Codex (OpenAI) - Code & execution
codex exec --full-auto -m gpt-5.1-codex-max -c reasoning.effort=xhigh --sandbox danger-full-access "
You are CODEX AGENT in a multi-AI swarm.
Task: $TOPIC

Focus on: Code implementation, practical execution, testing.
Run commands if needed. Return structured findings.
" > "$LOG_DIR/codex.txt" 2>&1 &
PID2=$!

# Agent 3: Copilot (GitHub) - Suggest & explain
{
  echo "=== SUGGESTIONS ==="
  gh copilot suggest -t shell "$TOPIC" 2>&1
  echo ""
  echo "=== EXPLANATION ==="
  gh copilot explain "$TOPIC" 2>&1
} > "$LOG_DIR/copilot.txt" 2>&1 &
PID3=$!

echo "[SWARM] Agents dispatched:"
echo "  - Claude (PID: $PID1) - reasoning"
echo "  - Codex  (PID: $PID2) - execution"
echo "  - Copilot(PID: $PID3) - suggestions"
echo "[SWARM] Waiting for results..."

wait $PID1 $PID2 $PID3

echo ""
echo "=== AGGREGATING CROSS-PROVIDER RESULTS ==="

# Use Claude to synthesize (best at reasoning across sources)
claude -p "
You are the AGGREGATOR synthesizing findings from 3 different AI providers.
Each has different strengths - combine them into a unified answer.

=== CLAUDE (Anthropic) - Reasoning ===
$(cat "$LOG_DIR/claude.txt" 2>/dev/null || echo "No response")

=== CODEX (OpenAI) - Execution ===
$(cat "$LOG_DIR/codex.txt" 2>/dev/null || echo "No response")

=== COPILOT (GitHub) - Suggestions ===
$(cat "$LOG_DIR/copilot.txt" 2>/dev/null || echo "No response")

Synthesize these into:
1. Key insights (what all agree on)
2. Unique perspectives (what each uniquely contributed)
3. Recommended action

Be concise.
" | tee "$LOG_DIR/final.txt"

echo ""
echo "=== HYBRID SWARM COMPLETE ==="
echo "Individual reports: $LOG_DIR/"
echo "  - claude.txt, codex.txt, copilot.txt, final.txt"
