#!/bin/sh
# Phase 1 - Environment Check Script for iSH

echo "=== Checking Core Environment ==="

check() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "[OK] $1 found"
  else
    echo "[FAIL] $1 NOT FOUND"
  fi
}

check python3
check pip
check node
check npm
check git
check jq
check curl
check bash

echo ""
echo "=== Version Summary ==="
python3 --version 2>/dev/null
pip --version 2>/dev/null
node --version 2>/dev/null
npm --version 2>/dev/null
git --version 2>/dev/null

echo ""
echo "Environment check complete."
