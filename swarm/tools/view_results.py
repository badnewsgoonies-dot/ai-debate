#!/usr/bin/env python3
"""
view_results.py - tiny viewer for contradiction-hunter anomalies.

Usage:
    python view_results.py path/to/flagged.jsonl
"""

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path


def load_anomalies(path: Path):
    anomalies = []
    with path.open("r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                anomalies.append(json.loads(line))
            except json.JSONDecodeError:
                print(
                    f"[warn] Skipping bad JSON on line {lineno}: {line[:80]!r}",
                    file=sys.stderr,
                )
    return anomalies


def main():
    parser = argparse.ArgumentParser(
        description="View anomalies from contradiction-hunter flagged.jsonl"
    )
    parser.add_argument(
        "file",
        help="Path to flagged.jsonl (e.g. swarm/runs/.../anomalies/flagged.jsonl)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=10,
        help="How many top items to show in each section (default: 10)",
    )
    args = parser.parse_args()

    path = Path(args.file)
    if not path.is_file():
        print(f"[error] File not found: {path}", file=sys.stderr)
        sys.exit(1)

    anomalies = load_anomalies(path)
    if not anomalies:
        print("No anomalies found in file.")
        return

    # 1) Counts per experiment name
    by_name = Counter(a.get("name", "<unknown>") for a in anomalies)

    # 2a) Simple: anomalies per iterator
    by_iter = Counter(a.get("iterator", -1) for a in anomalies)

    # 2b) Pairwise iterator disagreement per experiment name
    #     For each experiment name, compare sets of actual outputs per iterator.
    name_iter_actuals = defaultdict(lambda: defaultdict(set))
    for a in anomalies:
        name = a.get("name", "<unknown>")
        it = a.get("iterator", -1)
        actual = a.get("actual", "")
        name_iter_actuals[name][it].add(actual)

    pair_disagreements = Counter()
    for _, iter_map in name_iter_actuals.items():
        iters = sorted(iter_map.keys())
        for i_idx in range(len(iters)):
            for j_idx in range(i_idx + 1, len(iters)):
                i = iters[i_idx]
                j = iters[j_idx]
                if iter_map[i] != iter_map[j]:
                    pair_disagreements[(i, j)] += 1

    # 3) Top anomaly patterns: (name, expected, actual)
    pattern_counts = Counter(
        (a.get("name", "<unknown>"), a.get("expected", ""), a.get("actual", ""))
        for a in anomalies
    )

    # ---- Output ----
    print(f"Loaded {len(anomalies)} anomalies from {path}")
    print()

    # 1) Counts per experiment name
    print("=== Top experiments by anomaly count ===")
    for name, count in by_name.most_common(args.top):
        print(f"{count:4d}  {name}")
    print()

    # 2a) Anomalies per iterator
    print("=== Anomalies per iterator ===")
    for it, count in sorted(by_iter.items(), key=lambda x: x[0]):
        label = f"iterator {it}" if it != -1 else "iterator <missing>"
        print(f"{label:15s} {count:4d}")
    print()

    # 2b) Iterator pairs that disagree the most
    print("=== Iterator pairs with most disagreements (by experiment name) ===")
    if pair_disagreements:
        for (i, j), count in pair_disagreements.most_common(args.top):
            print(f"iter {i:2d} vs {j:2d} : {count} experiments")
    else:
        print("No iterator pairs with conflicting actual outputs detected.")
    print()

    # 3) Top anomaly patterns
    print("=== Top anomaly patterns (name | expected -> actual) ===")
    for (name, expected, actual), count in pattern_counts.most_common(args.top):
        print(f"\n[{count}x] {name}")
        print(f"  expected: {expected!r}")
        print(f"  actual  : {actual!r}")


if __name__ == "__main__":
    main()
