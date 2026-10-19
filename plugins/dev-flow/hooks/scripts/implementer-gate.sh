#!/usr/bin/env bash
# PreToolUse gate on Agent and Task calls that start the dev-flow implementer.
#
# It denies the call unless the plan named on a "Plan: <path>" line of the prompt
# passes plan-check.sh and is approved. Deny = exit 2 with the reason on stderr;
# nothing is ever printed on stdout.
#
# It allows every subagent_type except the one it gates (fail open, so other
# agents keep working; build step 0 is the instruction-level backstop). For the
# implementer it denies on every uncertain case: no jq, no plan line, a plan that
# is missing, failing or unapproved. It also denies while the plan has an
# unresolved BLOCKED deviation, so a BLOCKED task halts the build.
set -u
input=$(cat)
checker="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/plan-check.sh"
want=dev-flow:implementer   # subagent_type as the hook receives it; see README "Implementer gate"

deny() {
  {
    echo "BLOCKED: dev-flow implementer gate: $1"
    [ -n "${2:-}" ] && printf '%s\n' "$2"
    echo "Fix the plan and retry. If a plan-check finding is a false positive, the user (not you) adds"
    echo "\"Override: <code> task <N>: <reason>\" to the plan header; the reviewer is shown every override."
    echo "Do not work around this gate with another agent."
  } >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1; then
  if printf '%s' "$input" | grep -q 'implementer'; then
    deny "jq is not on PATH, so the payload cannot be parsed. Install jq (brew install jq / apt install jq) outside this session, then retry."
  fi
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool" in Agent|Task) ;; *) exit 0 ;; esac

type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty')
[ "$type" = "$want" ] || exit 0

prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty')
plan=$(printf '%s\n' "$prompt" | sed -n 's/^Plan:[[:space:]]*\(.*\.md\)[[:space:]]*$/\1/p' | head -n 1)
[ -n "$plan" ] || deny 'the prompt has no "Plan: <path to .claude/plans/<slug>.md>" line, so there is no plan to check.'

cd "${CLAUDE_PROJECT_DIR:-.}" || deny "cannot enter CLAUDE_PROJECT_DIR to resolve $plan."

out=$(bash "$checker" "$plan" 2>&1); rc=$?
[ "$rc" = 0 ] || deny "$plan does not pass plan-check (exit $rc). Do NOT set a Task status to DONE for a task that is not finished. If a task's verify failed or the plan changed mid-build, stop and report to the user instead of re-dispatching." "$(printf '%s\n' "$out" | tail -n 40)"

printf '%s\n' "$out" | grep -qx 'approved=yes' || deny "$plan is not approved: /dev-flow:build sets Approved: yes after plan-check passes."
b=$(printf '%s\n' "$out" | grep '^blocked=')
[ -z "$b" ] || deny "$plan has an unresolved BLOCKED entry, so the build halts here. Report it to the user; the user resolves it by rewriting the line as \"- Task N: RESOLVED: <decision>\" and runs the build again." "$b"
exit 0
