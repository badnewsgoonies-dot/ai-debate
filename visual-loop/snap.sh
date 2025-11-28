#!/usr/bin/env bash
#
# snap.sh - Take screenshot of running app
# Usage: ./snap.sh [url] [output.png] [--path /route] [--delay ms]
#
set -euo pipefail

URL="${1:-http://localhost:5173}"
OUTPUT="${2:-/tmp/snap-$(date +%s).png}"
WINDOW_SIZE="${WINDOW_SIZE:-1280,720}"
URL_PATH=""
DELAY=0

# Parse additional options
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) URL_PATH="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Append path to URL
[[ -n "$URL_PATH" ]] && URL="${URL%/}${URL_PATH}"

# Find chromium
CHROMIUM=""
for cmd in chromium chromium-browser google-chrome google-chrome-stable; do
    if command -v "$cmd" &>/dev/null; then
        CHROMIUM="$cmd"
        break
    fi
done

[[ -n "$CHROMIUM" ]] || { echo "Error: No chromium/chrome found"; exit 1; }

mkdir -p "$(dirname "$OUTPUT")"

# Optional delay for SPA to load
[[ "$DELAY" -gt 0 ]] && sleep "$(echo "scale=3; $DELAY/1000" | bc)"

# Take screenshot
"$CHROMIUM" --headless --disable-gpu --screenshot="$OUTPUT" --window-size="$WINDOW_SIZE" "$URL" 2>/dev/null

echo "$OUTPUT"
