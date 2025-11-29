#!/usr/bin/env bash
# progress.sh - Simple progress tracking for parallel tasks
# Requires jq.

set -euo pipefail

PROGRESS_FILE="${PROGRESS_FILE:-$LOG_DIR/progress.json}"

progress_init() {
    echo '{"tasks":{}}' > "$PROGRESS_FILE"
}

progress_update() {
    local task_id="$1" status="$2" message="${3:-}"
    local ts
    ts="$(date -Is)"
    local tmp
    tmp="$(mktemp)"
    jq --arg id "$task_id" --arg status "$status" --arg msg "$message" --arg ts "$ts" \
        '.tasks[$id] = {status:$status, message:$msg, updated:$ts}' \
        "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
}

progress_status() {
    jq -r '.tasks | to_entries | .[] | "\(.key): \(.value.status)"' "$PROGRESS_FILE"
}

progress_summary() {
    jq '{
        total: (.tasks | length),
        done: ([.tasks[] | select(.status == "done")] | length),
        failed: ([.tasks[] | select(.status == "failed")] | length),
        running: ([.tasks[] | select(.status == "running")] | length)
    }' "$PROGRESS_FILE"
}
