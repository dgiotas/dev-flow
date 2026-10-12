---
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent]
---
Use the dev-flow plan-reviewer subagent to review the plan .claude/plans/badge.md against its spec .claude/specs/badge.md. Give it the spec and plan paths, this plan-check output: result=ok errors=0 warnings=0, the repository root (the current working directory), and the fact that .codegraph/ does not exist. Then reply with the subagent's reply verbatim and nothing else.
