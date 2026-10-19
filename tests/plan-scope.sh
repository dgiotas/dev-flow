#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/plan-scope.sh.
# They run from .claude/test-cmd, and every repository is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/plan-scope.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# mkrepo <dir> <files line>: committed src/a.sh and src/b.sh, ignored .claude/ holding the spec and plan
mkrepo() {
  git init -q -b main "$1"
  mkdir -p "$1/src" "$1/.claude/specs" "$1/.claude/plans"
  echo a > "$1/src/a.sh"; echo b > "$1/src/b.sh"
  printf '.claude/\n' > "$1/.gitignore"
  echo spec > "$1/.claude/specs/demo.md"
  cat > "$1/.claude/plans/demo.md" <<PLAN
# Plan: Demo

Status: DRAFT
Approved: no
Spec: .claude/specs/demo.md

## Tasks

### Task 1: Change it

Task status: DONE

Objective: Change the file.

Files:
- $2

Test first: a test.

Test command: \`bash tests/t.sh\`

Done when:
- run \`bash tests/t.sh\` and expect ok

Risk: low

## Deviations

- Task 1: also touched \`src/c.sh\`
PLAN
  g -C "$1" add -A && g -C "$1" commit -q -m init
}

# expect <label> <want exit> <want exact line> [args...]; leaves out for also()
expect() {
  label=$1; want_rc=$2; want_line=$3; shift 3
  out=$(bash "$script" "$@" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  if [ "$rc" = "$want_rc" ] && printf '%s\n' "$out" | grep -qxF -- "$want_line" && [ "${last#summary=}" != "$last" ]; then
    pass "$label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

# also <label> <want exact line>: re-checks the output of the last expect
also() {
  if printf '%s\n' "$out" | grep -qxF -- "$2"; then pass "$1"; else bad "$1"; fi
}

D=$tmp/drift; mkrepo "$D" "modify src/a.sh"
base=$(g -C "$D" rev-parse HEAD)
echo a2 >> "$D/src/a.sh"; echo b2 >> "$D/src/b.sh"
echo c > "$D/src/c.sh"; echo d > "$D/src/d.sh"
echo before > "$D/.claude/plans/demo.md.before"
cd "$D" || exit 2
expect drift 1 drift=src/b.sh "$D/.claude/plans/demo.md" "$base"
also drift-d drift=src/d.sh
also drift-count drifted=2
also drift-result result=drift
if printf '%s\n' "$out" | grep -qE '^drift=src/(a|c)\.sh$'; then bad drift-declared-excluded; else pass drift-declared-excluded; fi

g -C "$D" add src/b.sh && g -C "$D" commit -q -m b
expect committed 1 drift=src/b.sh "$D/.claude/plans/demo.md" "$base"

C=$tmp/clean; mkrepo "$C" "modify src/a.sh"
base=$(g -C "$C" rev-parse HEAD)
echo a2 >> "$C/src/a.sh"
cd "$C" || exit 2
expect clean 0 result=ok "$C/.claude/plans/demo.md" "$base"

R=$tmp/rename; mkrepo "$R" "rename src/a.sh -> src/e.sh"
base=$(g -C "$R" rev-parse HEAD)
g -C "$R" mv src/a.sh src/e.sh
cd "$R" || exit 2
expect rename 0 result=ok "$R/.claude/plans/demo.md" "$base"

# hook state files are untracked run state, never drift (repo that does not gitignore them)
S=$tmp/state; mkrepo "$S" "modify src/a.sh"
printf '' > "$S/.gitignore"
g -C "$S" add -A && g -C "$S" commit -q -m unignore
base=$(g -C "$S" rev-parse HEAD)
echo a2 >> "$S/src/a.sh"
mkdir -p "$S/.claude/.approved-writes"
echo x > "$S/.claude/.stop-gate-state"; echo x > "$S/.claude/stop-gate-giveup.log"
echo x > "$S/.claude/.stop-gate-pass"; echo x > "$S/.claude/.stop-gate-plan"
echo x > "$S/.claude/.devflow-state.json"; echo x > "$S/.claude/.approved-writes/m1"
cd "$S" || exit 2
expect state-files 0 result=ok "$S/.claude/plans/demo.md" "$base"

# project root is a subdirectory of the git top level: only the undeclared change drifts
P=$tmp/sub; mkrepo "$P" "modify src/a.sh"
mkdir "$P/proj"; mv "$P/src" "$P/.claude" "$P/proj/"
echo top > "$P/top.txt"
g -C "$P" add -A && g -C "$P" commit -q -m sub
base=$(g -C "$P" rev-parse HEAD)
echo a2 >> "$P/proj/src/a.sh"; echo b2 >> "$P/proj/src/b.sh"; echo top2 >> "$P/top.txt"
cd "$P" || exit 2
expect subdir 1 drift=src/b.sh "$P/proj/.claude/plans/demo.md" "$base"
also subdir-count drifted=1

expect usage-none 2 error=usage
expect usage-bad-base 2 error=bad-base "$R/.claude/plans/demo.md" nope
expect usage-plan-missing 2 error=plan-missing "$R/.claude/plans/none.md" "$base"

# jq missing: a PATH with the tools the script needs but no jq
nojq=$tmp/nojq; mkdir -p "$nojq"
for t in bash awk sed sort mktemp tr grep cat rm dirname basename head tail git; do ln -s "$(command -v $t)" "$nojq/$t"; done
out=$(PATH="$nojq" bash "$script" "$R/.claude/plans/demo.md" "$base" 2>&1); rc=$?
last=$(printf '%s\n' "$out" | tail -n 1)
if [ "$rc" = 2 ] && [ "$(printf '%s\n' "$out" | head -n 1)" = error=jq-missing ] && [ "${last#summary=}" != "$last" ]; then pass no-jq; else echo "FAIL: no-jq (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; fi

if [ "$fail" = 0 ]; then echo ALL-PASS; else echo SOME-FAILED; exit 1; fi
