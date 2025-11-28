#!/bin/bash
#
# setup-env.sh - Configure environment for ai-debate tools
#
# Usage: ./setup-env.sh
#        OPENAI_API_KEY="sk-..." ./setup-env.sh
#

set -e

# npm global directory (avoid sudo)
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Add to PATH
export PATH=/opt/node22/bin:~/.npm-global/bin:$PATH

# Install codex CLI
npm install -g @openai/codex

# Login - opens browser for ChatGPT Pro auth (or use API key)
if [ -n "$OPENAI_API_KEY" ]; then
    echo "$OPENAI_API_KEY" | codex login --with-api-key
else
    echo "Run 'codex login' to authenticate with ChatGPT Pro"
fi

echo "Setup complete! Run 'codex --version' to verify."
