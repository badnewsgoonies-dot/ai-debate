#!/usr/bin/env bash
# log.sh - structured logging + metadata helpers
# Usage: source this in your scripts.

set -euo pipefail

# Default log level if not set
LOG_LEVEL="${LOG_LEVEL:-INFO}"

timestamp() {
    date -Is
}

log_json() {
    local level="$1"; shift
    local msg="$*"
    printf '{"ts":"%s","level":"%s","message":%s}\n' "$(timestamp)" "$level" "$(printf '%s' "$msg" | jq -Rs .)"
}

log() {
    log_json "$LOG_LEVEL" "$*"
}

log_info() { log_json "INFO" "$*"; }
log_warn() { log_json "WARN" "$*"; }
log_error() { log_json "ERROR" "$*"; }

init_run_dir() {
    local name="${1:-run}"
    LOG_DIR="${LOG_DIR:-$SCRIPT_ROOT/runs/${name}_$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/session.log"
    log_info "log_dir=$LOG_DIR"
}

write_meta_json() {
    local file="$1"; shift
    jq -n --arg ts "$(timestamp)" "$@" > "$file"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "missing_command=$1"
        exit 1
    fi
}
