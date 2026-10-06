#!/usr/bin/env bash
# Reports the repository's default branch for the base question in /dev-flow:build and the
# git-workflow skill. Local refs only, never fetches: origin/HEAD first, then the first local
# branch of main, master, develop. ref= is the local branch if it exists, else origin/<name>.
#
# Usage:  bash default-branch.sh [repo-dir]
# Prints key=value lines: default, ref, current (empty when detached), on_default; last line summary=.
# On failure prints error=<reason> then summary=, exit 1.
set -u

die() { echo "error=$1"; echo "summary=$2"; exit 1; }

[ $# -le 1 ] || die usage "usage: default-branch.sh [repo-dir]"
if ! cd "${1:-.}" 2>/dev/null || ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  die not-git "not inside a git repository"
fi

name=""
remote=$(git symbolic-ref -q refs/remotes/origin/HEAD)
[ -n "$remote" ] && name=${remote#refs/remotes/origin/}

if [ -z "$name" ]; then
  for n in main master develop; do
    if git show-ref --verify --quiet "refs/heads/$n"; then
      name=$n
      break
    fi
  done
fi
[ -n "$name" ] || die no-default-branch "no origin/HEAD and no local main, master or develop branch"

if git show-ref --verify --quiet "refs/heads/$name"; then
  ref=$name
elif git show-ref --verify --quiet "refs/remotes/origin/$name"; then
  ref=origin/$name
else
  die no-default-branch "default branch $name has no local or origin ref"
fi

current=$(git symbolic-ref -q HEAD)
current=${current#refs/heads/}
on_default=no
[ "$current" = "$name" ] && on_default=yes
shown=${current:-detached HEAD}

echo "default=$name"
echo "ref=$ref"
echo "current=$current"
echo "on_default=$on_default"
echo "summary=default branch is $name ($ref); current branch is $shown"
