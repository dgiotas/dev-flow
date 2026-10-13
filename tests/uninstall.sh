#!/usr/bin/env bash
# Deterministic tests for uninstall.sh. They run from .claude/test-cmd, always with
# --dry-run (or --help), against a fake `claude` on PATH and a temporary HOME.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "plugin list")
    printf '  dev-flow@dev-flow-marketplace\n  claude-powerline@claude-powerline\n  superpowers@superpowers-marketplace\n' ;;
  "plugin marketplace list")
    printf '  dev-flow-marketplace\n  claude-powerline\n  superpowers-marketplace\n' ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/npm"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/codegraph"
chmod +x "$tmp/bin/claude" "$tmp/bin/npm" "$tmp/bin/codegraph"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home"

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

run() { out=$(bash "$here/uninstall.sh" "$@" </dev/null 2>&1); rc=$?; }

run --remove-tools --dry-run
if [ "$rc" = 0 ] \
  && printf '%s\n' "$out" | grep -qxF '  would run: claude plugin uninstall dev-flow@dev-flow-marketplace' \
  && printf '%s\n' "$out" | grep -qxF '  would run: claude plugin marketplace remove dev-flow-marketplace'; then
  pass dry-run-tools
else bad "dry-run-tools (rc=$rc)"; fi

if printf '%s\n' "$out" | grep -qiE 'powerline|claude-mem|statusline'; then
  bad dry-run-clean
else pass dry-run-clean; fi

if printf '%s\n' "$out" | grep -qxF '  would run: npm uninstall -g @colbymchenry/codegraph'; then
  pass dry-run-codegraph
else bad dry-run-codegraph; fi

run --dry-run
if printf '%s\n' "$out" | grep -qF 'npm uninstall'; then
  bad no-tools-no-codegraph
else pass no-tools-no-codegraph; fi

run --help
if [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -qi powerline; then
  pass help-clean
else bad "help-clean (rc=$rc)"; fi

run --remove-superpowers --dry-run
if [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -qF 'unknown option: --remove-superpowers'; then
  pass removed-superpowers
else bad "removed-superpowers (rc=$rc)"; fi

run --help
if printf '%s\n' "$out" | grep -qi superpowers; then
  bad help-no-superpowers
else pass help-no-superpowers; fi

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
