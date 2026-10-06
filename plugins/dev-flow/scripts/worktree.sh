#!/usr/bin/env bash
# Creates .claude/worktrees/<slug> on a new branch from <start>, for the worktree mode of
# /dev-flow:build and the git-workflow skill. <branch> is the branch= value of branch-name.sh
# and may contain slashes; the directory is always .claude/worktrees/<slug>. <start> is HEAD
# (current branch) or the ref= value of default-branch.sh (default branch). Copies
# .claude/plans/<slug>.md and .claude/specs/<slug>.md into it when they exist, since both are
# usually gitignored.
#
# Usage:  bash worktree.sh <slug> <branch> <start> [repo-dir]
# Prints key=value lines: path, branch, start, base, ignored, dirty; the last line is always summary=.
# On failure prints error=<reason> (usage, not-git,
# already-in-worktree, no-commits, bad-start, path-exists, branch-exists, git-failed, copy-failed)
# then summary=, exit 1. dirty ignores .claude/plans, .claude/specs and .claude/worktrees. Never pushes, merges, fetches or deletes.
set -u

die() { echo "error=$1"; echo "summary=$2"; exit 1; }

[ $# -ge 3 ] && [ $# -le 4 ] || die usage "usage: worktree.sh <slug> <branch> <start> [repo-dir]"
slug=$1; branch=$2; start=$3
[[ $slug =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die usage "invalid slug: $slug"
case "$branch" in -*) die usage "invalid branch name: $branch" ;; esac
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die usage "invalid branch name: $branch"
if [ -z "$start" ]; then die usage "invalid start point: $start"; fi
case "$start" in -*) die usage "invalid start point: $start" ;; esac

cd "${4:-.}" 2>/dev/null || die not-git "not inside a git repository"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die not-git "not inside a git repository"
cd "$root"

[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] \
  || die already-in-worktree "already inside a linked worktree; work here on a branch instead"
git rev-parse --verify -q HEAD >/dev/null || die no-commits "repository has no commits to branch from"
git rev-parse --verify -q "$start^{commit}" >/dev/null || die bad-start "start point $start is not a commit"

plan=.claude/plans/$slug.md; spec=.claude/specs/$slug.md; dest=.claude/worktrees/$slug
[ ! -e "$dest" ] || die path-exists "$dest already exists; remove it with git worktree remove or pick branch mode"
git show-ref --verify --quiet "refs/heads/$branch" && die branch-exists "branch $branch already exists"

dirty=no; [ -n "$(git status --porcelain -- . ':!.claude/plans' ':!.claude/specs' ':!.claude/worktrees')" ] && dirty=yes
base=$(git rev-parse --short "$start^{commit}")

git worktree add -q --no-track -b "$branch" "$dest" "$start" || die git-failed "git worktree add failed"

for f in "$plan" "$spec"; do
  [ -f "$f" ] || continue
  { mkdir -p "$dest/${f%/*}" && cp "$f" "$dest/${f%/*}/"; } \
    || die copy-failed "created worktree $root/$dest but could not copy $f; remove it with git worktree remove --force $root/$dest and git branch -D $branch, then retry"
done

ignored=no; git check-ignore -q "$dest" && ignored=yes

echo "path=$root/$dest"
echo "branch=$branch"
echo "start=$start"
echo "base=$base"
echo "ignored=$ignored"
echo "dirty=$dirty"
echo "summary=created worktree $root/$dest on $branch from $start ($base)"
