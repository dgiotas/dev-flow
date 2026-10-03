---
description: Plan a feature with the strong model. Investigates the repo, resolves ambiguities against a fixed checklist, writes .claude/specs and .claude/plans. No code is written.
argument-hint: <feature or change to plan>
model: opus
---

Plan this work: $ARGUMENTS

Use the `spec-architect` subagent to do the investigation, the clarification check and the writing, so planning runs on the strong model even if this session was started on a cheaper one. It cannot talk to me mid-run; you relay its questions.

Steps:

1. Delegate to `spec-architect` with the full request. On a re-run, also pass its earlier reply and my answers. Ask it to run its clarification check, then produce `.claude/specs/<slug>.md` and `.claude/plans/<slug>.md`.
2. If its reply starts with `BLOCKING`, no files were written. Send me its numbered questions verbatim, in one message, under `**Questions for you**`, and stop. Do not add, drop or reword questions, and do not ask any of your own. When I reply, go back to step 1.
3. Read both files it wrote. Check that every plan task has exact files, a test-first step, and a verify command, and that the spec ends with an "Assumptions and open questions" section with one row for each of the seven categories. If not, send it back once with specifics.
4. Summarise for me: the design in five lines or fewer, the task count, each `assumed` row in one line, then its numbered questions under `**Questions for you**`, each with its default. If it replied `Fully specified: no questions.`, write that line instead of the questions. If there are questions, add: "Answer any of them to override its default and I will revise the spec and plan." Then end with exactly this, filling in the slug:

   > Review `.claude/plans/<slug>.md`. Reply **`ok build`** to start the build phase right here, or run `/dev-flow:build <slug>` yourself instead — that switches the orchestration to Sonnet for this phase; replying `ok build` keeps it on the current model (the `implementer` subagent still runs on Sonnet either way, so most of the coding cost is the same).

5. If my next reply is `ok build`, or another unambiguous approval to proceed (e.g. "build it", "approved, go build"), the defaults of any unanswered questions stand. Do not wait for the literal slash command: follow the exact procedure in `commands/build.md` yourself, in this conversation, using this plan's slug. Say in one line that you're continuing on the current model rather than switching to Sonnet. If the reply answers any numbered question, treat it as step 6 instead.
6. If my reply answers questions, asks for changes to the plan, or is anything other than an approval to build, do not start building. Revise the spec/plan (steps 1 to 4 again, passing my answers) or answer the question.

Do not write or edit source code in this command, except when carrying out step 5.
