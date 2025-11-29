#!/usr/bin/env bash
#
# summarize-runs.sh - Quick CLI digest of swarm run outputs
#
# Usage:
#   ./summarize-runs.sh [runs_root]
# Defaults to swarm/runs if not provided.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runs}"

if [[ ! -d "$ROOT" ]]; then
    echo "Runs root not found: $ROOT" >&2
    exit 1
fi

maybe_jq() {
    if command -v jq >/dev/null 2>&1; then
        jq "$@"
    else
        cat
    fi
}

for dir in $(find "$ROOT" -maxdepth 1 -mindepth 1 -type d | sort); do
    base="$(basename "$dir")"
    printf "\n=== %s ===\n" "$base"

    if [[ -f "$dir/meta.json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            # Use single quotes outside, double inside to avoid quoting hell
            jq -r '["script: " + (.script//""), "task: " + ((.task//.research_file)//""), "time: " + (.timestamp//"")] | join("  ")' "$dir/meta.json" || true
        else
            echo "meta.json present (jq not available)"
        fi
    fi

    case "$base" in
        contradiction-hunter_*)
            printf "anomalies: "
            if [[ -f "$dir/anomalies/flagged.jsonl" ]]; then
                wc -l < "$dir/anomalies/flagged.jsonl"
            else
                echo 0
            fi
            if [[ -f "$dir/insights.txt" ]]; then
                echo "-- insights (first 10 lines) --"
                sed -n '1,10p' "$dir/insights.txt"
            fi
            if [[ -f "$dir/guardian.txt" ]]; then
                echo "-- guardian --"
                sed -n '1,10p' "$dir/guardian.txt"
            fi
            ;;
        prompt_evolver_*)
            if [[ -f "$dir/summary.txt" ]]; then
                echo "-- summary --"
                sed -n '1,6p' "$dir/summary.txt"
            fi
            if [[ -f "$dir/best_prompt.txt" ]]; then
                echo "-- best prompt --"
                sed -n '1,12p' "$dir/best_prompt.txt"
            fi
            ;;
        reflexion_*)
            if [[ -f "$dir/reflexion.log" ]]; then
                echo "-- reflexion tail --"
                tail -n 12 "$dir/reflexion.log"
            fi
            ;;
        hybrid_*|parallel_*)
            if [[ -f "$dir/final.txt" ]]; then
                echo "-- final --"
                sed -n '1,20p' "$dir/final.txt"
            fi
            ;;
        swarm_*)
            if [[ -f "$dir/swarm.log" ]]; then
                echo "-- swarm tail --"
                tail -n 12 "$dir/swarm.log"
            fi
            ;;
    esac
done
