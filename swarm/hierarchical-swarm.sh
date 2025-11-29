#!/usr/bin/env bash
#
# hierarchical-swarm.sh - 3-tier pyramid orchestrator (scaffold)
#
# Usage:
#   ./hierarchical-swarm.sh "task"
# Env:
#   BRAIN_COUNT (default 1), SENIORS_PER_BRAIN (default 3), WORKERS_PER_SENIOR (default 3)
#   SAFE_MODE=1 (default), ALLOW_DANGER=0, DRY_RUN=1 (default)
#   ROSTER_FILE (default swarm/agents.json)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/log.sh"
source "$SCRIPT_DIR/lib/preflight.sh"
source "$SCRIPT_DIR/lib/job_pool.sh"
source "$SCRIPT_DIR/lib/progress.sh"
source "$SCRIPT_DIR/lib/merge_results.sh"

TASK="${1:-}"
BRAIN_COUNT="${BRAIN_COUNT:-1}"
SENIORS_PER_BRAIN="${SENIORS_PER_BRAIN:-3}"
WORKERS_PER_SENIOR="${WORKERS_PER_SENIOR:-3}"
SAFE_MODE="${SAFE_MODE:-1}"
ALLOW_DANGER="${ALLOW_DANGER:-0}"
DRY_RUN="${DRY_RUN:-1}"
ROSTER_FILE="${ROSTER_FILE:-$SCRIPT_DIR/agents.json}"

if [[ -z "$TASK" ]]; then
    echo "Usage: $0 \"task\"" >&2
    exit 1
fi

REQUIRE_CMDS=(jq codex)
preflight_check

init_run_dir "hierarchical"
LOG_FILE="$LOG_DIR/session.log"

cat > "$LOG_DIR/meta.json" <<EOF
{
  "script": "hierarchical-swarm",
  "task": "$TASK",
  "brain_count": $BRAIN_COUNT,
  "seniors_per_brain": $SENIORS_PER_BRAIN,
  "workers_per_senior": $WORKERS_PER_SENIOR,
  "safe_mode": $SAFE_MODE,
  "allow_danger": $ALLOW_DANGER,
  "dry_run": $DRY_RUN,
  "timestamp": "$(date -Is)"
}
EOF

log_info "hierarchical swarm start | task=$TASK | run_dir=$LOG_DIR"

progress_init

SANDBOX="workspace-write"
[[ "$ALLOW_DANGER" == "1" && "$SAFE_MODE" != "1" ]] && SANDBOX="danger-full-access"

mkdir -p "$LOG_DIR/subplans" "$LOG_DIR/workers" "$LOG_DIR/results"

run_brain() {
    log_info "phase=brain start"
    local idx=1
    while [[ $idx -le $BRAIN_COUNT ]]; do
        local plan="$LOG_DIR/subplans/brain${idx}_subplans.json"
        # Stub subplans: create seniors_per_brain entries
        jq -n --arg task "$TASK" --argjson seniors $SENIORS_PER_BRAIN \
            '{task:$task, seniors:[range(0;$seniors)|{id:.+1, plan:("Subplan " + (.+1|tostring)), depends_on:[]}]}'> "$plan"
        log_info "brain_subplans_written file=$plan"
        idx=$((idx+1))
    done
    log_info "phase=brain complete"
}

run_seniors() {
    log_info "phase=seniors start"
    for plan in "$LOG_DIR"/subplans/brain*_subplans.json; do
        [[ -f "$plan" ]] || continue
        local brain_id
        brain_id="$(basename "$plan" | sed 's/[^0-9]//g')"
        jq -c '.seniors[]' "$plan" | while read -r senior; do
            local sid
            sid="$(jq -r '.id' <<<"$senior")"
            local worker_tasks="$LOG_DIR/workers/brain${brain_id}_senior${sid}_tasks.json"
            # Stub worker tasks
            jq -n --argjson workers $WORKERS_PER_SENIOR \
                '{workers:[range(0;$workers)|{id:.+1, task:"Worker task " + (.+1|tostring)}]}' > "$worker_tasks"
            progress_update "brain${brain_id}_senior${sid}" "running" "tasks_prepared"
        done
    done
    log_info "phase=seniors complete"
}

run_workers() {
    log_info "phase=workers start (dry_run=$DRY_RUN)"
    for tasks in "$LOG_DIR"/workers/*_tasks.json; do
        [[ -f "$tasks" ]] || continue
        local prefix
        prefix="$(basename "$tasks" _tasks.json)"
        jq -c '.workers[]' "$tasks" | while read -r worker; do
            local wid
            wid="$(jq -r '.id' <<<"$worker")"
            local outfile="$LOG_DIR/results/${prefix}_worker${wid}.jsonl"
            if [[ "$DRY_RUN" == "1" ]]; then
                echo "{\"worker\":\"$prefix-$wid\",\"note\":\"DRY_RUN\"}" >> "$outfile"
                progress_update "${prefix}_worker${wid}" "done" "dry_run"
            else
                # Placeholder: integrate actual Codex calls here
                echo "{\"worker\":\"$prefix-$wid\",\"result\":\"TODO\"}" >> "$outfile"
                progress_update "${prefix}_worker${wid}" "done" "complete"
            fi
        done
    done
    log_info "phase=workers complete"
}

merge_all() {
    log_info "phase=merge start"
    # Simple merge: concatenate worker results
    local merged="$LOG_DIR/results/merged_workers.jsonl"
    merge_jsonl "$merged" "$LOG_DIR"/results/*.jsonl
    cp "$merged" "$LOG_DIR/final_result.jsonl"
    log_info "phase=merge complete | final=$LOG_DIR/final_result.jsonl"
}

run_brain
run_seniors
run_workers
merge_all

log_info "hierarchical swarm complete | run_dir=$LOG_DIR"
exit 0
