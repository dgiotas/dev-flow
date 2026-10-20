#!/usr/bin/env bash
# Deterministic checks that commands/build.md routes each task by its title tag,
# reviews the final diff with security-reviewer and reviewer, then runs verify-done.
# They run from .claude/test-cmd.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
b="$here/plugins/dev-flow/commands/build.md"
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

for s in 'no tag -> `implementer`' '`[backend]` -> `backend-implementer`' '`[frontend]` -> `frontend-implementer`' \
  '`[qa]` -> `qa-engineer`' '`[devops]` -> `devops-engineer`' '`[docs]` -> `docs-writer`' 'Do not merge or push'; do
  if grep -qF -- "$s" "$b"; then pass "has $s"; else bad "has $s"; fi
done

step3=$(grep '^3\. ' "$b")
case "$step3" in *'a tagged `Manual:` task'*) pass "step 3 has tagged Manual refusal" ;; *) bad "step 3 has tagged Manual refusal" ;; esac

step5=$(grep '^5\. ' "$b")
case "$step5" in *'`security-reviewer`'*) pass "step 5 invokes security-reviewer" ;; *) bad "step 5 invokes security-reviewer" ;; esac

step6=$(grep '^6\. ' "$b")
case "$step6" in *'`reviewer`'*) pass "step 6 invokes reviewer" ;; *) bad "step 6 invokes reviewer" ;; esac
case "$step6" in *security-reviewer*) pass "step 6 names security-reviewer" ;; *) bad "step 6 names security-reviewer" ;; esac
for s in 'returns no verdict' 'do not go on to step 7' 'highest-numbered such task' 'only if at least one fix dispatch was made' \
  'delete `<plan>.before`' "give step 7's finish report" 'without running `verify-done`' 'leave the `Status:` line unchanged'; do
  case "$step6" in *"$s"*) pass "step 6 has $s" ;; *) bad "step 6 has $s" ;; esac
done

step7=$(grep '^7\. ' "$b")
case "$step7" in *'`verify-done`'*) pass "step 7 runs verify-done" ;; *) bad "step 7 runs verify-done" ;; esac
for s in 'report-only' 'make no edits' 'never edit inline' 'do not dispatch a fix' 'I decide whether to run a fix'; do
  case "$step7" in *"$s"*) pass "step 7 has $s" ;; *) bad "step 7 has $s" ;; esac
done
case "$step7" in *'both reviews again'*) bad "step 7 lacks a fix-and-review loop" ;; *) pass "step 7 lacks a fix-and-review loop" ;; esac
vd=${step7%%verify-done*}
st=${step7%%Status: DONE*}
if [ "$vd" != "$step7" ] && [ "$st" != "$step7" ] && [ "${#vd}" -lt "${#st}" ]; then
  pass "step 7 runs verify-done before Status: DONE"
else
  bad "step 7 runs verify-done before Status: DONE"
fi

for s in requirements-analyst bug-triager; do
  if grep -qF -- "$s" "$b"; then bad "lacks $s"; else pass "lacks $s"; fi
done

if [ "$fail" = 0 ]; then echo ALL-PASS; else echo SOME-FAILED; exit 1; fi
