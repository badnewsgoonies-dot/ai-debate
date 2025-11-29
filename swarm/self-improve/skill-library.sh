#!/bin/bash
# skill-library.sh - Voyager-style skill accumulation
# Pattern: Execute → Succeed → Extract skill → Store → Retrieve later
#
# Usage:
#   ./skill-library.sh add "description" "commands"  # Add a skill
#   ./skill-library.sh find "query"                  # Find relevant skills
#   ./skill-library.sh run "task"                    # Run task with skill retrieval

set -euo pipefail

SKILL_DIR="$(dirname "$0")/../skills"
SKILL_FILE="$SKILL_DIR/skills.jsonl"
mkdir -p "$SKILL_DIR"
touch "$SKILL_FILE"

ACTION="${1:-help}"
shift || true

case "$ACTION" in
    add)
        # Add a new skill
        DESCRIPTION="${1:-}"
        COMMANDS="${2:-}"

        if [ -z "$DESCRIPTION" ] || [ -z "$COMMANDS" ]; then
            echo "Usage: ./skill-library.sh add \"description\" \"commands\""
            exit 1
        fi

        # Extract tags with Claude
        TAGS=$(claude -p "Extract 3-5 keyword tags from this description. Return as comma-separated lowercase words only: $DESCRIPTION")

        # Store as JSONL
        SKILL_JSON=$(jq -n \
            --arg desc "$DESCRIPTION" \
            --arg cmds "$COMMANDS" \
            --arg tags "$TAGS" \
            --arg ts "$(date -Iseconds)" \
            '{description: $desc, commands: $cmds, tags: $tags, timestamp: $ts}')

        echo "$SKILL_JSON" >> "$SKILL_FILE"
        echo "✓ Skill added: $DESCRIPTION"
        echo "  Tags: $TAGS"
        ;;

    find)
        # Find relevant skills
        QUERY="${1:-}"

        if [ -z "$QUERY" ]; then
            echo "Usage: ./skill-library.sh find \"query\""
            exit 1
        fi

        if [ ! -s "$SKILL_FILE" ]; then
            echo "No skills stored yet. Use 'add' first."
            exit 0
        fi

        # Use Claude to find relevant skills
        SKILLS=$(cat "$SKILL_FILE")

        MATCHES=$(claude -p "
Given this query: $QUERY

Find the most relevant skills from this library:
$SKILLS

Return the top 3 most relevant skills with their commands.
Format:
1. [description]: [commands]
2. ...

If none are relevant, say 'No matching skills found.'
")

        echo "=== Relevant Skills ==="
        echo "$MATCHES"
        ;;

    run)
        # Run a task with skill retrieval
        TASK="${1:-}"

        if [ -z "$TASK" ]; then
            echo "Usage: ./skill-library.sh run \"task description\""
            exit 1
        fi

        RUN_DIR="$(dirname "$0")/../runs/skill_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$RUN_DIR"

        echo "=== SKILL-AUGMENTED EXECUTION ==="
        echo "Task: $TASK"
        echo ""

        # Retrieve relevant skills
        SKILLS=""
        if [ -s "$SKILL_FILE" ]; then
            SKILLS=$(cat "$SKILL_FILE")
        fi

        # Execute with Codex, providing skill context
        echo "[1] Executing with skill context..."
        RESULT=$(codex exec -m gpt-5.1-codex-max -c reasoning.effort=high --sandbox danger-full-access "
You have access to these learned skills:
$SKILLS

Task to complete: $TASK

1. Check if any skills are relevant
2. Use or adapt them if helpful
3. Execute the task
4. Report success or failure
" 2>&1)

        echo "$RESULT" > "$RUN_DIR/execution.log"
        echo "$RESULT" | tail -30

        # If successful, extract and store new skill
        if echo "$RESULT" | grep -qiE "success|completed|done"; then
            echo ""
            echo "[2] Success! Extracting new skill..."

            NEW_SKILL=$(claude -p "
Extract a reusable skill from this successful execution:

Task: $TASK
Execution: $RESULT

Return in this format:
DESCRIPTION: [one line description of what the skill does]
COMMANDS: [the key commands or steps, semicolon-separated]

If no generalizable skill, say 'NO_SKILL'
")

            if ! echo "$NEW_SKILL" | grep -q "NO_SKILL"; then
                DESC=$(echo "$NEW_SKILL" | grep "DESCRIPTION:" | sed 's/DESCRIPTION: //')
                CMDS=$(echo "$NEW_SKILL" | grep "COMMANDS:" | sed 's/COMMANDS: //')

                if [ -n "$DESC" ] && [ -n "$CMDS" ]; then
                    "$0" add "$DESC" "$CMDS"
                    echo "  New skill extracted and stored!"
                fi
            fi
        fi

        echo ""
        echo "=== EXECUTION COMPLETE ==="
        echo "Log: $RUN_DIR/execution.log"
        ;;

    list)
        # List all skills
        if [ ! -s "$SKILL_FILE" ]; then
            echo "No skills stored yet."
            exit 0
        fi

        echo "=== SKILL LIBRARY ==="
        cat "$SKILL_FILE" | jq -r '"[\(.tags)] \(.description)"'
        echo ""
        echo "Total: $(wc -l < "$SKILL_FILE") skills"
        ;;

    clear)
        # Clear all skills
        rm -f "$SKILL_FILE"
        echo "✓ Skill library cleared."
        ;;

    *)
        echo "skill-library.sh - Voyager-style skill accumulation"
        echo ""
        echo "Usage:"
        echo "  ./skill-library.sh add \"description\" \"commands\"  # Add a skill"
        echo "  ./skill-library.sh find \"query\"                   # Find relevant skills"
        echo "  ./skill-library.sh run \"task\"                     # Run with skill retrieval"
        echo "  ./skill-library.sh list                            # List all skills"
        echo "  ./skill-library.sh clear                           # Clear library"
        ;;
esac
