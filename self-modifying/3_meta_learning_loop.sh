#!/usr/bin/env bash
set -euo pipefail

# PATTERN 3: META-LEARNING LOOP
# "Learning to Learn" - Improving the learning process itself
#
# The agent tracks what prompting strategies work best and adapts its approach.
# Meta-knowledge: "When I include examples, I get better results"

LEARNING_LOG="/tmp/meta_learning_log.jsonl"
STRATEGY_DB="/tmp/learning_strategies.json"

initialize() {
    echo "=== META-LEARNING LOOP: Learning to Learn ==="
    echo ""

    # Initialize strategy database if it doesn't exist
    if [[ ! -f "$STRATEGY_DB" ]]; then
        cat > "$STRATEGY_DB" <<'EOF'
{
  "strategies": [
    {
      "id": "direct",
      "name": "Direct Question",
      "template": "Question: {task}",
      "success_rate": 0.5,
      "uses": 0
    },
    {
      "id": "chain_of_thought",
      "name": "Chain of Thought",
      "template": "Question: {task}\n\nLet's think step by step:",
      "success_rate": 0.5,
      "uses": 0
    },
    {
      "id": "few_shot",
      "name": "Few-Shot Examples",
      "template": "Here are examples:\nQ: What is 2+2? A: 4\nQ: What is 3+3? A: 6\n\nQ: {task}\nA:",
      "success_rate": 0.5,
      "uses": 0
    }
  ]
}
EOF
    fi

    touch "$LEARNING_LOG"
}

select_strategy() {
    # UCB1 algorithm: balance exploration vs exploitation
    # Select strategy with highest: success_rate + sqrt(2*ln(total_uses)/strategy_uses)

    python3 -c "
import json
import math

with open('$STRATEGY_DB') as f:
    data = json.load(f)

strategies = data['strategies']
total_uses = sum(s['uses'] for s in strategies) + 1

best_score = -1
best_strategy = None

for s in strategies:
    uses = s['uses'] + 1
    exploit = s['success_rate']
    explore = math.sqrt(2 * math.log(total_uses) / uses)
    score = exploit + explore

    if score > best_score:
        best_score = score
        best_strategy = s

print(best_strategy['id'])
"
}

apply_strategy() {
    local strategy_id="$1"
    local task="$2"

    # Get strategy template
    local template=$(jq -r ".strategies[] | select(.id == \"$strategy_id\") | .template" "$STRATEGY_DB")

    # Substitute task
    echo "${template//\{task\}/$task}"
}

evaluate_response() {
    local response="$1"
    local expected_pattern="$2"

    # Simple evaluation: does response match expected pattern?
    if echo "$response" | grep -qiE "$expected_pattern"; then
        echo "1"  # Success
    else
        echo "0"  # Failure
    fi
}

update_strategy_stats() {
    local strategy_id="$1"
    local success="$2"  # 0 or 1

    python3 -c "
import json

with open('$STRATEGY_DB') as f:
    data = json.load(f)

for s in data['strategies']:
    if s['id'] == '$strategy_id':
        old_rate = s['success_rate']
        old_uses = s['uses']

        # Exponential moving average
        alpha = 0.3
        new_rate = alpha * $success + (1 - alpha) * old_rate

        s['success_rate'] = new_rate
        s['uses'] = old_uses + 1
        break

with open('$STRATEGY_DB', 'w') as f:
    json.dump(data, f, indent=2)
"
}

run_learning_episode() {
    local task="$1"
    local expected_pattern="$2"

    echo "Task: $task"

    # Select strategy using meta-learning
    strategy=$(select_strategy)
    echo "Selected strategy: $strategy"

    # Apply strategy
    prompt=$(apply_strategy "$strategy" "$task")
    echo ""
    echo "Prompt:"
    echo "$prompt"
    echo ""

    # Get LLM response
    response=$(claude -p "$prompt")
    echo "Response: $response"

    # Evaluate
    success=$(evaluate_response "$response" "$expected_pattern")

    if [[ "$success" == "1" ]]; then
        echo "✓ Success"
    else
        echo "✗ Failed"
    fi

    # Update meta-knowledge
    update_strategy_stats "$strategy" "$success"

    # Log episode
    echo "{\"task\": \"$task\", \"strategy\": \"$strategy\", \"success\": $success, \"timestamp\": $(date +%s)}" >> "$LEARNING_LOG"

    echo ""
}

show_meta_knowledge() {
    echo "=== Meta-Knowledge (Strategy Performance) ==="
    jq -r '.strategies[] | "  \(.name): \(.success_rate * 100 | round)% success (\(.uses) uses)"' "$STRATEGY_DB"
    echo ""
}

main() {
    initialize

    echo "Running learning episodes..."
    echo ""

    # Series of math tasks
    run_learning_episode "What is 15 + 27?" "42"
    run_learning_episode "What is 100 - 37?" "63"
    run_learning_episode "What is 12 × 8?" "96"
    run_learning_episode "What is 144 ÷ 12?" "12"

    show_meta_knowledge

    echo "The agent has learned which prompting strategies work best!"
    echo "Future tasks will favor successful strategies (exploitation)"
    echo "while still trying new approaches occasionally (exploration)."
}

main
