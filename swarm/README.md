# Swarm Toolkit Overview

## Core Orchestrators
- `multi-agent.sh` — 3-agent triad (Codex, Claude, Copilot); Claude-led path does Copilot draft → Codex draft → Claude vote/merge.
- `multi-brain.sh` — 2-tier swarm: brains (codex-max) dispatch minis (codex-mini/low) and merge outputs; emits `meta.json`, run dir under `swarm/runs/`.
- `parallel-swarm.sh`, `hybrid-swarm.sh` — parallel specialists with aggregation.
- `study-swarm.sh` — recursive research agent, depth-limited.
- `summarize-runs.sh` — quick CLI digest across `swarm/runs/` (supports multi-brain, contradiction-hunter, etc.).

## Analysis / Self-Improve
- `contradiction-hunter.sh` — mine problems → generate experiments (brain/drone effort split) → run iterators → Guardian + Claude review.
- `prompt-evolver.sh`, `reflexion.sh`, `self-improve/*` (darwin-loop, prompt-evolver, reflexion, skill-library).
- Tools: `swarm/tools/view_results.py` (JSONL anomaly viewer).

## Shared Libraries
- `swarm/lib/common.sh` — logging helpers, init log dir.
- `swarm/lib/log.sh` — structured JSON logging and meta helpers.
- `swarm/lib/preflight.sh` — dependency/env checks.

## Safety / Flags
- `SAFE_MODE=1` (default) → workspace-write sandbox; `ALLOW_DANGER=1` to allow danger-full-access (only when needed).
- `BRAIN_EFFORT`, `DRONE_EFFORT`, `MINI_EFFORT` control `model_reasoning_effort` for Codex calls.
- `DRY_RUN=1` where supported to avoid execution; Guardian audits in contradiction-hunter; add Guardian as a gate to other scripts as needed.

## Dependencies
- CLIs: `codex`, `claude`, `copilot`/`gh copilot`, `jq`, `tmux` (for some scripts), `chromium` (visual-loop), `guardian.sh`.
- Install check: ensure commands are on PATH; use `swarm/lib/preflight.sh` with `REQUIRE_CMDS=(codex claude copilot jq)`.

## Run Logs & Outputs
- Run artifacts under `swarm/runs/<script>_<timestamp>/` (meta.json, logs, outputs). Use `bash swarm/summarize-runs.sh` for a digest.

## Notes
- Keep scripts strict: `#!/usr/bin/env bash`, `set -euo pipefail`, quoted vars, preflight checks.
- Prefer structured logs/JSON outputs where possible for downstream parsing.
