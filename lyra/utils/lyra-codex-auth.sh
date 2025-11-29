#!/bin/sh
# LYRA - Codex Auth Injector
# Paste your ~/.codex/auth.json content when prompted

echo "=== LYRA Codex Auth Setup ==="
echo ""
echo "On your local machine (with browser), run:"
echo "  codex login"
echo "  cat ~/.codex/auth.json"
echo ""
echo "Then paste the JSON content below (press Ctrl+D when done):"
echo ""

# Create codex directory
mkdir -p ~/.codex

# Read multiline input
AUTH_JSON=$(cat)

# Save to auth.json
echo "$AUTH_JSON" > ~/.codex/auth.json
chmod 600 ~/.codex/auth.json

echo ""
echo "Auth saved to ~/.codex/auth.json"
echo ""

# Verify
export PATH=/opt/node22/bin:~/.npm-global/bin:$PATH
echo "Checking login status..."
codex login status
