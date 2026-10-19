#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/plan-edit-check.sh.
# They run from .claude/test-cmd, and every fixture is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/plan-edit-check.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

cat > "$tmp/before.md" <<'PLAN'
# Plan: Demo

Status: IN_PROGRESS
Approved: yes
Spec: .claude/specs/demo.md

## Tasks

### Task 1: First

Task status: NOT_STARTED

Objective: Do the first thing.

Files:
- modify src/a.sh

Test first: a test.

Test command: `bash tests/t.sh`

Done when:
- run `bash tests/t.sh` and expect ok

Risk: low

### Task 2: Second

Task status: NOT_STARTED

Objective: Do the second thing.

Files:
- modify src/b.sh
- modify src/c.sh

Test first: a test.

Test command: `bash tests/t.sh`

Done when:
- run `bash tests/t.sh` and expect ok

Depends on: 1

Risk: low

## Deviations

- Task 1: kept printf
PLAN

# mk <label> <awk program> [before file]: writes $tmp/<label>.md from the before plan
mk() { awk "$2" "${3:-$tmp/before.md}" > "$tmp/$1.md"; echo "$tmp/$1.md"; }

# expect <label> <want exit> <want exact line> <after file> [before file] [N]
expect() {
  label=$1; want_rc=$2; want_line=$3; after=$4; before=${5:-$tmp/before.md}; n=${6:-2}
  out=$(bash "$script" "$before" "$after" "$n" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  if [ "$rc" = "$want_rc" ] && printf '%s\n' "$out" | grep -qF -- "$want_line" && [ "${last#summary=}" != "$last" ]; then
    pass "$label"
  else
    bad "$label (rc=$rc, want $want_rc / $want_line)"; printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

expect ok-done 0 'result=ok' "$(mk ok-done '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"DONE")} t && /^- modify src\/c.sh/{print; print "- modify src/x.sh"; next} 1 END{print "- Task 2: touched src/x.sh"}')"
expect ok-blocked 0 'result=ok' "$(mk ok-blocked '1 END{print "- Task 2: BLOCKED: needs a schema decision"}')"
awk '/^## Deviations/{exit} 1' "$tmp/before.md" > "$tmp/nodev.md"
expect ok-new-section 0 'result=ok' "$(mk ok-new-section '1 END{print "## Deviations"; print ""; print "- Task 2: x"}' "$tmp/nodev.md")" "$tmp/nodev.md"

expect foreign-objective 1 'error=foreign-edit' "$(mk foreign-objective '/^Objective: Do the first/{sub(/first/,"1st")} 1')"
expect foreign-header 1 'error=foreign-edit' "$(mk foreign-header '{sub(/^Status: IN_PROGRESS$/,"Status: DONE")} 1')"
expect other-status 1 'error=foreign-edit' "$(mk other-status '/^### Task 1:/{t=1} t && /^Task status: NOT_STARTED/ && !d{sub(/NOT_STARTED/,"DONE"); d=1} 1')"
expect other-files 1 'error=foreign-edit' "$(mk other-files '/^- modify src\/a.sh/{print; print "- modify src/y.sh"; next} 1')"
awk '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"DONE")} 1' "$tmp/before.md" > "$tmp/pre-done.md"
expect regress-done 1 'error=status-edit' "$tmp/before.md" "$tmp/pre-done.md"
expect files-removed 1 'error=files-removed' "$(mk files-removed '/^- modify src\/c.sh/{next} 1')"
expect dev-rewrite 1 'error=deviation-rewritten' "$(mk dev-rewrite '{sub(/kept printf/,"kept echo")} 1')"
expect dev-task 1 'error=deviation-task' "$(mk dev-task '1 END{print "- Task 1: x"}')"
awk '/^- modify src\/c.sh/{print; print "Model: sonnet"; next} 1' "$tmp/before.md" > "$tmp/model-before.md"
expect model-edit 1 'error=foreign-edit' "$(mk model-edit '{sub(/^Model: sonnet$/,"Model: opus")} 1' "$tmp/model-before.md")" "$tmp/model-before.md"
# Finding 6: fence rule mirrors plan-check (same character, at least the opening run length).
awk '/^### Task 1:/{t=1} t && /^Objective:/{print; print ""; print "~~~"; print "```"; print "### Task 2: fixture"; print "~~~"; next} 1' "$tmp/before.md" > "$tmp/fence-before.md"
expect fence-tilde-ok 0 'result=ok' "$(mk fence-tilde-ok '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"DONE")} 1' "$tmp/fence-before.md")" "$tmp/fence-before.md"
awk '/^### Task 1:/{t=1} t && /^Objective:/{print; print ""; print "````"; print "```"; print "### Task 2: fixture"; print "````"; next} 1' "$tmp/before.md" > "$tmp/fence4-before.md"
expect fence-four-ok 0 'result=ok' "$(mk fence-four-ok '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"DONE")} 1' "$tmp/fence4-before.md")" "$tmp/fence4-before.md"

# Finding 7: diagnostics carry the line that differs.
expect dev-rewrite-line 1 'error=deviation-rewritten line=50' "$(mk dev-rewrite-line '{sub(/kept printf/,"kept echo")} 1')"
{ cat "$tmp/before.md"; echo "- Task 1: second"; } > "$tmp/dev2-before.md"
expect dev-rewrite-second 1 'error=deviation-rewritten line=51' "$(mk dev-rewrite-second '{sub(/Task 1: second/,"Task 1: other")} 1' "$tmp/dev2-before.md")" "$tmp/dev2-before.md"
expect status-missing-line 1 'error=status-edit line=27' "$(mk status-missing-line '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{next} 1')"

# Task status moves: forward only; a checkbox plan has no status line.
expect ok-start 0 'result=ok' "$(mk ok-start '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"IN_PROGRESS")} 1')"
awk '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"IN_PROGRESS")} 1' "$tmp/before.md" > "$tmp/pre-progress.md"
expect ok-finish 0 'result=ok' "$(mk ok-finish '/^### Task 2:/{t=1} t && /^Task status: IN_PROGRESS/{sub(/IN_PROGRESS/,"DONE")} 1' "$tmp/pre-progress.md")" "$tmp/pre-progress.md"
expect regress-start 1 'error=status-edit' "$tmp/before.md" "$tmp/pre-progress.md"
expect bad-value 1 'error=status-edit' "$(mk bad-value '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"FINISHED")} 1')"
expect ok-unchanged-done 0 'result=ok' "$(mk ok-unchanged-done '1 END{print "- Task 2: x"}' "$tmp/pre-done.md")" "$tmp/pre-done.md"
awk '/^Task status: NOT_STARTED/{print "- [ ] Done"; next} 1' "$tmp/before.md" > "$tmp/checkbox.md"
awk '/^### Task 2:/{t=1} t && /^- \[ \] Done/{sub(/\[ \]/,"[x]")} 1' "$tmp/checkbox.md" > "$tmp/checkbox-ticked.md"
expect checkbox-tick 1 'error=status-edit' "$tmp/checkbox-ticked.md" "$tmp/checkbox.md"
expect dup-status 1 'error=foreign-edit' "$(mk dup-status '/^### Task 2:/{t=1} {print} t && /^Task status: NOT_STARTED/ && !d{print "Task status: DONE"; d=1}')"

# A second status line inside the Files block is not a Files entry.
expect dup-status-files 1 'error=foreign-edit' "$(mk dup-status-files '/^### Task 2:/{t=1} {print} t && /^- modify src\/c.sh/ && !d{print "Task status: DONE"; d=1}')"
# A spaces-only line before the status line is blank, as in plan-check.
awk '/^### Task 2:/{print; print "  "; next} 1' "$tmp/before.md" > "$tmp/ws-before.md"
expect ws-status 0 'result=ok' "$(mk ws-status '/^### Task 2:/{t=1} t && /^Task status: NOT_STARTED/{sub(/NOT_STARTED/,"DONE")} 1' "$tmp/ws-before.md")" "$tmp/ws-before.md"

out=$(bash "$script" "$tmp/before.md" "$tmp/before.md" 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -qF 'error=usage' && [ "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-8)" = summary= ]; then pass usage-args; else bad "usage-args (rc=$rc)"; fi
expect task-missing 2 'error=task-missing' "$tmp/before.md" "$tmp/before.md" 9
expect plan-missing 2 'error=plan-missing' "$tmp/before.md" "$tmp/nope.md"

if [ "$fail" = 0 ]; then echo ALL-PASS; else echo SOME-FAILED; fi
exit "$fail"
