#!/bin/sh
# Phase 3 - Validate AI CLI Installation

echo "=== AI CLI Version Check ==="

# Python modules
echo ""
echo "Python CLIs:"
python3 -c 'import anthropic; print("  [OK] anthropic:", anthropic.__version__)' 2>/dev/null \
    || echo "  [FAIL] anthropic not installed"
python3 -c 'import openai; print("  [OK] openai:", openai.__version__)' 2>/dev/null \
    || echo "  [FAIL] openai not installed"

# Node CLIs
echo ""
echo "Node CLIs:"
export PATH=~/.npm-global/bin:$PATH
if command -v codex >/dev/null 2>&1; then
    echo "  [OK] codex: $(codex --version 2>/dev/null)"
else
    echo "  [FAIL] codex not installed"
fi

# Claude Code (if available)
if command -v claude >/dev/null 2>&1; then
    echo "  [OK] claude: $(claude --version 2>/dev/null)"
fi

# GitHub Copilot
if command -v gh >/dev/null 2>&1; then
    if gh copilot --version >/dev/null 2>&1; then
        echo "  [OK] gh copilot installed"
    else
        echo "  [--] gh copilot not configured"
    fi
fi

echo ""
echo "=== Quick API Test ==="

# Test if keys are loaded
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -n "Anthropic API... "
    python3 -c "
import anthropic
c = anthropic.Anthropic()
print('[OK] connected')
" 2>/dev/null || echo "[FAIL]"
else
    echo "Anthropic API... [SKIP] no key"
fi

if [ -n "$OPENAI_API_KEY" ]; then
    echo -n "OpenAI API... "
    python3 -c "
import openai
c = openai.OpenAI()
c.models.list()
print('[OK] connected')
" 2>/dev/null || echo "[FAIL]"
else
    echo "OpenAI API... [SKIP] no key"
fi

echo ""
echo "CLI check complete."
