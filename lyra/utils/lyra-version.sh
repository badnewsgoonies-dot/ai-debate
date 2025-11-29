#!/bin/sh
# LYRA Version Check

echo "=== Lyra Version ==="
cat ~/lyra/lyra.version
echo ""
echo "Build: $(date +%Y%m%d)"
echo "Platform: $(uname -s)"
