---
description: Implement an approved plan task by task with cheaper Sonnet subagents, then review with Opus and verify.
argument-hint: <slug of the plan in .claude/plans>
model: sonnet
---

Implement the approved plan `.claude/plans/$ARGUMENTS.md` (spec: `.claude/specs/$ARGUMENTS.md`).

You are the orchestrator, running on the cheaper model. Keep your own context small: delegate the coding.

1. Read the plan and the spec. If the plan is missing, or the spec's "Assumptions and open questions" section has any row with status `blocking`, or the spec has an unresolved "Open questions" section (older specs), stop and tell me. `assumed` rows are not blockers, and neither are numbered questions with a `default:` under that table: their defaults stand.
2. Work on a branch or worktree, not the default branch. If the tree has unrelated uncommitted changes, stop and ask.
3. For each task in dependency order, invoke the `implementer` subagent with only that task, the spec sections it references, and the spec's "Assumptions and open questions" section. Independent tasks (no shared files, no dependency) may run in parallel; otherwise run one at a time.
4. After each task, confirm its verify command passed. If the implementer replies `BLOCKED`, stop and report to me. Do not improvise design changes.
5. When all tasks are done, run the `verify-done` skill (tests, lint, behaviour check).
6. Invoke the `reviewer` subagent (Opus) on the full diff. It has no shell, so collect its inputs yourself and paste them into the prompt:
   - `base=$(git merge-base HEAD "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo main)")`
   - the diff: `git diff "$base"` (committed and uncommitted work), plus each new file from `git ls-files --others --exclude-standard` shown with `git diff --no-index /dev/null <file>`. If the result is too large to paste, pass `git diff --stat "$base"` and the list of changed and new files instead, and say the reviewer must Read them.
   - the log: `git log --oneline "$base"..HEAD`
   - the output and exit code of `bash .claude/test-cmd`, or "no .claude/test-cmd" if it does not exist
   - the spec and plan paths.
   If it returns `CHANGES REQUIRED`, send blocker and major findings back to `implementer` as new tasks, then re-review once, collecting fresh inputs.
7. Finish with: what was built, files changed, evidence of verification, remaining review findings, and anything not verified. Do not merge or push.
