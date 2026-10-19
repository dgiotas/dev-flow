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
# caps as a failing test-cmd. It blocks once per pending state and session (a SHA-256 of the session_id and the report, kept in
# .claude/.stop-gate-plan); on a repeat stop with the same state it prints a systemMessage
# instead of blocking. With no .claude/test-cmd the gate runs only for such a plan.
# Pass cache: a pass stores a work-tree fingerprint in .claude/.stop-gate-pass; while the tree matches it, test-cmd is not re-run.
set -u
# num DIGITS: decimal value with leading zeros stripped (no octal); over 6 digits reads as 999999 so it can't overflow.
num() { v=${1#"${1%%[!0]*}"}; v=${v:-0}; [ ${#v} -gt 6 ] && v=999999; echo "$v"; }
# untracked: untracked, non-ignored paths of the whole repository, relative to its top level, minus the hooks' own state files and the project's own .claude/worktrees/ (under CLAUDE_PROJECT_DIR, as plan-scope.sh). An untracked nested repository, including an unignored worktree under the repository root's .claude/worktrees/ when CLAUDE_PROJECT_DIR is a subdirectory, is listed as "dir/", which hash-object cannot hash, so it turns the cache off.
untracked() {
  git -C "$top" -c core.quotePath=false ls-files --others --exclude-standard \
    | P="$pfx" awk '
        BEGIN { p = ENVIRON["P"] }
        index($0, p ".claude/worktrees/") == 1 { next }
        $0 == p ".claude/.stop-gate-state" || $0 == p ".claude/stop-gate-giveup.log" ||
          $0 == p ".claude/.devflow-state.json" || $0 == p ".claude/.stop-gate-pass" ||
          $0 == p ".claude/.stop-gate-plan" { next }
        { print }
      '
}
# hash_of: SHA-256 hex of stdin (sha256sum, else shasum -a 256); returns 1 when neither exists.
hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    return 1
  fi
}
# fingerprint: one SHA-256 over HEAD, the tracked diff, the untracked paths and their
# blob hashes, and the test-cmd itself, all taken from the repository's top level. Returns 1
# (no fingerprint) outside a work tree, when any git step fails or when the index has
# gitlinks (submodule edits do not show in the diff) or when no SHA-256 tool exists.
fingerprint() {
  [ -n "$top" ] || return 1
  git -C "$top" ls-files -s | grep -q '^160000 ' && return 1
  u=$(untracked)
  h=""
  if [ -n "$u" ]; then h=$(printf '%s\n' "$u" | git -C "$top" hash-object --stdin-paths 2>/dev/null) || return 1; fi
  if git -C "$top" rev-parse -q --verify HEAD >/dev/null; then
    d=$(git -C "$top" rev-parse HEAD && git -C "$top" diff --no-ext-diff --no-textconv --binary HEAD) || return 1
  else
    d=$(git -C "$top" diff --no-ext-diff --no-textconv --binary --cached && git -C "$top" diff --no-ext-diff --no-textconv --binary) || return 1
  fi
  printf '%s\n%s\n%s\n%s\n' "$d" "$u" "$h" "$(cat "$cmd_file")" | hash_of
}
input=$(cat)
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

cmd_file=".claude/test-cmd"
checker="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/plan-check.sh"
plans=$(grep -lx 'Status: IN_PROGRESS' .claude/plans/*.md 2>/dev/null)
[ -f "$cmd_file" ] || [ -n "$plans" ] || exit 0

# top: the repository's top level, pfx: CLAUDE_PROJECT_DIR relative to it ("" at the top). Git runs from the top so a subdirectory project sees the whole repository and diff.relative cannot narrow the diffs.
top=""; pfx=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  top=$(git rev-parse --show-toplevel) && pfx=$(git rev-parse --show-prefix) || top=""
fi

# Skip if nothing changed (pure Q&A turns shouldn't trigger a test run).
changed=yes
if [ -n "$top" ]; then
  if git -C "$top" diff --quiet && git -C "$top" diff --cached --quiet \
     && [ -z "$(untracked)" ]; then
    changed=no
  fi
fi

state_file=".claude/.stop-gate-state"
pass_file=".claude/.stop-gate-pass"
plan_file=".claude/.stop-gate-plan"
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
  fp=$(fingerprint) || fp=""
  if [ -n "$fp" ] && [ -f "$pass_file" ] && [ "$(cat "$pass_file")" = "$fp" ]; then
    out=""
    status=0
  else
    out=$(bash "$cmd_file" 2>&1)
    status=$?
    if [ $status -eq 0 ] && [ -n "$fp" ]; then
      mkdir -p .claude
      printf '%s\n' "$fp" > "$pass_file"
    else
      rm -f "$pass_file"
    fi
  fi
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

seen=no
if [ -n "$pending" ]; then
  sig=$(printf '%s\n%s' "$sid" "$pending" | hash_of) || sig=""
  if [ -z "$sig" ]; then
    rm -f "$plan_file"
  elif [ -f "$plan_file" ] && [ "$(cat "$plan_file")" = "$sig" ]; then
    seen=yes; pending=""
  else
    mkdir -p .claude; printf '%s\n' "$sig" > "$plan_file"
  fi
else
  rm -f "$plan_file"
fi

if [ $status -eq 0 ] && [ -z "$pending" ]; then
  count=0
  save
  [ "$seen" = yes ] && printf '%s\n' '{"systemMessage":"Plan not finished: an IN_PROGRESS plan in .claude/plans still has open or blocked tasks (reported once, not blocking again)."}'
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
      echo "Finish the open tasks with /dev-flow:build. If a task is BLOCKED or the build is waiting for the user, tell the user exactly this state and end your turn. Never change a Task status, edit the plan or change its Status to get past this gate."
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
if [ -n "$pending" ] || [ "$seen" = yes ]; then
  [ -n "$causes" ] && causes="$causes; "
  causes="${causes}an IN_PROGRESS plan in .claude/plans is not finished"
fi
printf '{"systemMessage":"%s"}\n' "Quality gate gave up: $causes. Work is NOT verified. See $giveup_log."
exit 0
