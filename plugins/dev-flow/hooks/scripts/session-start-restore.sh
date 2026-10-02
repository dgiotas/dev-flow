#!/usr/bin/env bash
# SessionStart: re-injects the snapshot written by pre-compact-snapshot.sh as
# additionalContext, using the hookSpecificOutput JSON documented at
# https://code.claude.com/docs/en/hooks ("SessionStart decision control").
# Stays silent if the state file is missing, older than 24 h, has an unknown
# schema, or is unparseable. Never blocks: always exits 0.
set -u
input=$(cat) # consumed for API compliance; not otherwise used

restore() (
  command -v jq >/dev/null 2>&1 || exit 0
  cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
  f=.claude/.devflow-state.json
  [ -f "$f" ] || exit 0

  jq -e '.schema_version == "1" and (.plan.file | type) == "string" and ((now - (.saved_at | fromdateiso8601)) < 86400)' "$f" >/dev/null || exit 0

  ctx=$(jq -r '
    [ "dev-flow state saved before the last context compaction at \(.saved_at); docs/plans is the source of truth.",
      "Active plan: \(.plan.file) (slug \(.plan.slug)); "
        + (if .plan.total == null then "checklist progress not countable."
           else "\(.plan.done) of \(.plan.total) checklist items checked." end),
      (if .git == null then empty else
        "Git: branch \(.git.branch // "detached") at \(.git.head // "no commits"); \(.git.staged) staged, \(.git.unstaged) unstaged, \(.git.untracked) untracked files." end),
      (if .stop_gate.state == null and .stop_gate.giveup_logged_at == null then empty else
        "Stop gate: "
        + ([ (if .stop_gate.state == null then empty else "\(.stop_gate.state) failed attempt(s) recorded" end),
             (if .stop_gate.giveup_logged_at == null then empty else "give-up log last written at \(.stop_gate.giveup_logged_at)" end) ] | join("; "))
        + "." end),
      (if (.blocked | length) == 0 then empty else "Blocked lines in the plan:", (.blocked[0:10][] | "- \(.)") end)
    ] | join("\n")' "$f") || exit 0
  [ -n "$ctx" ] || exit 0

  jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
)

restore 2>/dev/null
exit 0
