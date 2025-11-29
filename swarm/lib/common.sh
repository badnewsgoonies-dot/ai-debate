#!/usr/bin/env bash
# Shared helpers for swarm scripts

# Caller should already set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

init_log_dir() {
    local name="${1:-run}"
    LOG_DIR="${LOG_DIR:-$SCRIPT_ROOT/runs/${name}_$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/session.log"
    log "Log dir: $LOG_DIR"
}

log() {
    local ts msg
    ts="$(date '+%H:%M:%S')"
    msg="$*"
    printf '[%s] %s\n' "$ts" "$msg" | tee -a "${LOG_FILE:-/dev/null}"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing command: $cmd" >&2
        exit 1
    fi
}

write_jsonl() {
    local line="$1"
    local file="$2"
    printf '%s\n' "$line" >> "$file"
}

validate_json_file() {
    local file="$1"
    if ! jq empty "$file" >/dev/null 2>&1; then
        echo "Invalid JSON in $file; saving raw output and aborting." >&2
        mv "$file" "${file%.json}.raw.txt"
        exit 1
    fi
}
