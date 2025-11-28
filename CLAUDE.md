# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

AI-Debate is a collection of bash scripts that orchestrate AI-to-AI interactions for various purposes: debates, collaborative design, autonomous development, and visual verification loops. All tools use tmux for multi-pane visualization and support headless operation.

**AI Tools Used:**
- `claude -p "prompt"` - Claude CLI for prompting
- `codex exec` - OpenAI Codex for code generation
- `codex exec -i image.png` - Codex with vision for screenshot analysis

---

## Commands

### Visual Development Loop
```bash
# Autonomous edit → screenshot → verify cycle
cd visual-loop
./auto.sh "Add a button to the header" --context-files "Header.tsx,Header.css"
./auto.sh "Fix the login form styling" --verify-code "login.*form|@keyframes"
./auto.sh "Change title color to blue" --expect "blue" --no-stash
```

### Task Orchestration
```bash
# Run task pipeline from task_list.json
cd visual-loop
./orchestrate.sh                    # Run all tasks
./orchestrate.sh --dry-run          # Preview without executing
./orchestrate.sh --stream visual    # Only visual tasks
./orchestrate.sh --start-from 3     # Skip first N tasks
./orchestrate.sh --review           # Pause for human approval each task
```

### AI Debates & Design
```bash
# Two AIs debate a topic (FOR vs AGAINST)
cd debate
./debate.sh "Should AI have consciousness rights?"

# Two AIs collaborate on a design decision
cd architect
./architect.sh "Should we use Redux or Zustand?"
./architect.sh --headless "Best database for this use case"

# Knowledge accumulation loop
./learn.sh "How should error boundaries work?"
./learn.sh --review  # View accumulated insights
```

### Other Tools
```bash
# User/Developer simulation
cd autopilot
./autopilot.sh "Add dark mode toggle"

# Screenshot utility
cd visual-loop
./snap.sh http://localhost:3000 /tmp/shot.png --delay 1000

# Vision analysis
./analyze.sh /tmp/shot.png "Is the button visible?"
```

---

## Architecture

```
ai-debate/
├── visual-loop/          # Autonomous visual development
│   ├── auto.sh           # Main loop: edit → screenshot → verify → iterate
│   ├── orchestrate.sh    # Runs task_list.json sequentially
│   ├── snap.sh           # Headless Chrome screenshots
│   ├── analyze.sh        # Vision model QA (codex with image)
│   └── task_list.json    # Task definitions with verification patterns
│
├── architect/            # Collaborative design sessions
│   ├── architect.sh      # Two AIs converge on solution
│   └── thinking-framework.txt
│
├── debate/               # Adversarial debates
│   ├── debate.sh         # FOR vs AGAINST debate
│   └── debate-framework.txt
│
├── autopilot/            # User/Dev simulation
│   └── autopilot.sh      # AI plays both roles until "ship it"
│
├── guardian/             # Rule enforcement
│   ├── guardian.sh       # Watches outputs, blocks violations
│   └── guardian-framework.txt
│
├── knowledge/            # Accumulated learnings
│   ├── learnings.md      # Extracted insights
│   └── sessions/         # Full transcripts
│
└── learn.sh              # Runs architect + extracts insights
```

---

## Task List Format

`visual-loop/task_list.json` defines tasks for orchestration:

```json
{
  "id": "feature-001",
  "task": "Add floating damage numbers above units",
  "stream": "visual",
  "context_files": "BattleView.tsx,battle.css",
  "verify_code": "damage-number|@keyframes.*float",
  "expect": "damage"
}
```

| Field | Purpose |
|-------|---------|
| `id` | Unique identifier for progress tracking |
| `task` | Natural language description for AI |
| `stream` | Category: `visual`, `core`, `content`, `polish` |
| `context_files` | Files to read and provide to AI (comma-separated) |
| `verify_code` | Regex pattern(s) to grep in source (code verification) |
| `expect` | Text to grep for quick validation before vision |

---

## Configuration

Each tool can be configured via `config.env` in its directory:

```bash
# architect/config.env
ARCHITECT_A_CMD="claude -p"
ARCHITECT_B_CMD="codex exec"
ARCHITECT_A_NAME="Claude"
ARCHITECT_B_NAME="Codex"
MAX_ROUNDS=5
PACE=100  # chars/sec output speed (0=instant)
```

---

## Key Patterns

**Visual Loop Flow:**
1. AI reads context files + task description
2. Outputs JSON edits: `{"file": "...", "search": "...", "replace": "..."}`
3. Edits applied via `perl -i -p0e`
4. Dev server restarted, screenshot taken
5. Vision model analyzes screenshot
6. If pass: done. If fail: feedback → iterate (max 5)

**Verification Modes:**
- `--expect "text"` - Quick grep check before expensive vision
- `--verify-code "pattern"` - Code-only verification (skip vision entirely)
- Default: Full vision verification via screenshot analysis

**Consensus Detection (architect.sh):**
Looks for phrases like "I agree", "let's go with", "settled" and absence of "however", "but I think", "I disagree".

---

## Dependencies

- `tmux` - Multi-pane terminal UI
- `jq` - JSON parsing
- `pv` - Pipe viewer for streaming output (optional)
- `chromium` or `google-chrome` - Headless screenshots
- `claude` CLI - Anthropic's Claude
- `codex` CLI - OpenAI Codex
