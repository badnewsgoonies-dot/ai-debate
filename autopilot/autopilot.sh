#!/usr/bin/env bash
#
# Autopilot - Autonomous User/Developer Simulation
# One AI gives requirements, another implements, until "ship it"
#
# Usage: ./autopilot.sh [feature/task]
# Example: ./autopilot.sh "Add a dark mode toggle to settings"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env" 2>/dev/null || true

# Defaults
USER_CMD="${USER_CMD:-claude -p}"
DEV_CMD="${DEV_CMD:-claude -p}"
USER_NAME="${USER_NAME:-User}"
DEV_NAME="${DEV_NAME:-Developer}"
USER_COLOR="${USER_COLOR:-colour226}"
DEV_COLOR="${DEV_COLOR:-colour46}"
MAX_CYCLES="${MAX_CYCLES:-10}"
PACE="${PACE:-100}"
PAUSE_BETWEEN_TURNS="${PAUSE_BETWEEN_TURNS:-1}"

# Parse flags
HEADLESS=false
while [[ "${1:-}" == -* ]]; do
    case "$1" in
        -H|--headless) HEADLESS=true; shift ;;
        -h|--help)
            echo "Usage: ./autopilot.sh [-H|--headless] [task]"
            echo ""
            echo "Options:"
            echo "  -H, --headless  Run without tmux UI (output to stdout)"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Task from argument or prompt
TASK="${1:-}"
if [[ -z "$TASK" ]] && [[ "$HEADLESS" == false ]]; then
    echo "🤖 Autopilot - User/Developer Simulation"
    echo "═══════════════════════════════════════"
    echo ""
    read -p "Enter feature/task: " TASK
fi

if [[ -z "$TASK" ]]; then
    echo "Error: No task provided"
    [[ "$HEADLESS" == true ]] && echo "Hint: In headless mode, task is required as argument"
    exit 1
fi

# Validate commands
validate_command() {
    local cmd="$1"
    local name="$2"
    local first_word=$(echo "$cmd" | awk '{print $1}')
    if ! command -v "$first_word" &>/dev/null; then
        echo "Error: $name command not found: $first_word"
        exit 1
    fi
}

validate_command "$USER_CMD" "$USER_NAME"
validate_command "$DEV_CMD" "$DEV_NAME"

# Create workspace
WORKSPACE=$(mktemp -d /tmp/autopilot.XXXXXX)
trap "rm -rf $WORKSPACE" EXIT

mkdir -p "$WORKSPACE/user" "$WORKSPACE/dev"

# Create log directory
LOG_DIR="$HOME/.cache/autopilot"
mkdir -p "$LOG_DIR"
SESSION_LOG="$LOG_DIR/session_$(date +%Y%m%d_%H%M%S).log"

# Load frameworks
USER_FRAMEWORK="USER ROLE: You are a product owner giving requirements to a developer.

BEHAVIOR:
- Give clear requirements but leave implementation details to the developer
- Provide feedback on what they show you
- Be realistic - sometimes vague, sometimes change your mind
- Say 'ship it' or 'looks good, deploy it' when satisfied
- Push back if something doesn't meet your needs

RESPONSE FORMAT:
- 50-100 words
- Plain language (no technical jargon)
- Focus on WHAT you want, not HOW to build it
- Be direct about approval or requested changes"

DEV_FRAMEWORK="DEVELOPER ROLE: You are implementing features for a product owner.

BEHAVIOR:
- Ask clarifying questions when requirements are unclear
- Explain your approach in simple terms
- Show what you're building (describe the implementation)
- Flag any concerns or tradeoffs
- Say 'ready for review' when you've completed something

RESPONSE FORMAT:
- 80-120 words
- Mix simple explanations with brief technical details
- Show progress: what's done, what's next
- Ask specific questions when blocked"

# Create pane script
cat > "$WORKSPACE/pane.sh" << 'PANE_SCRIPT'
#!/usr/bin/env bash

NAME="$1"
COLOR="$2"
CMD="$3"
WORKDIR="$4"
PACE="$5"

case "$COLOR" in
    colour226) COLOR_CODE="\033[38;5;226m" ;;
    colour46)  COLOR_CODE="\033[38;5;46m" ;;
    colour39)  COLOR_CODE="\033[38;5;39m" ;;
    colour208) COLOR_CODE="\033[38;5;208m" ;;
    *)         COLOR_CODE="\033[0m" ;;
esac
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

clear
echo -e "${COLOR_CODE}${BOLD}╔════════════════════════════════════════╗${RESET}"
echo -e "${COLOR_CODE}${BOLD}║  $NAME${RESET}"
echo -e "${COLOR_CODE}${BOLD}╚════════════════════════════════════════╝${RESET}"
echo ""

touch "$WORKDIR/ready"

while true; do
    while [[ ! -f "$WORKDIR/prompt.txt" ]]; do
        sleep 0.1
    done

    PROMPT=$(cat "$WORKDIR/prompt.txt")
    rm -f "$WORKDIR/prompt.txt"

    if [[ "$PROMPT" == "__EXIT__" ]]; then
        echo -e "\n${DIM}[Session ended]${RESET}"
        break
    fi

    echo -e "${DIM}─────────────────────────────────────────${RESET}"
    echo ""

    if [[ "$PACE" -gt 0 ]] && command -v pv &>/dev/null; then
        $CMD "$PROMPT" 2>"$WORKDIR/stderr.txt" | tee "$WORKDIR/response.txt" | pv -qL "$PACE"
    else
        $CMD "$PROMPT" 2>"$WORKDIR/stderr.txt" | tee "$WORKDIR/response.txt"
    fi

    if [[ -s "$WORKDIR/stderr.txt" ]]; then
        echo -e "\n${COLOR_CODE}${BOLD}[Error:]${RESET}"
        cat "$WORKDIR/stderr.txt"
    fi

    echo ""
    echo ""
    touch "$WORKDIR/done"
done
PANE_SCRIPT
chmod +x "$WORKSPACE/pane.sh"

# Create orchestrator script
cat > "$WORKSPACE/orchestrator.sh" << 'ORCH_SCRIPT'
#!/usr/bin/env bash

WORKSPACE="$1"
TASK="$2"
MAX_CYCLES="$3"
PAUSE="$4"
USER_NAME="$5"
DEV_NAME="$6"
USER_FRAMEWORK="$7"
DEV_FRAMEWORK="$8"
SESSION_LOG="$9"

BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"

log_message() {
    echo -e "$1" >> "$SESSION_LOG"
}

clear
echo -e "${CYAN}${BOLD}"
echo "    ╔═══════════════════════════════════════════════════════════╗"
echo "    ║            🤖 AUTOPILOT DEV SESSION 🤖                    ║"
echo "    ╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""
echo -e "${BOLD}Task:${RESET} $TASK"
echo -e "${BOLD}Roles:${RESET} $USER_NAME (requirements) → $DEV_NAME (implementation)"
echo -e "${BOLD}Max Cycles:${RESET} $MAX_CYCLES"
echo ""
echo -e "${DIM}════════════════════════════════════════════════════════════════${RESET}"

log_message "AUTOPILOT SESSION - $(date '+%Y-%m-%d %H:%M:%S')"
log_message "TASK: $TASK"
log_message ""

wait_for_done() {
    local dir="$1"
    local elapsed=0
    while [[ ! -f "$dir/done" ]]; do
        sleep 0.2
        ((elapsed++))
        if (( elapsed % 25 == 0 )); then echo -n "."; fi
        if (( elapsed >= 600 )); then
            echo -e "\n${YELLOW}Timeout${RESET}"
            return 1
        fi
    done
    rm -f "$dir/done"
    return 0
}

send_prompt() {
    echo "$2" > "$1/prompt.txt"
}

get_response() {
    cat "$1/response.txt" 2>/dev/null || echo ""
}

check_shipped() {
    local response="$1"
    echo "$response" | grep -qiE "\b(ship it|deploy it|looks good|approved|lgtm|go ahead and deploy|ready to ship)\b"
}

# Wait for panes
echo -e "${DIM}Waiting for agents...${RESET}"
while [[ ! -f "$WORKSPACE/user/ready" ]] || [[ ! -f "$WORKSPACE/dev/ready" ]]; do
    sleep 0.1
done
rm -f "$WORKSPACE/user/ready" "$WORKSPACE/dev/ready"

sleep 1

# Phase 1: Initial requirement
echo ""
echo -e "${CYAN}${BOLD}► PHASE 1: INITIAL REQUIREMENT${RESET}"
echo ""
log_message "─────────────────────────────────────────"
log_message "PHASE 1: INITIAL REQUIREMENT"
log_message ""

echo -e "${DIM}[$USER_NAME describing the task...]${RESET}"
send_prompt "$WORKSPACE/user" "$USER_FRAMEWORK

---

You need this built: \"$TASK\"

Give the developer your initial requirements. Be clear about what you want but don't tell them how to build it. Include what success looks like."

wait_for_done "$WORKSPACE/user"
USER_REQ=$(get_response "$WORKSPACE/user")
log_message "[$USER_NAME - Initial]"
log_message "$USER_REQ"
log_message ""

sleep $PAUSE

# Developer clarifies
echo -e "${DIM}[$DEV_NAME reviewing requirements...]${RESET}"
send_prompt "$WORKSPACE/dev" "$DEV_FRAMEWORK

---

USER REQUEST:
\"\"\"
$USER_REQ
\"\"\"

Review this requirement. Ask any clarifying questions, then propose your approach."

wait_for_done "$WORKSPACE/dev"
DEV_RESPONSE=$(get_response "$WORKSPACE/dev")
log_message "[$DEV_NAME - Clarification]"
log_message "$DEV_RESPONSE"
log_message ""

sleep $PAUSE

# Implementation cycles
for ((cycle=1; cycle<=MAX_CYCLES; cycle++)); do
    echo ""
    echo -e "${YELLOW}${BOLD}► CYCLE $cycle / $MAX_CYCLES${RESET}"
    echo ""
    log_message "─────────────────────────────────────────"
    log_message "CYCLE $cycle"
    log_message ""

    # User responds
    echo -e "${DIM}[$USER_NAME responding...]${RESET}"
    send_prompt "$WORKSPACE/user" "$USER_FRAMEWORK

---

DEVELOPER SAYS:
\"\"\"
$DEV_RESPONSE
\"\"\"

Respond to them:
- Answer their questions
- Give feedback on their approach
- If satisfied, say 'ship it' or 'looks good, deploy it'
- If not, explain what needs to change"

    wait_for_done "$WORKSPACE/user"
    USER_RESPONSE=$(get_response "$WORKSPACE/user")
    log_message "[$USER_NAME - Cycle $cycle]"
    log_message "$USER_RESPONSE"
    log_message ""

    # Check if shipped
    if check_shipped "$USER_RESPONSE"; then
        echo ""
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo -e "${GREEN}${BOLD}                    🚀 SHIPPED! 🚀${RESET}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo ""
        log_message "🚀 SHIPPED (Cycle $cycle)"
        log_message ""
        log_message "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${DIM}Session log: $SESSION_LOG${RESET}"
        echo ""
        echo -e "${DIM}Press Enter to exit...${RESET}"
        send_prompt "$WORKSPACE/user" "__EXIT__"
        send_prompt "$WORKSPACE/dev" "__EXIT__"
        read
        exit 0
    fi

    sleep $PAUSE

    # Developer implements
    echo -e "${DIM}[$DEV_NAME implementing...]${RESET}"
    send_prompt "$WORKSPACE/dev" "$DEV_FRAMEWORK

---

USER FEEDBACK:
\"\"\"
$USER_RESPONSE
\"\"\"

Based on their feedback:
- Implement or update your solution
- Describe what you're building
- When done, say 'ready for review'"

    wait_for_done "$WORKSPACE/dev"
    DEV_RESPONSE=$(get_response "$WORKSPACE/dev")
    log_message "[$DEV_NAME - Cycle $cycle]"
    log_message "$DEV_RESPONSE"
    log_message ""

    sleep $PAUSE
done

# Max cycles
echo ""
echo -e "${YELLOW}${BOLD}► MAX CYCLES - FINAL CHECK${RESET}"
echo ""
log_message "MAX CYCLES REACHED"

send_prompt "$WORKSPACE/user" "$USER_FRAMEWORK

---

We've hit the iteration limit. The developer's latest:
\"\"\"
$DEV_RESPONSE
\"\"\"

Final decision: Ship it as-is, or explain what's still missing?"

wait_for_done "$WORKSPACE/user"
FINAL=$(get_response "$WORKSPACE/user")
log_message "[$USER_NAME - Final]"
log_message "$FINAL"

if check_shipped "$FINAL"; then
    echo -e "${GREEN}${BOLD}🚀 SHIPPED!${RESET}"
else
    echo -e "${YELLOW}${BOLD}⚠ NOT SHIPPED - Review needed${RESET}"
fi

log_message ""
log_message "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"

echo ""
echo -e "${DIM}Session log: $SESSION_LOG${RESET}"
echo -e "${DIM}Press Enter to exit...${RESET}"
send_prompt "$WORKSPACE/user" "__EXIT__"
send_prompt "$WORKSPACE/dev" "__EXIT__"
read
ORCH_SCRIPT
chmod +x "$WORKSPACE/orchestrator.sh"

# Headless mode - run without tmux
run_headless() {
    local BOLD="\033[1m"
    local DIM="\033[2m"
    local RESET="\033[0m"
    local CYAN="\033[36m"
    local GREEN="\033[32m"
    local YELLOW="\033[33m"

    log_msg() { echo -e "$1" | tee -a "$SESSION_LOG"; }

    check_shipped() {
        echo "$1" | grep -qiE "\b(ship it|deploy it|looks good|approved|lgtm|go ahead and deploy|ready to ship)\b"
    }

    # Header
    log_msg ""
    log_msg "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
    log_msg "${CYAN}${BOLD}  AUTOPILOT (headless) - $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    log_msg "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
    log_msg ""
    log_msg "${BOLD}Task:${RESET} $TASK"
    log_msg "${BOLD}Roles:${RESET} $USER_NAME → $DEV_NAME"
    log_msg ""

    # Phase 1: Initial requirement
    log_msg "${CYAN}► PHASE 1: INITIAL REQUIREMENT${RESET}"
    log_msg ""

    log_msg "${DIM}[$USER_NAME describing task...]${RESET}"
    USER_REQ=$($USER_CMD "$USER_FRAMEWORK

---

You need this built: \"$TASK\"

Give the developer your initial requirements. Be clear about what you want but don't tell them how to build it. Include what success looks like." 2>/dev/null)
    log_msg ""
    log_msg "${BOLD}[$USER_NAME]:${RESET}"
    log_msg "$USER_REQ"
    log_msg ""

    log_msg "${DIM}[$DEV_NAME reviewing...]${RESET}"
    DEV_RESPONSE=$($DEV_CMD "$DEV_FRAMEWORK

---

USER REQUEST:
\"\"\"
$USER_REQ
\"\"\"

Review this requirement. Ask any clarifying questions, then propose your approach." 2>/dev/null)
    log_msg ""
    log_msg "${BOLD}[$DEV_NAME]:${RESET}"
    log_msg "$DEV_RESPONSE"
    log_msg ""

    # Implementation cycles
    for ((cycle=1; cycle<=MAX_CYCLES; cycle++)); do
        log_msg "${YELLOW}► CYCLE $cycle / $MAX_CYCLES${RESET}"
        log_msg ""

        # User responds
        USER_RESPONSE=$($USER_CMD "$USER_FRAMEWORK

---

DEVELOPER SAYS:
\"\"\"
$DEV_RESPONSE
\"\"\"

Respond to them:
- Answer their questions
- Give feedback on their approach
- If satisfied, say 'ship it' or 'looks good, deploy it'
- If not, explain what needs to change" 2>/dev/null)
        log_msg "${BOLD}[$USER_NAME]:${RESET}"
        log_msg "$USER_RESPONSE"
        log_msg ""

        # Check if shipped
        if check_shipped "$USER_RESPONSE"; then
            log_msg ""
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg "${GREEN}${BOLD}                    🚀 SHIPPED! 🚀${RESET}"
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg ""
            log_msg "Session log: $SESSION_LOG"
            exit 0
        fi

        # Developer implements
        DEV_RESPONSE=$($DEV_CMD "$DEV_FRAMEWORK

---

USER FEEDBACK:
\"\"\"
$USER_RESPONSE
\"\"\"

Based on their feedback:
- Implement or update your solution
- Describe what you're building
- When done, say 'ready for review'" 2>/dev/null)
        log_msg "${BOLD}[$DEV_NAME]:${RESET}"
        log_msg "$DEV_RESPONSE"
        log_msg ""
    done

    # Max cycles reached
    log_msg "${YELLOW}► MAX CYCLES - FINAL CHECK${RESET}"
    log_msg ""

    FINAL=$($USER_CMD "$USER_FRAMEWORK

---

We've hit the iteration limit. The developer's latest:
\"\"\"
$DEV_RESPONSE
\"\"\"

Final decision: Ship it as-is, or explain what's still missing?" 2>/dev/null)
    log_msg "${BOLD}[$USER_NAME - Final]:${RESET}"
    log_msg "$FINAL"
    log_msg ""

    if check_shipped "$FINAL"; then
        log_msg "${GREEN}${BOLD}🚀 SHIPPED!${RESET}"
        exit 0
    else
        log_msg "${YELLOW}${BOLD}⚠ NOT SHIPPED - Review needed${RESET}"
        exit 1
    fi
}

# Branch: headless vs tmux
if [[ "$HEADLESS" == true ]]; then
    # Log session
    {
        echo "════════════════════════════════════════════════════════════════"
        echo "AUTOPILOT SESSION (HEADLESS) - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        echo "TASK: $TASK"
        echo "USER: $USER_NAME ($USER_CMD)"
        echo "DEV: $DEV_NAME ($DEV_CMD)"
        echo ""
    } > "$SESSION_LOG"

    run_headless
    exit $?
fi

# Check tmux (only needed for non-headless)
if ! command -v tmux &>/dev/null; then
    echo "Error: tmux required. Install: sudo apt install tmux"
    echo "Hint: Use --headless to run without tmux"
    exit 1
fi

# Log session start
{
    echo "════════════════════════════════════════════════════════════════"
    echo "AUTOPILOT SESSION - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "TASK: $TASK"
    echo ""
    echo "USER: $USER_NAME ($USER_CMD)"
    echo "DEV: $DEV_NAME ($DEV_CMD)"
    echo "MAX CYCLES: $MAX_CYCLES"
    echo ""
} > "$SESSION_LOG"

export TERM="${TERM:-xterm-256color}"
SESSION="autopilot_$$"
tmux kill-session -t "$SESSION" 2>/dev/null || true

tmux new-session -d -s "$SESSION" -x 180 -y 50
tmux split-window -v -l 15 -t "$SESSION"
tmux split-window -h -l 90 -t "$SESSION:0.1"

tmux select-pane -t "$SESSION:0.0" -T "Orchestrator"
tmux select-pane -t "$SESSION:0.1" -T "$USER_NAME"
tmux select-pane -t "$SESSION:0.2" -T "$DEV_NAME"

tmux set -t "$SESSION" pane-border-status top
tmux set -t "$SESSION" pane-border-format " #{pane_title} "

tmux send-keys -t "$SESSION:0.1" "'$WORKSPACE/pane.sh' '$USER_NAME' '$USER_COLOR' '$USER_CMD' '$WORKSPACE/user' '$PACE'" Enter
tmux send-keys -t "$SESSION:0.2" "'$WORKSPACE/pane.sh' '$DEV_NAME' '$DEV_COLOR' '$DEV_CMD' '$WORKSPACE/dev' '$PACE'" Enter

sleep 1

echo "$USER_FRAMEWORK" > "$WORKSPACE/user_framework.txt"
echo "$DEV_FRAMEWORK" > "$WORKSPACE/dev_framework.txt"
echo "$TASK" > "$WORKSPACE/task.txt"

tmux send-keys -t "$SESSION:0.0" "USER_FW=\$(cat '$WORKSPACE/user_framework.txt') && DEV_FW=\$(cat '$WORKSPACE/dev_framework.txt') && TASK=\$(cat '$WORKSPACE/task.txt') && '$WORKSPACE/orchestrator.sh' '$WORKSPACE' \"\$TASK\" '$MAX_CYCLES' '$PAUSE_BETWEEN_TURNS' '$USER_NAME' '$DEV_NAME' \"\$USER_FW\" \"\$DEV_FW\" '$SESSION_LOG'" Enter

tmux attach -t "$SESSION"
tmux kill-session -t "$SESSION" 2>/dev/null || true
