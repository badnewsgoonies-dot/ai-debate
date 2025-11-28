#!/usr/bin/env bash
#
# Architect - Collaborative Design Session
# Two senior devs iterate on a problem until they converge on a solution
#
# Usage: ./architect.sh [problem/challenge]
# Example: ./architect.sh "Should we use Redux or Zustand for state management?"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env" 2>/dev/null || true

# Defaults
ARCHITECT_A_CMD="${ARCHITECT_A_CMD:-claude -p}"
ARCHITECT_B_CMD="${ARCHITECT_B_CMD:-codex exec}"
ARCHITECT_A_NAME="${ARCHITECT_A_NAME:-Claude}"
ARCHITECT_B_NAME="${ARCHITECT_B_NAME:-Codex}"
ARCHITECT_A_COLOR="${ARCHITECT_A_COLOR:-colour39}"
ARCHITECT_B_COLOR="${ARCHITECT_B_COLOR:-colour208}"
MAX_ROUNDS="${MAX_ROUNDS:-5}"
PACE="${PACE:-100}"
PAUSE_BETWEEN_TURNS="${PAUSE_BETWEEN_TURNS:-1}"

# Parse flags
HEADLESS=false
while [[ "${1:-}" == -* ]]; do
    case "$1" in
        -H|--headless) HEADLESS=true; shift ;;
        -h|--help)
            echo "Usage: ./architect.sh [-H|--headless] [problem]"
            echo ""
            echo "Options:"
            echo "  -H, --headless  Run without tmux UI (output to stdout)"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Problem from argument or prompt
PROBLEM="${1:-}"
if [[ -z "$PROBLEM" ]] && [[ "$HEADLESS" == false ]]; then
    echo "🏗️  Architect - Collaborative Design Session"
    echo "═══════════════════════════════════════"
    echo ""
    read -p "Enter problem/challenge: " PROBLEM
fi

if [[ -z "$PROBLEM" ]]; then
    echo "Error: No problem provided"
    [[ "$HEADLESS" == true ]] && echo "Hint: In headless mode, problem is required as argument"
    exit 1
fi

# Validate AI commands before proceeding
validate_command() {
    local cmd="$1"
    local name="$2"
    local first_word=$(echo "$cmd" | awk '{print $1}')

    if ! command -v "$first_word" &>/dev/null; then
        echo "Error: $name command not found: $first_word"
        echo "Expected command: $cmd"
        echo ""
        echo "Please ensure the AI tool is installed and accessible in PATH,"
        echo "or update the command in config.env"
        exit 1
    fi
}

validate_command "$ARCHITECT_A_CMD" "$ARCHITECT_A_NAME"
validate_command "$ARCHITECT_B_CMD" "$ARCHITECT_B_NAME"

# Create temp workspace
WORKSPACE=$(mktemp -d /tmp/architect.XXXXXX)
trap "rm -rf $WORKSPACE" EXIT

mkdir -p "$WORKSPACE/a" "$WORKSPACE/b"

# Create log directory and session log
LOG_DIR="$HOME/.cache/architect"
mkdir -p "$LOG_DIR"
SESSION_LOG="$LOG_DIR/session_$(date +%Y%m%d_%H%M%S).log"

# Load framework
FRAMEWORK_FILE="$SCRIPT_DIR/thinking-framework.txt"
if [[ -f "$FRAMEWORK_FILE" ]]; then
    FRAMEWORK=$(cat "$FRAMEWORK_FILE")
else
    FRAMEWORK="You are a senior developer in a collaborative design session. Goal: converge on the best solution. Be concise, specific, and willing to change your mind."
fi

# Create the architect pane script
cat > "$WORKSPACE/architect-pane.sh" << 'PANE_SCRIPT'
#!/usr/bin/env bash

NAME="$1"
COLOR="$2"
CMD="$3"
WORKDIR="$4"
PACE="$5"

case "$COLOR" in
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

# Signal pane is ready
touch "$WORKDIR/ready"

while true; do
    while [[ ! -f "$WORKDIR/prompt.txt" ]]; do
        sleep 0.1
    done

    PROMPT=$(cat "$WORKDIR/prompt.txt")
    rm -f "$WORKDIR/prompt.txt"

    if [[ "$PROMPT" == "__EXIT__" ]]; then
        echo -e "\n${DIM}[Session concluded]${RESET}"
        break
    fi

    echo -e "${DIM}─────────────────────────────────────────${RESET}"
    echo ""

    # Skip pv if PACE=0 or pv not installed
    if [[ "$PACE" -gt 0 ]] && command -v pv &>/dev/null; then
        $CMD "$PROMPT" 2>"$WORKDIR/stderr.txt" | tee "$WORKDIR/response.txt" | pv -qL "$PACE"
    else
        $CMD "$PROMPT" 2>"$WORKDIR/stderr.txt" | tee "$WORKDIR/response.txt"
    fi

    # Show errors if any
    if [[ -s "$WORKDIR/stderr.txt" ]]; then
        echo -e "\n${COLOR_CODE}${BOLD}[Error output:]${RESET}"
        cat "$WORKDIR/stderr.txt"
    fi

    echo ""
    echo ""
    touch "$WORKDIR/done"
done
PANE_SCRIPT
chmod +x "$WORKSPACE/architect-pane.sh"

# Create the orchestrator script
cat > "$WORKSPACE/orchestrator.sh" << 'ORCH_SCRIPT'
#!/usr/bin/env bash

WORKSPACE="$1"
PROBLEM="$2"
MAX_ROUNDS="$3"
PAUSE="$4"
NAME_A="$5"
NAME_B="$6"
FRAMEWORK="$7"
SESSION_LOG="$8"

BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"

log_message() {
    local message="$1"
    if [[ -n "$SESSION_LOG" ]]; then
        echo -e "$message" >> "$SESSION_LOG"
    fi
}

clear
echo -e "${CYAN}${BOLD}"
echo "    ╔═══════════════════════════════════════════════════════════╗"
echo "    ║            🏗️  ARCHITECT DESIGN SESSION 🏗️                ║"
echo "    ╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""
echo -e "${BOLD}Problem:${RESET} $PROBLEM"
echo -e "${BOLD}Architects:${RESET} $NAME_A & $NAME_B"
echo -e "${BOLD}Max Rounds:${RESET} $MAX_ROUNDS"
echo ""
echo -e "${DIM}════════════════════════════════════════════════════════════════${RESET}"

log_message "SESSION START - $(date '+%Y-%m-%d %H:%M:%S')"
log_message ""

wait_for_done() {
    local dir="$1"
    local timeout=120
    local elapsed=0
    local interval=5

    while [[ ! -f "$dir/done" ]]; do
        sleep 0.2
        elapsed=$((elapsed + 1))

        # Print dot every 5 seconds
        if (( elapsed % 25 == 0 )); then  # 25 * 0.2s = 5s
            echo -n "."
        fi

        # Check timeout (120s / 0.2s = 600 iterations)
        if (( elapsed >= 600 )); then
            echo ""
            echo -e "${YELLOW}Warning: Response timeout (120s). Continuing...${RESET}"
            return 1
        fi
    done
    rm -f "$dir/done"
    return 0
}

send_prompt() {
    local dir="$1"
    local prompt="$2"
    echo "$prompt" > "$dir/prompt.txt"
}

get_response() {
    local dir="$1"
    cat "$dir/response.txt" 2>/dev/null || echo ""
}

check_consensus() {
    local response="$1"
    local signals=0

    # Count multiple convergence signals (need 2+ to confirm)
    echo "$response" | grep -qiE "\\b(I agree|you're right|I'm convinced)\\b" && ((signals++))
    echo "$response" | grep -qiE "\\b(let's go with|we should use|let's proceed)\\b" && ((signals++))
    echo "$response" | grep -qiE "\\b(settled|consensus reached|that's the approach)\\b" && ((signals++))
    echo "$response" | grep -qiE "\\b(no objections|sounds good|makes sense to me)\\b" && ((signals++))

    # Also check for disagreement signals that override
    if echo "$response" | grep -qiE "\\b(however|but I think|I disagree|concern|issue with|problem with)\\b"; then
        return 1
    fi

    # Need at least 2 signals for consensus
    [[ $signals -ge 2 ]]
}

# Wait for both panes to be ready
echo -e "${DIM}Waiting for architects to initialize...${RESET}"
while [[ ! -f "$WORKSPACE/a/ready" ]] || [[ ! -f "$WORKSPACE/b/ready" ]]; do
    sleep 0.1
done
rm -f "$WORKSPACE/a/ready" "$WORKSPACE/b/ready"

# Phase 1: Initial Assessment (Blind)
echo ""
echo -e "${CYAN}${BOLD}► PHASE 1: INITIAL ASSESSMENT (BLIND)${RESET}"
echo ""

log_message "─────────────────────────────────────────────────────────────────"
log_message "PHASE 1: INITIAL ASSESSMENT (BLIND)"
log_message "─────────────────────────────────────────────────────────────────"
log_message ""

echo -e "${DIM}[$NAME_A and $NAME_B are assessing independently...]${RESET}"

# Both architects assess independently without seeing each other's response
send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Initial Assessment

Assess this problem independently. First, determine: Is this a clear-cut decision (one approach is obviously better) or a genuine 50/50 where both paths have merit?

If obvious: State the clear winner and why. No need to manufacture disagreement.
If split: Identify the two (or more) viable approaches and which one you'd lean toward exploring. Be specific about the tradeoffs."

send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Initial Assessment

Assess this problem independently. First, determine: Is this a clear-cut decision (one approach is obviously better) or a genuine 50/50 where both paths have merit?

If obvious: State the clear winner and why. No need to manufacture disagreement.
If split: Identify the two (or more) viable approaches and which one you'd lean toward exploring. Be specific about the tradeoffs."

# Wait for both to complete (parallel)
wait_for_done "$WORKSPACE/a" &
pid_a=$!
wait_for_done "$WORKSPACE/b" &
pid_b=$!
wait $pid_a $pid_b || true

RESPONSE_A=$(get_response "$WORKSPACE/a")
RESPONSE_B=$(get_response "$WORKSPACE/b")

log_message "[$NAME_A - Initial Assessment]"
log_message "$RESPONSE_A"
log_message ""
log_message "[$NAME_B - Initial Assessment]"
log_message "$RESPONSE_B"
log_message ""

sleep $PAUSE

# Now show each other's assessments
echo ""
echo -e "${CYAN}${BOLD}► PHASE 1b: REVIEW PEER ASSESSMENT${RESET}"
echo ""

log_message "PHASE 1b: REVIEW PEER ASSESSMENT"
log_message ""

echo -e "${DIM}[$NAME_A reviewing $NAME_B's assessment...]${RESET}"
send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Review Peer Assessment

Your colleague's independent assessment:
\"\"\"
$RESPONSE_B
\"\"\"

Your earlier assessment:
\"\"\"
$RESPONSE_A
\"\"\"

Review your colleague's take. Do you agree or see it differently? If you see the same clear winner, say so and we can wrap up. If you see it differently, explain which path you'd take and why."

wait_for_done "$WORKSPACE/a"
RESPONSE_A=$(get_response "$WORKSPACE/a")

log_message "[$NAME_A - Review Response]"
log_message "$RESPONSE_A"
log_message ""

sleep $PAUSE

echo -e "${DIM}[$NAME_B reviewing $NAME_A's assessment...]${RESET}"
send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Review Peer Assessment

Your colleague's response after seeing your assessment:
\"\"\"
$RESPONSE_A
\"\"\"

Review their take. Do you agree or want to continue exploring? If aligned, say so clearly. If you still see value in an alternative, explain."

wait_for_done "$WORKSPACE/b"
RESPONSE_B=$(get_response "$WORKSPACE/b")

log_message "[$NAME_B - Review Response]"
log_message "$RESPONSE_B"
log_message ""

# Check for early consensus
if check_consensus "$RESPONSE_B"; then
    echo ""
    echo -e "${GREEN}${BOLD}► EARLY CONSENSUS REACHED${RESET}"
    echo ""
    log_message "EARLY CONSENSUS DETECTED"
    log_message ""
    echo -e "${DIM}[$NAME_A confirming agreement...]${RESET}"
    send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Confirmation

Your colleague responded:
\"\"\"
$RESPONSE_B
\"\"\"

If you're aligned, summarize the agreed approach in 2-3 sentences. If you still have concerns, voice them."

    wait_for_done "$WORKSPACE/a"
    FINAL_A=$(get_response "$WORKSPACE/a")

    log_message "[$NAME_A - Confirmation]"
    log_message "$FINAL_A"
    log_message ""

    if check_consensus "$FINAL_A"; then
        echo ""
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo -e "${GREEN}${BOLD}                    ✓ CONSENSUS ACHIEVED ✓${RESET}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo ""
        log_message "════════════════════════════════════════════════════════════════"
        log_message "✓ CONSENSUS ACHIEVED ✓ (Early - Phase 1)"
        log_message "════════════════════════════════════════════════════════════════"
        log_message ""
        log_message "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${DIM}Session log saved to: $SESSION_LOG${RESET}"
        echo ""
        echo -e "${DIM}Press Enter to exit...${RESET}"
        send_prompt "$WORKSPACE/a" "__EXIT__"
        send_prompt "$WORKSPACE/b" "__EXIT__"
        read
        exit 0
    fi
fi

sleep $PAUSE

# Phase 2: Deep Exploration (if needed)
for ((round=1; round<=MAX_ROUNDS; round++)); do
    echo ""
    echo -e "${YELLOW}${BOLD}► ROUND $round / $MAX_ROUNDS: EXPLORATION & REFINEMENT${RESET}"
    echo ""

    log_message "─────────────────────────────────────────────────────────────────"
    log_message "ROUND $round / $MAX_ROUNDS: EXPLORATION & REFINEMENT"
    log_message "─────────────────────────────────────────────────────────────────"
    log_message ""

    # A responds to B
    echo -e "${DIM}[$NAME_A exploring/responding...]${RESET}"
    send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Round $round

Your colleague's latest thinking:
\"\"\"
$RESPONSE_B
\"\"\"

Continue the discussion. Options:
- If you're convinced by their approach, say so clearly
- If you see a hybrid solution, propose it specifically
- If you still see value in your approach, explain what they might be missing
- If you need more information to decide, say what specifically

Goal: Move toward convergence, not endless debate."

    wait_for_done "$WORKSPACE/a"
    RESPONSE_A=$(get_response "$WORKSPACE/a")

    log_message "[$NAME_A - Round $round]"
    log_message "$RESPONSE_A"
    log_message ""

    if check_consensus "$RESPONSE_A"; then
        echo ""
        echo -e "${GREEN}${BOLD}► $NAME_A SIGNALS AGREEMENT${RESET}"
        log_message "$NAME_A SIGNALS AGREEMENT"
        log_message ""
        sleep $PAUSE

        echo -e "${DIM}[$NAME_B confirming...]${RESET}"
        send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Confirmation

Your colleague says:
\"\"\"
$RESPONSE_A
\"\"\"

Confirm the agreed approach or raise any final concerns. If aligned, summarize the decision in 2-3 sentences."

        wait_for_done "$WORKSPACE/b"
        CONFIRM_B=$(get_response "$WORKSPACE/b")

        log_message "[$NAME_B - Confirmation]"
        log_message "$CONFIRM_B"
        log_message ""

        echo ""
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo -e "${GREEN}${BOLD}                    ✓ CONSENSUS ACHIEVED ✓${RESET}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo ""
        log_message "════════════════════════════════════════════════════════════════"
        log_message "✓ CONSENSUS ACHIEVED ✓ (Round $round)"
        log_message "════════════════════════════════════════════════════════════════"
        log_message ""
        log_message "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${DIM}Session log saved to: $SESSION_LOG${RESET}"
        echo ""
        echo -e "${DIM}Press Enter to exit...${RESET}"
        send_prompt "$WORKSPACE/a" "__EXIT__"
        send_prompt "$WORKSPACE/b" "__EXIT__"
        read
        exit 0
    fi

    sleep $PAUSE

    # B responds to A
    echo -e "${DIM}[$NAME_B exploring/responding...]${RESET}"
    send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Round $round

Your colleague's latest thinking:
\"\"\"
$RESPONSE_A
\"\"\"

Continue the discussion. Options:
- If you're convinced by their approach, say so clearly
- If you see a hybrid solution, propose it specifically
- If you still see value in your approach, explain what they might be missing
- If you need more information to decide, say what specifically

Goal: Move toward convergence, not endless debate."

    wait_for_done "$WORKSPACE/b"
    RESPONSE_B=$(get_response "$WORKSPACE/b")

    log_message "[$NAME_B - Round $round]"
    log_message "$RESPONSE_B"
    log_message ""

    if check_consensus "$RESPONSE_B"; then
        echo ""
        echo -e "${GREEN}${BOLD}► $NAME_B SIGNALS AGREEMENT${RESET}"
        log_message "$NAME_B SIGNALS AGREEMENT"
        log_message ""
        sleep $PAUSE

        echo -e "${DIM}[$NAME_A confirming...]${RESET}"
        send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Confirmation

Your colleague says:
\"\"\"
$RESPONSE_B
\"\"\"

Confirm the agreed approach or raise any final concerns. If aligned, summarize the decision in 2-3 sentences."

        wait_for_done "$WORKSPACE/a"
        CONFIRM_A=$(get_response "$WORKSPACE/a")

        log_message "[$NAME_A - Confirmation]"
        log_message "$CONFIRM_A"
        log_message ""

        echo ""
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo -e "${GREEN}${BOLD}                    ✓ CONSENSUS ACHIEVED ✓${RESET}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        echo ""
        log_message "════════════════════════════════════════════════════════════════"
        log_message "✓ CONSENSUS ACHIEVED ✓ (Round $round)"
        log_message "════════════════════════════════════════════════════════════════"
        log_message ""
        log_message "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${DIM}Session log saved to: $SESSION_LOG${RESET}"
        echo ""
        echo -e "${DIM}Press Enter to exit...${RESET}"
        send_prompt "$WORKSPACE/a" "__EXIT__"
        send_prompt "$WORKSPACE/b" "__EXIT__"
        read
        exit 0
    fi

    sleep $PAUSE
done

# Max rounds reached - force conclusion
echo ""
echo -e "${YELLOW}${BOLD}► MAX ROUNDS REACHED - FORCING CONCLUSION${RESET}"
echo ""

log_message "─────────────────────────────────────────────────────────────────"
log_message "MAX ROUNDS REACHED - FORCING CONCLUSION"
log_message "─────────────────────────────────────────────────────────────────"
log_message ""

echo -e "${DIM}[$NAME_A final recommendation...]${RESET}"
send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Final Decision (max rounds reached)

We've discussed extensively. Time to decide. Given everything discussed, state your final recommendation and the key reason. If you still disagree with your colleague, explain what information would change your mind."

wait_for_done "$WORKSPACE/a"
FINAL_REC_A=$(get_response "$WORKSPACE/a")

log_message "[$NAME_A - Final Recommendation]"
log_message "$FINAL_REC_A"
log_message ""

sleep $PAUSE

echo -e "${DIM}[$NAME_B final recommendation...]${RESET}"
send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Final Decision (max rounds reached)

Your colleague's final take:
\"\"\"
$(get_response "$WORKSPACE/a")
\"\"\"

State your final recommendation. If you agree, confirm. If you still disagree, explain the remaining crux. Either way, what should the human do next?"

wait_for_done "$WORKSPACE/b"
FINAL_REC_B=$(get_response "$WORKSPACE/b")

log_message "[$NAME_B - Final Recommendation]"
log_message "$FINAL_REC_B"
log_message ""

echo ""
echo -e "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${YELLOW}${BOLD}                    SESSION COMPLETE${RESET}"
echo -e "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo ""

log_message "════════════════════════════════════════════════════════════════"
log_message "SESSION COMPLETE (Max rounds reached)"
log_message "════════════════════════════════════════════════════════════════"
log_message ""
log_message "Session ended: $(date '+%Y-%m-%d %H:%M:%S')"

echo -e "${DIM}Session log saved to: $SESSION_LOG${RESET}"
echo ""
echo -e "${DIM}Press Enter to exit...${RESET}"

send_prompt "$WORKSPACE/a" "__EXIT__"
send_prompt "$WORKSPACE/b" "__EXIT__"

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

    check_consensus() {
        local response="$1"
        local signals=0
        echo "$response" | grep -qiE "\b(I agree|you're right|I'm convinced)\b" && ((signals++))
        echo "$response" | grep -qiE "\b(let's go with|we should use|let's proceed)\b" && ((signals++))
        echo "$response" | grep -qiE "\b(settled|consensus reached|that's the approach)\b" && ((signals++))
        echo "$response" | grep -qiE "\b(no objections|sounds good|makes sense to me)\b" && ((signals++))
        if echo "$response" | grep -qiE "\b(however|but I think|I disagree|concern|issue with|problem with)\b"; then
            return 1
        fi
        [[ $signals -ge 2 ]]
    }

    # Header
    log_msg ""
    log_msg "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
    log_msg "${CYAN}${BOLD}  ARCHITECT (headless) - $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    log_msg "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
    log_msg ""
    log_msg "${BOLD}Problem:${RESET} $PROBLEM"
    log_msg "${BOLD}Architects:${RESET} $ARCHITECT_A_NAME & $ARCHITECT_B_NAME"
    log_msg ""

    # Phase 1: Initial Assessment (both assess independently)
    log_msg "${CYAN}► PHASE 1: INITIAL ASSESSMENT (BLIND)${RESET}"
    log_msg ""

    log_msg "${DIM}[$ARCHITECT_A_NAME and $ARCHITECT_B_NAME assessing independently...]${RESET}"

    RESPONSE_A=$($ARCHITECT_A_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Initial Assessment

Assess this problem independently. First, determine: Is this a clear-cut decision (one approach is obviously better) or a genuine 50/50 where both paths have merit?

If obvious: State the clear winner and why. No need to manufacture disagreement.
If split: Identify the two (or more) viable approaches and which one you'd lean toward exploring. Be specific about the tradeoffs." 2>/dev/null)

    RESPONSE_B=$($ARCHITECT_B_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Initial Assessment

Assess this problem independently. First, determine: Is this a clear-cut decision (one approach is obviously better) or a genuine 50/50 where both paths have merit?

If obvious: State the clear winner and why. No need to manufacture disagreement.
If split: Identify the two (or more) viable approaches and which one you'd lean toward exploring. Be specific about the tradeoffs." 2>/dev/null)

    log_msg "${BOLD}[$ARCHITECT_A_NAME - Initial]:${RESET}"
    log_msg "$RESPONSE_A"
    log_msg ""
    log_msg "${BOLD}[$ARCHITECT_B_NAME - Initial]:${RESET}"
    log_msg "$RESPONSE_B"
    log_msg ""

    # Phase 1b: Review Peer Assessment
    log_msg "${CYAN}► PHASE 1b: REVIEW PEER ASSESSMENT${RESET}"
    log_msg ""

    log_msg "${DIM}[$ARCHITECT_A_NAME reviewing $ARCHITECT_B_NAME's assessment...]${RESET}"
    RESPONSE_A=$($ARCHITECT_A_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Review Peer Assessment

Your colleague's independent assessment:
\"\"\"
$RESPONSE_B
\"\"\"

Your earlier assessment:
\"\"\"
$RESPONSE_A
\"\"\"

Review your colleague's take. Do you agree or see it differently? If you see the same clear winner, say so and we can wrap up. If you see it differently, explain which path you'd take and why." 2>/dev/null)
    log_msg "${BOLD}[$ARCHITECT_A_NAME]:${RESET}"
    log_msg "$RESPONSE_A"
    log_msg ""

    log_msg "${DIM}[$ARCHITECT_B_NAME reviewing $ARCHITECT_A_NAME's assessment...]${RESET}"
    RESPONSE_B=$($ARCHITECT_B_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Review Peer Assessment

Your colleague's response after seeing your assessment:
\"\"\"
$RESPONSE_A
\"\"\"

Review their take. Do you agree or want to continue exploring? If aligned, say so clearly. If you still see value in an alternative, explain." 2>/dev/null)
    log_msg "${BOLD}[$ARCHITECT_B_NAME]:${RESET}"
    log_msg "$RESPONSE_B"
    log_msg ""

    # Check for early consensus
    if check_consensus "$RESPONSE_B"; then
        log_msg "${GREEN}► EARLY CONSENSUS DETECTED${RESET}"
        log_msg ""
        FINAL_A=$($ARCHITECT_A_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Confirmation

Your colleague responded:
\"\"\"
$RESPONSE_B
\"\"\"

If you're aligned, summarize the agreed approach in 2-3 sentences. If you still have concerns, voice them." 2>/dev/null)
        log_msg "${BOLD}[$ARCHITECT_A_NAME - Confirmation]:${RESET}"
        log_msg "$FINAL_A"
        log_msg ""

        if check_consensus "$FINAL_A"; then
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg "${GREEN}${BOLD}                    ✓ CONSENSUS ACHIEVED ✓${RESET}"
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg ""
            log_msg "Session log: $SESSION_LOG"
            exit 0
        fi
    fi

    # Phase 2: Deep Exploration
    for ((round=1; round<=MAX_ROUNDS; round++)); do
        log_msg "${YELLOW}► ROUND $round / $MAX_ROUNDS: EXPLORATION${RESET}"
        log_msg ""

        # A responds to B
        log_msg "${DIM}[$ARCHITECT_A_NAME exploring...]${RESET}"
        RESPONSE_A=$($ARCHITECT_A_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Round $round

Your colleague's latest thinking:
\"\"\"
$RESPONSE_B
\"\"\"

Continue the discussion. Options:
- If you're convinced by their approach, say so clearly
- If you see a hybrid solution, propose it specifically
- If you still see value in your approach, explain what they might be missing
- If you need more information to decide, say what specifically

Goal: Move toward convergence, not endless debate." 2>/dev/null)
        log_msg "${BOLD}[$ARCHITECT_A_NAME]:${RESET}"
        log_msg "$RESPONSE_A"
        log_msg ""

        if check_consensus "$RESPONSE_A"; then
            log_msg "${GREEN}► $ARCHITECT_A_NAME SIGNALS AGREEMENT${RESET}"
            CONFIRM_B=$($ARCHITECT_B_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Confirmation

Your colleague says:
\"\"\"
$RESPONSE_A
\"\"\"

Confirm the agreed approach or raise any final concerns. If aligned, summarize the decision in 2-3 sentences." 2>/dev/null)
            log_msg "${BOLD}[$ARCHITECT_B_NAME - Confirmation]:${RESET}"
            log_msg "$CONFIRM_B"
            log_msg ""
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg "${GREEN}${BOLD}                    ✓ CONSENSUS ACHIEVED ✓${RESET}"
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg ""
            log_msg "Session log: $SESSION_LOG"
            exit 0
        fi

        # B responds to A
        log_msg "${DIM}[$ARCHITECT_B_NAME exploring...]${RESET}"
        RESPONSE_B=$($ARCHITECT_B_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Round $round

Your colleague's latest thinking:
\"\"\"
$RESPONSE_A
\"\"\"

Continue the discussion. Options:
- If you're convinced by their approach, say so clearly
- If you see a hybrid solution, propose it specifically
- If you still see value in your approach, explain what they might be missing
- If you need more information to decide, say what specifically

Goal: Move toward convergence, not endless debate." 2>/dev/null)
        log_msg "${BOLD}[$ARCHITECT_B_NAME]:${RESET}"
        log_msg "$RESPONSE_B"
        log_msg ""

        if check_consensus "$RESPONSE_B"; then
            log_msg "${GREEN}► $ARCHITECT_B_NAME SIGNALS AGREEMENT${RESET}"
            CONFIRM_A=$($ARCHITECT_A_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Confirmation

Your colleague says:
\"\"\"
$RESPONSE_B
\"\"\"

Confirm the agreed approach or raise any final concerns. If aligned, summarize the decision in 2-3 sentences." 2>/dev/null)
            log_msg "${BOLD}[$ARCHITECT_A_NAME - Confirmation]:${RESET}"
            log_msg "$CONFIRM_A"
            log_msg ""
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg "${GREEN}${BOLD}                    ✓ CONSENSUS ACHIEVED ✓${RESET}"
            log_msg "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
            log_msg ""
            log_msg "Session log: $SESSION_LOG"
            exit 0
        fi
    done

    # Max rounds - force conclusion
    log_msg "${YELLOW}► MAX ROUNDS - FORCING CONCLUSION${RESET}"
    log_msg ""

    FINAL_A=$($ARCHITECT_A_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Final Decision (max rounds reached)

We've discussed extensively. Time to decide. Given everything discussed, state your final recommendation and the key reason. If you still disagree with your colleague, explain what information would change your mind." 2>/dev/null)
    log_msg "${BOLD}[$ARCHITECT_A_NAME - Final]:${RESET}"
    log_msg "$FINAL_A"
    log_msg ""

    FINAL_B=$($ARCHITECT_B_CMD "$FRAMEWORK

---

PROBLEM: \"$PROBLEM\"
PHASE: Final Decision (max rounds reached)

Your colleague's final take:
\"\"\"
$FINAL_A
\"\"\"

State your final recommendation. If you agree, confirm. If you still disagree, explain the remaining crux. Either way, what should the human do next?" 2>/dev/null)
    log_msg "${BOLD}[$ARCHITECT_B_NAME - Final]:${RESET}"
    log_msg "$FINAL_B"
    log_msg ""

    log_msg "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
    log_msg "${YELLOW}${BOLD}                    SESSION COMPLETE${RESET}"
    log_msg "${YELLOW}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
    log_msg ""
    log_msg "Session log: $SESSION_LOG"

    if check_consensus "$FINAL_B"; then
        exit 0
    else
        exit 1
    fi
}

# Branch: headless vs tmux
if [[ "$HEADLESS" == true ]]; then
    {
        echo "════════════════════════════════════════════════════════════════"
        echo "ARCHITECT SESSION (HEADLESS) - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        echo "PROBLEM: $PROBLEM"
        echo "ARCHITECTS: $ARCHITECT_A_NAME & $ARCHITECT_B_NAME"
        echo ""
    } > "$SESSION_LOG"

    run_headless
    exit $?
fi

# Check for tmux (only needed for non-headless)
if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is required. Install with: sudo apt install tmux"
    echo "Hint: Use --headless to run without tmux"
    exit 1
fi

# Log session start
{
    echo "════════════════════════════════════════════════════════════════"
    echo "ARCHITECT SESSION - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "PROBLEM: $PROBLEM"
    echo ""
    echo "ARCHITECTS: $ARCHITECT_A_NAME & $ARCHITECT_B_NAME"
    echo "MAX ROUNDS: $MAX_ROUNDS"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo ""
} > "$SESSION_LOG"

export TERM="${TERM:-xterm-256color}"
COLS=180
ROWS=50

SESSION="architect_$$"
tmux kill-session -t "$SESSION" 2>/dev/null || true

tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"
tmux split-window -v -l 15 -t "$SESSION"
tmux split-window -h -l 90 -t "$SESSION:0.1"

tmux select-pane -t "$SESSION:0.0" -T "Orchestrator"
tmux select-pane -t "$SESSION:0.1" -T "$ARCHITECT_A_NAME"
tmux select-pane -t "$SESSION:0.2" -T "$ARCHITECT_B_NAME"

tmux set -t "$SESSION" pane-border-status top
tmux set -t "$SESSION" pane-border-format " #{pane_title} "

tmux send-keys -t "$SESSION:0.1" "'$WORKSPACE/architect-pane.sh' '$ARCHITECT_A_NAME' '$ARCHITECT_A_COLOR' '$ARCHITECT_A_CMD' '$WORKSPACE/a' '$PACE'" Enter
tmux send-keys -t "$SESSION:0.2" "'$WORKSPACE/architect-pane.sh' '$ARCHITECT_B_NAME' '$ARCHITECT_B_COLOR' '$ARCHITECT_B_CMD' '$WORKSPACE/b' '$PACE'" Enter

# Give panes time to start before orchestrator
sleep 1

echo "$FRAMEWORK" > "$WORKSPACE/framework.txt"
echo "$PROBLEM" > "$WORKSPACE/problem.txt"
tmux send-keys -t "$SESSION:0.0" "FRAMEWORK=\$(cat '$WORKSPACE/framework.txt') && PROBLEM=\$(cat '$WORKSPACE/problem.txt') && '$WORKSPACE/orchestrator.sh' '$WORKSPACE' \"\$PROBLEM\" '$MAX_ROUNDS' '$PAUSE_BETWEEN_TURNS' '$ARCHITECT_A_NAME' '$ARCHITECT_B_NAME' \"\$FRAMEWORK\" '$SESSION_LOG'" Enter

tmux attach -t "$SESSION"
tmux kill-session -t "$SESSION" 2>/dev/null || true
