#!/usr/bin/env bash
# job_pool.sh - Concurrency-limited job execution
# Source this file and use job_pool_add/wait to control parallelism.

set -euo pipefail

JOB_POOL_MAX="${JOB_POOL_MAX:-4}"
JOB_POOL_PIDS=()

job_pool_add() {
    local cmd="$1"

    while [[ ${#JOB_POOL_PIDS[@]} -ge $JOB_POOL_MAX ]]; do
        job_pool_reap
        sleep 0.1
    done

    eval "$cmd" &
    JOB_POOL_PIDS+=($!)
}

job_pool_reap() {
    local keep=()
    for pid in "${JOB_POOL_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            keep+=("$pid")
        fi
    done
    JOB_POOL_PIDS=("${keep[@]}")
}

job_pool_wait() {
    for pid in "${JOB_POOL_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    JOB_POOL_PIDS=()
}
