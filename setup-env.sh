#!/bin/bash
#
# Environment Setup for ai-debate tools
# Run this script to configure npm globals and install AI CLIs
#
# Usage: ./setup-env.sh
#        OPENAI_API_KEY="sk-..." ./setup-env.sh
#

set -e

echo "Setting up ai-debate environment..."

# npm global directory (avoid sudo)
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo "✓ npm global directory configured"

# Ensure node and npm-global are in PATH
export PATH=/opt/node22/bin:~/.npm-global/bin:$PATH

# Add to bashrc if not already there
if ! grep -q 'npm-global/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
    echo "✓ Added npm-global to ~/.bashrc"
fi

if ! grep -q '/opt/node22/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH=/opt/node22/bin:$PATH' >> ~/.bashrc
    echo "✓ Added node to ~/.bashrc"
fi

# Install codex CLI
echo "Installing @openai/codex..."
npm install -g @openai/codex
echo "✓ Codex CLI installed ($(codex --version))"

# Login to codex
OPENAI_API_KEY="${OPENAI_API_KEY:-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}"
echo "$OPENAI_API_KEY" | codex login --with-api-key
echo "✓ Logged in to Codex"

# Verify claude CLI
if command -v claude &>/dev/null; then
    echo "✓ Claude CLI available ($(claude --version 2>/dev/null || echo 'installed'))"
else
    echo "⚠ Claude CLI not found in PATH"
fi

echo ""
echo "Setup complete! You may need to run: source ~/.bashrc"
echo ""
echo "Test with:"
echo "  codex --version"
echo "  claude --version"
