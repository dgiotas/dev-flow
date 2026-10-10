#!/usr/bin/env bash
# Deterministic tests for ci/eval-run.sh with a stubbed `claude` binary.
# They run from .claude/test-cmd and never call the real `claude plugin eval`.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
run="$here/ci/eval-run.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

mkdir "$tmp/bin"
cat > "$tmp/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_ARGS"
json=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --json ]; then json=$2; fi
  shift
done
if [ -n "${STUB_JSON:-}" ]; then cp "$STUB_JSON" "$json"; fi
exit "${STUB_RC:-0}"
STUB
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"
export STUB_ARGS="$tmp/args"

cat > "$tmp/pass.json" <<'JSON'
{"schemaVersion":1,"partial":false,"partialReason":null,"costUsd":1.5,
 "aggregates":{"overallScore":1,"meanDelta":0.5},
 "cases":[
  {"name":"a","graders":[{"name":"rx","type":"regex"}],
   "aggregates":{"score":1,"scoreWithout":0.5,"delta":0.5},
   "arms":{"with":[{"score":1,"error":null,"graders":[{"name":"rx","passed":true}]}],
           "without":[{"score":0.5,"error":null,"graders":[{"name":"rx","passed":false}]}]}}]}
JSON
jq '.partial=true | .partialReason="cost_ceiling"' "$tmp/pass.json" > "$tmp/partial.json"

# expect <label> <want exit> <want exact line> [args...]; leaves out for also()
expect() {
  label=$1; want_rc=$2; want_line=$3; shift 3
  out=$(bash "$run" "$@" 2>&1); rc=$?
  if [ "$rc" = "$want_rc" ] && printf '%s\n' "$out" | grep -qxF -- "$want_line"; then
    pass "$label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

# also <label> <want exact line>: re-checks the output of the last expect
also() {
  if printf '%s\n' "$out" | grep -qxF -- "$2"; then pass "$1"; else bad "$1"; fi
}

# after <flag> <want>: the stub saw <want> on the line after <flag>
after() {
  got=$(grep -A1 -xF -- "$1" "$STUB_ARGS" | sed -n 2p)
  if [ "$got" = "$2" ]; then pass "after $1"; else bad "after $1 (got '$got', want '$2')"; fi
}

expect usage-none 1 'error=usage'
expect usage-tier 1 'error=usage' weekly "$tmp/o"

STUB_JSON="$tmp/pass.json" expect pr-flags 0 'result=pass' pr "$tmp/o1"
want=$(printf '%s\n' plugin eval "$here/plugins/dev-flow")
if [ "$(sed -n 1,3p "$STUB_ARGS")" = "$want" ]; then pass pr-target; else bad pr-target; fi
for flag in --trust-plugin --scaffold --no-publish; do
  if grep -qxF -- "$flag" "$STUB_ARGS"; then pass "has $flag"; else bad "has $flag"; fi
done
after --ablation none
after --runs 1
after --threshold 0
after --model claude-sonnet-5
after --judge-model claude-haiku-4-5
after --max-cost-usd 5
after -j 2
after --json "$tmp/o1/results.json"
after --report "$tmp/o1/report.html"
if [ "$(tail -n 3 "$STUB_ARGS")" = "$(printf '%s\n' --allow-tools Write Bash)" ]; then
  pass allow-tools-last
else
  bad allow-tools-last
fi
if grep -qxF WebSearch "$STUB_ARGS"; then bad no-websearch; else pass no-websearch; fi

STUB_JSON="$tmp/pass.json" expect nightly-flags 0 'result=pass' nightly "$tmp/o2"
after --ablation with-without
after --runs 3
after --max-cost-usd 25

DEVFLOW_EVAL_MODEL=m1 DEVFLOW_JUDGE_MODEL=j1 DEVFLOW_MAX_COST_USD=7 STUB_JSON="$tmp/pass.json" \
  expect env-override 0 'result=pass' pr "$tmp/o3"
after --model m1
after --judge-model j1
after --max-cost-usd 7

STUB_RC=2 STUB_JSON="$tmp/partial.json" expect exit-2-partial 2 'result=inconclusive' pr "$tmp/o4"
also exit-2-partial-reason 'reason=cost_ceiling'
STUB_RC=2 expect exit-2-nojson 2 'reason=exit-2' pr "$tmp/o5"
STUB_RC=1 expect exit-1 1 'result=fail' pr "$tmp/o6"
also exit-1-reason 'reason=eval-exit-1'

if [ -d "$tmp/fresh" ]; then bad out-dir-precondition; fi
STUB_JSON="$tmp/pass.json" bash "$run" pr "$tmp/fresh" >/dev/null 2>&1
if [ -d "$tmp/fresh" ]; then pass out-dir-created; else bad out-dir-created; fi

mkdir "$tmp/stale"
cp "$tmp/pass.json" "$tmp/stale/results.json"
expect stale-results 1 'reason=no-results' pr "$tmp/stale"
also stale-results-fail 'result=fail'

[ "$fail" = 0 ] && echo ALL-PASS
exit "$fail"
