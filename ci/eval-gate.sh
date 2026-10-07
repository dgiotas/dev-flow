#!/usr/bin/env bash
# Gate over a `claude plugin eval --json` results document.
# Usage: eval-gate.sh <pr|nightly> <results.json>
# Prints key=value lines and ends with result=pass|fail|inconclusive,
# exiting 0, 1 or 2 respectively. The first terminal verdict wins.
# A jq failure on a document that passed the validity check is a gate
# failure (reason=gate-jq-error), never a pass.
set -u

if [ "$#" -ne 2 ] || { [ "$1" != pr ] && [ "$1" != nightly ]; }; then
  echo error=usage
  exit 1
fi
tier=$1
f=$2

floor=${DEVFLOW_MIN_MEAN_DELTA:-0.25}
if ! jq -en --argjson f "$floor" '$f|numbers' >/dev/null 2>&1; then
  echo error=usage
  exit 1
fi

if [ ! -f "$f" ] || ! jq -e '(.cases | type == "array" and length > 0)' "$f" >/dev/null 2>&1; then
  echo result=fail
  echo reason=no-results
  exit 1
fi

jq_fail() {
  echo result=fail
  echo reason=gate-jq-error
  exit 1
}

head=$(jq -r '
  "cost=\(.costUsd)",
  (.cases[] | "case=\(.name) score=\(.aggregates.score) without=\(.aggregates.scoreWithout // "-") delta=\(.aggregates.delta // "-")")
' "$f") || jq_fail
echo "$head"

errs=$(jq -r '
  .cases[] | .name as $n | .arms as $a
  | ("with", "without") as $arm
  | ($a[$arm] // []) | to_entries[]
  | select(.value.error != null)
  | "fail=run-error case=\($n) arm=\($arm) run=\(.key)"
' "$f") || jq_fail
[ -n "$errs" ] && echo "$errs"

partial=$(jq -r '.partial == true' "$f") || jq_fail
if [ "$partial" = true ]; then
  reason=$(jq -r '"reason=\(.partialReason // "partial")"' "$f") || jq_fail
  echo result=inconclusive
  echo "$reason"
  exit 2
fi

limited=$(jq -r '[.cases[].arms | ((.with // [])[], (.without // [])[]) | (.error // "" | tostring) | test("rate.?limit|usage limit|overloaded|\\b429\\b|too many requests"; "i")] | any' "$f") || jq_fail
if [ "$limited" = true ]; then
  echo result=inconclusive
  echo reason=rate-limited
  exit 2
fi

if [ -n "$errs" ]; then
  echo result=fail
  exit 1
fi

if [ "$tier" = pr ]; then
  out=$(jq -r '
    .cases[] | . as $c
    | ($c.graders // []) as $declared
    | ($declared | map({key: .name, value: .type}) | from_entries) as $t
    | ($c.arms.with // []) as $w
    | if ($w | length) == 0
      then "fail=no-with-runs case=\($c.name)"
      elif ([$declared[] | select(.type | IN("regex","tool_used","tool_order","file_exists"))] | length) == 0
      then "fail=no-deterministic-graders case=\($c.name)"
      else
        $w | to_entries[] | .key as $i | (.value.graders // []) as $g
        | ($g | map(.name)) as $have
        | (
            ($declared[] | select(.type | IN("regex","tool_used","tool_order","file_exists"))
              | .name as $n | select(any($have[]; . == $n) | not)
              | "fail=missing-grader case=\($c.name) grader=\($n) run=\($i)"),
            ($g[] | select(.name as $gn | $t | has($gn) | not)
              | "fail=unknown-grader case=\($c.name) grader=\(.name) run=\($i)"),
            ($g[] | ($t[.name] // "") as $type
              | if ($type | IN("regex","tool_used","tool_order","file_exists")) and .passed != true
                then "fail=deterministic case=\($c.name) grader=\(.name) run=\($i)"
                elif ($type | IN("llm","baseline"))
                then "note=llm case=\($c.name) grader=\(.name) passed=\(.passed)"
                else empty end)
          )
      end
  ' "$f") || jq_fail
  [ -n "$out" ] && echo "$out"
  if printf '%s\n' "$out" | grep -q '^fail='; then
    echo result=fail
    exit 1
  fi
  echo result=pass
  exit 0
fi

out=$(jq -r --argjson f "$floor" '
  (.cases[] | select(.aggregates.delta == null) | "fail=no-delta case=\(.name)"),
  (.cases[] | select(.aggregates.delta != null and .aggregates.delta < 0) | "fail=negative-delta case=\(.name) delta=\(.aggregates.delta)"),
  (if (.aggregates.meanDelta == null) or (.aggregates.meanDelta <= $f)
   then "fail=mean-delta mean=\(.aggregates.meanDelta // "-") floor=\($f)" else empty end),
  (.cases[] | select(any((.arms.without // [])[]; .score >= 1)) | "finding=baseline-passes case=\(.name)"),
  (.cases[] | select(.aggregates.scoreWithout != null and .aggregates.scoreWithout >= .aggregates.score) | "finding=no-plugin-effect case=\(.name)")
' "$f") || jq_fail
[ -n "$out" ] && echo "$out"
if printf '%s\n' "$out" | grep -q '^fail='; then
  echo result=fail
  exit 1
fi
echo result=pass
exit 0
