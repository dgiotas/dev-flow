#!/usr/bin/env bash
# Runs when Claude tries to finish. Exit 2 = block stopping, stderr goes back to Claude.
#
# Retries up to N times (default 3) before giving up, instead of blocking forever
# or (the old behaviour) blocking only once per stop-sequence via stop_hook_active.
# Override the cap with a number in .claude/test-cmd-retries, or env DEV_FLOW_STOP_GATE_MAX.
set -u
input=$(cat) # consumed for API compliance; not otherwise used

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

cmd_file=".claude/test-cmd"
[ -f "$cmd_file" ] || exit 0

# Skip if nothing changed (pure Q&A turns shouldn't trigger a test run).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git diff --quiet && git diff --cached --quiet \
     && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    exit 0
  fi
fi

state_file=".claude/.stop-gate-state"
giveup_log=".claude/stop-gate-giveup.log"

max=3
if [ -f ".claude/test-cmd-retries" ]; then
  n=$(tr -dc '0-9' < .claude/test-cmd-retries)
  [ -n "$n" ] && max="$n"
fi
[ -n "${DEV_FLOW_STOP_GATE_MAX:-}" ] && max="$DEV_FLOW_STOP_GATE_MAX"

count=0
if [ -f "$state_file" ]; then
  n=$(tr -dc '0-9' < "$state_file")
  [ -n "$n" ] && count="$n"
fi

out=$(bash "$cmd_file" 2>&1)
status=$?

if [ $status -eq 0 ]; then
  rm -f "$state_file"
  exit 0
fi

count=$((count + 1))
mkdir -p .claude
printf '%s' "$count" > "$state_file"

if [ "$count" -le "$max" ]; then
  {
    echo "Quality gate failed (attempt $count/$max, exit $status). Fix these before finishing:"
    printf '%s\n' "$out" | tail -60
  } >&2
  exit 2
fi

# Cap reached: stop blocking so this can't loop forever, but make the failure
# impossible to miss. Reset the counter so the next real attempt starts fresh.
rm -f "$state_file"
{
  echo "=================================================================="
  echo "Quality gate: giving up after $max failed attempts. Work is NOT verified."
  echo "Last failure (exit $status):"
  printf '%s\n' "$out" | tail -60
  echo "See $giveup_log for the full history. Tell the user this could not be fixed automatically."
  echo "=================================================================="
} | tee -a "$giveup_log" >&2
exit 0
