#!/usr/bin/env bash
# Deterministic tests for ci/eval-gate.sh on synthetic results documents.
# They run from .claude/test-cmd, and every document is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
gate="$here/ci/eval-gate.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

cat > "$tmp/base.json" <<'JSON'
{"schemaVersion":1,"partial":false,"partialReason":null,"costUsd":1.5,
 "aggregates":{"overallScore":1,"meanDelta":0.5},
 "cases":[
  {"name":"a","graders":[{"name":"file-exists","type":"file_exists"},{"name":"finding","type":"llm"},{"name":"agent-fired","type":"tool_used"}],
   "aggregates":{"score":1,"scoreWithout":0.5,"delta":0.5},
   "arms":{"with":[{"score":1,"error":null,"graders":[{"name":"file-exists","passed":true},{"name":"finding","passed":true},{"name":"agent-fired","passed":true}]}],
           "without":[{"score":0.5,"error":null,"graders":[{"name":"file-exists","passed":false},{"name":"finding","passed":true},{"name":"agent-fired","passed":false}]}]}},
  {"name":"b","graders":[{"name":"rx","type":"regex"}],
   "aggregates":{"score":1,"scoreWithout":0.5,"delta":0.5},
   "arms":{"with":[{"score":1,"error":null,"graders":[{"name":"rx","passed":true}]}],
           "without":[{"score":0.5,"error":null,"graders":[{"name":"rx","passed":false}]}]}}]}
JSON

# mk <name> <jq filter>: derives $tmp/<name>.json from the base document
mk() { jq "$2" "$tmp/base.json" > "$tmp/$1.json"; }

# expect <label> <want exit> <want exact line> [args...]; leaves out for also()
expect() {
  label=$1; want_rc=$2; want_line=$3; shift 3
  out=$(bash "$gate" "$@" 2>&1); rc=$?
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

expect usage-none 1 'error=usage'
expect usage-tier 1 'error=usage' weekly "$tmp/base.json"

expect missing 1 'result=fail' pr "$tmp/nope.json"
also missing-reason 'reason=no-results'
echo '{' > "$tmp/invalid.json"
expect invalid 1 'reason=no-results' pr "$tmp/invalid.json"

mk partial '.partial=true | .partialReason="cost_ceiling"'
for tier in pr nightly; do
  expect "partial-$tier" 2 'result=inconclusive' "$tier" "$tmp/partial.json"
  also "partial-$tier-reason" 'reason=cost_ceiling'
done

mk rl '.cases[0].arms.with[0].error="API Error: Rate limit reached"'
expect rate-limited-with 2 'reason=rate-limited' pr "$tmp/rl.json"
mk rlw '.cases[0].arms.without[0].error="API Error: Rate limit reached"'
expect rate-limited-without 2 'reason=rate-limited' pr "$tmp/rlw.json"
mk r429 '.cases[0].arms.with[0].error="API Error: 429 Too Many Requests"'
for tier in pr nightly; do
  expect "429-$tier" 2 'result=inconclusive' "$tier" "$tmp/r429.json"
  also "429-$tier-reason" 'reason=rate-limited'
done

expect pr-pass 0 'result=pass' pr "$tmp/base.json"
also pr-pass-cost 'cost=1.5'
also pr-pass-case 'case=a score=1 without=0.5 delta=0.5'

mk llmfail '.cases[0].arms.with[0].graders[1].passed=false'
expect pr-llm-ignored 0 'result=pass' pr "$tmp/llmfail.json"
also pr-llm-note 'note=llm case=a grader=finding passed=false'

mk detfail '.cases[1].arms.with[0].graders[0].passed=false'
expect pr-det-fail 1 'fail=deterministic case=b grader=rx run=0' pr "$tmp/detfail.json"
also pr-det-fail-result 'result=fail'

mk single 'del(.cases[].arms.without) | del(.cases[].aggregates.delta, .cases[].aggregates.scoreWithout) | del(.aggregates.meanDelta)'
expect pr-single-arm 0 'case=a score=1 without=- delta=-' pr "$tmp/single.json"

expect nightly-pass 0 'result=pass' nightly "$tmp/base.json"

mk neg '.cases[1].aggregates.delta=-0.25'
expect nightly-negative 1 'fail=negative-delta case=b delta=-0.25' nightly "$tmp/neg.json"
also nightly-negative-result 'result=fail'

mk nodelta 'del(.cases[0].aggregates.delta)'
expect nightly-no-delta 1 'fail=no-delta case=a' nightly "$tmp/nodelta.json"

mk low '.aggregates.meanDelta=0.25'
expect nightly-low-mean 1 'fail=mean-delta mean=0.25 floor=0.25' nightly "$tmp/low.json"

DEVFLOW_MIN_MEAN_DELTA=0.6 expect nightly-floor-env 1 'fail=mean-delta mean=0.5 floor=0.6' nightly "$tmp/base.json"
DEVFLOW_MIN_MEAN_DELTA=abc expect nightly-floor-bad 1 'error=usage' nightly "$tmp/base.json"

mk bp '.cases[1].arms.without[0].score=1'
expect finding-baseline-passes 0 'finding=baseline-passes case=b' nightly "$tmp/bp.json"

mk ne '.cases[0].aggregates.scoreWithout=1 | .cases[0].aggregates.delta=0'
expect finding-no-effect 0 'finding=no-plugin-effect case=a' nightly "$tmp/ne.json"

expect pr-skips-nightly-checks 0 'result=pass' pr "$tmp/neg.json"

mk errw '.cases[0].arms.with[0] |= (.error="sandbox" | .score=0 | .graders=[])'
expect pr-run-error 1 'fail=run-error case=a arm=with run=0' pr "$tmp/errw.json"
also pr-run-error-result 'result=fail'
expect nightly-run-error 1 'fail=run-error case=a arm=with run=0' nightly "$tmp/errw.json"

mk errwo '.cases[0].arms.without[0].error="sandbox"'
expect nightly-run-error-without 1 'fail=run-error case=a arm=without run=0' nightly "$tmp/errwo.json"

mk errobj '.cases[0].arms.with[0].error={"message":"boom"}'
expect run-error-object 1 'fail=run-error case=a arm=with run=0' pr "$tmp/errobj.json"

mk allerr '.cases[].arms[][] |= (.error="x" | .score=0 | .graders=[])'
expect pr-all-errored 1 'result=fail' pr "$tmp/allerr.json"
expect nightly-all-errored 1 'result=fail' nightly "$tmp/allerr.json"

mk nowith '.cases[0].arms.with=[]'
expect pr-no-with-runs 1 'fail=no-with-runs case=a' pr "$tmp/nowith.json"

mk nograder '.cases[1].arms.with[0].graders=[]'
expect pr-missing-grader 1 'fail=missing-grader case=b grader=rx run=0' pr "$tmp/nograder.json"

echo '{}' > "$tmp/empty.json"
for tier in pr nightly; do
  expect "empty-doc-$tier" 1 'result=fail' "$tier" "$tmp/empty.json"
done

mk nullgraders '.cases[0].arms.with[0].graders=null | .cases[1].arms.with[0].graders[0].passed=false'
expect pr-null-graders 1 'result=fail' pr "$tmp/nullgraders.json"
also pr-null-graders-later-case 'fail=deterministic case=b grader=rx run=0'

mk nodecl 'del(.cases[].graders)'
expect pr-no-deterministic-graders 1 'fail=no-deterministic-graders case=a' pr "$tmp/nodecl.json"
also pr-no-deterministic-graders-b 'fail=no-deterministic-graders case=b'

mk llmonly '.cases[1].graders=[{"name":"rx","type":"llm"}]'
expect pr-llm-only-declared 1 'fail=no-deterministic-graders case=b' pr "$tmp/llmonly.json"

mk unknown '.cases[1].arms.with[0].graders += [{"name":"ghost","passed":true}]'
expect pr-unknown-grader 1 'fail=unknown-grader case=b grader=ghost run=0' pr "$tmp/unknown.json"

mk nullpassed '.cases[1].arms.with[0].graders[0].passed=null'
expect pr-det-null-passed 1 'fail=deterministic case=b grader=rx run=0' pr "$tmp/nullpassed.json"

mk partialerr '.partial=true | .partialReason="cost_ceiling" | .cases[0].arms.with[0].error="sandbox"'
expect partial-run-error 2 'fail=run-error case=a arm=with run=0' pr "$tmp/partialerr.json"
also partial-run-error-inconclusive 'result=inconclusive'

mk noarms 'del(.cases[].arms)'
expect pr-no-arms 1 'fail=no-with-runs case=a' pr "$tmp/noarms.json"

for v in null false '"x"'; do
  DEVFLOW_MIN_MEAN_DELTA=$v expect "nightly-floor-$v" 1 'error=usage' nightly "$tmp/base.json"
done

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
