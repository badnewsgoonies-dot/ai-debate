#!/bin/sh
# Phase 3 - Install AI Orchestration CLIs for iSH
# Run after Phase 1 (packages) and Phase 2 (keys)

set -e

echo "=========================================="
echo " PHASE 3: AI CLI Installation"
echo "=========================================="
echo ""

# Ensure PATH includes npm globals
export PATH=~/.npm-global/bin:$PATH

# Python CLIs
echo "[1/4] Installing Anthropic CLI..."
pip install --quiet anthropic
echo "      Done"

echo "[2/4] Installing OpenAI CLI..."
pip install --quiet openai
echo "      Done"

# Node CLIs
echo "[3/4] Installing Codex CLI..."
npm install -g @openai/codex --silent 2>/dev/null || npm install -g @openai/codex
echo "      Done"

# Optional: GitHub Copilot CLI (requires auth)
echo "[4/4] Checking GitHub Copilot CLI..."
if command -v gh >/dev/null 2>&1; then
    gh extension install github/gh-copilot 2>/dev/null || echo "      (already installed or needs auth)"
else
    echo "      Skipped (gh CLI not installed)"
fi

echo ""
echo "=========================================="
echo " Installation Complete"
echo "=========================================="
echo ""
echo "Verify with:"
echo "  python3 -c 'import anthropic; print(\"anthropic:\", anthropic.__version__)'"
echo "  python3 -c 'import openai; print(\"openai:\", openai.__version__)'"
echo "  codex --version"
echo ""
