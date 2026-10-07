#!/usr/bin/env bash
# Runs `claude plugin eval` on the plugin and gates the results.
# Usage: eval-run.sh <pr|nightly> <out-dir>
# Prints key=value lines; exits 0 pass, 1 fail, 2 inconclusive.
#
# Flags that are not obvious:
#   --scaffold            fixtures don't apply without it
#   --allow-tools Write Bash
#                         the command can't write the threat model or run
#                         date/git/grep without them
#   (no WebSearch)        keeps runs deterministic and offline, so the
#                         baseline line falls back to 2023
#   --threshold 0         the gate decides pass/fail, not the eval command
#   target first, --allow-tools last
#                         --allow-tools is variadic, so it must come last
# Variables are DEVFLOW_*, never EVAL_*: EVAL_* is forwarded into eval runs.
set -u

if [ "$#" -ne 2 ] || { [ "$1" != pr ] && [ "$1" != nightly ]; }; then
  echo error=usage
  exit 1
fi
tier=$1
out=$2

root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
rm -f "$out/results.json" "$out/report.html"

if [ "$tier" = pr ]; then
  ablation=none runs=1 cost=${DEVFLOW_MAX_COST_USD:-5}
else
  ablation=with-without runs=3 cost=${DEVFLOW_MAX_COST_USD:-25}
fi

claude plugin eval "$root/plugins/dev-flow" --trust-plugin --scaffold --no-publish --threshold 0 \
  --model "${DEVFLOW_EVAL_MODEL:-claude-sonnet-5}" --judge-model "${DEVFLOW_JUDGE_MODEL:-claude-haiku-4-5}" \
  --max-cost-usd "$cost" -j 2 --ablation "$ablation" --runs "$runs" \
  --json "$out/results.json" --report "$out/report.html" --allow-tools Write Bash
rc=$?

case "$rc" in
  0) exec bash "$root/ci/eval-gate.sh" "$tier" "$out/results.json" ;;
  2)
    echo result=inconclusive
    echo "reason=$(jq -r '.partialReason // "exit-2"' "$out/results.json" 2>/dev/null || echo exit-2)"
    exit 2
    ;;
  *)
    echo result=fail
    echo "reason=eval-exit-$rc"
    exit 1
    ;;
esac
