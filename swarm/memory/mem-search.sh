#!/usr/bin/env bash
#
# mem-search.sh - Query memory anchors with filters
#
# Usage:
#   ./mem-search.sh [filters...]
#
# Filters:
#   t=decision|question|action|fact|note  - Filter by type (or d/q/a/f/n)
#   topic=memory                          - Filter by topic
#   session=memory_planning               - Filter by session ID
#   source=claude-chat                    - Filter by source
#   since=2025-11-25                      - Only entries after date
#   until=2025-11-30                      - Only entries before date
#   text=keyword                          - Search in text field
#   status=pending|done                   - Filter by action/choice field
#   choice=E5-large-v2                    - Filter by choice field
#   limit=10                              - Max results (default: 20)
#
# Examples:
#   ./mem-search.sh t=d topic=memory
#   ./mem-search.sh since=2025-11-29 limit=5
#   ./mem-search.sh text=compression
#
# Output:
#   Human-readable by default, or --json for raw JSONL
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_FILE="${MEMORY_FILE:-$SCRIPT_DIR/anchors.jsonl}"

# Defaults
LIMIT=20
OUTPUT_JSON=0

# Type abbreviation map
type_expand() {
    case "$1" in
        d|decision) echo "d" ;;
        q|question) echo "q" ;;
        a|action)   echo "a" ;;
        f|fact)     echo "f" ;;
        n|note)     echo "n" ;;
        *) echo "$1" ;;
    esac
}

# Build jq filter from args
build_filter() {
    local filter="true"

    for arg in "$@"; do
        [[ "$arg" == "--json" ]] && continue

        local key="${arg%%=*}"
        local val="${arg#*=}"

        case "$key" in
            t|type)
                val=$(type_expand "$val")
                filter="$filter and .[0] == \"$val\""
                ;;
            topic)
                filter="$filter and .[1] == \"$val\""
                ;;
            text)
                filter="$filter and (.[2] | test(\"$val\"; \"i\"))"
                ;;
            session)
                filter="$filter and .[6] == \"$val\""
                ;;
            source)
                filter="$filter and .[7] == \"$val\""
                ;;
            status)
                # For actions, status is stored in the choice slot (index 3)
                filter="$filter and .[3] == \"$val\""
                ;;
            choice)
                # Choice/status share the same field (index 3)
                filter="$filter and .[3] == \"$val\""
                ;;
            since)
                filter="$filter and .[5] >= \"${val}T00:00:00Z\""
                ;;
            until)
                filter="$filter and .[5] <= \"${val}T23:59:59Z\""
                ;;
            limit)
                LIMIT="$val"
                ;;
        esac
    done

    echo "$filter"
}

# Pretty print an anchor
pretty_print() {
    local line="$1"
    local t topic text choice rationale ts session source

    t=$(echo "$line" | jq -r '.[0]')
    topic=$(echo "$line" | jq -r '.[1]')
    text=$(echo "$line" | jq -r '.[2]')
    choice=$(echo "$line" | jq -r '.[3] // empty')
    ts=$(echo "$line" | jq -r '.[5] // "?"')
    session=$(echo "$line" | jq -r '.[6] // empty')

    # Type labels
    local type_label
    case "$t" in
        d) type_label="DECISION" ;;
        q) type_label="QUESTION" ;;
        a) type_label="ACTION" ;;
        f) type_label="FACT" ;;
        n) type_label="NOTE" ;;
        *) type_label="$t" ;;
    esac

    # Format output
    printf "\033[1;36m[%s]\033[0m \033[1;33m%s\033[0m\n" "$type_label" "$topic"
    printf "  %s\n" "$text"
    [[ -n "$choice" ]] && printf "  \033[32mChoice:\033[0m %s\n" "$choice"
    printf "  \033[90m%s | %s\033[0m\n" "${ts:0:10}" "$session"
    echo
}

main() {
    # Check for --json flag
    for arg in "$@"; do
        [[ "$arg" == "--json" ]] && OUTPUT_JSON=1
    done

    if [[ ! -f "$MEMORY_FILE" ]]; then
        echo "Memory file not found: $MEMORY_FILE" >&2
        exit 1
    fi

    local filter
    filter=$(build_filter "$@")

    # Skip comment lines, apply filter, limit results
    local results
    results=$(grep -v '^#' "$MEMORY_FILE" | jq -c "select($filter)" 2>/dev/null | head -n "$LIMIT")

    if [[ -z "$results" ]]; then
        echo "No matches found." >&2
        exit 0
    fi

    if [[ "$OUTPUT_JSON" -eq 1 ]]; then
        echo "$results"
    else
        echo "$results" | while IFS= read -r line; do
            pretty_print "$line"
        done
    fi
}

main "$@"
