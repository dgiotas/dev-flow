#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/hooks/scripts/implementer-gate.sh.
# They run from .claude/test-cmd, and the fixture repo and plans are generated
# into a temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
gate="$here/plugins/dev-flow/hooks/scripts/implementer-gate.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

P=$tmp/p
mkdir -p "$P/.claude/specs" "$P/.claude/plans" "$P/src"
echo '# Spec: gate' > "$P/.claude/specs/gate.md"
echo 'echo hello' > "$P/src/app.sh"
cat > "$P/.claude/plans/ok.md" <<'PLAN'
# Plan: gate

Status: IN_PROGRESS
Approved: yes
Spec: .claude/specs/gate.md

## Tasks

### Task 1: Touch the app

Task status: NOT_STARTED

Objective: Change the app.

Files:
- modify src/app.sh

Test first: the app test fails.

Test command: `bash src/app.sh`

Done when:
- the app prints hello
PLAN
sed 's/^Approved: yes$/Approved: no/' "$P/.claude/plans/ok.md" > "$P/.claude/plans/draft.md"
sed 's/^Status: IN_PROGRESS$/Status: WIP/' "$P/.claude/plans/ok.md" > "$P/.claude/plans/bad.md"
{ cat "$P/.claude/plans/ok.md"; printf '\n## Deviations\n\n- Task 1: BLOCKED: needs a schema decision\n'; } > "$P/.claude/plans/blocked.md"
sed 's/BLOCKED:/RESOLVED:/' "$P/.claude/plans/blocked.md" > "$P/.claude/plans/resolved.md"

# run <label> <want rc> <want stderr substring or empty> <tool_name> <subagent_type> <prompt> [project dir]
run() {
  label=$1; want_rc=$2; want_err=$3; tool=$4; type=$5; prompt=$6; pdir=${7:-$P}
  out=$(jq -n --arg t "$tool" --arg s "$type" --arg p "$prompt" \
    '{tool_name:$t, tool_input:{subagent_type:$s, prompt:$p, description:"x"}}' \
    | CLAUDE_PROJECT_DIR="$pdir" bash "$gate" 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
  if [ "$rc" = "$want_rc" ] && [ -z "$out" ] \
     && { [ -n "$want_err" ] || [ -z "$err" ]; } \
     && { [ -z "$want_err" ] || printf '%s\n' "$err" | grep -qF -- "$want_err"; }; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n%s\n' "$out" "$err" | sed 's/^/    /'; fail=1
  fi
}

imp=dev-flow:implementer
run write-tool 0 '' Write "$imp" 'Plan: .claude/plans/bad.md'
run general 0 '' Agent general-purpose 'Plan: .claude/plans/bad.md'
run reviewer 0 '' Agent dev-flow:reviewer 'Plan: .claude/plans/bad.md'
run bare-name 2 'error=header-status' Agent implementer 'Plan: .claude/plans/bad.md'
run bare-name-no-plan 2 'no "Plan:' Agent qa-engineer 'do task 1'
run bare-name-approved 0 '' Agent docs-writer 'Plan: .claude/plans/ok.md'
run bare-reviewer 0 '' Agent reviewer 'Plan: .claude/plans/bad.md'
run no-plan-line 2 'no "Plan:' Agent "$imp" 'do task 1'
run missing-plan 2 'error=plan-missing' Agent "$imp" 'Plan: .claude/plans/nope.md'
run failing 2 'error=header-status' Agent "$imp" 'Plan: .claude/plans/bad.md'
run draft 2 'is not approved' Agent "$imp" 'Plan: .claude/plans/draft.md'
run approved 0 '' Agent "$imp" 'Plan: .claude/plans/ok.md'
run blocked 2 'unresolved BLOCKED' Agent "$imp" 'Plan: .claude/plans/blocked.md'
run resolved 0 '' Agent "$imp" 'Plan: .claude/plans/resolved.md'
run task-tool 2 'error=header-status' Task "$imp" 'Plan: .claude/plans/bad.md'
run mid-prompt 0 '' Agent "$imp" "$(printf 'Task 1\nPlan: .claude/plans/ok.md')"
run absolute 0 '' Agent "$imp" "Plan: $P/.claude/plans/ok.md" "$tmp"

run no-project-dir 2 'cannot enter CLAUDE_PROJECT_DIR' Agent "$imp" 'Plan: .claude/plans/ok.md' "$tmp/nope"

for who in backend-implementer frontend-implementer qa-engineer devops-engineer docs-writer; do
  run "$who-draft" 2 'is not approved' Agent "dev-flow:$who" 'Plan: .claude/plans/draft.md'
  run "$who-approved" 0 '' Agent "dev-flow:$who" 'Plan: .claude/plans/ok.md'
  run "$who-no-plan" 2 'no "Plan:' Agent "dev-flow:$who" 'do task 1'
done

# Deny message must not push the orchestrator to tick an unfinished task.
msg=$(jq -n --arg p 'Plan: .claude/plans/bad.md' \
  '{tool_name:"Agent", tool_input:{subagent_type:"dev-flow:implementer", prompt:$p}}' \
  | CLAUDE_PROJECT_DIR="$P" bash "$gate" 2>&1)
if printf '%s\n' "$msg" | grep -qF 'stop and report' \
  && printf '%s\n' "$msg" | grep -qF 'Do NOT set a Task status to DONE' \
  && ! printf '%s\n' "$msg" | grep -qw 'tick'; then
  echo "PASS: failing-plan message"
else
  echo "FAIL: failing-plan message"; printf '%s\n' "$msg" | sed 's/^/    /'; fail=1
fi

# jq missing: a bin dir with the other tools the script uses, but no jq.
nojq=$tmp/nojq; mkdir "$nojq"
for t in bash cat grep dirname sed head tail; do ln -s "$(command -v $t)" "$nojq/$t"; done
for case in "implementer:2:BLOCKED" "backend-implementer:2:BLOCKED" "frontend-implementer:2:BLOCKED" "qa-engineer:2:BLOCKED" "devops-engineer:2:BLOCKED" "docs-writer:2:BLOCKED" "reviewer:0:"; do
  who=${case%%:*}; rest=${case#*:}; want_rc=${rest%%:*}; want_err=${rest#*:}
  out=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"dev-flow:%s","prompt":"Plan: x.md"}}' "$who" \
    | PATH=$nojq CLAUDE_PROJECT_DIR="$P" bash "$gate" 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
  if [ "$rc" = "$want_rc" ] && [ -z "$out" ] && { [ -z "$want_err" ] || printf '%s\n' "$err" | grep -qF "$want_err"; }; then
    echo "PASS: no-jq $who"
  else
    echo "FAIL: no-jq $who (exit $rc)"; printf '%s\n%s\n' "$out" "$err" | sed 's/^/    /'; fail=1
  fi
done

if jq -e '.hooks.PreToolUse | map(select(.matcher == "Agent|Task" and (.hooks | length) == 1 and (.hooks[0].command | endswith("hooks/scripts/implementer-gate.sh\""))))
  | length == 1' "$here/plugins/dev-flow/hooks/hooks.json" >/dev/null; then
  echo "PASS: wired"
else
  echo "FAIL: wired"; fail=1
fi

[ "$fail" = 0 ] && echo ALL-PASS
exit "$fail"
