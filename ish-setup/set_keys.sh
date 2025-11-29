#!/bin/sh
# Phase 2 - Secure Key Setup for iSH
# Stores API keys with base64 encoding in protected directory

echo "=== Setting up API keys safely ==="

# Ensure secure directory exists
mkdir -p ~/.ai-secure
chmod 700 ~/.ai-secure

read -p "Enter your OpenAI API key: " OPENAI_KEY
read -p "Enter your Anthropic API key (Claude): " ANTHROPIC_KEY
read -p "Enter your GitHub token (Copilot): " GITHUB_KEY

# Save base64 encoded (protects formatting, not encryption)
echo "$OPENAI_KEY" | base64 > ~/.ai-secure/openai.key
echo "$ANTHROPIC_KEY" | base64 > ~/.ai-secure/anthropic.key
echo "$GITHUB_KEY" | base64 > ~/.ai-secure/github.key

chmod 600 ~/.ai-secure/*.key

# Write loader file
cat > ~/.ai-secure/load_keys.sh << 'EOFLT'
#!/bin/sh
export OPENAI_API_KEY="$(base64 -d ~/.ai-secure/openai.key 2>/dev/null)"
export ANTHROPIC_API_KEY="$(base64 -d ~/.ai-secure/anthropic.key 2>/dev/null)"
export GITHUB_TOKEN="$(base64 -d ~/.ai-secure/github.key 2>/dev/null)"
EOFLT

chmod 600 ~/.ai-secure/load_keys.sh

echo ""
echo "[OK] Keys saved to ~/.ai-secure/"
echo "[OK] Loader created: ~/.ai-secure/load_keys.sh"
echo ""
echo "Add to your profile with:"
echo "  echo '. ~/.ai-secure/load_keys.sh' >> ~/.profile"
