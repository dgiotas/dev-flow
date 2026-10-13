#!/usr/bin/env bash
# Runs when Claude tries to finish. Exit 2 = block stopping, stderr goes back to Claude.
#
# Retries up to N times (default 3; .claude/test-cmd-retries or env DEV_FLOW_STOP_GATE_MAX)
# before giving up, instead of blocking forever.
# Claude Code itself ends the turn after CLAUDE_CODE_STOP_HOOK_BLOCK_CAP (default 8, 0 = off)
# consecutive stop-hook continuations, counted across all Stop hooks. So the gate counts
# continuations from stop_hook_active in .claude/.stop-gate-state ("<failures> <continuations>"),
# keeps N below that cap, and gives up with the banner rather than make the cap-th continuation.
#
# Plan check: a .claude/plans/*.md with "Status: IN_PROGRESS" that still has open tasks or
# unresolved BLOCKED entries (per plan-check.sh) also blocks stopping, on the same counter and
# caps as a failing test-cmd. With no .claude/test-cmd the gate runs only for such a plan.
set -u
# num DIGITS: decimal value with leading zeros stripped (no octal); over 6 digits reads as 999999 so it can't overflow.
num() { v=${1#"${1%%[!0]*}"}; v=${v:-0}; [ ${#v} -gt 6 ] && v=999999; echo "$v"; }
input=$(cat)
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

cmd_file=".claude/test-cmd"
checker="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/plan-check.sh"
plans=$(grep -lx 'Status: IN_PROGRESS' .claude/plans/*.md 2>/dev/null)
[ -f "$cmd_file" ] || [ -n "$plans" ] || exit 0

# Skip if nothing changed (pure Q&A turns shouldn't trigger a test run).
changed=yes
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git diff --quiet && git diff --cached --quiet \
     && [ -z "$(git ls-files --others --exclude-standard \
            | grep -vxF -e .claude/.stop-gate-state -e .claude/stop-gate-giveup.log -e .claude/.devflow-state.json)" ]; then
    changed=no
  fi
fi

state_file=".claude/.stop-gate-state"
giveup_log=".claude/stop-gate-giveup.log"

count=0
streak=0
if [ -f "$state_file" ]; then
  read -r a b _ < "$state_file"
  a=$(printf '%s' "${a:-}" | tr -dc '0-9'); b=$(printf '%s' "${b:-}" | tr -dc '0-9')
  [ -n "$a" ] && count=$(num "$a")
  [ -n "$b" ] && streak=$(num "$b")
fi
if [ "$active" = true ]; then streak=$((streak + 1)); else streak=0; fi

# One line "<failures> <consecutive stop-hook continuations>"; no file when both are 0.
save() {
  if [ "$count" -eq 0 ] && [ "$streak" -eq 0 ]; then
    rm -f "$state_file"
  else
    mkdir -p .claude
    printf '%s %s\n' "$count" "$streak" > "$state_file"
  fi
}
save

[ "$changed" = yes ] || exit 0

max=3
if [ -f ".claude/test-cmd-retries" ]; then
  n=$(tr -dc '0-9' < .claude/test-cmd-retries)
  [ -n "$n" ] && max=$(num "$n")
fi
case "${DEV_FLOW_STOP_GATE_MAX:-}" in ''|*[!0-9]*) ;; *) max=$(num "$DEV_FLOW_STOP_GATE_MAX") ;; esac

harness=8
case "${CLAUDE_CODE_STOP_HOOK_BLOCK_CAP:-}" in ''|*[!0-9]*) ;; *) harness=$(num "$CLAUDE_CODE_STOP_HOOK_BLOCK_CAP") ;; esac
note=""
if [ "$harness" -gt 0 ] && [ "$max" -ge "$harness" ]; then
  note="Note: the configured retry cap $max was reduced to $((harness - 1)) to stay below Claude Code's stop-hook block cap ($harness, CLAUDE_CODE_STOP_HOOK_BLOCK_CAP). At that cap Claude Code ends the turn itself and this gate could not report the failure."
  max=$((harness - 1))
fi
cap_label="harness cap $harness"
[ "$harness" -eq 0 ] && cap_label="harness cap off"

if [ -f "$cmd_file" ]; then
  out=$(bash "$cmd_file" 2>&1)
  status=$?
else
  out=""
  status=0
fi

pending=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  res=$(bash "$checker" "$p" 2>/dev/null)
  [ $? -eq 2 ] && continue
  printf '%s\n' "$res" | grep -qx 'status=IN_PROGRESS' || continue
  left=$(printf '%s\n' "$res" | grep -E '^(open|blocked)=')
  [ -n "$left" ] || continue
  pending="$pending$p is Status: IN_PROGRESS with work left:
$left
"
done <<EOF
$plans
EOF

if [ $status -eq 0 ] && [ -z "$pending" ]; then
  count=0
  save
  exit 0
fi

count=$((count + 1))
near_cap=no
[ "$harness" -gt 0 ] && [ $((streak + 1)) -ge "$harness" ] && near_cap=yes

if [ "$count" -le "$max" ] && [ "$near_cap" = no ]; then
  save
  {
    if [ $status -ne 0 ]; then
      echo "Quality gate failed (attempt $count/$max ($cap_label), $streak consecutive stop-hook continuation(s) so far, exit $status). Fix these before finishing:"
    else
      echo "Plan incomplete (attempt $count/$max ($cap_label), $streak consecutive stop-hook continuation(s) so far). Do not report this work as done:"
    fi
    [ -n "$note" ] && [ "$count" -eq 1 ] && echo "$note"
    [ $status -ne 0 ] && printf '%s\n' "$out" | tail -60
    if [ -n "$pending" ]; then
      printf '%s' "$pending"
      echo "Finish the open tasks with /dev-flow:build. If a task is BLOCKED or the build is waiting for the user, tell the user exactly this state and end your turn. Never tick a box, edit the plan or change its Status to get past this gate."
    fi
  } >&2
  exit 2
fi

# Retry cap reached, or one more block would reach Claude Code's cap: stop blocking so
# this can't loop forever, but make the failure impossible to miss. Reset the counter so
# the next real attempt starts fresh.
if [ "$count" -le "$max" ]; then
  headline="Quality gate: giving up at attempt $count/$max because one more block would reach Claude Code's stop-hook block cap ($harness; $streak consecutive continuation(s) so far). Work is NOT verified."
elif [ "$max" -eq 0 ]; then
  headline="Quality gate: giving up without blocking (retry cap is 0). Work is NOT verified."
else
  headline="Quality gate: giving up after $max failed attempts. Work is NOT verified."
fi
count=0
save
{
  echo "=================================================================="
  echo "$headline"
  if [ $status -ne 0 ]; then
    echo "Last failure (exit $status):"
    printf '%s\n' "$out" | tail -60
  fi
  [ -n "$pending" ] && printf '%s' "$pending"
  echo "See $giveup_log for the full history."
  echo "=================================================================="
} | tee -a "$giveup_log" >&2
# Stderr on exit 0 never reaches the transcript; systemMessage is shown to the user.
causes=""
[ $status -ne 0 ] && causes=".claude/test-cmd still fails"
if [ -n "$pending" ]; then
  [ -n "$causes" ] && causes="$causes; "
  causes="${causes}an IN_PROGRESS plan in .claude/plans is not finished"
fi
printf '{"systemMessage":"%s"}\n' "Quality gate gave up: $causes. Work is NOT verified. See $giveup_log."
exit 0
