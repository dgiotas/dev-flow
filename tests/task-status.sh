#!/usr/bin/env bash
# Deterministic checks that README.md and the model-facing agent and command texts
# document the Task status lifecycle. They run from .claude/test-cmd.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
readme="$here/README.md"
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

for s in 'Task status: NOT_STARTED' '`status-edit`' 'tasks done' 'Upgrading to 1.26.0' 'a second status line shows as'; do
  if grep -qF -- "$s" "$readme"; then pass "has $s"; else bad "has $s"; fi
done

for s in '`checkbox-edit`' 'checklist counts' 'checklist items checked' 'unticked' 'Ticked tasks' 'or was removed or duplicated' 'the retry cap still bounds this'; do
  if grep -qF -- "$s" "$readme"; then bad "lacks $s"; else pass "lacks $s"; fi
done

impl="$here/plugins/dev-flow/agents/implementer.md"
build="$here/plugins/dev-flow/commands/build.md"
arch="$here/plugins/dev-flow/agents/spec-architect.md"
rev="$here/plugins/dev-flow/agents/plan-reviewer.md"

for f in "$impl" "$build"; do
  for s in 'Task status: IN_PROGRESS' 'Task status: DONE'; do
    if grep -qF -- "$s" "$f"; then pass "$(basename "$f") has $s"; else bad "$(basename "$f") has $s"; fi
  done
done
if grep -qF -- 'Task status: NOT_STARTED' "$arch"; then pass "spec-architect.md has Task status: NOT_STARTED"; else bad "spec-architect.md has Task status: NOT_STARTED"; fi
if grep -qxF -- '- task status lines' "$rev"; then pass "plan-reviewer.md lists task status lines"; else bad "plan-reviewer.md lists task status lines"; fi

assets="$here/plugins/dev-flow/agents $here/plugins/dev-flow/commands $here/plugins/dev-flow/hooks $here/plugins/dev-flow/skills"
# shellcheck disable=SC2086
old=$(grep -rlE -- '- \[[ xX]\] Done|checkbox' $assets)
if [ -z "$old" ]; then pass "assets lack checkbox wording"; else bad "assets lack checkbox wording: $old"; fi
# shellcheck disable=SC2086
old=$(grep -rliwE 'tick|ticks|ticked|unticked' $assets)
if [ -z "$old" ]; then pass "assets lack tick wording"; else bad "assets lack tick wording: $old"; fi

if grep -qF -- "leave Task N's status as it is" "$impl"; then pass "implementer.md leaves the status on escalation"; else bad "implementer.md leaves the status on escalation"; fi
if grep -qF -- 'so a resume does not trip' "$impl"; then bad "implementer.md lacks the path-exists reason"; else pass "implementer.md lacks the path-exists reason"; fi
if grep -qF -- '(review-fix dispatches in step 6 excepted)' "$build"; then pass "build.md excepts review-fix dispatches"; else bad "build.md excepts review-fix dispatches"; fi

if [ "$fail" = 0 ]; then echo ALL-PASS; else echo SOME-FAILED; exit 1; fi
