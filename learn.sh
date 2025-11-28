#!/usr/bin/env bash
#
# Learn - Knowledge-building loop
# Runs architect discussions and accumulates insights
#
# Usage: ./learn.sh "problem to discuss"
#        ./learn.sh --review              # review recent learnings
#        ./learn.sh --list                # list all sessions
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="$SCRIPT_DIR/knowledge"
LEARNINGS_FILE="$KNOWLEDGE_DIR/learnings.md"
SESSIONS_DIR="$KNOWLEDGE_DIR/sessions"

mkdir -p "$KNOWLEDGE_DIR" "$SESSIONS_DIR"

# Initialize learnings file if needed
if [[ ! -f "$LEARNINGS_FILE" ]]; then
    cat > "$LEARNINGS_FILE" << 'EOF'
# Accumulated Learnings

Knowledge extracted from architect discussions.

---

EOF
fi

# Colors
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

case "${1:-}" in
    --review|-r)
        echo -e "${CYAN}${BOLD}Recent Learnings:${RESET}"
        echo ""
        tail -50 "$LEARNINGS_FILE"
        exit 0
        ;;
    --list|-l)
        echo -e "${CYAN}${BOLD}Past Sessions:${RESET}"
        ls -lt "$SESSIONS_DIR"/*.md 2>/dev/null | head -20 || echo "No sessions yet"
        exit 0
        ;;
    --help|-h)
        echo "Usage: ./learn.sh [options] \"problem to discuss\""
        echo ""
        echo "Options:"
        echo "  -r, --review    Show recent learnings"
        echo "  -l, --list      List past sessions"
        echo "  -h, --help      Show this help"
        echo ""
        echo "Examples:"
        echo "  ./learn.sh \"Should we use Redux or Zustand?\""
        echo "  ./learn.sh \"How should error boundaries work in React?\""
        exit 0
        ;;
    "")
        echo "Error: No problem provided"
        echo "Usage: ./learn.sh \"problem to discuss\""
        exit 1
        ;;
esac

PROBLEM="$1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_FILE="$SESSIONS_DIR/session_$TIMESTAMP.md"

echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  LEARN - Knowledge Building Loop${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${BOLD}Problem:${RESET} $PROBLEM"
echo ""

# Step 1: Run architect headless
echo -e "${YELLOW}► Step 1: Running architect discussion...${RESET}"
echo ""

"$SCRIPT_DIR/architect/architect.sh" --headless "$PROBLEM" | tee "$SESSION_FILE"
ARCHITECT_EXIT=$?

echo ""

# Step 2: Extract insights (using claude to summarize)
echo -e "${YELLOW}► Step 2: Extracting insights...${RESET}"
echo ""

SUMMARY=$(claude -p "You are a knowledge curator. Read this architect discussion and extract 2-4 key insights or decisions. Be concise - bullet points only, no fluff.

---

$(cat "$SESSION_FILE")

---

Format:
- **Insight 1**: [one line]
- **Insight 2**: [one line]
..." 2>/dev/null || echo "- Discussion completed (manual review needed)")

echo -e "${GREEN}$SUMMARY${RESET}"
echo ""

# Step 3: Append to learnings
echo -e "${YELLOW}► Step 3: Recording to knowledge base...${RESET}"

{
    echo ""
    echo "## $(date '+%Y-%m-%d %H:%M') - $PROBLEM"
    echo ""
    echo "$SUMMARY"
    echo ""
    echo "---"
} >> "$LEARNINGS_FILE"

echo -e "${GREEN}✓ Added to $LEARNINGS_FILE${RESET}"
echo ""

# Summary
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Session Complete${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "Session transcript: ${DIM}$SESSION_FILE${RESET}"
echo -e "Knowledge base:     ${DIM}$LEARNINGS_FILE${RESET}"
echo ""

if [[ $ARCHITECT_EXIT -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ Consensus reached${RESET}"
else
    echo -e "${YELLOW}${BOLD}⚠ No consensus - may need follow-up${RESET}"
fi
