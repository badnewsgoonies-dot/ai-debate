# Non-Coder Verification Workflow Proposal

*Generated from Architect Session - 2025-11-27*

## The Problem
How can a non-coder verify AI-generated code changes quickly and confidently?

## Consensus Solution: Two-Stage Verification

### Stage 1: Local (Immediate Feedback)
Single command: `pnpm precommit` → green ✓ or red ✗

- Non-coder sees pass/fail, not code
- Error messages are actionable even without code understanding

### Stage 2: PR-Based (Remote Review)
Push → Create PR → CI runs → Claude reviews → read summaries

- Acts as "second opinion" from independent AI
- Non-coder reads summary comments, not diffs
- Green checks = safe to merge

## Key Insight
Non-coders verify **outcomes**, not code:
- Did tests pass?
- Did it build?
- Did the AI reviewer flag anything?
- Does the app work when you run it? (`pnpm dev`)

## Proposed Tooling

### verify.sh wrapper
Single entry point with human-readable output

### YAML config with rules
```yaml
- id: zod-schema
  category: data-integrity
  confidence: high
  matcher: "src/data/schemas/*.ts"
  check: "pnpm validate:data"

- id: core-touched
  category: architecture
  confidence: medium
  matcher: "src/core/**"
  instructions: "Ensure no React imports in core"
```

### Confidence-driven verbosity
- **High confidence** rules: terse pass/fail
- **Low confidence** rules: include explanations and examples
- **Fallback**: unknown changes → escalate to human reviewer

## Next Steps (if implementing)
1. Add `verify.sh` wrapper script
2. Create YAML config with project-specific rules
3. Document 2-step checklist in README
4. Ensure CI status and Claude comments easy to find in PRs

---

*Session participants: Claude & Codex*
*Full log: ~/.cache/architect/session_20251127_023900.log*
