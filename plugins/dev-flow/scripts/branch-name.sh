#!/usr/bin/env bash
# Prints the name for a new branch, [<prefix>/]<type>/<name>, for /dev-flow:build and the
# git-workflow skill. <type> is feature, fix, chore or refactor. <prefix> is the first non-blank
# line of the committed .claude/branch-prefix, trimmed, with runs of / collapsed and one leading
# and trailing / removed; no file or an empty line means no prefix. Changes no git state.
#
# Usage:  bash branch-name.sh <type> <name> [repo-dir]
# Prints key=value lines: prefix (empty when none), type, name, branch; the last line is always summary=.
# On failure prints error=<reason> then summary=, exit 1.
set -u

die() { echo "error=$1"; echo "summary=$2"; exit 1; }

[ $# -ge 2 ] && [ $# -le 3 ] || die usage "usage: branch-name.sh <type> <name> [repo-dir]"
type=$1; name=$2
case "$type" in feature|fix|chore|refactor) ;; *) die usage "type must be feature, fix, chore or refactor, got $type" ;; esac
if ! [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || ! git check-ref-format --branch "$type/$name" >/dev/null 2>&1; then
  die usage "invalid name: $name"
fi

if ! cd "${3:-.}" 2>/dev/null || ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  die not-git "not inside a git repository"
fi
cd "$root"

prefix=""
if [ -f .claude/branch-prefix ]; then
  prefix=$(tr -d '\r' < .claude/branch-prefix | awk 'NF { print; exit }' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#/+#/#g; s#^/##; s#/$##')
fi

branch="$type/$name"
if [ -n "$prefix" ]; then
  branch="$prefix/$branch"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || die bad-prefix "invalid prefix in .claude/branch-prefix: $prefix"
fi

note="no project prefix"
[ -n "$prefix" ] && note="prefix $prefix from .claude/branch-prefix"

echo "prefix=$prefix"
echo "type=$type"
echo "name=$name"
echo "branch=$branch"
echo "summary=branch name is $branch ($note)"
