#!/usr/bin/env bash
# Auto-effort Codex wrapper for swarm orchestration
# Usage: source this file, then call codex_auto "prompt" [role]
#
# Roles:
#   brain   → xhigh  (architecture, planning, complex reasoning)
#   senior  → high   (implementation, debugging, review)
#   worker  → medium (straightforward tasks)
#   drone   → low    (simple execution, file ops)
#   auto    → detect from prompt (default)
#
# Environment overrides:
#   EFFORT_OVERRIDE=low|medium|high|xhigh  - force specific effort
#   CODEX_MODEL=gpt-5.1-codex-max          - model to use (default)
#   CODEX_SANDBOX=workspace-write          - sandbox mode
#   CODEX_TIMEOUT=120                      - timeout in seconds
#
# Example:
#   source swarm/lib/codex_auto.sh
#   codex_auto "Design the caching architecture" brain
#   codex_auto "Run the tests and fix failures"       # auto-detects: senior
#   codex_auto "List files in src/"                   # auto-detects: drone

set -euo pipefail

# Default config
CODEX_MODEL="${CODEX_MODEL:-gpt-5.1-codex-max}"
CODEX_SANDBOX="${CODEX_SANDBOX:-workspace-write}"
CODEX_TIMEOUT="${CODEX_TIMEOUT:-120}"

# Keywords that suggest high reasoning effort
BRAIN_KEYWORDS="architect|design|plan|strategy|trade-?off|complex|system|framework|decide|evaluate|compare|analyze|research|investigate|why|how should"
SENIOR_KEYWORDS="implement|fix|debug|refactor|review|test|optimize|improve|update|modify|integrate|handle"
DRONE_KEYWORDS="list|echo|print|cat|ls|run|execute|count|find|grep|show|display|check version"

# Detect effort level from prompt content
detect_effort() {
    local prompt="$1"
    local len=${#prompt}

    # Check for drone keywords FIRST (simple ops override length)
    if echo "$prompt" | grep -qiE "^($DRONE_KEYWORDS)"; then
        echo "low"
        return
    fi

    # Check for brain-level keywords (complex reasoning)
    if echo "$prompt" | grep -qiE "$BRAIN_KEYWORDS"; then
        # Long complex prompts get xhigh
        if [[ $len -gt 300 ]]; then
            echo "xhigh"
        else
            echo "high"
        fi
        return
    fi

    # Check for senior-level keywords (implementation work)
    if echo "$prompt" | grep -qiE "$SENIOR_KEYWORDS"; then
        # Medium-length impl tasks get high, short ones medium
        if [[ $len -gt 100 ]]; then
            echo "high"
        else
            echo "medium"
        fi
        return
    fi

    # Very short prompts without keywords → drone
    if [[ $len -lt 30 ]]; then
        echo "low"
        return
    fi

    # Default to medium for ambiguous prompts
    echo "medium"
}

# Map role to effort level
role_to_effort() {
    local role="$1"
    case "$role" in
        brain)  echo "xhigh" ;;
        senior) echo "high" ;;
        worker) echo "medium" ;;
        drone)  echo "low" ;;
        *)      echo "medium" ;;
    esac
}

# Select effort: override > explicit role > auto-detect
select_effort() {
    local prompt="$1"
    local role="${2:-auto}"

    # Environment override takes precedence
    if [[ -n "${EFFORT_OVERRIDE:-}" ]]; then
        echo "$EFFORT_OVERRIDE"
        return
    fi

    # Explicit role
    if [[ "$role" != "auto" ]]; then
        role_to_effort "$role"
        return
    fi

    # Auto-detect from prompt
    detect_effort "$prompt"
}

# Main wrapper function
# Usage: codex_auto "prompt" [role] [extra_args...]
codex_auto() {
    local prompt="$1"
    local role="${2:-auto}"
    shift 2 2>/dev/null || shift 1 2>/dev/null || true
    local extra_args=("$@")

    local effort
    effort=$(select_effort "$prompt" "$role")

    # Log if log function exists (from common.sh)
    if declare -f log >/dev/null 2>&1; then
        log "codex_auto: role=$role effort=$effort model=$CODEX_MODEL"
    else
        echo "[codex_auto] role=$role effort=$effort model=$CODEX_MODEL" >&2
    fi

    # Build command
    local cmd=(
        codex exec
        -m "$CODEX_MODEL"
        -c "model_reasoning_effort=\"$effort\""
        --sandbox "$CODEX_SANDBOX"
        --full-auto
    )

    # Add extra args if any
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        cmd+=("${extra_args[@]}")
    fi

    # Add prompt last
    cmd+=("$prompt")

    # Execute with optional timeout
    if [[ "$CODEX_TIMEOUT" -gt 0 ]]; then
        timeout "$CODEX_TIMEOUT" "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
}

# Convenience wrappers for common roles
codex_brain() {
    codex_auto "$1" brain "${@:2}"
}

codex_senior() {
    codex_auto "$1" senior "${@:2}"
}

codex_worker() {
    codex_auto "$1" worker "${@:2}"
}

codex_drone() {
    codex_auto "$1" drone "${@:2}"
}

# Quick test function
codex_auto_test() {
    echo "=== Effort Detection Tests ==="
    local tests=(
        "ls -la"
        "echo hello"
        "Implement error handling for the API endpoints"
        "Design the caching architecture for our microservices"
        "Fix the bug in the login form"
        "Analyze the trade-offs between Redis and Memcached for our use case, considering our specific requirements around consistency, persistence, and cluster management"
    )

    for t in "${tests[@]}"; do
        local effort
        effort=$(detect_effort "$t")
        printf "%-8s | %s\n" "$effort" "${t:0:60}"
    done
}

# Export functions for subshells
export -f codex_auto codex_brain codex_senior codex_worker codex_drone
export -f select_effort detect_effort role_to_effort
