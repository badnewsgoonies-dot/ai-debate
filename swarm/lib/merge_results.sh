#!/usr/bin/env bash
# merge_results.sh - helpers to aggregate worker outputs
# Requires jq for JSON merging.

set -euo pipefail

merge_jsonl() {
    local output_file="$1"; shift
    local inputs=("$@")
    : > "$output_file"
    for f in "${inputs[@]}"; do
        [[ -f "$f" ]] && cat "$f" >> "$output_file"
    done
    if ! jq -e 'true' "$output_file" >/dev/null 2>&1; then
        echo "WARNING: merged JSONL may be invalid: $output_file" >&2
    fi
}

merge_with_voting() {
    local output_file="$1"; shift
    local inputs=("$@")
    jq -s '
      map(select(.key?)) |
      group_by(.key) |
      map({
        key: .[0].key,
        result: (group_by(.result) | max_by(length) | .[0].result),
        confidence: ([.[].confidence] | add / length),
        votes: length
      })
    ' "${inputs[@]}" > "$output_file"
}

merge_code_files() {
    local output_dir="$1"; shift
    mkdir -p "$output_dir"
    for src_dir in "$@"; do
        [[ -d "$src_dir" ]] || continue
        for f in "$src_dir"/*; do
            [[ -f "$f" ]] || continue
            cp -n "$f" "$output_dir/" 2>/dev/null || true
        done
    done
}
