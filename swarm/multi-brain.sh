#!/usr/bin/env bash
#
# multi-brain.sh - 2-tier codex swarm
#
set -euo pipefail

usage() {
    cat <<'EOF'
multi-brain.sh - spawn N "brains" (codex-max) each dispatching M "minis" (codex-mini) and merge outputs.

Usage:
  ./multi-brain.sh "task to solve" [BRAINS] [MINIS_PER_BRAIN]

Env overrides:
  SAFE_MODE=1           # default; workspace-write sandbox
  ALLOW_DANGER=0        # set 1 to allow danger-full-access (not recommended)
  BRAIN_EFFORT=xhigh    # reasoning effort for brains
  MINI_EFFORT=low       # reasoning effort for minis
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

TASK="${1:-}"
BRAINS="${2:-3}"
MINIS="${3:-5}"
SAFE_MODE="${SAFE_MODE:-1}"
ALLOW_DANGER="${ALLOW_DANGER:-0}"
BRAIN_EFFORT="${BRAIN_EFFORT:-xhigh}"
MINI_EFFORT="${MINI_EFFORT:-low}"

if [[ -z "$TASK" ]]; then
    usage >&2
    exit 1
fi

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing command: $1" >&2
        exit 1
    fi
}

require_cmd codex

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$SCRIPT_DIR/runs/multi_brain_$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$RUN_DIR/out"
LOG_FILE="$RUN_DIR/run.log"
mkdir -p "$OUT_DIR"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

sandbox_flag=("--sandbox" "workspace-write")
if [[ "$ALLOW_DANGER" == "1" && "$SAFE_MODE" != "1" ]]; then
    sandbox_flag=("--sandbox" "danger-full-access")
fi

brain_cmd() {
    codex exec --full-auto \
        -m gpt-5.1-codex-max \
        -c model_reasoning_effort="$BRAIN_EFFORT" \
        "${sandbox_flag[@]}" \
        "$@"
}

mini_cmd() {
    codex exec --full-auto \
        -m gpt-5.1-codex-mini \
        -c model_reasoning_effort="$MINI_EFFORT" \
        --sandbox workspace-write \
        "$@"
}

cat > "$RUN_DIR/meta.json" <<EOF
{
  "script": "multi-brain",
  "task": "$TASK",
  "brains": $BRAINS,
  "minis_per_brain": $MINIS,
  "brain_effort": "$BRAIN_EFFORT",
  "mini_effort": "$MINI_EFFORT",
  "safe_mode": $SAFE_MODE,
  "allow_danger": $ALLOW_DANGER,
  "timestamp": "$(date -Is)",
  "run_dir": "$RUN_DIR"
}
EOF

log "=== MULTI-BRAIN SWARM ==="
log "Task: $TASK"
log "Brains: $BRAINS | Minis per brain: $MINIS"
log "Effort (brain/mini): $BRAIN_EFFORT / $MINI_EFFORT"
log "Safe mode: $SAFE_MODE | Danger sandbox: $([[ ${sandbox_flag[1]} == \"danger-full-access\" ]] && echo on || echo off)"
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
