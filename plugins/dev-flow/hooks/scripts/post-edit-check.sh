#!/usr/bin/env bash
# Runs after Write/Edit. Exit 2 = send stderr back to Claude. Exit 0 = fine.
#
# Containerised toolchains: if the project's linters/interpreters are not on the
# host (a per-project PHP/Python/Java version in Docker, for instance), create
# .claude/lint-cmd in the repo. It is called with the repo-relative path of the
# edited file as $1 and fully replaces the native checks below -- it owns running
# the tool and translating the path into the container. A starting point lives at
# <plugin>/templates/lint-cmd.docker.example.
#
# Native checks are SKIPPED, never failed, when the tool is not installed, so a
# host without php/ruff/eslint does not produce bogus "command not found" blocks.
set -u
input=$(cat)
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -n "$f" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true
[ -f "$f" ] || exit 0
rel="${f#"$PWD"/}"

fail() { printf 'Post-edit check failed for %s:\n%s\n' "$rel" "$1" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Project-defined checker wins (containers, custom runners, monorepo dispatch).
if [ -f ".claude/lint-cmd" ]; then
  out=$(bash ".claude/lint-cmd" "$rel" 2>&1) || fail "$out"
  exit 0
fi

case "$f" in
  *.php)
    if have php; then out=$(php -l "$f" 2>&1) || fail "$out"; fi
    if [ -x vendor/bin/pint ]; then
      out=$(vendor/bin/pint --test "$f" 2>&1) || fail "$out"
    elif [ -x vendor/bin/php-cs-fixer ]; then
      out=$(vendor/bin/php-cs-fixer fix --dry-run --diff "$f" 2>&1) || fail "$out"
    fi
    # Opt-in static analysis: export QG_PHPSTAN=1 in your shell
    if [ "${QG_PHPSTAN:-0}" = "1" ] && [ -x vendor/bin/phpstan ]; then
      out=$(vendor/bin/phpstan analyse --no-progress --error-format=raw "$f" 2>&1) || fail "$out"
    fi
    ;;
  *.py)
    if have ruff; then
      out=$(ruff check "$f" 2>&1) || fail "$out"
      out=$(ruff format --check "$f" 2>&1) || fail "$out"
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    if [ -x node_modules/.bin/eslint ]; then
      out=$(node_modules/.bin/eslint "$f" 2>&1) || fail "$out"
    fi
    if [ -x node_modules/.bin/prettier ]; then
      out=$(node_modules/.bin/prettier --check "$f" 2>&1) || fail "$out"
    fi
    ;;
  *.java)
    # Per-file compilation is rarely meaningful; the stop gate (.claude/test-cmd)
    # or .claude/lint-cmd is the right place for JVM builds.
    ;;
  *.json)
    if have jq; then out=$(jq empty "$f" 2>&1) || fail "$out"; fi
    ;;
esac
exit 0
