#!/usr/bin/env bash
#
# multi-brain.sh - 2-tier codex swarm
# Spawns N "brains" (codex-max, xhigh) each dispatching M "minis" (codex-mini, low)
# and merges their outputs per brain.
#
# Usage:
#   ./multi-brain.sh "task to solve" [BRAINS] [MINIS_PER_BRAIN]
#

set -euo pipefail

TASK="${1:-}"
BRAINS="${2:-3}"
MINIS="${3:-5}"

[[ -n "$TASK" ]] || { echo "Usage: $0 \"task\" [brains=3] [minis_per_brain=5]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$SCRIPT_DIR/runs/multi_brain_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$RUN_DIR/out"
LOG_FILE="$RUN_DIR/run.log"
mkdir -p "$OUT_DIR"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

brain_cmd() {
    codex exec --full-auto \
        -m gpt-5.1-codex-max \
        -c model_reasoning_effort=xhigh \
        --sandbox danger-full-access \
        "$@"
}

mini_cmd() {
    codex exec --full-auto \
        -m gpt-5.1-codex-mini \
        -c model_reasoning_effort=low \
        --sandbox workspace-write \
        "$@"
}

log "=== MULTI-BRAIN SWARM ==="
log "Task: $TASK"
log "Brains: $BRAINS | Minis per brain: $MINIS"
log "Run dir: $RUN_DIR"

for b in $(seq 1 "$BRAINS"); do
    (
        log "[Brain $b] dispatching minis..."
        for m in $(seq 1 "$MINIS"); do
            mini_out="$OUT_DIR/brain${b}_mini${m}.txt"
            mini_cmd "Task: $TASK
You are Mini $m for Brain $b. Produce as much helpful code/steps as possible within your context. Do not call other tools. Output plain text/code." \
                2>&1 | tee "$mini_out" >/dev/null &
        done
        wait

        log "[Brain $b] merging minis..."
        brain_out="$OUT_DIR/brain${b}_final.txt"
        brain_cmd "You are Brain $b. Task: $TASK
You received drafts from minis:
$(ls "$OUT_DIR"/brain${b}_mini*.txt | sed 's/^/FILE: /')

Read all mini outputs and produce a merged, best-effort solution. Output plain text/code." \
            2>&1 | tee "$brain_out" >/dev/null
    ) &
done

wait

log "=== ALL BRAINS DONE ==="
log "Outputs: $OUT_DIR/brain*_final.txt"
exit 0
