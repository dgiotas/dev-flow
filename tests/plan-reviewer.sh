#!/usr/bin/env bash
# Offline checks of the plan-reviewer agent: frontmatter, seven checks and reply contract.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

agent="$here/plugins/dev-flow/agents/plan-reviewer.md"
fm=$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$agent" 2>/dev/null)

if [ -f "$agent" ]; then pass agent-exists; else bad agent-exists; fi
if printf '%s\n' "$fm" | grep -qx 'name: plan-reviewer'; then pass agent-name; else bad agent-name; fi
if printf '%s\n' "$fm" | grep -qx 'model: inherit'; then pass agent-model; else bad agent-model; fi
if printf '%s\n' "$fm" | grep -qx 'tools: Read, Grep, Glob, mcp__plugin_dev-flow_codegraph'; then pass agent-tools; else bad agent-tools; fi

ok=1
for s in '**Coverage**' '**Executable**' '**Test first**' '**Ordering**' '**Symbols**' '**Scope**' '**Risk**'; do
  grep -qF -- "$s" "$agent" 2>/dev/null || ok=0
done
if [ "$ok" = 1 ]; then pass agent-checks; else bad agent-checks; fi

if grep -qx '## Output' "$agent" 2>/dev/null && grep -qF '`PASS`' "$agent" && grep -qF '`REVISE`' "$agent"; then
  pass agent-contract
else
  bad agent-contract
fi
if grep -qF 'plan-check already enforces' "$agent" 2>/dev/null; then pass agent-no-dup; else bad agent-no-dup; fi

cmd="$here/plugins/dev-flow/commands/spec.md"
s3=$(grep '^3\. ' "$cmd")
s4=$(grep '^4\. ' "$cmd")
s5=$(grep '^5\. ' "$cmd")
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }

if has "$s3" 'plan-check.sh" .claude/plans'; then pass spec-step3-plancheck; else bad spec-step3-plancheck; fi
if [[ "$s4" == '4. **Plan review.**'* ]] && has "$s4" '`plan-reviewer`' && has "$s4" 'never from inside' && has "$s4" 'at most 1 revision'; then
  pass spec-step4-review
else
  bad spec-step4-review
fi
if [[ "$s5" == '5. Summarise'* ]] && has "$s5" 'Plan review: unresolved'; then pass spec-step5-summary; else bad spec-step5-summary; fi
if grep -qF 'treat it as step 7' "$cmd" && grep -qF 'steps 1 to 5 again' "$cmd"; then pass spec-renumbered; else bad spec-renumbered; fi

ev="$here/plugins/dev-flow/evals"
for c in plan-review-arity plan-review-pass; do
  d="$tmp/$c"; mkdir -p "$d"
  if (cd "$d" && bash "$ev/$c/fixture.sh") >/dev/null 2>&1; then pass "$c-fixture-runs"; else bad "$c-fixture-runs"; fi
  out=$(bash "$here/plugins/dev-flow/scripts/plan-check.sh" "$d/.claude/plans/badge.md" 2>&1); rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'errors=0' && printf '%s\n' "$out" | grep -qx 'warnings=0'; then
    pass "$c-plan-check"
  else
    bad "$c-plan-check"
  fi
  if [ "$(sed -n 3p "$d/src/names.js" 2>/dev/null)" = 'function displayName(first, last, title) {' ]; then pass "$c-signature-line"; else bad "$c-signature-line"; fi
done
if grep -qF 'return greeting(displayName(user)); }' "$ev/plan-review-arity/fixture.sh" 2>/dev/null; then pass arity-task3; else bad arity-task3; fi
if grep -qF 'return greeting(displayName(user.first, user.last, user.title)); }' "$ev/plan-review-pass/fixture.sh" 2>/dev/null; then pass pass-task3; else bad pass-task3; fi
dl=$(diff "$ev/plan-review-arity/fixture.sh" "$ev/plan-review-pass/fixture.sh" 2>/dev/null | grep '^[<>]')
if [ "$(printf '%s\n' "$dl" | wc -l | tr -d ' ')" = 2 ] && [ "$(printf '%s\n' "$dl" | grep -vcF 'displayName(user')" = 0 ]; then pass fixtures-differ-once; else bad fixtures-differ-once; fi
if cmp -s "$ev/plan-review-arity/prompt.md" "$ev/plan-review-pass/prompt.md"; then pass prompts-equal; else bad prompts-equal; fi
if grep -qF '| `plan-reviewer` (routed) | Agent |' "$here/README.md"; then pass readme-agent-row; else bad readme-agent-row; fi
if grep -qF '### Plan review' "$here/README.md"; then pass readme-section; else bad readme-section; fi
if grep -qF '| `plan-reviewer` | the plan' "$here/README.md"; then pass readme-routing; else bad readme-routing; fi
if grep -qF 'Agents 13' "$here/README.md"; then pass readme-inventory; else bad readme-inventory; fi
if grep -qF 'Six billed cases' "$here/README.md"; then pass readme-six; else bad readme-six; fi
if grep -qF 'plan-review-arity' "$here/README.md"; then pass readme-arity; else bad readme-arity; fi
if grep -qF 'plan-review-pass' "$here/README.md"; then pass readme-pass; else bad readme-pass; fi
if grep -qF '2,257' "$here/README.md"; then pass readme-tokens; else bad readme-tokens; fi
if grep -qF 'src/names.js' "$here/plugins/dev-flow/agents/plan-reviewer.md"; then bad agent-no-fixture-leak; else pass agent-no-fixture-leak; fi

[ "$fail" = 0 ] && echo ALL-PASS
exit "$fail"
