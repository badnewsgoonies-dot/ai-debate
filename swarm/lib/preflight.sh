#!/usr/bin/env bash
# preflight.sh - dependency and env checks
# Usage: source in scripts after setting REQUIRE_CMDS and optional REQUIRED_ENV.

set -euo pipefail

preflight_check() {
    local fail=0
    for cmd in "${REQUIRE_CMDS[@]:-}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Missing command: $cmd" >&2
            fail=1
        }
    done
    for envvar in "${REQUIRED_ENV[@]:-}"; do
        if [[ -z "${!envvar:-}" ]]; then
            echo "Missing env: $envvar" >&2
            fail=1
        fi
    done
    if [[ $fail -ne 0 ]]; then
        exit 1
    fi
}
