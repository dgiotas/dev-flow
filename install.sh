#!/usr/bin/env bash
# dev-flow bootstrap. Safe to re-run.
# Usage: bash install.sh [marketplace-source] [--with-memory] [--with-powerline]
#                        [--skip-superpowers] [--skip-codegraph]
#                        [-y|--yes|--non-interactive] [--no-color] [--dry-run]
#   marketplace-source: local path or GitHub "org/repo" (default: this folder when run
#                        from a clone, else dgiotas/dev-flow)
#   --with-memory:      also install claude-mem for cross-session recall (opt-in)
#   --with-powerline:   also install claude-powerline (cosmetic status line, opt-in)
#   DEV_FLOW_VERSION=x.y.z  env var: install that tagged release (tag dev-flow--vx.y.z; available from 1.12.0)
#   -y, --yes, --non-interactive: force non-interactive mode even on a TTY
#   --no-color:          disable coloured output
#   --dry-run:           show the plan, then exit 0 without installing anything
#
# One-liner:  curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash
#   flags:    ... | bash -s -- --with-memory
#   checklist: bash <(curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh)
#
# Design notes (learned the hard way):
#  * Never hide output blindly. Output is captured and printed on failure.
#  * Every external command gets </dev/null so nothing can block on an unseen
#    prompt -- a command that needs input fails fast with a visible error.
#  * `claude plugin install` needs -y when stdout is not a TTY, which is exactly
#    the case inside a script. Without it, the install waits for confirmation.
#  * GIT_TERMINAL_PROMPT=0 so a private-repo clone errors instead of hanging on
#    a credential prompt.
# Whole script in one brace group: bash parses it fully before running anything, so a truncated curl | bash download runs nothing.
{
set -u
export GIT_TERMINAL_PROMPT=0

usage() {
  cat <<'EOF'
Usage: bash install.sh [marketplace-source] [--with-memory] [--with-powerline]
                        [--skip-superpowers] [--skip-codegraph]
                        [-y|--yes|--non-interactive] [--no-color] [--dry-run]
  marketplace-source: local path or GitHub "org/repo" (default: this folder when run
                       from a clone, else dgiotas/dev-flow)
  --with-memory:      also install claude-mem for cross-session recall (opt-in)
  --with-powerline:   also install claude-powerline (cosmetic status line, opt-in)
  DEV_FLOW_VERSION=x.y.z  env var: install that tagged release (tag dev-flow--vx.y.z; available from 1.12.0)

One-liner:  curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash
  flags:    ... | bash -s -- --with-memory
  checklist: bash <(curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh)
EOF
}

WITH_MEMORY=0
WITH_POWERLINE=0
SKIP_SUPERPOWERS=0
SKIP_CODEGRAPH=0
NON_INTERACTIVE=0
NO_COLOR_FLAG=0
FLAGS_SET=0
DRY_RUN=0
SRC=""
for arg in "$@"; do
  case "$arg" in
    --with-memory)      WITH_MEMORY=1; FLAGS_SET=1 ;;
    --with-powerline)   WITH_POWERLINE=1; FLAGS_SET=1 ;;
    --skip-superpowers) SKIP_SUPERPOWERS=1; FLAGS_SET=1 ;;
    --skip-codegraph)   SKIP_CODEGRAPH=1; FLAGS_SET=1 ;;
    -y|--yes|--non-interactive) NON_INTERACTIVE=1 ;;
    --no-color)         NO_COLOR_FLAG=1 ;;
    --dry-run)          DRY_RUN=1 ;;
    -h|--help)          usage; exit 0 ;;
    --*)                printf 'unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    *)                  SRC="$arg" ;;
  esac
done
REPO="dgiotas/dev-flow"
here=""
script="${BASH_SOURCE[0]:-}"
if [ -n "$script" ] && [ -f "$(dirname "$script")/.claude-plugin/marketplace.json" ]; then
  here="$(cd "$(dirname "$script")" && pwd)"
fi
if [ -n "${DEV_FLOW_VERSION:-}" ]; then
  ver="${DEV_FLOW_VERSION#v}"
  if ! [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'invalid DEV_FLOW_VERSION: %s (expected x.y.z)\n' "$DEV_FLOW_VERSION" >&2
    usage >&2
    exit 2
  fi
  src="${SRC:-$REPO}"
  if [ -d "$src" ]; then
    printf 'DEV_FLOW_VERSION pins a GitHub tag; it can'"'"'t be combined with the local path %s. Check out tag dev-flow--v%s in your clone instead.\n' "$src" "$ver" >&2
    exit 2
  fi
  SRC="$src#dev-flow--v$ver"
else
  SRC="${SRC:-${here:-$REPO}}"
fi

INTERACTIVE=0
if [ "$NON_INTERACTIVE" = 0 ] && [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ]; then INTERACTIVE=1; fi

USE_COLOR=0
if [ "$INTERACTIVE" = 1 ] && [ "$NO_COLOR_FLAG" = 0 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1; fi

if [ "$USE_COLOR" = 1 ]; then
  C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_BAD=$'\033[0;31m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m';    C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_BAD=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi

case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*) BAR_FULL='█'; BAR_EMPTY='░' ;;
  *)       BAR_FULL='#'; BAR_EMPTY='-' ;;
esac

BAR_VISIBLE=0
BAR_LABEL=""
STEP_DONE=0
STEP_TOTAL=0

# bar_show -- prints the fixed-width progress bar with no trailing newline, so
# it always occupies (and can be overwritten on) the terminal's last line.
# No-op outside interactive mode or before count_steps has run.
bar_show() {
  [ "$INTERACTIVE" = 1 ] || return 0
  [ "$STEP_TOTAL" -gt 0 ] || return 0
  local cells=24
  local filled=$((STEP_DONE * cells / STEP_TOTAL))
  [ "$filled" -gt "$cells" ] && filled=$cells
  local empty=$((cells - filled))
  local bar
  bar=$(printf "%${filled}s" '' | tr ' ' "$BAR_FULL")
  bar="$bar$(printf "%${empty}s" '' | tr ' ' "$BAR_EMPTY")"
  # Truncate only the label, via bash's multibyte-aware substring (not
  # printf's '%.Ns', which counts bytes and would mangle a UTF-8 bar/label).
  local prefix="  [$bar]  $STEP_DONE/$STEP_TOTAL  "
  local budget=$((78 - ${#prefix}))
  local label="$BAR_LABEL"
  [ "$budget" -lt 0 ] && budget=0
  printf '%s%s' "$prefix" "${label:0:$budget}"
  BAR_VISIBLE=1
}

# bar_clear -- erases the progress bar line, leaving the cursor at column 0.
bar_clear() {
  if [ "$BAR_VISIBLE" = 1 ]; then
    printf '\r\033[2K'
    BAR_VISIBLE=0
  fi
}

# step_done -- advances the progress bar's counter, clamped at STEP_TOTAL
# (CodeGraph's count is an estimate; clamping prevents e.g. "13/12").
step_done() {
  STEP_DONE=$((STEP_DONE + 1))
  [ "$STEP_DONE" -gt "$STEP_TOTAL" ] && STEP_DONE=$STEP_TOTAL
}

emit() { bar_clear; printf '%s\n' "$1"; bar_show; }

ok()   { emit "  ${C_OK}[ok]${C_OFF}   $1"; N_OK=$((N_OK + 1)); }
have() { emit "  ${C_WARN}[have]${C_OFF} $1"; N_WARN=$((N_WARN + 1)); }
warn() { emit "  ${C_WARN}[warn]${C_OFF} $1"; N_WARN=$((N_WARN + 1)); }
fail() { emit "  ${C_BAD}[FAIL]${C_OFF} $1"; N_FAIL=$((N_FAIL + 1)); }
bad()  { emit "  ${C_BAD}[MISSING]${C_OFF} $1"; MISSING=1; }
skip() { emit "  ${C_DIM}[skip]${C_OFF} $1"; }
note() { emit "         ${C_DIM}$1${C_OFF}"; }
section() { emit ""; emit "${C_BOLD}$1) $2${C_OFF}"; }
MISSING=0
N_OK=0
N_WARN=0
N_FAIL=0

# cap <secs> <cmd...> -- runs a command with a hard timeout when the `timeout`
# binary exists, falls back to running it uncapped otherwise (some dev
# machines don't have coreutils' timeout on PATH).
cap() {
  local t="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$t" "$@"
  else
    "$@"
  fi
}

# run_step <timeout-seconds> <label> <command...>
# Prints the label first (so a slow step never looks frozen), runs the command
# with no stdin and a hard timeout, and shows the output only if it fails.
# STEP_ALREADY=1, set by a caller before invoking run_step, turns a success
# into `have "<label> (already present)"` instead of `ok`.
STEP_ALREADY=0
run_step() {
  local t="$1" label="$2"; shift 2
  local already="$STEP_ALREADY"; STEP_ALREADY=0
  BAR_LABEL="$label"
  emit "  ...   $label"
  local out status
  out=$(cap "$t" "$@" </dev/null 2>&1); status=$?
  step_done
  # Redraw the progress line only on a real terminal; piped/logged output would
  # otherwise be littered with literal escape sequences.
  if [ "$INTERACTIVE" = 1 ]; then
    bar_clear; printf '\033[1A\r\033[2K'
  else
    [ -t 1 ] && printf '\033[1A\033[2K'
  fi
  if [ $status -eq 0 ]; then
    if [ "$already" = "1" ]; then have "$label (already present)"; else ok "$label"; fi
    return 0
  fi
  if [ $status -eq 124 ]; then
    warn "$label -- TIMED OUT after ${t}s (skipped; run it manually to see what it wants)"
  else
    fail "$label -- exit $status"
  fi
  [ -n "$out" ] && emit "$(printf '%s\n' "$out" | tail -8 | sed 's/^/         | /')"
  return 1
}

section 1 "Prerequisites"
command -v claude >/dev/null && ok "claude CLI" || bad "claude CLI (https://docs.claude.com/en/docs/claude-code)"
command -v jq     >/dev/null && ok "jq"         || bad "jq (needed by the hooks): brew install jq / apt install jq"
command -v git    >/dev/null && ok "git"        || bad "git"
command -v node   >/dev/null && ok "node $(node --version 2>/dev/null)" || warn "node 18+ not found: the Context7 and Chrome DevTools MCP servers will not start, and npm (needed for CodeGraph) requires it too"
command -v uvx    >/dev/null && ok "uv/uvx"     || warn "uv not found: Semble code search will not start (https://docs.astral.sh/uv/)"
command -v codegraph >/dev/null && ok "codegraph" || warn "codegraph not found: the bundled CodeGraph MCP server will not start (section 3 installs it, or: npm install -g @colbymchenry/codegraph)"
command -v php    >/dev/null && ok "php"        || warn "php not found: per-edit PHP syntax check is skipped, not failed. Containerised toolchain? see .claude/lint-cmd in the README"
command -v docker >/dev/null && ok "docker (containerised toolchains supported via .claude/lint-cmd)" || true
command -v timeout >/dev/null || warn "no 'timeout' command (macOS: brew install coreutils); steps cannot be time-limited"
if [ "$MISSING" = "1" ]; then emit ""; emit "Fix the MISSING items above and re-run."; exit 1; fi

# State detection: one-shot caches of what's already configured, so re-running
# this script can show `[have] ... (already present)` instead of `[ok]`.
# Cosmetic only -- degrades to "assume absent" on any error or format change;
# never gates whether a command runs.
MKT_CACHE=$(cap 30 claude plugin marketplace list 2>/dev/null </dev/null || true)
PLG_CACHE=$(cap 30 claude plugin list 2>/dev/null </dev/null || true)
has_marketplace() { printf '%s\n' "$MKT_CACHE" | awk '{print $NF}' | grep -qxF "$1"; }
has_plugin()      { printf '%s\n' "$PLG_CACHE" | awk '{print $NF}' | grep -qxF "$1"; }

mark() { [ "$1" = "1" ] && printf 'x' || printf ' '; }

# select_components -- interactive-only checklist (spec's Checklist prompt).
# Runs before count_steps/plan_block so their output reflects the resolved
# selection. No-op when a selection flag was already passed (FLAGS_SET=1) or
# outside an interactive TTY -- a --dry-run alone does NOT suppress it, since
# a dry run should still let the user pick components.
select_components() {
  [ "$INTERACTIVE" = 1 ] && [ "$FLAGS_SET" = 0 ] || return 0

  local sel_superpowers=1 sel_codegraph=1 sel_memory=0 sel_powerline=0
  local hint="" first=1 n=13 i reply word bad

  render_checklist() {
    printf '\n'
    printf 'Select components  (dev-flow itself is always installed)\n'
    printf '\n'
    printf '  %-2s [%s]  %-18s %-30s%s\n' "1" "$(mark "$sel_superpowers")" "Superpowers" "superpowers-marketplace" "recommended"
    printf '  %-2s [%s]  %-18s %-30s%s\n' "-" "x" "dev-flow" "this marketplace" "required"
    printf '  %-2s [%s]  %-18s %-30s%s\n' "2" "$(mark "$sel_codegraph")" "CodeGraph" "structure / caller analysis" "optional"
    printf '  %-2s [%s]  %-18s %-30s%s\n' "3" "$(mark "$sel_memory")" "claude-mem" "cross-session memory" "reads tool output"
    printf '  %-2s [%s]  %-18s %-30s%s\n' "4" "$(mark "$sel_powerline")" "claude-powerline" "status line" "cosmetic"
    printf '\n'
    printf '  Numbers toggle (e.g. "2" or "2 4").  a = all,  d = defaults\n'
    printf '  Enter = install,  q = quit\n'
    if [ -n "$hint" ]; then
      printf '  %s%s%s\n' "$C_WARN" "$hint" "$C_OFF"
    else
      printf '\n'
    fi
    printf '> '
  }

  while :; do
    if [ "$first" = 1 ]; then
      first=0
    else
      printf '\033[%dA' "$n"
      i=1
      while [ "$i" -le "$n" ]; do
        printf '\r\033[2K'
        [ "$i" -lt "$n" ] && printf '\033[1B'
        i=$((i + 1))
      done
      printf '\033[%dA' "$((n - 1))"
    fi
    render_checklist

    if ! read -r -t 120 reply; then
      printf '\n'
      emit "         ${C_WARN}no input received; proceeding with the current selection${C_OFF}"
      break
    fi

    hint=""
    if [ -z "$reply" ]; then
      break
    fi
    case "$reply" in
      q) emit "nothing installed"; exit 0 ;;
      a) sel_superpowers=1; sel_codegraph=1; sel_memory=1; sel_powerline=1; continue ;;
      d) sel_superpowers=1; sel_codegraph=1; sel_memory=0; sel_powerline=0; continue ;;
    esac

    bad=0
    for word in $reply; do
      case "$word" in
        1|2|3|4|-) ;;
        *) bad=1 ;;
      esac
    done
    if [ "$bad" = 1 ]; then
      hint="unrecognized input: $reply"
      continue
    fi
    for word in $reply; do
      case "$word" in
        1) sel_superpowers=$((1 - sel_superpowers)) ;;
        2) sel_codegraph=$((1 - sel_codegraph)) ;;
        3) sel_memory=$((1 - sel_memory)) ;;
        4) sel_powerline=$((1 - sel_powerline)) ;;
        -) hint="dev-flow is required" ;;
      esac
    done
  done

  if [ "$sel_superpowers" = 1 ]; then SKIP_SUPERPOWERS=0; else SKIP_SUPERPOWERS=1; fi
  if [ "$sel_codegraph" = 1 ]; then SKIP_CODEGRAPH=0; else SKIP_CODEGRAPH=1; fi
  WITH_MEMORY=$sel_memory
  WITH_POWERLINE=$sel_powerline
}

# count_steps -- sets STEP_TOTAL to the number of run_step calls the chosen
# path will make (see spec's Progress indicator table). CodeGraph's count is
# an estimate: it can't know whether the npm install itself will succeed.
count_steps() {
  STEP_TOTAL=0
  [ "$SKIP_SUPERPOWERS" = "0" ] && STEP_TOTAL=$((STEP_TOTAL + 2))
  STEP_TOTAL=$((STEP_TOTAL + 2))  # dev-flow: always
  if [ "$SKIP_CODEGRAPH" = "0" ] && command -v npm >/dev/null; then
    command -v codegraph >/dev/null || STEP_TOTAL=$((STEP_TOTAL + 1))
  fi
  [ "$WITH_MEMORY" = "1" ] && command -v npx >/dev/null && STEP_TOTAL=$((STEP_TOTAL + 1))
  [ "$WITH_POWERLINE" = "1" ] && STEP_TOTAL=$((STEP_TOTAL + 2))
  STEP_TOTAL=$((STEP_TOTAL + 1))  # verify
  STEP_DONE=0
}

# plan_block -- pre-flight preview of exactly what will run, printed once
# after state detection and before any command is executed. [have] marks an
# artefact Task 6's predicates already found; [skip] marks one that won't run
# this time (flag-skipped or not selected).
plan_block() {
  emit ""
  emit "${C_BOLD}Plan  ($STEP_TOTAL steps)${C_OFF}"

  local tag
  if [ "$SKIP_SUPERPOWERS" = "0" ]; then
    tag=""; has_marketplace superpowers-marketplace && tag="  ${C_WARN}[have]${C_OFF}"
    emit "  superpowers      marketplace obra/superpowers-marketplace$tag"
    tag=""; has_plugin superpowers@superpowers-marketplace && tag="  ${C_WARN}[have]${C_OFF}"
    emit "                   plugin      superpowers@superpowers-marketplace$tag"
  fi

  tag=""; has_marketplace dev-flow-marketplace && tag="  ${C_WARN}[have]${C_OFF}"
  emit "  dev-flow         marketplace dev-flow-marketplace  <- $SRC$tag"
  tag=""; has_plugin dev-flow@dev-flow-marketplace && tag="  ${C_WARN}[have]${C_OFF}"
  emit "                   plugin      dev-flow@dev-flow-marketplace$tag"

  if [ "$SKIP_CODEGRAPH" = "1" ] || ! command -v npm >/dev/null; then
    emit "  codegraph        npm install -g @colbymchenry/codegraph  ${C_DIM}[skip]${C_OFF}"
  elif command -v codegraph >/dev/null; then
    emit "  codegraph        npm install -g @colbymchenry/codegraph  ${C_WARN}[have]${C_OFF}"
  else
    emit "  codegraph        npm install -g @colbymchenry/codegraph"
  fi

  if [ "$WITH_MEMORY" = "1" ] && command -v npx >/dev/null; then
    emit "  claude-mem       npx --yes claude-mem install"
  else
    emit "  claude-mem       npx --yes claude-mem install  ${C_DIM}[skip]${C_OFF}"
  fi

  if [ "$WITH_POWERLINE" = "1" ]; then
    tag=""; has_marketplace claude-powerline && tag="  ${C_WARN}[have]${C_OFF}"
    emit "  claude-powerline marketplace Owloops/claude-powerline$tag"
    tag=""; has_plugin claude-powerline@claude-powerline && tag="  ${C_WARN}[have]${C_OFF}"
    emit "                   plugin      claude-powerline@claude-powerline$tag"
  else
    emit "  claude-powerline marketplace Owloops/claude-powerline  ${C_DIM}[skip]${C_OFF}"
    emit "                   plugin      claude-powerline@claude-powerline"
  fi
  emit "                   manual follow-up: run /powerline inside Claude Code"

  emit "  verify           claude plugin list"
}

select_components
count_steps
plan_block

if [ "$DRY_RUN" = "1" ]; then
  note "Dry run: nothing installed. Re-run without --dry-run to apply."
  bar_clear
  exit 0
fi

section 2 "Plugins"
if [ "$SKIP_SUPERPOWERS" = "0" ]; then
  has_marketplace superpowers-marketplace && STEP_ALREADY=1
  run_step 120 "add marketplace obra/superpowers-marketplace" \
    claude plugin marketplace add obra/superpowers-marketplace
  has_plugin superpowers@superpowers-marketplace && STEP_ALREADY=1
  run_step 180 "install superpowers" \
    claude plugin install -y superpowers@superpowers-marketplace
else
  skip "superpowers skipped (--skip-superpowers)"
fi
has_marketplace dev-flow-marketplace && STEP_ALREADY=1
run_step 120 "add marketplace dev-flow ($SRC)" claude plugin marketplace add "$SRC" \
  || { has_marketplace dev-flow-marketplace && { note "dev-flow-marketplace is already registered from a different source or version."; note "Run uninstall.sh first (see README > Uninstalling), then re-run this installer."; }; }
has_plugin dev-flow@dev-flow-marketplace && STEP_ALREADY=1
run_step 180 "install dev-flow"                claude plugin install -y dev-flow@dev-flow-marketplace

section 3 "CodeGraph (optional, structure/caller analysis)"
if [ "$SKIP_CODEGRAPH" = "1" ]; then
  skip "skipped (--skip-codegraph): the bundled CodeGraph MCP server will not connect until you install the binary"
elif command -v npm >/dev/null; then
  if command -v codegraph >/dev/null; then
    have "codegraph already present"
  else
    run_step 300 "npm install -g @colbymchenry/codegraph (can take a minute)" \
      npm install -g @colbymchenry/codegraph
  fi
  if command -v codegraph >/dev/null; then
    note "per repo, once:  /dev-flow:onboard   (or manually: cd <repo> && codegraph init, add .codegraph/ to .gitignore)"
  fi
else
  warn "npm not found; skipping CodeGraph: the bundled CodeGraph MCP server will not connect until you install the binary"
fi

section 4 "Persistent memory (optional, off by default)"
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
  skip "skipped. Re-run with --with-memory to install claude-mem (cross-session recall)."
fi

section 5 "claude-powerline status line (optional, cosmetic, off by default)"
if [ "$WITH_POWERLINE" = "1" ]; then
  # Warn before touching an existing status line -- its wizard replaces it.
  settings="$HOME/.claude/settings.json"
  if [ -f "$settings" ] && command -v jq >/dev/null && jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
    warn "you already have a statusLine configured; the /powerline wizard will replace it:"
    emit "         | $(jq -c '.statusLine' "$settings" 2>/dev/null)"
    warn "back it up first if you want it:  cp \"$settings\" \"$settings.bak\""
  fi
  has_marketplace claude-powerline && STEP_ALREADY=1
  run_step 120 "add marketplace Owloops/claude-powerline" \
    claude plugin marketplace add Owloops/claude-powerline
  has_plugin claude-powerline@claude-powerline && STEP_ALREADY=1
  run_step 180 "install claude-powerline" \
    claude plugin install -y claude-powerline@claude-powerline
  note "FINAL STEP IS MANUAL: run  /powerline  inside Claude Code."
  note "That wizard writes ~/.claude/claude-powerline.json and wires statusLine;"
  note "it is interactive, so this script cannot run it for you."
  note "Needs a Nerd Font for the glyphs -- otherwise use --charset=text."
  note "Themes: dark light nord tokyo-night rose-pine gruvbox. Visual config: powerline.owloops.com"
else
  skip "skipped. Re-run with --with-powerline for the claude-powerline status line."
fi

section 6 "Verify"
run_step 60 "claude plugin list" claude plugin list || true
bar_clear
STEP_TOTAL=0

if [ "$N_FAIL" -gt 0 ]; then
  emit "${C_BAD}Done  $N_OK ok, $N_WARN warnings, $N_FAIL failures${C_OFF}"
elif [ "$N_WARN" -gt 0 ]; then
  emit "${C_WARN}Done  $N_OK ok, $N_WARN warnings, $N_FAIL failures${C_OFF}"
else
  emit "${C_OK}Done  $N_OK ok, $N_WARN warnings, $N_FAIL failures${C_OFF}"
fi

emit ""
note "Done. Restart Claude Code, then check /plugin, /mcp, /agents and /hooks."
note "Per repo:"
note "  - run 'setup-rules' (ask Claude: \"Set up AGENTS.md and rules for this repo\")"
note "  - create .claude/test-cmd            (the stop gate does nothing without it)"
note "  - create .claude/lint-cmd            (only if linters run in a container)"
note "  - optional .claude/test-cmd-retries  (stop-gate retries before giving up; default 3)"
}
