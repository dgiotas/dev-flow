---
description: Initialize the CodeGraph index for this repo so the already-registered codegraph MCP server has something to query.
---

Give the `plugin:dev-flow:codegraph` MCP server an index to query in this repo.

## 0. Resolve the repo root

Run `git rev-parse --show-toplevel` and do all work there. If that fails (not a git repo), or the resolved path is `$HOME`, say so and stop — never run `codegraph init` in `$HOME` or `/`, and never pass `-f`/`--force` to make it possible.

## 1. Check the binary exists

Run `command -v codegraph`. If it is missing, report that CodeGraph is optional (it is optional everywhere else in this plugin) and the MCP server is registered regardless — it just has nothing to answer with yet — then tell the user to run `npm install -g @colbymchenry/codegraph` (or `bash install.sh`, section 3) and **stop cleanly**. This is not an error.

## 2. Check whether an index already exists

Run `codegraph status --json` at the repo root.

- If `.initialized` is `true`, skip init entirely. Report `lastIndexed` and `fileCount` from the output.
- If `pendingChanges` is non-zero, mention `codegraph sync` as the next step the user can take — do not run it yourself; syncing is the `code-intel` skill's territory, and this command stays single-concern.
- If `.initialized` is `false`, continue to step 3.

## 3. Initialize

Run `codegraph init -y </dev/null` at the repo root. Expect exit 0 and a tail showing `Initialized in <path>` / `Indexed N files` / `N nodes, N edges`. Report those counts.

If the exit code is non-zero, report the output verbatim and stop. Do not retry with `-f`.

## 4. Keep `git status` clean

`codegraph init` already writes `.codegraph/.gitignore` (containing `*` / `!.gitignore`), so the database itself was never committable. But that inner file is not self-ignored, so `.codegraph/` still shows up as untracked in `git status` until the repo's own `.gitignore` excludes it.

Check the repo's `.gitignore` for an existing `.codegraph/` (or equivalent) entry. Only if none matches, append a `.codegraph/` line. Do not touch the file if it already covers it.

## 5. Report

State: the `codegraph` binary path and version; whether an index already existed or was just created; the file/node/edge counts; whether `.gitignore` was appended to; and what this unlocks — the `codegraph_explore` tool via the `plugin:dev-flow:codegraph` MCP server, verifiable with `claude mcp list`.
