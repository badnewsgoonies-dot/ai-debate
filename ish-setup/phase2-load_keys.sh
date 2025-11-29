#!/bin/sh
# Phase 2 - Secure Key Loader for iSH
# Sources API keys from protected file

KEYS_FILE="$HOME/.ai-keys.env"

if [ ! -f "$KEYS_FILE" ]; then
    echo "[ERROR] Keys file not found: $KEYS_FILE"
    echo ""
    echo "Create it with:"
    echo "  cp phase2-keys.env.template ~/.ai-keys.env"
    echo "  chmod 600 ~/.ai-keys.env"
    echo "  vi ~/.ai-keys.env  # add your keys"
    exit 1
fi

# Check permissions (should be 600)
PERMS=$(stat -c %a "$KEYS_FILE" 2>/dev/null || stat -f %Lp "$KEYS_FILE" 2>/dev/null)
if [ "$PERMS" != "600" ]; then
    echo "[WARN] Keys file has loose permissions: $PERMS"
    echo "       Fixing to 600..."
    chmod 600 "$KEYS_FILE"
fi

# Source the keys
. "$KEYS_FILE"

echo "[OK] API keys loaded from $KEYS_FILE"
