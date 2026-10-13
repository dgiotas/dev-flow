#!/usr/bin/env bash
# Deterministic tests for install.sh. They run from .claude/test-cmd, always with
# --dry-run (or --help), against a fake `claude` on PATH and a temporary HOME.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

mkdir -p "$tmp/bin" "$tmp/home"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/claude"
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home"

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

run() { out=$(bash "$here/install.sh" "$@" </dev/null 2>&1); rc=$?; }

run --with-memory --dry-run
if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -qF 'unknown option: --with-memory'; then
  pass removed-memory
else bad "removed-memory (rc=$rc)"; fi

run --with-powerline --dry-run
if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -qF 'unknown option: --with-powerline'; then
  pass removed-powerline
else bad "removed-powerline (rc=$rc)"; fi

run -y --dry-run
if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qF 'dev-flow         marketplace dev-flow-marketplace'; then
  pass dry-run
else bad "dry-run (rc=$rc)"; fi

if printf '%s\n' "$out" | grep -qiE 'claude-mem|powerline|statusline|superpowers'; then
  bad dry-run-clean
else pass dry-run-clean; fi

run --skip-superpowers --dry-run
if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -qF 'unknown option: --skip-superpowers'; then
  pass removed-superpowers
else bad "removed-superpowers (rc=$rc)"; fi

run --help
if [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -qiE 'with-memory|with-powerline|superpowers'; then
  pass help-clean
else bad "help-clean (rc=$rc)"; fi

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
