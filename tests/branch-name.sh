#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/branch-name.sh.
# They run from .claude/test-cmd, and every repository is generated into a
# temporary directory.
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/branch-name.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

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

R=$tmp/r; git init -q -b main "$R"; mkdir -p "$R/.claude" "$R/sub"
P=$R/.claude/branch-prefix
mkdir "$tmp/plain"

expect no-args 1 'error=usage'
expect too-many-args 1 'error=usage' feature x "$R" extra
expect old-feat-type 1 'error=usage' feat x "$R"
expect bad-type 1 'error=usage' bugfix x "$R"
expect slash-name 1 'error=usage' feature a/b "$R"
expect dots-name 1 'error=usage' feature a..b "$R"
expect lock-name 1 'error=usage' feature x.lock "$R"
expect not-git 1 'error=not-git' feature x "$tmp/plain"

expect no-prefix 0 'prefix=' feature add-login "$R"
also no-prefix-type 'type=feature'
also no-prefix-name 'name=add-login'
also no-prefix-branch 'branch=feature/add-login'
expect fix 0 'branch=fix/x' fix x "$R"
expect chore 0 'branch=chore/x' chore x "$R"
expect refactor 0 'branch=refactor/x' refactor x "$R"

: > "$P"
expect empty-file 0 'prefix=' feature x "$R"
also empty-file-branch 'branch=feature/x'
printf '  \n\n' > "$P"
expect blank-file 0 'branch=feature/x' feature x "$R"
printf 'team\n' > "$P"
expect plain-prefix 0 'prefix=team' feature x "$R"
also plain-prefix-branch 'branch=team/feature/x'
printf 'team/\n' > "$P"
expect trailing-slash 0 'prefix=team' fix x "$R"
also trailing-slash-branch 'branch=team/fix/x'
printf '\n /team//web/ \r\nignored\n' > "$P"
expect messy 0 'prefix=team/web' chore x "$R"
also messy-branch 'branch=team/web/chore/x'
printf 'team' > "$P"
expect no-newline 0 'branch=team/feature/x' feature x "$R"
printf '/\n' > "$P"
expect slash-only 0 'prefix=' feature x "$R"
also slash-only-branch 'branch=feature/x'
printf 'team\n' > "$P"
expect from-subdir 0 'branch=team/feature/x' feature x "$R/sub"
printf 'te am\n' > "$P"
expect space-prefix 1 'error=bad-prefix' feature x "$R"
printf 'a..b\n' > "$P"
expect dots-prefix 1 'error=bad-prefix' feature x "$R"
printf -- '-x\n' > "$P"
expect dash-prefix 1 'error=bad-prefix' feature x "$R"

printf 'team\n' > "$P"
out=$(cd "$R" && bash "$script" feature x 2>&1); rc=$?
last=$(printf '%s\n' "$out" | tail -n 1)
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qxF -- 'branch=team/feature/x' && [ "${last#summary=}" != "$last" ]; then
  pass default-dir
else
  echo "FAIL: default-dir (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
fi

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
