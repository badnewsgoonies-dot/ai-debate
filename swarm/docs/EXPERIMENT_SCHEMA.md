# Experiment Schema for `contradiction-hunter`

This document defines the expected structure of experiments produced by
`swarm/contradiction-hunter.sh` and how they are interpreted by the runner.

The goal is to keep experiments:

- **Small** (≤ `TIMEOUT_SECS`, default 10s)
- **Side-effect free** (no destructive changes)
- **Deterministic** (same inputs → same outputs)
- **Shell-friendly** (no interactive prompts)

---

## 1. Files produced by the pipeline

### 1.1 `problems.json`

Output of the "mine problems" phase.

- Type: JSON array of objects.
- Shape (per problem):

  ```json
  {
    "problem": "string description of the 'impossible' or contradictory claim",
    "why_impossible": "why the text suggests this is impossible",
    "evidence": "citation or supporting text from the research file",
    "suggested_experiment": "very short idea for an experiment (<= 10s)"
  }
  ```

This file is **input** to the experiment generation phase.

---

### 1.2 `experiments.json`

Output of the "generate experiments" phase.

* Type: JSON array of **experiment objects**.
* Shape (per experiment):

  ```json
  {
    "name": "short_slug_describing_the_experiment",
    "code": "shell snippet to run the experiment",
    "expected": "string representing the expected output"
  }
  ```

#### `name` (string)

* Short, stable identifier for the experiment.
* Should be unique within a run.
* Good examples:

  * `"check_noise_std"`
  * `"compare_sampling_temperature_0_vs_1"`
  * `"gradients_vanish_on_layer_5"`

#### `code` (string, shell snippet)

* Executed as:

  ```bash
  timeout "$TIMEOUT_SECS" bash -lc "$code"
  ```

* Should:

  * Finish within `TIMEOUT_SECS` on a normal machine.
  * Not require interactive input.
  * Avoid destructive side effects (no `rm`, mass writes, network, etc.).
  * Prefer writing output to stdout only.

* Because multiple iterators may run the same experiment in parallel, **do not rely on shared global state** (e.g., writing fixed filenames without care).

Good patterns:

* Compute a single numeric/statistical quantity and print it.
* Print a short, human-readable summary line.
* Optionally print machine-readable JSON (but then your `expected` needs to match that JSON string).

#### `expected` (string)

* Interpreted **literally** by the current runner.
* The runner captures the entire stdout+stderr of `code` as a string `actual`.
* An anomaly is flagged if **any** of the following hold:

  * `actual != expected` (string inequality)
  * `actual` contains `"ERROR"`
  * `actual` contains `"TIMEOUT"`

In other words:

* `expected` is the *ideal exact textual outcome* of `code`.
* If you want more flexible comparisons (e.g. tolerances), you can:

  * Encode these in the text itself (e.g., `"std ~ 0.1"`), and
  * Later add smarter comparison logic to the runner.

---

### 1.3 `experiments/iterator_*.jsonl`

Output of the execution phase.

* One file per iterator:

  * `experiments/iterator_1.jsonl`
  * `experiments/iterator_2.jsonl`
  * …
* Each line is a JSON object:

  ```json
  {
    "name": "experiment_name",
    "expected": "expected string",
    "actual": "full captured stdout+stderr from code",
    "code_hash": "sha1 hash of the code snippet"
  }
  ```

This is the **raw run log** per iterator.

---

### 1.4 `anomalies/flagged.jsonl`

Anomalies detected during the execution phase.

* Type: JSON Lines (one JSON object per line).
* Shape (per anomaly):

  ```json
  {
    "iterator": 1,
    "name": "experiment_name",
    "expected": "expected string",
    "actual": "captured stdout+stderr",
    "code_hash": "sha1 hash of the code snippet"
  }
  ```

A line appears here when:

* `actual != expected`, or
* `actual` contains `"ERROR"`, or
* `actual` contains `"TIMEOUT"`, or
* `actual` is `"SKIPPED_UNSAFE"` (blocked by safety filter).

This file is consumed by tools like `view_results.py` and by the anomaly reviewer (`REVIEWER_CMD`, e.g. `claude -p`).

---

### 1.5 `insights.txt`

Optional summary from the reviewer LLM.

* Plain text: ranked/structured notes about which anomalies seem:

  * Clearly buggy,
  * Possibly interesting,
  * Worth deeper investigation.

---

### 1.6 `meta.json`

Run metadata for reproducibility.

```json
{
  "script": "contradiction-hunter",
  "timestamp": "2025-11-29T03:12:40-05:00",
  "research_file": "path/to/research.txt",
  "num_iterators": 2,
  "max_experiments": 10,
  "codex_model": "gpt-5.1-codex-max",
  "codex_effort": "xhigh",
  "timeout_secs": 10,
  "dry_run": 0
}
```

---

## 2. Experiment design guidelines

To get high-quality signals from `contradiction-hunter`:

1. **Make experiments minimal.**

   * One clear question per experiment.
   * One primary output quantity or conclusion.

2. **Make experiments deterministic.**

   * Fix seeds for any randomness.
   * Avoid time-based randomness or network calls.

3. **Keep runtime small.**

   * Aim for well under `TIMEOUT_SECS` (e.g. < 2s).
   * Short experiments means you can run many iterators/trials.

4. **Use clear, interpretable `expected` values.**

   * For now, expectation is a direct string match.
   * Fuzzier semantics (e.g. tolerances) can be layered on later.

5. **Assume parallel execution.**

   * Do not rely on global mutable state or shared hard-coded paths.
   * If you must write files, use unique names (e.g. temp dirs or UUIDs).

Designing experiments with this schema in mind makes the logs and anomaly reports
much easier to interpret and automate.

---

## 3. Tooling

| Tool | Purpose |
|------|---------|
| `swarm/contradiction-hunter.sh` | Main pipeline: mine → generate → run → review |
| `swarm/tools/view_results.py` | Analyze `flagged.jsonl` for patterns |
| `swarm/lib/common.sh` | Shared utilities (logging, JSON validation) |
