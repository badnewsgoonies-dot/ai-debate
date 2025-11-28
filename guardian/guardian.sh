#!/usr/bin/env bash
#
# Guardian - Vale Chronicles Mechanics Auditor
# Watches AI outputs and blocks rule violations
#
# Usage:
#   Standalone:  ./guardian.sh [file-to-watch]
#   With tmux:   Source this and call add_guardian_pane SESSION_NAME
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK="$SCRIPT_DIR/guardian-framework.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Load framework into variable for prompting
load_framework() {
    if [[ -f "$FRAMEWORK" ]]; then
        cat "$FRAMEWORK"
    else
        echo "ERROR: Framework file not found at $FRAMEWORK"
        exit 1
    fi
}

# Guardian prompt builder
build_guardian_prompt() {
    local content="$1"
    local framework
    framework=$(load_framework)

    cat <<EOF
$framework

═══════════════════════════════════════════════════════════════
CONTENT TO AUDIT
═══════════════════════════════════════════════════════════════

$content

───────────────────────────────────────────────────────────────
Audit this content. Stay SILENT if correct. Say "⛔ BLOCKED" only if you find a rule violation.
EOF
}

# Watch mode - monitors a file for changes and audits each update
watch_file() {
    local file="$1"
    local last_content=""

    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║  🛡️  GUARDIAN - MECHANICS AUDITOR      ║${RESET}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${DIM}Watching: $file${RESET}"
    echo -e "${DIM}Will audit all AI outputs for rule violations${RESET}"
    echo ""

    while true; do
        if [[ -f "$file" ]]; then
            current=$(cat "$file" 2>/dev/null || echo "")

            if [[ "$current" != "$last_content" ]] && [[ -n "$current" ]]; then
                last_content="$current"

                echo -e "${DIM}─────────────────────────────────────────${RESET}"
                echo -e "${YELLOW}[Auditing new content...]${RESET}"

                prompt=$(build_guardian_prompt "$current")
                result=$(claude -p "$prompt" 2>/dev/null || echo "[Guardian offline]")

                if echo "$result" | grep -q "BLOCKED"; then
                    echo -e "${RED}${BOLD}$result${RESET}"
                elif [[ -n "$result" ]] && [[ "$result" != *"[Guardian offline]"* ]]; then
                    # Guardian spoke but didn't block - might be a warning
                    echo -e "${YELLOW}$result${RESET}"
                else
                    echo -e "${GREEN}✓ No violations${RESET}"
                fi
                echo ""
            fi
        fi
        sleep 1
    done
}

# Audit a single piece of content
audit_once() {
    local content="$1"
    prompt=$(build_guardian_prompt "$content")
    claude -p "$prompt"
}

# Add guardian pane to existing tmux session
add_guardian_pane() {
    local session="$1"
    local watch_file="${2:-}"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "Error: tmux session '$session' not found"
        return 1
    fi

    # Split and add guardian pane
    tmux split-window -h -t "$session" -l 50
    tmux select-pane -t "$session:.2" -T "Guardian"

    if [[ -n "$watch_file" ]]; then
        tmux send-keys -t "$session:.2" "'$SCRIPT_DIR/guardian.sh' '$watch_file'" Enter
    else
        tmux send-keys -t "$session:.2" "'$SCRIPT_DIR/guardian.sh'" Enter
    fi
}

# Interactive mode - paste content to audit
interactive_mode() {
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║  🛡️  GUARDIAN - INTERACTIVE MODE       ║${RESET}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${DIM}Paste AI output to audit, then press Ctrl+D${RESET}"
    echo -e "${DIM}Or type 'q' to quit${RESET}"
    echo ""

    while true; do
        echo -e "${YELLOW}───── Paste content to audit ─────${RESET}"
        content=""
        while IFS= read -r line; do
            if [[ "$line" == "q" ]] && [[ -z "$content" ]]; then
                echo -e "${DIM}Goodbye!${RESET}"
                exit 0
            fi
            content+="$line"$'\n'
        done

        if [[ -n "$content" ]]; then
            echo ""
            echo -e "${DIM}[Auditing...]${RESET}"
            audit_once "$content"
            echo ""
        fi
    done
}

# Main
case "${1:-}" in
    --help|-h)
        echo "Guardian - Vale Chronicles Mechanics Auditor"
        echo ""
        echo "Usage:"
        echo "  ./guardian.sh                    Interactive mode (paste content)"
        echo "  ./guardian.sh <file>             Watch file for changes"
        echo "  ./guardian.sh --audit <text>     Audit single piece of content"
        echo ""
        echo "With tmux (source this script):"
        echo "  add_guardian_pane SESSION_NAME [watch_file]"
        ;;
    --audit)
        shift
        audit_once "$*"
        ;;
    "")
        interactive_mode
        ;;
    *)
        watch_file "$1"
        ;;
esac
