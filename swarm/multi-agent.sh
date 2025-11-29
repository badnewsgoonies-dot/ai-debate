#!/usr/bin/env bash
#
# multi-agent.sh - 3-Agent Orchestrator (Claude + Codex + Copilot)
#
# Usage:
#   ./multi-agent.sh "<task>"
#   ./multi-agent.sh --orchestrator codex "<task>"
#
# Orchestrator modes:
#   codex  - Codex leads, calls Claude + Copilot (default)
#   claude - Script-based, calls Codex + Copilot sequentially

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || true

ORCHESTRATOR="${1:-}"
TASK=""
SAFE_MODE="${SAFE_MODE:-0}"
ALLOW_DANGER="${ALLOW_DANGER:-0}"
BRAIN_EFFORT="${BRAIN_EFFORT:-xhigh}"

# Parse args
if [[ "$ORCHESTRATOR" == "--orchestrator" ]]; then
    ORCHESTRATOR="$2"
    TASK="$3"
elif [[ "$ORCHESTRATOR" == "--"* ]]; then
    echo "Unknown option: $ORCHESTRATOR" >&2
    exit 1
else
    TASK="$ORCHESTRATOR"
    ORCHESTRATOR="codex"
fi

if [[ -z "$TASK" ]]; then
    echo "Usage: $0 [--orchestrator codex|claude] \"<task>\"" >&2
    exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing command: $1" >&2
        exit 1
    fi
}

sandbox_flag=("--sandbox" "workspace-write")
if [[ "$ALLOW_DANGER" == "1" && "$SAFE_MODE" != "1" ]]; then
    sandbox_flag=("--sandbox" "danger-full-access")
fi

call_claude() {
    claude -p "$1" 2>&1
}

call_codex() {
    codex exec --full-auto \
        -m gpt-5.1-codex-max \
        -c model_reasoning_effort="$BRAIN_EFFORT" \
        "${sandbox_flag[@]}" \
        "$1" 2>&1
}

call_copilot() {
    copilot -p "$1" 2>&1 | grep -v "^Total\|^Usage"
}

main() {
    require_cmd codex
    require_cmd claude
    require_cmd copilot

    log "=== 3-AGENT ORCHESTRATOR ==="
    log "Orchestrator: $ORCHESTRATOR"
    log "Agents: Claude, Codex, Copilot"
    log "Task: $TASK"
    log "Safe mode: $SAFE_MODE | Danger sandbox: $([[ ${sandbox_flag[1]} == \"danger-full-access\" ]] && echo on || echo off)"
    log "Codex effort (brain): $BRAIN_EFFORT"
    echo ""

    if [[ "$ORCHESTRATOR" == "codex" ]]; then
        log "[CODEX ORCHESTRATING]"
        if ! codex_out=$(call_codex "You are an orchestrator. Complete this task: $TASK

Available agents (call via shell, DO NOT call codex - that's you):
- claude -p \"prompt\" - for reasoning/analysis
- copilot -p \"prompt\" - for code suggestions

Break down the task, delegate to agents, synthesize their outputs into a final result."); then
            log "Codex orchestration failed. Falling back to claude mode."
            ORCHESTRATOR="claude"
        else
            echo "$codex_out"
        fi

    elif [[ "$ORCHESTRATOR" == "claude" ]]; then
        log "[SCRIPT-BASED ORCHESTRATION]"

        log "[1/3] Copilot draft..."
        local copilot_out
        copilot_out=$(call_copilot "Suggest approach for: $TASK") || copilot_out="(failed)"

        log "[2/3] Codex draft..."
        local codex_out_a
        codex_out_a=$(call_codex "Draft a solution for: $TASK
Use copilot's hint if helpful: $copilot_out") || codex_out_a="(failed)"

        log "[3/3] Claude vote/merge..."
        local claude_vote
        claude_vote=$(call_claude "You are reviewing two drafts for the same task.

TASK:
$TASK

DRAFT A (codex):
$codex_out_a

DRAFT B (copilot suggestion):
$copilot_out

Pick the better draft or merge them. Return a concise final answer.") || claude_vote="(failed)"

        echo ""
        log "=== RESULTS ==="
        echo "--- Copilot ---"
        echo "$copilot_out"
        echo ""
        echo "--- Codex Draft ---"
        echo "$codex_out_a"
        echo ""
        echo "--- Claude Decision ---"
        echo "$claude_vote"
    else
        echo "Unknown orchestrator: $ORCHESTRATOR (use codex or claude)" >&2
        exit 1
    fi

    log "=== COMPLETE ==="
}

main
