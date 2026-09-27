---
name: investigate
description: Answer questions about how a codebase works, with citations to exact files and lines, without changing any code. Use when the user asks "how does X work", "why does this happen", "trace the flow of", "explain this service", "what is the request path for", or wants to understand a bug, an architecture, or a service interaction before deciding what to do. Use even when the user does not say "investigate". Read-only.
---

# Investigate (read-only, cited)

You are answering a question, not making changes. Do not edit, create, or delete any project files.

## Procedure

1. **Restate the question** in one line and list what a complete answer must cover (for example: entry point, data flow, persistence, failure modes).
2. **Locate** using the `code-intel` skill: concept search first, then structure (callers/callees) for anything that crosses files or services.
3. **Trace the path end to end.** Follow the flow from entry point (route, handler, consumer, CLI) to the final effect (DB write, external call, response). For distributed systems, name each hop and its transport (HTTP, queue, event), and where the code for the next hop lives, even if it is another repo.
4. **Verify claims.** For each claim, open the code and confirm it. Do not rely on function names or comments alone. If behaviour depends on config, environment, or feature flags, find the actual values or say they are unknown.
5. **Answer** in this structure:
   - **Short answer** (2 to 4 sentences).
   - **Flow**: numbered steps, each with `path:line`.
   - **Key decisions and gotchas**: anything surprising (retries, caching, silent failures, ordering assumptions).
   - **Unverified**: what you could not confirm and how to check it.
6. **Stop.** Offer next steps (fix, refactor, test) but do not start them.

## Rules

- Every non-trivial claim carries a `path:line` reference.
- Distinguish "the code does X" (verified) from "probably X" (inferred). Label inferences.
- If the question is really a bug report, hand off to `fix-bug` after answering.
