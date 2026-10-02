---
paths:
  - "plugins/dev-flow/hooks/scripts/**/*.sh"
---
- `set -u` at the top; read the hook's JSON payload exactly once via `input=$(cat)`, then pull fields with `jq -r '.some.field // empty'` — never re-read stdin.
- Exit 0 = allow/pass silently. Exit 2 = block; put the message on stderr. No other exit code is meaningful to Claude Code. Stdout is ignored by the harness except on `SessionStart`, where it is injected as context (`session-start-restore.sh` prints a `hookSpecificOutput` JSON object). `PreCompact` and `SessionStart` hooks here must never exit 2 or print a decision: they always exit 0.
- No shebang execute bit required — `hooks.json` invokes every script as `bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh"`, so don't add `chmod +x` as a setup step.
- `cd "${CLAUDE_PROJECT_DIR:-.}"` before touching repo-relative paths — hooks run with an unpredictable cwd otherwise.
- Missing host tools are skipped, not failed (see `post-edit-check.sh`'s `have()` checks) — containerised toolchains where the host lacks php/python/java are the normal case here, not an edge case.
- A project-defined override (`.claude/lint-cmd`, `.claude/test-cmd`) always wins over the script's built-in native checks; check for it first and return early if present.
