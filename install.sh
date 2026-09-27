#!/usr/bin/env bash
# dev-flow bootstrap. Safe to re-run.
# Usage: bash install.sh [marketplace-source] [--with-memory] [--skip-superpowers] [--skip-codegraph]
#   marketplace-source: local path or GitHub "org/repo" (default: this folder)
#   --with-memory:      also install claude-mem for cross-session recall (opt-in)
#
# Design notes (learned the hard way):
#  * Never hide output blindly. Output is captured and printed on failure.
#  * Every external command gets </dev/null so nothing can block on an unseen
#    prompt -- a command that needs input fails fast with a visible error.
#  * `claude plugin install` needs -y when stdout is not a TTY, which is exactly
#    the case inside a script. Without it, the install waits for confirmation.
#  * GIT_TERMINAL_PROMPT=0 so a private-repo clone errors instead of hanging on
#    a credential prompt.
set -u
export GIT_TERMINAL_PROMPT=0

WITH_MEMORY=0
SKIP_SUPERPOWERS=0
SKIP_CODEGRAPH=0
SRC=""
for arg in "$@"; do
  case "$arg" in
    --with-memory)      WITH_MEMORY=1 ;;
    --skip-superpowers) SKIP_SUPERPOWERS=1 ;;
    --skip-codegraph)   SKIP_CODEGRAPH=1 ;;
    -h|--help)          sed -n '2,8p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)                  SRC="$arg" ;;
  esac
done
SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

ok()   { printf '  [ok]   %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; }
bad()  { printf '  [MISSING] %s\n' "$1"; MISSING=1; }
MISSING=0

# run_step <timeout-seconds> <label> <command...>
# Prints the label first (so a slow step never looks frozen), runs the command
# with no stdin and a hard timeout, and shows the output only if it fails.
run_step() {
  local t="$1" label="$2"; shift 2
  printf '  ...   %s\n' "$label"
  local out status
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout "$t" "$@" </dev/null 2>&1); status=$?
  else
    out=$("$@" </dev/null 2>&1); status=$?
  fi
  # Redraw the progress line only on a real terminal; piped/logged output would
  # otherwise be littered with literal escape sequences.
  [ -t 1 ] && printf '\033[1A\033[2K'
  if [ $status -eq 0 ]; then
    ok "$label"; return 0
  fi
  if [ $status -eq 124 ]; then
    warn "$label -- TIMED OUT after ${t}s (skipped; run it manually to see what it wants)"
  else
    warn "$label -- exit $status"
  fi
  [ -n "$out" ] && printf '%s\n' "$out" | tail -8 | sed 's/^/         | /'
  return 1
}

echo "1) Prerequisites"
command -v claude >/dev/null && ok "claude CLI" || bad "claude CLI (https://docs.claude.com/en/docs/claude-code)"
command -v jq     >/dev/null && ok "jq"         || bad "jq (needed by the hooks): brew install jq / apt install jq"
command -v git    >/dev/null && ok "git"        || bad "git"
command -v node   >/dev/null && ok "node $(node --version 2>/dev/null)" || warn "node 18+ not found: the Context7 and Chrome DevTools MCP servers will not start (everything else works)"
command -v uvx    >/dev/null && ok "uv/uvx"     || warn "uv not found: Semble code search will not start (https://docs.astral.sh/uv/)"
command -v php    >/dev/null && ok "php"        || warn "php not found: per-edit PHP syntax check is skipped, not failed. Containerised toolchain? see .claude/lint-cmd in the README"
command -v docker >/dev/null && ok "docker (containerised toolchains supported via .claude/lint-cmd)" || true
command -v timeout >/dev/null || warn "no 'timeout' command (macOS: brew install coreutils); steps cannot be time-limited"
if [ "$MISSING" = "1" ]; then echo; echo "Fix the MISSING items above and re-run."; exit 1; fi

echo; echo "2) Plugins"
if [ "$SKIP_SUPERPOWERS" = "0" ]; then
  run_step 120 "add marketplace obra/superpowers-marketplace" \
    claude plugin marketplace add obra/superpowers-marketplace
  run_step 180 "install superpowers" \
    claude plugin install -y superpowers@superpowers-marketplace
else
  echo "  ...   superpowers skipped (--skip-superpowers)"
fi
run_step 120 "add marketplace dev-flow ($SRC)" claude plugin marketplace add "$SRC"
run_step 180 "install dev-flow"                claude plugin install -y dev-flow@dev-flow-marketplace

echo; echo "3) CodeGraph (optional, structure/caller analysis)"
if [ "$SKIP_CODEGRAPH" = "1" ]; then
  echo "  ...   skipped (--skip-codegraph)"
elif command -v npm >/dev/null; then
  if command -v codegraph >/dev/null; then
    ok "codegraph already present"
  else
    run_step 300 "npm install -g @colbymchenry/codegraph (can take a minute)" \
      npm install -g @colbymchenry/codegraph
  fi
  if command -v codegraph >/dev/null; then
    run_step 120 "wire codegraph into Claude Code" codegraph install
    echo "         per repo, once:  cd <repo> && codegraph init   (add .codegraph/ to .gitignore)"
  fi
else
  warn "npm not found; skipping CodeGraph"
fi

echo; echo "4) Persistent memory (optional, off by default)"
if [ "$WITH_MEMORY" = "1" ]; then
  if command -v npx >/dev/null; then
    run_step 300 "install claude-mem" npx --yes claude-mem install
    warn "IMPORTANT: recent claude-mem versions default some integrations to a hosted"
    warn "provider. Open its config and select the local/offline provider before use,"
    warn "especially on repos with secrets or PCI-adjacent code (it captures tool output)."
  else
    warn "npx not found; skipping claude-mem"
  fi
else
  echo "  ...   skipped. Re-run with --with-memory to install claude-mem (cross-session recall)."
fi

echo; echo "5) Verify"
run_step 60 "claude plugin list" claude plugin list || true
echo
echo "Done. Restart Claude Code, then check /plugin, /mcp, /agents and /hooks."
echo "Per repo:"
echo "  - run 'setup-rules' (ask Claude: \"Set up AGENTS.md and rules for this repo\")"
echo "  - create .claude/test-cmd            (the stop gate does nothing without it)"
echo "  - create .claude/lint-cmd            (only if linters run in a container)"
echo "  - optional .claude/test-cmd-retries  (stop-gate retries before giving up; default 3)"
