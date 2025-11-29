#!/bin/sh
# Phase 2 - Validate API Keys are set

echo "=== Validating API Keys ==="

check_key() {
    KEY_NAME="$1"
    eval KEY_VAL="\$$KEY_NAME"

    if [ -n "$KEY_VAL" ]; then
        # Show first/last 4 chars only
        MASKED=$(echo "$KEY_VAL" | sed 's/^\(.\{4\}\).*\(.\{4\}\)$/\1****\2/')
        echo "[OK] $KEY_NAME = $MASKED"
    else
        echo "[--] $KEY_NAME = (not set)"
    fi
}

check_key OPENAI_API_KEY
check_key ANTHROPIC_API_KEY
check_key GITHUB_TOKEN
check_key GOOGLE_API_KEY

echo ""
echo "=== Quick API Tests ==="

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
    # 400 is expected (no body), 401 means bad key
    [ "$RESP" = "400" ] && echo "[OK]" || echo "[FAIL] HTTP $RESP"
fi

echo ""
echo "Validation complete."
