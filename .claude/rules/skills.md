---
paths:
  - "plugins/dev-flow/skills/**/SKILL.md"
---
- Frontmatter is only `name` and `description` — no other fields are read by the harness.
- `description` is what drives auto-invocation, not a summary for humans: state the concrete trigger phrases and situations ("Use when the user asks X, Y, or says Z") plus what the skill explicitly does NOT do, so it fires on the right requests and doesn't shadow other skills.
- Match the existing skills' posture: read-only/report-only by default where the domain is risky (security, DB migrations, dead-code removal, git pushes) — state explicitly in the description and body when the skill stops short of taking action without confirmation.
- One directory per skill, one `SKILL.md` per directory — don't nest skills or share a directory between two.
