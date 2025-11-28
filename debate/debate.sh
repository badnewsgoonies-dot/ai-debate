#!/usr/bin/env bash
#
# AI Debate Orchestrator
# Pits two AI agents against each other in a live, streaming debate
#
# Usage: ./debate.sh [topic]
# Example: ./debate.sh "Should AI have rights?"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env" 2>/dev/null || true

# Defaults (can be overridden in config.env)
DEBATER_A_CMD="${DEBATER_A_CMD:-claude -p}"
DEBATER_B_CMD="${DEBATER_B_CMD:-codex exec}"
DEBATER_A_NAME="${DEBATER_A_NAME:-Claude}"
DEBATER_B_NAME="${DEBATER_B_NAME:-Codex}"
DEBATER_A_COLOR="${DEBATER_A_COLOR:-colour39}"   # Blue
DEBATER_B_COLOR="${DEBATER_B_COLOR:-colour208}"  # Orange
ROUNDS="${ROUNDS:-3}"
PACE="${PACE:-80}"  # Characters per second (0 = full speed)
PAUSE_BETWEEN_TURNS="${PAUSE_BETWEEN_TURNS:-2}"

# Topic from argument or prompt
TOPIC="${1:-}"
if [[ -z "$TOPIC" ]]; then
    echo "🎭 AI Debate Arena"
    echo "═══════════════════════════════════════"
    echo ""
    read -p "Enter debate topic: " TOPIC
fi

if [[ -z "$TOPIC" ]]; then
    echo "Error: No topic provided"
    exit 1
fi

# Create temp workspace
WORKSPACE=$(mktemp -d /tmp/debate.XXXXXX)
trap "rm -rf $WORKSPACE" EXIT

mkdir -p "$WORKSPACE/a" "$WORKSPACE/b"

# Load debate framework
FRAMEWORK_FILE="$SCRIPT_DIR/debate-framework.txt"
if [[ -f "$FRAMEWORK_FILE" ]]; then
    FRAMEWORK=$(cat "$FRAMEWORK_FILE")
else
    FRAMEWORK="You are a skilled debater. Argue your assigned position effectively. Be concise (80-120 words). No markdown."
fi

# Create the debater pane script
cat > "$WORKSPACE/debater.sh" << 'DEBATER_SCRIPT'
#!/usr/bin/env bash
# Debater pane script - waits for prompts and streams responses

NAME="$1"
COLOR="$2"
CMD="$3"
WORKDIR="$4"
PACE="$5"

# ANSI colors
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

# Wait for prompts
while true; do
    # Wait for prompt file
    while [[ ! -f "$WORKDIR/prompt.txt" ]]; do
        sleep 0.1
    done

    PROMPT=$(cat "$WORKDIR/prompt.txt")
    rm -f "$WORKDIR/prompt.txt"

    # Check for exit signal
    if [[ "$PROMPT" == "__EXIT__" ]]; then
        echo -e "\n${DIM}[Debate concluded]${RESET}"
        break
    fi

    echo -e "${DIM}─────────────────────────────────────────${RESET}"
    echo ""

    # Run the AI command and stream with pacing
    if [[ "$PACE" -gt 0 ]] && command -v pv &>/dev/null; then
        $CMD "$PROMPT" 2>/dev/null | tee "$WORKDIR/response.txt" | pv -qL "$PACE"
    else
        # Fallback: character-by-character with sleep
        $CMD "$PROMPT" 2>/dev/null | tee "$WORKDIR/response.txt" | while IFS= read -r -n1 char; do
            printf '%s' "$char"
            if [[ "$PACE" -gt 0 ]]; then
                sleep $(echo "scale=4; 1/$PACE" | bc)
            fi
        done
    fi

    echo ""
    echo ""

    # Signal completion
    touch "$WORKDIR/done"
done
DEBATER_SCRIPT
chmod +x "$WORKSPACE/debater.sh"

# Create the orchestrator script
cat > "$WORKSPACE/orchestrator.sh" << 'ORCH_SCRIPT'
#!/usr/bin/env bash
# Orchestrator - manages the debate flow

WORKSPACE="$1"
TOPIC="$2"
ROUNDS="$3"
PAUSE="$4"
NAME_A="$5"
NAME_B="$6"
FRAMEWORK="$7"

BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
CYAN="\033[36m"

clear
echo -e "${CYAN}${BOLD}"
echo "    ╔═══════════════════════════════════════════════════════════╗"
echo "    ║                    🎭 AI DEBATE ARENA 🎭                  ║"
echo "    ╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""
echo -e "${BOLD}Topic:${RESET} $TOPIC"
echo -e "${BOLD}Rounds:${RESET} $ROUNDS"
echo -e "${BOLD}Debaters:${RESET} $NAME_A vs $NAME_B"
echo ""
echo -e "${DIM}════════════════════════════════════════════════════════════════${RESET}"

wait_for_done() {
    local dir="$1"
    while [[ ! -f "$dir/done" ]]; do
        sleep 0.2
    done
    rm -f "$dir/done"
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

sleep 2  # Let panes initialize

# Opening statements
echo ""
echo -e "${CYAN}${BOLD}► OPENING STATEMENTS${RESET}"
echo ""

# Debater A opens
echo -e "${DIM}[$NAME_A is formulating opening argument...]${RESET}"
send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

DEBATE TOPIC: \"$TOPIC\"
YOUR POSITION: FOR (argue in favor)
PHASE: Opening Statement

Deliver your opening argument. Remember: you have no personal bias on this topic - argue the FOR position as effectively as possible. Consider the strongest counter-arguments and address them preemptively where strategic."
wait_for_done "$WORKSPACE/a"
RESPONSE_A=$(get_response "$WORKSPACE/a")

sleep $PAUSE

# Debater B opens
echo -e "${DIM}[$NAME_B is formulating opening argument...]${RESET}"
send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

DEBATE TOPIC: \"$TOPIC\"
YOUR POSITION: AGAINST (argue in opposition)
PHASE: Opening Statement

Deliver your opening argument. Remember: you have no personal bias on this topic - argue the AGAINST position as effectively as possible. Consider the strongest counter-arguments and address them preemptively where strategic."
wait_for_done "$WORKSPACE/b"
RESPONSE_B=$(get_response "$WORKSPACE/b")

sleep $PAUSE

# Rebuttals
for ((round=1; round<=ROUNDS; round++)); do
    echo ""
    echo -e "${CYAN}${BOLD}► ROUND $round / $ROUNDS${RESET}"
    echo ""

    # A rebuts B
    echo -e "${DIM}[$NAME_A is preparing rebuttal...]${RESET}"
    send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

DEBATE TOPIC: \"$TOPIC\"
YOUR POSITION: FOR
PHASE: Rebuttal (Round $round)

Your opponent just argued:
\"\"\"
$RESPONSE_B
\"\"\"

Respond to their specific points. Concede what is valid, challenge what is weak, and advance your strongest counter-argument. Stay focused on the crux of disagreement."
    wait_for_done "$WORKSPACE/a"
    RESPONSE_A=$(get_response "$WORKSPACE/a")

    sleep $PAUSE

    # B rebuts A
    echo -e "${DIM}[$NAME_B is preparing rebuttal...]${RESET}"
    send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

DEBATE TOPIC: \"$TOPIC\"
YOUR POSITION: AGAINST
PHASE: Rebuttal (Round $round)

Your opponent just argued:
\"\"\"
$RESPONSE_A
\"\"\"

Respond to their specific points. Concede what is valid, challenge what is weak, and advance your strongest counter-argument. Stay focused on the crux of disagreement."
    wait_for_done "$WORKSPACE/b"
    RESPONSE_B=$(get_response "$WORKSPACE/b")

    sleep $PAUSE
done

# Closing statements
echo ""
echo -e "${CYAN}${BOLD}► CLOSING STATEMENTS${RESET}"
echo ""

echo -e "${DIM}[$NAME_A is preparing closing...]${RESET}"
send_prompt "$WORKSPACE/a" "$FRAMEWORK

---

DEBATE TOPIC: \"$TOPIC\"
YOUR POSITION: FOR
PHASE: Closing Statement

Deliver a concise, memorable closing. Crystallize your strongest argument in 2-3 sentences. Acknowledge the legitimate tension in this debate, then explain why your position ultimately prevails."
wait_for_done "$WORKSPACE/a"

sleep $PAUSE

echo -e "${DIM}[$NAME_B is preparing closing...]${RESET}"
send_prompt "$WORKSPACE/b" "$FRAMEWORK

---

DEBATE TOPIC: \"$TOPIC\"
YOUR POSITION: AGAINST
PHASE: Closing Statement

Deliver a concise, memorable closing. Crystallize your strongest argument in 2-3 sentences. Acknowledge the legitimate tension in this debate, then explain why your position ultimately prevails."
wait_for_done "$WORKSPACE/b"

echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}                      🎭 DEBATE CONCLUDED 🎭${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${DIM}Press Enter to exit...${RESET}"

# Signal debaters to exit
send_prompt "$WORKSPACE/a" "__EXIT__"
send_prompt "$WORKSPACE/b" "__EXIT__"

read
ORCH_SCRIPT
chmod +x "$WORKSPACE/orchestrator.sh"

# Check for tmux
if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is required. Install with: sudo apt install tmux"
    exit 1
fi

# Ensure proper terminal
export TERM="${TERM:-xterm-256color}"

# Force terminal size - hardcode if detection fails
COLS=180
ROWS=50

# Launch tmux session
SESSION="debate_$$"

# Kill any existing session with same name
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Create session with explicit size
tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"

# Create layout: orchestrator on top, two debaters below side-by-side
# Use line counts instead of percentages to avoid "size missing" error
tmux split-window -v -l 35 -t "$SESSION"
tmux split-window -h -l 90 -t "$SESSION:0.1"

# Set pane colors/titles
tmux select-pane -t "$SESSION:0.0" -T "Orchestrator"
tmux select-pane -t "$SESSION:0.1" -T "$DEBATER_A_NAME"
tmux select-pane -t "$SESSION:0.2" -T "$DEBATER_B_NAME"

# Enable pane borders with titles
tmux set -t "$SESSION" pane-border-status top
tmux set -t "$SESSION" pane-border-format " #{pane_title} "

# Start debater A (left pane)
tmux send-keys -t "$SESSION:0.1" "'$WORKSPACE/debater.sh' '$DEBATER_A_NAME' '$DEBATER_A_COLOR' '$DEBATER_A_CMD' '$WORKSPACE/a' '$PACE'" Enter

# Start debater B (right pane)
tmux send-keys -t "$SESSION:0.2" "'$WORKSPACE/debater.sh' '$DEBATER_B_NAME' '$DEBATER_B_COLOR' '$DEBATER_B_CMD' '$WORKSPACE/b' '$PACE'" Enter

# Start orchestrator (top pane)
# Write framework to temp file for orchestrator to read (avoids quoting hell)
echo "$FRAMEWORK" > "$WORKSPACE/framework.txt"

tmux send-keys -t "$SESSION:0.0" "FRAMEWORK=\$(cat '$WORKSPACE/framework.txt') && '$WORKSPACE/orchestrator.sh' '$WORKSPACE' '$TOPIC' '$ROUNDS' '$PAUSE_BETWEEN_TURNS' '$DEBATER_A_NAME' '$DEBATER_B_NAME' \"\$FRAMEWORK\"" Enter

# Attach to session
tmux attach -t "$SESSION"

# Cleanup
tmux kill-session -t "$SESSION" 2>/dev/null || true
