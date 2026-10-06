#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/default-branch.sh.
# They run from .claude/test-cmd, and every repository is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/default-branch.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
g() { git -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

mkrepo() {
  git init -q -b "$2" "$1"
  echo hi > "$1/README"
  g -C "$1" add README && g -C "$1" commit -q -m init
}

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

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

M=$tmp/m; mkrepo "$M" main
X=$tmp/x; mkrepo "$X" master
D=$tmp/d; mkrepo "$D" develop
N=$tmp/n; mkrepo "$N" trunk
T=$tmp/t; mkrepo "$T" trunk
K=$tmp/k; git clone -q "$T" "$K"
Q=$tmp/q; mkrepo "$Q" trunk
g -C "$Q" branch origin/main
g -C "$Q" update-ref refs/remotes/origin/main HEAD
g -C "$Q" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
L=$tmp/l; mkrepo "$L" trunk
g -C "$L" branch -q -m trunk work
g -C "$L" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
mkdir "$tmp/plain"

expect usage 1 'error=usage' "$M" extra
expect not-git 1 'error=not-git' "$tmp/plain"

expect main 0 'default=main' "$M"
also main-ref 'ref=main'
also main-current 'current=main'
also main-on-default 'on_default=yes'

g -C "$M" tag main
expect tag-named-like-branch 0 'current=main' "$M"
also tag-named-like-branch-on-default 'on_default=yes'

expect master 0 'default=master' "$X"

g -C "$X" branch -q main
expect main-before-master 0 'default=main' "$X"
also main-before-master-off 'on_default=no'

expect develop 0 'default=develop' "$D"
expect none 1 'error=no-default-branch' "$N"

expect origin-head 0 'default=trunk' "$K"
also origin-head-ref 'ref=trunk'
also origin-head-on-default 'on_default=yes'

g -C "$K" branch -q main
expect origin-head-wins 0 'default=trunk' "$K"

git -C "$K" switch -q -c topic
expect on-topic 0 'current=topic' "$K"
also on-topic-off 'on_default=no'

git -C "$K" branch -q -D trunk
expect remote-only 0 'default=trunk' "$K"
also remote-only-ref 'ref=origin/trunk'

git -C "$K" switch -q --detach
expect detached 0 'current=' "$K"
also detached-off 'on_default=no'

expect ambiguous-origin-branch 0 'default=main' "$Q"
also ambiguous-origin-ref 'ref=origin/main'

expect dangling-origin-head 1 'error=no-default-branch' "$L"

out=$(cd "$M" && bash "$script" 2>&1); rc=$?
last=$(printf '%s\n' "$out" | tail -n 1)
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qxF 'default=main' && [ "${last#summary=}" != "$last" ]; then
  pass default-dir
else
  bad default-dir
fi

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
