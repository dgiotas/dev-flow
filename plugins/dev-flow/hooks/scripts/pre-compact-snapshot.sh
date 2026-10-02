#!/usr/bin/env bash
# PreCompact: saves a small state snapshot to .claude/.devflow-state.json so the
# active plan survives context compaction (session-start-restore.sh reads it back).
#
# Captures only: plan file name/slug, checklist counts, git branch/short sha/counts,
# stop-gate counter and give-up log time, and redacted, truncated BLOCKED lines.
# No file contents, prompts, payload text or absolute paths.
#
# Never blocks: always exits 0 and prints nothing. It does not read the payload,
# and writes nothing without jq or without a plan in .claude/plans/.
set -u
input=$(cat) # consumed for API compliance; not otherwise used

snapshot() (
  command -v jq >/dev/null 2>&1 || exit 0
  cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

  plan=$(ls -t .claude/plans/*.md 2>/dev/null | head -1)
  [ -n "$plan" ] && [ -f "$plan" ] || exit 0
  slug=$(basename "$plan" .md)

  total=$(grep -cE '^[[:space:]]*[-*] \[[ xX]\]' "$plan")
  checked=$(grep -cE '^[[:space:]]*[-*] \[[xX]\]' "$plan")
  if [ "$total" -eq 0 ]; then total=null; checked=null; fi

  git=null
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git symbolic-ref --short -q HEAD)
    head=$(git rev-parse --short HEAD 2>/dev/null)
    counts=$(git --no-optional-locks status --porcelain | awk '
      substr($0,1,2)=="??" { u++; next }
      { if (substr($0,1,1) != " ") s++; if (substr($0,2,1) != " ") w++ }
      END { printf "%d %d %d", s, w, u }')
    set -- $counts
    git=$(jq -n --arg b "$branch" --arg h "$head" --argjson s "$1" --argjson w "$2" --argjson u "$3" \
      '{branch: (if $b == "" then null else $b end), head: (if $h == "" then null else $h end),
        staged: $s, unstaged: $w, untracked: $u}')
  fi

  state=null
  if [ -f .claude/.stop-gate-state ]; then
    read -r n _ < .claude/.stop-gate-state
    n=$(printf '%s' "${n:-}" | tr -dc '0-9')
    [ -n "$n" ] && [ "$n" -gt 0 ] && state="$n"
  fi
  giveup=""
  [ -f .claude/stop-gate-giveup.log ] && giveup=$(date -u -r .claude/stop-gate-giveup.log +%Y-%m-%dT%H:%M:%SZ)

  blocked=$(jq -R -s 'split("\n") | map(select(contains("BLOCKED"))
    | gsub("(?<![^\\s\"'"'"'`(=:])/[^\\s\"'"'"'`)]*"; "<path>") | .[0:200]) | .[0:10]' "$plan")

  mkdir -p .claude
  jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg file "$plan" --arg slug "$slug" \
    --argjson checked "$checked" --argjson total "$total" --argjson git "$git" \
    --argjson state "$state" --arg giveup "$giveup" --argjson blocked "$blocked" \
    '{schema_version: "1", saved_at: $at,
      plan: {file: $file, slug: $slug, done: $checked, total: $total},
      git: $git,
      stop_gate: {state: $state, giveup_logged_at: (if $giveup == "" then null else $giveup end)},
      blocked: $blocked}' > .claude/.devflow-state.json.tmp \
    && mv .claude/.devflow-state.json.tmp .claude/.devflow-state.json \
    || rm -f .claude/.devflow-state.json.tmp
)

snapshot >/dev/null 2>&1 # never print: PreCompact stdout JSON could block compaction
exit 0
