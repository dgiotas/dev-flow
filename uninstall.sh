#!/usr/bin/env bash
# dev-flow uninstall. Safe to re-run.
# Usage: bash uninstall.sh [--remove-tools] [--remove-superpowers] [--dry-run] [-h|--help]
#   (default)             uninstall dev-flow@dev-flow-marketplace, remove dev-flow-marketplace
#   --remove-tools        also: claude-powerline plugin + marketplace; npm uninstall -g @colbymchenry/codegraph
#   --remove-superpowers  also: superpowers plugin + superpowers-marketplace
#   --dry-run             print what would run, run nothing, exit 0
#
# One-liner:  curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash
#
# Never touches: claude-mem, a legacy global codegraph MCP entry, statusLine in
# ~/.claude/settings.json, or per-repo files (.claude/, AGENTS.md, CLAUDE.md) --
# see README > Uninstalling for those manual steps.
#
# Whole script in one brace group: bash parses it fully before running anything, so a truncated curl | bash download runs nothing.
{
set -u
export GIT_TERMINAL_PROMPT=0

usage() {
  cat <<'EOF'
Usage: bash uninstall.sh [--remove-tools] [--remove-superpowers] [--dry-run] [-h|--help]
  (default)             uninstall dev-flow@dev-flow-marketplace, remove dev-flow-marketplace
  --remove-tools        also: claude-powerline plugin + marketplace; npm uninstall -g @colbymchenry/codegraph
  --remove-superpowers  also: superpowers plugin + superpowers-marketplace
  --dry-run             print what would run, run nothing, exit 0

One-liner:  curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash
EOF
}

REMOVE_TOOLS=0
REMOVE_SUPERPOWERS=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --remove-tools)       REMOVE_TOOLS=1 ;;
    --remove-superpowers) REMOVE_SUPERPOWERS=1 ;;
    --dry-run)            DRY_RUN=1 ;;
    -h|--help)            usage; exit 0 ;;
    *)                    printf 'unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

command -v claude >/dev/null 2>&1 || { printf 'claude CLI not found\n' >&2; exit 1; }

# State detection: one-shot caches of what's installed, same idiom as
# install.sh:198-201 (no cap/timeout here -- this script is small by design).
MKT_CACHE=$(claude plugin marketplace list 2>/dev/null </dev/null || true)
PLG_CACHE=$(claude plugin list 2>/dev/null </dev/null || true)
has_marketplace() { printf '%s\n' "$MKT_CACHE" | awk '{print $NF}' | grep -qxF "$1"; }
has_plugin()      { printf '%s\n' "$PLG_CACHE" | awk '{print $NF}' | grep -qxF "$1"; }

N_FAIL=0
ok()   { printf '  [ok]   %s\n' "$1"; }
skip() { printf '  [skip] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; N_FAIL=$((N_FAIL + 1)); }
note() { printf '         %s\n' "$1"; }

remove_plugin() {
  local id="$1"
  if ! has_plugin "$id"; then
    skip "$id not installed"
    return
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '  would run: claude plugin uninstall %s\n' "$id"
    return
  fi
  local out status
  out=$(claude plugin uninstall "$id" </dev/null 2>&1); status=$?
  if [ $status -eq 0 ]; then
    ok "$id"
  else
    fail "$id -- exit $status"
    [ -n "$out" ] && printf '%s\n' "$out" | tail -8 | sed 's/^/         | /'
  fi
}

remove_marketplace() {
  local name="$1"
  if ! has_marketplace "$name"; then
    skip "$name not installed"
    return
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '  would run: claude plugin marketplace remove %s\n' "$name"
    return
  fi
  local out status
  out=$(claude plugin marketplace remove "$name" </dev/null 2>&1); status=$?
  if [ $status -eq 0 ]; then
    ok "$name"
  else
    fail "$name -- exit $status"
    [ -n "$out" ] && printf '%s\n' "$out" | tail -8 | sed 's/^/         | /'
  fi
}

run() {
  local label="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then
    printf '  would run: %s\n' "$*"
    return
  fi
  local out status
  out=$("$@" </dev/null 2>&1); status=$?
  if [ $status -eq 0 ]; then
    ok "$label"
  else
    fail "$label -- exit $status"
    [ -n "$out" ] && printf '%s\n' "$out" | tail -8 | sed 's/^/         | /'
  fi
}

remove_plugin dev-flow@dev-flow-marketplace
remove_marketplace dev-flow-marketplace

if [ "$REMOVE_SUPERPOWERS" = 1 ]; then
  remove_plugin superpowers@superpowers-marketplace
  remove_marketplace superpowers-marketplace
fi

if [ "$REMOVE_TOOLS" = 1 ]; then
  remove_plugin claude-powerline@claude-powerline
  remove_marketplace claude-powerline
  if command -v codegraph >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    run "codegraph binary" npm uninstall -g @colbymchenry/codegraph
  else
    skip "codegraph binary not found"
  fi
fi

note "Not done by this script (see README > Uninstalling):"
note "  claude-mem: npx claude-mem uninstall"
note "  legacy global CodeGraph MCP (pre-1.11.0): claude mcp remove codegraph"
note "  statusLine in ~/.claude/settings.json (if you used claude-powerline)"
note "  per-repo files: .claude/test-cmd, lint-cmd, rules, .codegraph/"

note "Restart Claude Code."

if [ "$DRY_RUN" = 1 ]; then
  note "Dry run: nothing removed."
  exit 0
fi

[ "$N_FAIL" -gt 0 ] && exit 1
exit 0
}
