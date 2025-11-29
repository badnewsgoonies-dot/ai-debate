#!/bin/sh
# Phase 2 - Complete Setup Script
# Run this after Phase 1 packages are installed

set -e

echo "=========================================="
echo " PHASE 2: Secure API Key Integration"
echo "=========================================="
echo ""

# Create keys file from template if not exists
if [ ! -f "$HOME/.ai-keys.env" ]; then
    echo "[1/4] Creating keys file template..."
    cp phase2-keys.env.template "$HOME/.ai-keys.env"
    chmod 600 "$HOME/.ai-keys.env"
    echo "      Created ~/.ai-keys.env (permissions: 600)"
else
    echo "[1/4] Keys file already exists"
fi

# Add auto-load to shell profile
echo "[2/4] Configuring shell auto-load..."
PROFILE="$HOME/.profile"
LOADER_LINE='. ~/ai-orchestrator/phase2-load_keys.sh 2>/dev/null'

if ! grep -q "phase2-load_keys" "$PROFILE" 2>/dev/null; then
    echo "$LOADER_LINE" >> "$PROFILE"
    echo "      Added key loader to $PROFILE"
else
    echo "      Already in $PROFILE"
fi

# Make scripts executable
echo "[3/4] Setting script permissions..."
chmod +x phase2-load_keys.sh phase2-validate_keys.sh 2>/dev/null || true
echo "      Done"

# Instructions
echo "[4/4] Setup complete!"
echo ""
echo "=========================================="
echo " NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Edit your keys file:"
echo "   vi ~/.ai-keys.env"
echo ""
echo "2. Add your API keys (get them from):"
echo "   - OpenAI:    https://platform.openai.com/api-keys"
echo "   - Anthropic: https://console.anthropic.com/settings/keys"
echo "   - GitHub:    https://github.com/settings/tokens"
echo ""
echo "3. Load keys in current session:"
echo "   . ./phase2-load_keys.sh"
echo ""
echo "4. Validate keys are working:"
echo "   ./phase2-validate_keys.sh"
echo ""
echo "=========================================="
