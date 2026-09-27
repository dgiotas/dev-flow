---
description: Implement an approved plan task by task with cheaper Sonnet subagents, then review with Opus and verify.
argument-hint: <slug of the plan in docs/plans>
model: sonnet
---

Implement the approved plan `docs/plans/$ARGUMENTS.md` (spec: `docs/specs/$ARGUMENTS.md`).

You are the orchestrator, running on the cheaper model. Keep your own context small: delegate the coding.

1. Read the plan. If it is missing or has unresolved "Open questions", stop and tell me.
2. Work on a branch or worktree, not the default branch. If the tree has unrelated uncommitted changes, stop and ask.
3. For each task in dependency order, invoke the `implementer` subagent with only that task and the spec sections it references. Independent tasks (no shared files, no dependency) may run in parallel; otherwise run one at a time.
4. After each task, confirm its verify command passed. If the implementer replies `BLOCKED`, stop and report to me. Do not improvise design changes.
5. When all tasks are done, run the `verify-done` skill (tests, lint, behaviour check).
6. Invoke the `reviewer` subagent (Opus) on the full diff. If it returns `CHANGES REQUIRED`, send blocker and major findings back to `implementer` as new tasks, then re-review once.
7. Finish with: what was built, files changed, evidence of verification, remaining review findings, and anything not verified. Do not merge or push.
