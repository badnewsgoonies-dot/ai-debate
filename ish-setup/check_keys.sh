#!/bin/sh
# Phase 2 - Key Validation Script for iSH
# Verifies API keys are loaded and working

echo "=== Verifying AI Key Environment ==="

check_env() {
  if [ -z "$1" ]; then
    echo "[FAIL] $2 is NOT LOADED"
  else
    # Mask the key (show first 4 and last 4 chars)
    MASKED=$(echo "$1" | sed 's/^\(.\{4\}\).*\(.\{4\}\)$/\1****\2/')
    echo "[OK] $2 = $MASKED"
  fi
}

check_env "$OPENAI_API_KEY" "OpenAI API key"
check_env "$ANTHROPIC_API_KEY" "Anthropic (Claude) API key"
check_env "$GITHUB_TOKEN" "GitHub token (Copilot)"

echo ""
echo "=== Checking API Connectivity ==="

# Test OpenAI
if [ -n "$OPENAI_API_KEY" ]; then
  echo -n "Testing OpenAI... "
  RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    https://api.openai.com/v1/models 2>/dev/null)
  [ "$RESP" = "200" ] && echo "[OK]" || echo "[FAIL] HTTP $RESP"
fi

# Test Anthropic
if [ -n "$ANTHROPIC_API_KEY" ]; then
  echo -n "Testing Anthropic... "
  RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    https://api.anthropic.com/v1/messages 2>/dev/null)
  # 400 expected (no body), 401 means bad key
  [ "$RESP" = "400" ] && echo "[OK]" || echo "[FAIL] HTTP $RESP"
fi

# Test GitHub
if [ -n "$GITHUB_TOKEN" ]; then
  echo -n "Testing GitHub... "
  RESP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/user 2>/dev/null)
  [ "$RESP" = "200" ] && echo "[OK]" || echo "[FAIL] HTTP $RESP"
fi

echo ""
echo "Key validation complete."
