#!/bin/sh
# LYRA System Check

echo "=== LYRA SYSTEM CHECK ==="
echo ""

# Show banner
~/lyra/utils/lyra-banner.sh

# Version
cat ~/lyra/lyra.version
echo ""

check() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "[OK] $1"
  else
    echo "[--] $1 (not installed)"
  fi
}

echo "=== Core Tools ==="
check python3
check pip
check node
check npm
check git
check jq
check curl

echo ""
echo "=== AI Engines ==="

# Python modules
python3 -c 'import anthropic' 2>/dev/null && echo "[OK] anthropic (Lyra-Core)" || echo "[--] anthropic"
python3 -c 'import openai' 2>/dev/null && echo "[OK] openai (Lyra-Architect)" || echo "[--] openai"

# Node CLIs
export PATH=~/.npm-global/bin:$PATH
check codex
check claude

# GitHub Copilot
if command -v gh >/dev/null 2>&1; then
  gh copilot --version >/dev/null 2>&1 && echo "[OK] gh-copilot (Lyra-Fixer)" || echo "[--] gh-copilot"
fi

echo ""
echo "=== Directory Structure ==="
for dir in brain agents pipeline presets keys logs utils; do
  [ -d ~/lyra/$dir ] && echo "[OK] ~/lyra/$dir" || echo "[--] ~/lyra/$dir missing"
done

echo ""
echo "Lyra System Check Complete."
