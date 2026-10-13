#!/usr/bin/env bash
# Characterisation test for plugins/dev-flow/hooks/scripts/stop-gate.sh: pins
# the block-cap retry cycle byte for byte. It runs from .claude/test-cmd, and
# the fixture repos are generated into a temporary directory.
set -u
unset CLAUDE_CODE_STOP_HOOK_BLOCK_CAP DEV_FLOW_STOP_GATE_MAX
here=$(cd "$(dirname "$0")/.." && pwd)
gate="$here/plugins/dev-flow/hooks/scripts/stop-gate.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

# repo <dir> <test-cmd body>: a git repo with a test-cmd and an untracked change.
repo() {
  mkdir -p "$1/.claude"
  git -C "$1" init -q
  printf '%s\n' "$2" > "$1/.claude/test-cmd"
  echo x > "$1/changed.txt"
}

# step <dir> <active> [VAR=value...]: one Stop hook run, printed in the spec format.
step() {
  local dir=$1 active=$2 rc state
  shift 2
  printf '{"stop_hook_active":%s}' "$active" \
    | env "$@" CLAUDE_PROJECT_DIR="$dir" bash "$gate" > "$tmp/out" 2> "$tmp/err"
  rc=$?
  state=none
  [ -f "$dir/.claude/.stop-gate-state" ] && state=$(cat "$dir/.claude/.stop-gate-state")
  echo "-- active=$active rc=$rc state=$state"
  sed 's/^/   err| /' "$tmp/err"
  grep . "$tmp/out" | sed 's/^/   out| /'
}

transcript() {
  local d
  echo "## A default cap (max 3, harness 8)"
  d=$tmp/a; repo "$d" 'echo boom; exit 1'
  step "$d" false; step "$d" true; step "$d" true; step "$d" true
  echo "   log lines: $(wc -l < "$d/.claude/stop-gate-giveup.log" | tr -d ' ')"

  echo "## B harness cap 3 reduces max to 2"
  d=$tmp/b; repo "$d" 'echo boom; exit 1'
  step "$d" false CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=3
  step "$d" true CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=3
  step "$d" true CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=3

  echo "## C near harness cap from a prior streak"
  d=$tmp/c; repo "$d" 'echo boom; exit 1'
  echo "0 5" > "$d/.claude/.stop-gate-state"
  step "$d" true; step "$d" true

  echo "## D retry cap 0"
  d=$tmp/d; repo "$d" 'echo boom; exit 1'
  step "$d" false DEV_FLOW_STOP_GATE_MAX=0

  echo "## E pass resets"
  d=$tmp/e; repo "$d" 'exit 0'
  echo "2 1" > "$d/.claude/.stop-gate-state"
  step "$d" true

  echo "## F nothing changed"
  d=$tmp/f; repo "$d" 'echo boom; exit 1'
  rm "$d/changed.txt"
  echo ".claude/" > "$d/.gitignore"
  git -C "$d" add .gitignore
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm init
  step "$d" false
}

golden() {
  cat <<'GOLDEN'
## A default cap (max 3, harness 8)
-- active=false rc=2 state=1 0
   err| Quality gate failed (attempt 1/3 (harness cap 8), 0 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:
   err| boom
-- active=true rc=2 state=2 1
   err| Quality gate failed (attempt 2/3 (harness cap 8), 1 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:
   err| boom
-- active=true rc=2 state=3 2
   err| Quality gate failed (attempt 3/3 (harness cap 8), 2 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:
   err| boom
-- active=true rc=0 state=0 3
   err| ==================================================================
   err| Quality gate: giving up after 3 failed attempts. Work is NOT verified.
   err| Last failure (exit 1):
   err| boom
   err| See .claude/stop-gate-giveup.log for the full history.
   err| ==================================================================
   out| {"systemMessage":"Quality gate gave up: .claude/test-cmd still fails. Work is NOT verified. See .claude/stop-gate-giveup.log."}
   log lines: 6
## B harness cap 3 reduces max to 2
-- active=false rc=2 state=1 0
   err| Quality gate failed (attempt 1/2 (harness cap 3), 0 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:
   err| Note: the configured retry cap 3 was reduced to 2 to stay below Claude Code's stop-hook block cap (3, CLAUDE_CODE_STOP_HOOK_BLOCK_CAP). At that cap Claude Code ends the turn itself and this gate could not report the failure.
   err| boom
-- active=true rc=2 state=2 1
   err| Quality gate failed (attempt 2/2 (harness cap 3), 1 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:
   err| boom
-- active=true rc=0 state=0 2
   err| ==================================================================
   err| Quality gate: giving up after 2 failed attempts. Work is NOT verified.
   err| Last failure (exit 1):
   err| boom
   err| See .claude/stop-gate-giveup.log for the full history.
   err| ==================================================================
   out| {"systemMessage":"Quality gate gave up: .claude/test-cmd still fails. Work is NOT verified. See .claude/stop-gate-giveup.log."}
## C near harness cap from a prior streak
-- active=true rc=2 state=1 6
   err| Quality gate failed (attempt 1/3 (harness cap 8), 6 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:
   err| boom
-- active=true rc=0 state=0 7
   err| ==================================================================
   err| Quality gate: giving up at attempt 2/3 because one more block would reach Claude Code's stop-hook block cap (8; 7 consecutive continuation(s) so far). Work is NOT verified.
   err| Last failure (exit 1):
   err| boom
   err| See .claude/stop-gate-giveup.log for the full history.
   err| ==================================================================
   out| {"systemMessage":"Quality gate gave up: .claude/test-cmd still fails. Work is NOT verified. See .claude/stop-gate-giveup.log."}
## D retry cap 0
-- active=false rc=0 state=none
   err| ==================================================================
   err| Quality gate: giving up without blocking (retry cap is 0). Work is NOT verified.
   err| Last failure (exit 1):
   err| boom
   err| See .claude/stop-gate-giveup.log for the full history.
   err| ==================================================================
   out| {"systemMessage":"Quality gate gave up: .claude/test-cmd still fails. Work is NOT verified. See .claude/stop-gate-giveup.log."}
## E pass resets
-- active=true rc=0 state=0 2
## F nothing changed
-- active=false rc=0 state=none
GOLDEN
}

if [ "${1:-}" = "--transcript" ]; then transcript; exit 0; fi

if out=$(diff <(golden) <(transcript)); then
  echo "PASS: retry-cycle"
else
  echo "FAIL: retry-cycle"; echo "$out" | sed 's/^/  /'; fail=1
fi

# plan <dir> <status> <ticked>: a four-task plan whose first <ticked> tasks are ticked.
plan() {
  local dir=$1 status=$2 ticked=$3 n box names=(x One Two Three Four)
  mkdir -p "$dir/.claude/specs" "$dir/.claude/plans"
  echo '# Spec: demo' > "$dir/.claude/specs/demo.md"
  {
    echo '# Plan: demo'
    echo "Status: $status"
    echo 'Approved: yes'
    echo 'Spec: .claude/specs/demo.md'
    echo
    echo '## Tasks'
    for n in 1 2 3 4; do
      box=' '; [ "$n" -le "$ticked" ] && box=x
      echo
      echo "### Task $n: ${names[$n]}"
      echo
      echo "- [$box] Done"
      echo
      echo 'Objective: Do it.'
      echo
      echo 'Files:'
      echo "- test t$n.sh"
      echo
      echo "Test first: t$n fails."
      echo
      echo "Test command: \`bash t$n.sh\`"
      echo
      echo 'Done when:'
      echo "- t$n passes"
    done
  } > "$dir/.claude/plans/demo.md"
}

# run <dir> <active>: one gate run; sets rc, state, and leaves $tmp/out and $tmp/err.
run() {
  printf '{"stop_hook_active":%s}' "$2" \
    | CLAUDE_PROJECT_DIR="$1" bash "$gate" > "$tmp/out" 2> "$tmp/err"
  rc=$?
  state=none
  [ -f "$1/.claude/.stop-gate-state" ] && state=$(cat "$1/.claude/.stop-gate-state")
}

# check <label> <condition command...>: PASS or FAIL line.
check() {
  local label=$1
  shift
  if "$@"; then echo "PASS: $label"; else echo "FAIL: $label"; fail=1; fi
}

has() { grep -qF -- "$1" "$tmp/err"; }

g_ok() {
  local d=$tmp/g
  repo "$d" 'exit 0'; plan "$d" IN_PROGRESS 2
  run "$d" false
  [ "$rc" = 2 ] && [ "$state" = "1 0" ] \
    && has 'Plan incomplete (attempt 1/3 (harness cap 8), 0 consecutive stop-hook continuation(s) so far)' \
    && has 'open=3: Three' && has 'open=4: Four' \
    && ! has 'open=1:' && ! has 'open=2:'
}
check G g_ok

h_ok() {
  local d=$tmp/h
  repo "$d" 'exit 0'; plan "$d" IN_PROGRESS 2
  printf '\n## Deviations\n\n- Task 3: BLOCKED: needs a schema decision\n' >> "$d/.claude/plans/demo.md"
  run "$d" false
  has 'blocked=3 line=' && has 'needs a schema decision'
}
check H h_ok

i_ok() {
  local d=$tmp/i
  repo "$d" 'exit 0'; plan "$d" APPROVED 2
  run "$d" false
  [ "$rc" = 0 ]
}
check I i_ok

j_ok() {
  local d=$tmp/j
  repo "$d" 'exit 0'; plan "$d" IN_PROGRESS 4
  run "$d" false
  [ "$rc" = 0 ] && [ "$state" = none ]
}
check J j_ok

k_ok() {
  local d=$tmp/k rcs="" states="" a
  repo "$d" 'exit 0'; plan "$d" IN_PROGRESS 2
  for a in false true true true; do
    run "$d" "$a"; rcs="$rcs $rc"; states="$states|$state"
  done
  [ "$rcs" = " 2 2 2 0" ] && [ "$states" = "|1 0|2 1|3 2|0 3" ] \
    && [ "$(cat "$tmp/out")" = '{"systemMessage":"Quality gate gave up: an IN_PROGRESS plan in .claude/plans is not finished. Work is NOT verified. See .claude/stop-gate-giveup.log."}' ] \
    && has 'open=3: Three'
}
check K k_ok

l_ok() {
  local d=$tmp/l
  repo "$d" 'exit 0'; rm "$d/.claude/test-cmd"; plan "$d" IN_PROGRESS 2
  run "$d" false
  [ "$rc" = 2 ]
}
check L l_ok

m_ok() {
  local d=$tmp/m
  {
    echo "## A default cap (max 3, harness 8)"
    repo "$d" 'echo boom; exit 1'; plan "$d" IN_PROGRESS 4
    step "$d" false; step "$d" true; step "$d" true; step "$d" true
    echo "   log lines: $(wc -l < "$d/.claude/stop-gate-giveup.log" | tr -d ' ')"
  } > "$tmp/m.txt"
  diff <(golden | sed -n '/^## A/,/^## B/{/^## B/!p;}') "$tmp/m.txt" >/dev/null
}
check M m_ok

n_ok() {
  local d=$tmp/n
  repo "$d" 'echo boom; exit 1'; plan "$d" IN_PROGRESS 2
  run "$d" false
  [ "$(head -1 "$tmp/err")" = 'Quality gate failed (attempt 1/3 (harness cap 8), 0 consecutive stop-hook continuation(s) so far, exit 1). Fix these before finishing:' ] \
    && has boom && has 'open=3: Three'
}
check N n_ok

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
