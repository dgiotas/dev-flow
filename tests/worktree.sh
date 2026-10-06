#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/worktree.sh.
# They run from .claude/test-cmd, and every repository is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/worktree.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

mkrepo() {
  git init -q -b main "$1"
  echo hi > "$1/README"
  g -C "$1" add README && g -C "$1" commit -q -m init
  mkdir -p "$1/.claude/plans" "$1/.claude/specs"
  echo x > "$1/.claude/plans/s.md"
  echo x > "$1/.claude/specs/s.md"
  echo x > "$1/.claude/plans/s2.md"
}

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then pass "$1"; else bad "$1"; fi; }   # check <label> <shell test>

# expect <label> <want exit> <want exact line> [args...]; leaves rc and out for also()
expect() {
  label=$1; want_rc=$2; want_line=$3; shift 3
  out=$(bash "$script" "$@" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  if [ "$rc" = "$want_rc" ] && printf '%s\n' "$out" | grep -qxF -- "$want_line" && [ "${last#summary=}" != "$last" ]; then
    pass "$label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

# also <label> <want exact line>: re-checks the output of the last expect
also() {
  if printf '%s\n' "$out" | grep -qxF -- "$2"; then pass "$1"; else bad "$1"; fi
}

A=$tmp/a; mkrepo "$A"
B=$tmp/b; mkrepo "$B"
printf '.claude/plans/\n.claude/specs/\n.claude/worktrees/\n' > "$B/.gitignore"
g -C "$B" add .gitignore && g -C "$B" commit -q -m ignore
C=$tmp/c; mkrepo "$C"
g -C "$C" switch -q -c topic
echo t > "$C/T"
g -C "$C" add T && g -C "$C" commit -q -m topic
echo d > "$A/dirt"
E=$tmp/e; mkrepo "$E"
F=$tmp/f; mkrepo "$F"
fakebin=$tmp/fakebin; mkdir "$fakebin"
printf '#!/bin/sh\necho "cp: forced failure" >&2\nexit 1\n' > "$fakebin/cp"; chmod +x "$fakebin/cp"
O=$tmp/o; mkrepo "$O"
g -C "$O" remote add origin "$tmp/nowhere"
g -C "$O" update-ref refs/remotes/origin/main HEAD
G=$tmp/g; mkrepo "$G"
g -C "$G" branch feature
mkdir "$tmp/plain"
git init -q "$tmp/empty"

expect no-args 1 'error=usage'
expect too-few-args 1 'error=usage' s feature/s
expect too-many-args 1 'error=usage' s feature/s HEAD "$A" extra
expect bad-slug 1 'error=usage' ../x feature/x HEAD "$A"
expect bad-branch 1 'error=usage' s 'a..b' HEAD "$A"
expect dash-branch 1 'error=usage' s -x HEAD "$A"
expect dash-start 1 'error=usage' s feature/s -x "$A"
expect not-git 1 'error=not-git' s feature/s HEAD "$tmp/plain"
expect no-commits 1 'error=no-commits' s feature/s HEAD "$tmp/empty"
expect bad-start 1 'error=bad-start' q feature/q nosuch "$A"

atop=$(git -C "$A" rev-parse --show-toplevel)
expect create-dirty-unignored 0 'ignored=no' s feature/s HEAD "$A"
also dirty-yes 'dirty=yes'
also branch-line 'branch=feature/s'
also start-line 'start=HEAD'
check files-copied '[ -e "$A/.claude/worktrees/s/.claude/plans/s.md" ] && [ -e "$A/.claude/worktrees/s/.claude/specs/s.md" ]'
check base-is-head '[ "$(git -C "$A/.claude/worktrees/s" rev-parse HEAD)" = "$(git -C "$A" rev-parse HEAD)" ] && printf "%s\n" "$out" | grep -qxF "base=$(git -C "$A" rev-parse --short HEAD)"'
check on-branch '[ "$(git -C "$A/.claude/worktrees/s" branch --show-current)" = feature/s ]'
check path-absolute 'printf "%s\n" "$out" | grep -qxF "path=$atop/.claude/worktrees/s"'

expect path-exists 1 'error=path-exists' s feature/other HEAD "$A"
expect branch-exists 1 'error=branch-exists' s2 feature/s HEAD "$A"
expect already-in-worktree 1 'error=already-in-worktree' s feature/z HEAD "$A/.claude/worktrees/s"

expect plan-optional 0 'branch=feature/nope' nope feature/nope HEAD "$A"
check nothing-copied '[ ! -e "$A/.claude/worktrees/nope/.claude/plans" ] && [ ! -e "$A/.claude/worktrees/nope/.claude/specs" ]'

expect prefixed-branch 0 'branch=team-web/feature/p' p team-web/feature/p HEAD "$A"
also prefixed-path "path=$atop/.claude/worktrees/p"
check dir-is-slug '[ -d "$A/.claude/worktrees/p" ] && [ ! -e "$A/.claude/worktrees/team-web" ] && [ "$(git -C "$A/.claude/worktrees/p" branch --show-current)" = team-web/feature/p ]'

expect create-clean-ignored 0 'ignored=yes' s fix/s HEAD "$B"
also dirty-no 'dirty=no'

expect start-main 0 'start=main' s feature/s main "$C"
check base-is-main '[ "$(git -C "$C/.claude/worktrees/s" rev-parse HEAD)" = "$(git -C "$C" rev-parse main)" ] && [ "$(git -C "$C/.claude/worktrees/s" rev-parse HEAD)" != "$(git -C "$C" rev-parse topic)" ]'
check main-checkout-unchanged '[ "$(git -C "$C" branch --show-current)" = topic ]'

(cd "$B" && bash "$script" s2 feature/s2 HEAD >/dev/null 2>&1); rc=$?
check spec-optional '[ "$rc" = 0 ] && [ -e "$B/.claude/worktrees/s2/.claude/plans/s2.md" ] && [ ! -e "$B/.claude/worktrees/s2/.claude/specs/s2.md" ]'

expect plans-not-dirty 0 'dirty=no' s feature/s HEAD "$E"

PATH="$fakebin:$PATH" expect copy-failed 1 'error=copy-failed' s feature/s HEAD "$F"
check copy-failed-recovery 'printf "%s\n" "$out" | tail -n 1 | grep -F "git worktree remove --force" | grep -qF "git branch -D"'

H=$tmp/h; mkrepo "$H"
expect first-worktree 0 'dirty=no' s feature/s HEAD "$H"
expect worktrees-dir-not-dirty 0 'dirty=no' s2 feature/s2 HEAD "$H"
echo d > "$H/dirt"
expect real-dirt-still-dirty 0 'dirty=yes' nope feature/nope HEAD "$H"

expect from-origin-ref 0 'start=origin/main' s feature/s origin/main "$O"
check no-upstream '! git -C "$O/.claude/worktrees/s" rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1'

expect git-failed 1 'error=git-failed' s feature/x HEAD "$G"

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
