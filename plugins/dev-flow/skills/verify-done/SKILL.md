---
name: verify-done
description: 'Verify work is finished before claiming it: run tests, lint and type checks, plus a browser check for web changes, and report the evidence. Use at the end of any implementation, fix, refactor or migration, before saying "done", "fixed", "implemented" or "ready", or when the user asks "is this ready", "does it work" or "can you verify".'
---

# Verify before you say "done"

Never claim success without command output that proves it.

## Checklist (run in this order, stop at the first failure and fix it)

1. **Diff review.** `git diff --stat` then read the diff. Remove debug output, commented-out code, and unrelated changes.
2. **Tests.** Run the tests for the touched modules, then the project's fast suite (the command in `.claude/test-cmd` if present). Show pass/fail counts.
3. **Static checks.** If `.claude/lint-cmd` exists, run `bash .claude/lint-cmd <repo-relative-path>` for each touched file. Lint, formatter check, and type or static analysis for touched files (`ruff`, `phpstan`, `tsc --noEmit`, `mvn -q compile`, and so on).
4. **Behaviour check** for the thing that was actually asked for:
   - API change: call the endpoint (curl or an HTTP test) with a success case and a failure case. Show status and body.
   - UI change: follow the `visual-verify` skill (it uses the bundled `chrome-devtools` MCP); if its tools are not connected, ask the user to check it in a browser and say it is unverified.
   - Migration or data change: run it on a copy or dev database and show the before/after.
   - Auth or session change: test valid, expired, and missing credentials.
5. **Docs and contracts.** If you changed an API shape, config key, or env var, update its documentation and callers.
6. **Report** with this structure:
   - **Changed:** files and a one-line summary each.
   - **Verified:** each command run and its result.
   - **Not verified:** anything you could not run, and why.
   - **Risks / follow-ups:** things the user should look at.

## Rules

- "Should work" is not verification. If you did not run it, say you did not.
- A failing or skipped check is reported, not hidden.
- If the environment cannot run a check (no DB, no network, no browser), say exactly what to run and what output to expect.
