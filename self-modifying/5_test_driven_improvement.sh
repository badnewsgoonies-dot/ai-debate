#!/usr/bin/env bash
set -euo pipefail

# PATTERN 5: TEST-DRIVEN SELF-IMPROVEMENT
# Tests serve as the fitness function. Agent iterates until all tests pass.
#
# Why this matters for AI agents:
# - Clear objective: pass the tests
# - Automatic validation of improvements
# - Prevents regression (old tests keep passing)
# - Can run unattended

WORK_DIR="/tmp/tdd_self_improvement"
IMPL_FILE="$WORK_DIR/solution.py"
TEST_FILE="$WORK_DIR/test_solution.py"
HISTORY_FILE="$WORK_DIR/history.jsonl"

initialize() {
    mkdir -p "$WORK_DIR"

    # Create test suite (the specification)
    cat > "$TEST_FILE" <<'EOF'
import unittest
from solution import parse_url

class TestURLParser(unittest.TestCase):
    def test_basic_http(self):
        result = parse_url("http://example.com/path")
        self.assertEqual(result["scheme"], "http")
        self.assertEqual(result["host"], "example.com")
        self.assertEqual(result["path"], "/path")

    def test_with_port(self):
        result = parse_url("https://example.com:8080/api")
        self.assertEqual(result["scheme"], "https")
        self.assertEqual(result["host"], "example.com")
        self.assertEqual(result["port"], 8080)
        self.assertEqual(result["path"], "/api")

    def test_with_query(self):
        result = parse_url("http://example.com/search?q=test&limit=10")
        self.assertEqual(result["query"], {"q": "test", "limit": "10"})

    def test_with_fragment(self):
        result = parse_url("http://example.com/page#section")
        self.assertEqual(result["fragment"], "section")

if __name__ == "__main__":
    unittest.main()
EOF

    # Initial (wrong) implementation
    cat > "$IMPL_FILE" <<'EOF'
def parse_url(url):
    # TODO: implement URL parser
    return {}
EOF

    echo "{}" > "$HISTORY_FILE"
}

run_tests() {
    cd "$WORK_DIR"
    if python3 -m pytest test_solution.py -v 2>&1; then
        return 0
    else
        return 1
    fi
}

get_test_output() {
    cd "$WORK_DIR"
    python3 -m pytest test_solution.py -v 2>&1 || true
}

count_passing_tests() {
    local output="$1"
    echo "$output" | grep -oP '\d+(?= passed)' || echo "0"
}

count_failing_tests() {
    local output="$1"
    echo "$output" | grep -oP '\d+(?= failed)' || echo "0"
}

improve_code() {
    local iteration="$1"
    local current_code=$(cat "$IMPL_FILE")
    local test_output=$(get_test_output)

    local prompt="You are improving a Python implementation to pass unit tests.

Current implementation:
\`\`\`python
$current_code
\`\`\`

Test output:
\`\`\`
$test_output
\`\`\`

Output ONLY the improved Python code for solution.py. Make minimal changes to fix failing tests. No explanations."

    echo "$prompt" | claude -p "$(cat)" > "$IMPL_FILE.new"

    # Extract code from potential markdown
    if grep -q '```python' "$IMPL_FILE.new"; then
        sed -n '/```python/,/```/p' "$IMPL_FILE.new" | sed '1d;$d' > "$IMPL_FILE"
    elif grep -q '```' "$IMPL_FILE.new"; then
        sed -n '/```/,/```/p' "$IMPL_FILE.new" | sed '1d;$d' > "$IMPL_FILE"
    else
        mv "$IMPL_FILE.new" "$IMPL_FILE"
    fi

    rm -f "$IMPL_FILE.new"
}

log_iteration() {
    local iteration="$1"
    local passing="$2"
    local failing="$3"

    echo "{\"iteration\": $iteration, \"passing\": $passing, \"failing\": $failing, \"timestamp\": $(date +%s)}" >> "$HISTORY_FILE"
}

main() {
    echo "=== TEST-DRIVEN SELF-IMPROVEMENT ==="
    echo ""

    initialize

    local max_iterations=10
    local iteration=0

    echo "📝 Test suite created (4 tests)"
    echo "🔧 Initial implementation (empty)"
    echo ""

    while (( iteration < max_iterations )); do
        iteration=$((iteration + 1))

        echo "Iteration $iteration"
        echo "─────────────────"

        test_output=$(get_test_output)
        passing=$(count_passing_tests "$test_output")
        failing=$(count_failing_tests "$test_output")

        echo "  Tests: $passing passed, $failing failed"

        log_iteration "$iteration" "$passing" "$failing"

        if [[ "$failing" == "0" ]] && [[ "$passing" != "0" ]]; then
            echo ""
            echo "🎉 All tests passing! Self-improvement complete."
            echo ""
            echo "Final implementation:"
            cat "$IMPL_FILE"
            return 0
        fi

        echo "  → Asking LLM to improve code..."
        improve_code "$iteration"

        echo ""
    done

    echo "⚠️  Max iterations reached. Final status:"
    get_test_output | tail -5
}

main
