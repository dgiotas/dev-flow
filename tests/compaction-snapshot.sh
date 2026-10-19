#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh and
# session-start-restore.sh. They run from .claude/test-cmd, and every project is
# generated into a temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
snap="$here/plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh"
restore="$here/plugins/dev-flow/hooks/scripts/session-start-restore.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# mkproj <dir> <status line 1> <status line 2> <status line 3>
mkproj() {
  git init -q "$1"
  mkdir -p "$1/.claude/plans"
  cat > "$1/.claude/plans/demo.md" <<PLAN
# Plan: Demo

Status: IN_PROGRESS

## Tasks

### Task 1: One

$2

### Task 2: Two

$3

### Task 3: Three

$4

## Acceptance criteria

- [ ] first
- [ ] second
PLAN
}

run_snap() { printf '{}' | CLAUDE_PROJECT_DIR="$1" bash "$snap"; }
run_restore() { printf '{}' | CLAUDE_PROJECT_DIR="$1" bash "$restore"; }

# a: status counts
d="$tmp/a"; mkproj "$d" 'Task status: DONE' 'Task status: IN_PROGRESS' 'Task status: NOT_STARTED'
run_snap "$d"
if jq -e '.schema_version == "2" and .plan.done == 1 and .plan.in_progress == 1 and .plan.total == 3' "$d/.claude/.devflow-state.json" >/dev/null; then
  pass "a: snapshot counts"; else bad "a: snapshot counts"; fi
out=$(run_restore "$d")
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("1 of 3 tasks done, 1 in progress.")' >/dev/null; then
  pass "a: restore text"; else bad "a: restore text: $out"; fi

# b: a plan without status lines is not countable
d="$tmp/b"; mkproj "$d" '' '' ''
run_snap "$d"
if jq -e '.plan.total == null' "$d/.claude/.devflow-state.json" >/dev/null; then
  pass "b: total null"; else bad "b: total null"; fi
out=$(run_restore "$d")
if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("task progress not countable.")' >/dev/null; then
  pass "b: restore text"; else bad "b: restore text: $out"; fi

# c: old schema is ignored
d="$tmp/c"; mkproj "$d" 'Task status: DONE' 'Task status: DONE' 'Task status: DONE'
run_snap "$d"
jq '.schema_version = "1"' "$d/.claude/.devflow-state.json" > "$d/.claude/s.tmp" && mv "$d/.claude/s.tmp" "$d/.claude/.devflow-state.json"
out=$(run_restore "$d"); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass "c: schema 1 ignored"; else bad "c: schema 1 ignored (rc=$rc out=$out)"; fi

[ "$fail" -eq 0 ] && echo ALL-PASS || exit 1
