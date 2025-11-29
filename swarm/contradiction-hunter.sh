#!/usr/bin/env bash
#
# contradiction-hunter.sh - Run small experiments to surface anomalies in "impossible" problems.
#
# Usage:
#   ./contradiction-hunter.sh <research_file> [num_iterators] [max_experiments]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

RESEARCH_FILE="${1:-}"
NUM_ITERATORS="${2:-${NUM_ITERATORS:-2}}"
MAX_EXPERIMENTS="${3:-${MAX_EXPERIMENTS:-10}}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.1-codex-max}"
BRAIN_EFFORT="${BRAIN_EFFORT:-xhigh}"
DRONE_EFFORT="${DRONE_EFFORT:-low}"
REVIEWER_CMD="${REVIEWER_CMD:-claude -p}"
TIMEOUT_SECS="${TIMEOUT_SECS:-10}"
DRY_RUN="${DRY_RUN:-0}"

SCRIPT_NAME="contradiction-hunter"
WORK_DIR=""
PYTHON_BIN=""

# Detect python interpreter (python3 preferred, fallback to python)
detect_python() {
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
    else
        log "WARNING: No python or python3 found. Python experiments will fail."
        PYTHON_BIN="python"  # Will error but at least shows clear message
    fi
    log "Python interpreter: $PYTHON_BIN"
}

# Normalize code to use detected python interpreter
normalize_python_code() {
    local code="$1"
    # Replace 'python -' and 'python <<' with detected interpreter
    # Handle both start of string and after newlines
    code="${code//python -/$PYTHON_BIN -}"
    code="${code//python <</$PYTHON_BIN <<}"
    echo "$code"
}

main() {
    require_cmd codex
    require_cmd jq
    require_cmd timeout
    require_cmd sha1sum
    detect_python

    if [[ -z "$RESEARCH_FILE" || ! -f "$RESEARCH_FILE" ]]; then
        echo "Usage: $0 <research_file> [num_iterators] [max_experiments]" >&2
        exit 1
    fi

    init_log_dir "$SCRIPT_NAME"
    WORK_DIR="$LOG_DIR/work"
    mkdir -p "$WORK_DIR"
    write_meta
    log "=== CONTRADICTION HUNTER ==="
    log "Research: $RESEARCH_FILE"
    log "Iterators: $NUM_ITERATORS | Max experiments: $MAX_EXPERIMENTS"
    log "Dry run: $DRY_RUN"
    log "Codex effort (brain/drone): $BRAIN_EFFORT / $DRONE_EFFORT"

    mine_problems
    generate_experiments
    run_iterators
    review_anomalies

    log "=== HUNT COMPLETE ==="
    log "Logs: $LOG_DIR"
}

codex_run() {
    local effort prompt
    if [[ $# -ge 2 ]]; then
        effort="$1"
        shift
        prompt="$*"
    else
        effort="$BRAIN_EFFORT"
        prompt="$1"
    fi
    codex exec --full-auto \
        -m "$CODEX_MODEL" \
        -c model_reasoning_effort="$effort" \
        --sandbox danger-full-access \
        "$prompt"
}

mine_problems() {
    log "[1/4] Mining problems..."
    local prompt
    prompt=$(cat <<'EOF'
Given this AI research text, list the TOP 5 "impossible/contradictory" problems.
Return JSON array with fields: problem, why_impossible, evidence, suggested_experiment (<=10s).
Only output JSON.
EOF
)
    local content problems
    content="$(cat "$RESEARCH_FILE")"
    problems=$(codex_run "$prompt
---
$content")
    echo "$problems" > "$LOG_DIR/problems.json"
    log "Problems saved to $LOG_DIR/problems.json"
    validate_json_file "$LOG_DIR/problems.json"
}

generate_experiments() {
    log "[2/4] Generating experiments..."
    local prompt experiments
    prompt=$(cat <<EOF
Take these problems and propose small experiments (<=10s each).
Return JSON array of {name, code, expected}.
Keep it shell-friendly and side-effect free.
Limit to $MAX_EXPERIMENTS experiments.

Problems:
$(cat "$LOG_DIR/problems.json")
EOF
)
    experiments=$(codex_run "$DRONE_EFFORT" "$prompt")
    echo "$experiments" > "$LOG_DIR/experiments.json"
    log "Experiments saved to $LOG_DIR/experiments.json"
    validate_json_file "$LOG_DIR/experiments.json"
}

run_iterators() {
    log "[3/4] Running experiments with $NUM_ITERATORS iterators..."
    mkdir -p "$LOG_DIR/experiments" "$LOG_DIR/anomalies"
    : > "$LOG_DIR/anomalies/flagged.jsonl"

    mapfile -t experiment_lines < <(jq -c '.[] | {name,code,expected}' "$LOG_DIR/experiments.json" | head -n "$MAX_EXPERIMENTS")
    if [[ ${#experiment_lines[@]} -eq 0 ]]; then
        log "No experiments found; skipping."
        return
    fi

    for i in $(seq 1 "$NUM_ITERATORS"); do
        (
            local exp_line name code expected result anomaly_line code_hash
            for exp_line in "${experiment_lines[@]}"; do
                name=$(echo "$exp_line" | jq -r '.name')
                code=$(echo "$exp_line" | jq -r '.code')
                expected=$(echo "$exp_line" | jq -r '.expected')
                code_hash=$(printf '%s' "$code" | sha1sum | awk '{print $1}')

                # Normalize python -> python3 if needed
                normalized_code=$(normalize_python_code "$code")

                if is_unsafe_code "$normalized_code"; then
                    result="SKIPPED_UNSAFE"
                elif [[ "$DRY_RUN" -eq 1 ]]; then
                    result="DRY_RUN: $normalized_code"
                else
                    result=$(cd "$WORK_DIR" && timeout "$TIMEOUT_SECS" bash -lc "$normalized_code" 2>&1 || true)
                fi

                write_jsonl "$(jq -nc --arg name "$name" --arg expected "$expected" --arg actual "$result" --arg hash "$code_hash" \
                    '{name:$name,expected:$expected,actual:$actual,code_hash:$hash}')" \
                    "$LOG_DIR/experiments/iterator_${i}.jsonl"

                if [[ "$result" != "$expected" ]] || [[ "$result" == *"ERROR"* ]] || [[ "$result" == *"TIMEOUT"* ]] || [[ "$result" == "SKIPPED_UNSAFE" ]]; then
                    anomaly_line=$(jq -nc --arg iterator "$i" --arg name "$name" --arg expected "$expected" --arg actual "$result" --arg hash "$code_hash" \
                        '{iterator:($iterator|tonumber),name:$name,expected:$expected,actual:$actual,code_hash:$hash}')
                    write_jsonl "$anomaly_line" "$LOG_DIR/anomalies/flagged.jsonl"
                fi
            done
        ) &
    done
    wait

    ANOMALY_COUNT=$(wc -l < "$LOG_DIR/anomalies/flagged.jsonl" 2>/dev/null || echo 0)
    log "Anomalies found: $ANOMALY_COUNT"
}

review_anomalies() {
    log "[4/4] Reviewing anomalies..."
    local anomaly_file="$LOG_DIR/anomalies/flagged.jsonl"
    if [[ ! -s "$anomaly_file" ]]; then
        log "No anomalies to review."
        return
    fi

    if command -v ${REVIEWER_CMD%% *} >/dev/null 2>&1; then
        local prompt insights
        prompt=$(cat <<EOF
You are reviewing anomalies from experiments probing "impossible" problems.
Problems:
$(cat "$LOG_DIR/problems.json")

Anomalies (JSONL):
$(cat "$anomaly_file")

For each anomaly:
- Is it a bug or potentially interesting?
- What assumption might be wrong?
- Could this point toward a solution path?
Return a concise ranked summary.
EOF
)
        insights=$($REVIEWER_CMD "$prompt")
        echo "$insights" > "$LOG_DIR/insights.txt"
        log "Insights saved to $LOG_DIR/insights.txt"
    else
        log "Reviewer command not available: $REVIEWER_CMD"
    fi
}

is_unsafe_code() {
    local code="$1"
    if [[ "$code" =~ rm\ -rf\ / ]] || [[ "$code" =~ :\(\)\{\:\|\:\&\}\:\; ]] || [[ "$code" =~ shutdown ]] || [[ "$code" =~ reboot ]]; then
        return 0
    fi
    return 1
}

write_meta() {
    cat > "$LOG_DIR/meta.json" <<EOF
{
  "script": "$SCRIPT_NAME",
  "timestamp": "$(date -Is)",
  "research_file": "$RESEARCH_FILE",
  "num_iterators": $NUM_ITERATORS,
  "max_experiments": $MAX_EXPERIMENTS,
  "codex_model": "$CODEX_MODEL",
  "codex_effort_brain": "$BRAIN_EFFORT",
  "codex_effort_drone": "$DRONE_EFFORT",
  "timeout_secs": $TIMEOUT_SECS,
  "dry_run": $DRY_RUN
}
EOF
}

main "$@"
