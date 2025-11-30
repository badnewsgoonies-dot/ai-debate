#!/usr/bin/env python3
"""
PATTERN 1: QUINE - Self-Replicating Code
A program that outputs its own source code exactly.

Why this matters for AI agents:
- Foundation for self-modification (read self, modify, write new version)
- Understanding program structure introspectively
- Base pattern for genetic programming evolution
"""

# Simple Python quine
s = 's = %r\nprint(s %% s)'
print(s % s)
