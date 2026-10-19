#!/usr/bin/env bash
# plan-scope.sh: list changed paths that no task's Files block and no
# Deviations line declares.
# Usage: bash plan-scope.sh <plan> <base>   (run from inside the git work tree)
# Output (key=value lines): plan=, base=, one drift=<path> per undeclared
#   changed path, declared=<n>, changed=<n>, drifted=<n>, result=ok|drift,
#   and a final summary= line. Errors print error=<code> then summary=.
# Exit: 0 no drift, 1 drift, 2 usage or environment error
#   (error=usage|plan-missing|jq-missing|not-git|bad-base|plan-check).
set -u

die() { echo "error=$1"; echo "summary=$2"; exit 2; }

[ "$#" = 2 ] || die usage "usage: bash plan-scope.sh <plan> <base>"
plan=$1; base=$2
[ -f "$plan" ] || die plan-missing "plan not found: $plan"
command -v jq >/dev/null 2>&1 || die jq-missing "jq is required"
git rev-parse --show-toplevel >/dev/null 2>&1 || die not-git "not inside a git work tree"

here=$(cd "$(dirname "$0")" && pwd)
plan=$(cd "$(dirname "$plan")" && pwd)/$(basename "$plan")

# the project root is the plan's ../.., as in plan-check.sh; git paths are taken relative to it
root=$(cd "$(dirname "$plan")/../.." && pwd)
git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || die not-git "not inside a git work tree"
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || die bad-base "not a commit: $base"

json=$(bash "$here/plan-check.sh" --json "$plan"); rc=$?
[ "$rc" = 0 ] || [ "$rc" = 1 ] || die plan-check "plan-check.sh exited $rc"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '%s' "$json" | jq -r '.declared[]' | sort -u > "$tmp/declared"

{
  git -C "$root" -c core.quotePath=false diff --relative --name-only --no-renames "$base" -- .
  git -C "$root" -c core.quotePath=false ls-files --others --exclude-standard -- .
} | grep -v -e '^\.claude/plans/' -e '^\.claude/specs/' -e '^\.claude/worktrees/' \
    -e '^\.claude/\.stop-gate-state$' -e '^\.claude/\.stop-gate-pass$' -e '^\.claude/\.stop-gate-plan$' -e '^\.claude/stop-gate-giveup\.log$' \
    -e '^\.claude/\.devflow-state\.json$' -e '^\.claude/\.approved-writes/' | sort -u > "$tmp/changed"

awk 'NR==FNR{d[$0]=1;next} !($0 in d)' "$tmp/declared" "$tmp/changed" > "$tmp/drift"

declared=$(wc -l < "$tmp/declared" | tr -d ' ')
changed=$(wc -l < "$tmp/changed" | tr -d ' ')
drifted=$(wc -l < "$tmp/drift" | tr -d ' ')

echo "plan=$plan"
echo "base=$base"
while IFS= read -r p; do echo "drift=$p"; done < "$tmp/drift"
echo "declared=$declared"
echo "changed=$changed"
echo "drifted=$drifted"
if [ "$drifted" = 0 ]; then
  echo "result=ok"
  echo "summary=plan-scope: every changed path is declared ($changed changed)"
  exit 0
fi
echo "result=drift"
echo "summary=plan-scope: $drifted changed path(s) outside the plan's Files blocks and Deviations"
exit 1
