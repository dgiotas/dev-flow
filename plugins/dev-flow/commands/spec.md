---
description: Plan a feature with the strong model. Investigates the repo, writes docs/specs and docs/plans. No code is written.
argument-hint: <feature or change to plan>
model: opus
---

Plan this work: $ARGUMENTS

Use the `spec-architect` subagent to do the investigation and write the files, so planning runs on the strong model even if this session was started on a cheaper one.

Steps:

1. If the request is vague, ask up to three short clarifying questions first, then continue.
2. Delegate to `spec-architect` with the full request and any answers. Ask it to produce `docs/specs/<slug>.md` and `docs/plans/<slug>.md`.
3. Read both files it wrote. Check that every plan task has exact files, a test-first step, and a verify command. If not, send it back once with specifics.
4. Summarise for me: the design in five lines or fewer, the task count, and every open question. Then end with exactly this, filling in the slug:

   > Review `docs/plans/<slug>.md`. Reply **`ok build`** to start the build phase right here, or run `/dev-flow:build <slug>` yourself instead — that switches the orchestration to Sonnet for this phase; replying `ok build` keeps it on the current model (the `implementer` subagent still runs on Sonnet either way, so most of the coding cost is the same).

5. If my next reply is `ok build`, or another unambiguous approval to proceed (e.g. "build it", "approved, go build"), do not wait for the literal slash command: follow the exact procedure in `commands/build.md` yourself, in this conversation, using this plan's slug. Say in one line that you're continuing on the current model rather than switching to Sonnet. If there are still open questions from step 4, resolve those first instead of proceeding.
6. If my reply instead asks for changes to the plan, or is anything other than an approval to build, do not start building — revise the spec/plan (steps 1 to 4 again) or answer the question.

Do not write or edit source code in this command, except when carrying out step 5.
