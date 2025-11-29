# Swarm Best Practices Cheat Sheet

## Safety & Execution
- Default to `SAFE_MODE=1`; only set `ALLOW_DANGER=1` when you truly need spawning/subprocesses.
- Use `DRY_RUN=1` to validate flows before spending tokens or making changes.
- Cap parallelism with `MAX_JOBS` (e.g., 4–8); stagger launches if needed (`stagger_delay_ms` in `agents.json`).
- Set timeouts on agent calls (see `agents.json`); treat timeouts as failures.

## Shell Hygiene
- Always: `#!/usr/bin/env bash` and `set -euo pipefail`.
- Require deps early: `require_cmd codex claude jq` (preflight).
- Quote variables; fail fast on missing env/args.
- Use `swarm/lib/log.sh` for structured logging; `swarm/lib/preflight.sh` for dependency checks.

## Logging & Metadata
- Structured logs (JSON) via `log.sh`; keep `session.log` per run dir.
- Emit `meta.json` with task, counts, efforts, safety flags, timestamp.
- Track progress with `progress.sh` (`progress.json`).
- Summaries: `bash swarm/summarize-runs.sh` to skim outputs across runs.

## Effort Levels & Roles
- Brains: `model_reasoning_effort=xhigh` (decompose/merge).
- Seniors: `medium` (sub-plan coordination).
- Workers: `low` or `codex-mini` (fast execution).
- Advisor: Claude for review/merge; Copilot for hints only.

## File Layout & Handoffs
- Use structured JSON for subplans/worker tasks (explicit ids, task, expected_output).
- Workers write JSONL results with `id`, `result`, `confidence`, `notes`.
- Merge with `merge_results.sh` (voting/concat) and keep merged artifacts.

## Guardrails
- Run Guardian on final outputs when possible (`guardian/guardian.sh --audit <file>`).
- Use safe temp dirs/work dirs to avoid polluting the repo.

## Prompts (keep them tight)
- Brain: “Decompose into exactly 3 sub-plans; return strict JSON …”
- Senior: “Make exactly 3 worker tasks; return strict JSON …”
- Worker: “Do task; return JSON object {id, result, confidence, notes}.”
- Advisor: “Review worker results; resolve conflicts; produce FINAL_RESULT and ISSUES_FOUND.”

## Docs & Discoverability
- Keep `swarm/README.md` updated with deps, flags, and script roles.
- Add `--help`/usage to scripts for quick recall.

## Quick Usage
- Hierarchical dry run: `DRY_RUN=1 ./swarm/hierarchical-swarm.sh "task"`
- Real run (safe): `SAFE_MODE=1 DRY_RUN=0 ./swarm/hierarchical-swarm.sh "task"`
- Multi-brain (2-tier): `./swarm/multi-brain.sh "task" 1 3`
- Summaries: `bash swarm/summarize-runs.sh`
