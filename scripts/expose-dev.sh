#!/usr/bin/env bash
# Expose a local dev server on LAN for mobile testing (iPhone)
# Usage examples:
#   ./scripts/expose-dev.sh                  # default: python3 -m http.server 8000
#   PORT=5173 COMMAND="npm run dev -- --host 0.0.0.0 --port \$PORT" ./scripts/expose-dev.sh

set -euo pipefail

PORT="${PORT:-8000}"
COMMAND="${COMMAND:-python3 -m http.server $PORT}"

# Get LAN IP (ignoring 127.0.0.1)
LAN_IP=$(ip -4 addr show | awk '/inet / && $2 !~ /^127/ {print $2}' | cut -d/ -f1 | head -n1)

if [[ -z "$LAN_IP" ]]; then
  echo "Could not determine LAN IP. Are you on Wi‑Fi/LAN?" >&2
  exit 1
fi

echo "== Exposing dev server =="
echo "LAN IP: $LAN_IP"
echo "Port:   $PORT"
echo "iPhone test: curl http://$LAN_IP:$PORT/"
echo "Starting: $COMMAND"
echo "Press Ctrl+C to stop."

# Optional: open firewall port if using ufw (requires sudo):
# if command -v ufw >/dev/null 2>&1; then
#   echo "Attempting to allow port $PORT via ufw..."
#   sudo ufw allow "$PORT"/tcp || true
# fi

# Run the server bound to all interfaces (host command must listen on 0.0.0.0)
eval "$COMMAND"
