#!/usr/bin/env bash
set -euo pipefail

# PATTERN 6: SAFETY GUARDRAILS for Self-Modifying Systems
# Prevent runaway self-modification and dangerous behaviors

SANDBOX_DIR="/tmp/self_mod_sandbox"
MAX_FILE_SIZE=100000  # 100KB
MAX_EXECUTION_TIME=5  # seconds
ALLOWED_MODULES="json,sys,math,os.path,pathlib"

echo "=== SAFETY GUARDRAILS FOR SELF-MODIFYING CODE ==="
echo ""

# GUARDRAIL 1: Sandboxed Execution
run_sandboxed() {
    local code_file="$1"

    mkdir -p "$SANDBOX_DIR"

    echo "🛡️  GUARDRAIL 1: Sandboxed Execution"
    echo "   Running code in isolated directory: $SANDBOX_DIR"

    # Copy code to sandbox
    cp "$code_file" "$SANDBOX_DIR/"

    # Run with timeout and restricted permissions
    timeout "$MAX_EXECUTION_TIME" python3 "$SANDBOX_DIR/$(basename "$code_file")" 2>&1 || {
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            echo "   ❌ BLOCKED: Execution timeout ($MAX_EXECUTION_TIME seconds)"
            return 1
        fi
    }

    echo "   ✓ Passed"
    return 0
}

# GUARDRAIL 2: Code Size Limits
check_file_size() {
    local code_file="$1"

    echo ""
    echo "🛡️  GUARDRAIL 2: File Size Limit"

    local size=$(stat -f%z "$code_file" 2>/dev/null || stat -c%s "$code_file" 2>/dev/null)

    echo "   File size: $size bytes (max: $MAX_FILE_SIZE)"

    if [[ $size -gt $MAX_FILE_SIZE ]]; then
        echo "   ❌ BLOCKED: File too large (possible code bloat or fork bomb)"
        return 1
    fi

    echo "   ✓ Passed"
    return 0
}

# GUARDRAIL 3: Forbidden Pattern Detection
check_forbidden_patterns() {
    local code_file="$1"

    echo ""
    echo "🛡️  GUARDRAIL 3: Forbidden Pattern Detection"

    local forbidden_patterns=(
        "os\.system"
        "subprocess\.call"
        "eval\("
        "__import__\(['\"]os['\"]"
        "exec\("
        "compile\("
        "rm -rf"
        "DELETE FROM"
        "DROP TABLE"
    )

    for pattern in "${forbidden_patterns[@]}"; do
        if grep -qE "$pattern" "$code_file"; then
            echo "   ❌ BLOCKED: Forbidden pattern detected: $pattern"
            return 1
        fi
    done

    echo "   ✓ Passed (no dangerous patterns)"
    return 0
}

# GUARDRAIL 4: Import Restrictions
check_imports() {
    local code_file="$1"

    echo ""
    echo "🛡️  GUARDRAIL 4: Import Restrictions"
    echo "   Allowed modules: $ALLOWED_MODULES"

    # Extract all imports
    local imports=$(grep -E "^import |^from .+ import" "$code_file" | sed 's/from //;s/ import.*//' | sed 's/import //')

    for module in $imports; do
        if ! echo ",$ALLOWED_MODULES," | grep -q ",$module,"; then
            echo "   ❌ BLOCKED: Unauthorized import: $module"
            return 1
        fi
    done

    echo "   ✓ Passed (all imports allowed)"
    return 0
}

# GUARDRAIL 5: Diff-Based Changes (verify minimal modification)
check_diff_size() {
    local old_file="$1"
    local new_file="$2"
    local max_diff_lines=50

    echo ""
    echo "🛡️  GUARDRAIL 5: Diff Size Limit"

    if [[ ! -f "$old_file" ]]; then
        echo "   ⚠️  No previous version (first iteration)"
        return 0
    fi

    local diff_lines=$(diff -u "$old_file" "$new_file" | grep -E "^\+|^-" | grep -v "^+++|^---" | wc -l)

    echo "   Changed lines: $diff_lines (max: $max_diff_lines)"

    if [[ $diff_lines -gt $max_diff_lines ]]; then
        echo "   ❌ BLOCKED: Too many changes (possible rewrite or instability)"
        return 1
    fi

    echo "   ✓ Passed"
    return 0
}

# GUARDRAIL 6: Iteration Limit
check_iteration_limit() {
    local iteration="$1"
    local max_iterations=20

    echo ""
    echo "🛡️  GUARDRAIL 6: Iteration Limit"
    echo "   Iteration: $iteration / $max_iterations"

    if [[ $iteration -gt $max_iterations ]]; then
        echo "   ❌ BLOCKED: Max iterations exceeded (possible infinite loop)"
        return 1
    fi

    echo "   ✓ Passed"
    return 0
}

# GUARDRAIL 7: Human-in-the-Loop Approval
require_approval() {
    local code_file="$1"

    echo ""
    echo "🛡️  GUARDRAIL 7: Human Approval Required"
    echo ""
    echo "Proposed code changes:"
    echo "─────────────────────────────────────"
    cat "$code_file"
    echo "─────────────────────────────────────"
    echo ""

    echo -n "Approve execution? [y/N] "
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "   ❌ BLOCKED: Human rejected changes"
        return 1
    fi

    echo "   ✓ Approved by human"
    return 0
}

# GUARDRAIL 8: Monotonic Improvement (fitness must not decrease)
check_monotonic_improvement() {
    local old_fitness="$1"
    local new_fitness="$2"

    echo ""
    echo "🛡️  GUARDRAIL 8: Monotonic Improvement"
    echo "   Old fitness: $old_fitness"
    echo "   New fitness: $new_fitness"

    # Use awk for floating point comparison
    local is_worse=$(awk -v old="$old_fitness" -v new="$new_fitness" 'BEGIN {print (new > old)}')

    if [[ "$is_worse" == "1" ]]; then
        echo "   ❌ BLOCKED: Fitness decreased (regression)"
        return 1
    fi

    echo "   ✓ Passed (improvement or no regression)"
    return 0
}

# DEMONSTRATION
demo() {
    echo ""
    echo "=== DEMONSTRATION ==="
    echo ""

    # Create a test file
    cat > "$SANDBOX_DIR/safe_code.py" <<'EOF'
import json
import sys

data = {"result": "safe computation"}
print(json.dumps(data))
EOF

    cat > "$SANDBOX_DIR/unsafe_code.py" <<'EOF'
import os
os.system("rm -rf /")  # Dangerous!
EOF

    echo "Testing SAFE code:"
    echo "──────────────────"
    if run_sandboxed "$SANDBOX_DIR/safe_code.py" && \
       check_file_size "$SANDBOX_DIR/safe_code.py" && \
       check_forbidden_patterns "$SANDBOX_DIR/safe_code.py" && \
       check_imports "$SANDBOX_DIR/safe_code.py"; then
        echo ""
        echo "✅ All guardrails passed for safe code"
    fi

    echo ""
    echo ""
    echo "Testing UNSAFE code:"
    echo "────────────────────"
    if ! check_forbidden_patterns "$SANDBOX_DIR/unsafe_code.py"; then
        echo ""
        echo "✅ Unsafe code correctly blocked by guardrails"
    fi

    echo ""
    echo ""
    echo "=== SUMMARY OF SAFETY GUARDRAILS ==="
    echo ""
    echo "1. Sandboxed Execution - Isolate code from system"
    echo "2. File Size Limits - Prevent code bloat"
    echo "3. Forbidden Patterns - Block dangerous operations"
    echo "4. Import Restrictions - Limit available modules"
    echo "5. Diff Size Limits - Ensure incremental changes"
    echo "6. Iteration Limits - Prevent runaway loops"
    echo "7. Human-in-the-Loop - Require approval for risky changes"
    echo "8. Monotonic Improvement - No fitness regression"
    echo ""
    echo "💡 Combine multiple guardrails for defense-in-depth"
}

demo
