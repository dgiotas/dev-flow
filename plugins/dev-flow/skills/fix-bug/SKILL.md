---
name: fix-bug
description: Fix a bug with a reproducing test first, a root-cause explanation, a minimal fix, and a quality gate. Use whenever the user reports a bug, a failing test, an exception, a regression, wrong output, or says "fix this", "this is broken", "why does this fail", "make this test pass", even if they do not mention TDD. Combines systematic debugging and test-driven development into one flow.
---

# Fix a bug: RED, root cause, GREEN, gate

If the superpowers plugin is installed, use its `systematic-debugging` and `test-driven-development` skills for the detailed method. This skill defines the order and the exit criteria.

## Procedure

1. **Reproduce.** Get the exact failing input, error, or stack trace. If you cannot reproduce it, say so and ask for what is missing. Do not guess-fix.
2. **Write the failing test first (RED).**
   - Put it next to the existing tests for that module, following their style.
   - Run it. Confirm it fails **for the reason the bug describes**, not because of a typo or setup error. Show the failure output.
3. **Find the root cause.** Use `code-intel` to trace the flow. State the cause in one or two sentences, and say why the symptom follows from it. Fixing a symptom (a null check that hides bad data, a retry that hides a race) is not a fix. If the root cause is elsewhere, say where.
4. **Minimal fix (GREEN).** Change the smallest amount of code that removes the cause. No drive-by refactors. Run the new test and confirm it passes.
5. **Regression sweep.**
   - Run the test file, then the wider suite for the affected module (use the command in `.claude/test-cmd` if present).
   - Use `codegraph` or `rg` to find other callers or copies of the same pattern. Fix them or list them.
6. **Quality gate.** Run lint and type or static checks for touched files. Follow the `verify-done` skill before saying you are done.
7. **Report:** root cause, the test added, the fix (files and lines), what was run and its results, and any related risks you saw but did not touch.

## Rules

- Never delete, skip, or weaken an existing test to get green. If a test is wrong, explain why and get agreement.
- If the fix needs a schema change, migration, or an API contract change, stop and confirm before proceeding.
- Two failed fix attempts in a row: stop, re-read the trace from step 3, and reconsider the root cause instead of trying a third variation.
