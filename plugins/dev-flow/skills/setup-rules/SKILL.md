---
name: setup-rules
description: Analyze a repository and generate or update its agent guidance - AGENTS.md (preferred when present) or CLAUDE.md, plus path-scoped rules in .claude/rules/ and the .claude/test-cmd and .claude/lint-cmd hook commands. Use when the user asks to set up Claude for a project, create or improve AGENTS.md or CLAUDE.md, document conventions for the agent, onboard an agent to a repo, wire up checks for a containerised toolchain, or asks "what rules should this repo have". Produces concise, verified, repo-specific guidance rather than generic advice.
---

# Set up project rules

Goal: short, accurate project guidance in the file this repo already uses, plus a few path-scoped rule files and working hook commands. Only include things you verified in this repo.

## Which file to write (run the detector before writing anything)

Do not eyeball this — run it, and follow what it says:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/guidance-target.sh"
```

It prints `link_kind`, `canonical`, `edit`, and (when relevant) `never_edit`. Act on `edit`:

| Situation | `edit` | What to do |
|---|---|---|
| `CLAUDE.md` is a **symlink** to `AGENTS.md`, a **hard link** to it, or **imports** it (`@AGENTS.md`) | `AGENTS.md` | **Put everything in `AGENTS.md` and never touch `CLAUDE.md`.** It is only a pointer. |
| `AGENTS.md` only | `AGENTS.md` | Write there; it may need a `CLAUDE.md` pointer so Claude Code loads it (below). |
| `CLAUDE.md` only | `CLAUDE.md` | Write there. |
| Both exist, unlinked | `ask-the-user` | Ask which is canonical. Never duplicate rules across both; offer to reduce the other to a pointer. |
| Neither | `ask-the-user` | Ask. Default: `AGENTS.md` plus a pointer. |

**Why `never_edit` is absolute:** when `CLAUDE.md` is a symlink or hard link, writing to it rewrites `AGENTS.md` *through the link* while looking like a `CLAUDE.md` change — so a diff you showed for one file silently lands in the other. When it is an import, anything added there is duplicated or lost. A `pre-write-guard` hook refuses these writes outright, with no approve-and-retry path, and tells you to target `AGENTS.md` instead. Do not create its override marker yourself; that exists only for the user who genuinely wants to fix the pointer line.

**Making sure Claude Code loads an `AGENTS.md`** (only when no pointer exists yet): Claude Code reliably reads `CLAUDE.md`; whether it reads `AGENTS.md` natively is version-dependent, so do not assume. Add one pointer and say which you used:

- A symlink, which works on any version: `ln -s AGENTS.md CLAUDE.md`
- Or a `CLAUDE.md` containing only the import line `@AGENTS.md` (documented import syntax; version-dependent).

Where this skill says `<guidance file>` below, it means whatever the detector reported as `edit`.

## Procedure

1. **Inspect** (read-only): package manifests (`composer.json`, `package.json`, `pyproject.toml`, `pom.xml`), CI config, Makefile or scripts, `docker-compose.yml`/`compose.yaml` and `Dockerfile`, linter and formatter config, test layout, directory structure, existing `AGENTS.md` / `CLAUDE.md`, `README`, and `.claude/`.
2. **Extract facts** and confirm each by running or reading it:
   - Exact commands to install, run, test, lint, and build — as this project actually runs them (see *Containerised toolchains* below). Run the test and lint commands once to make sure they work.
   - Architecture: entry points, layers, where business logic lives, how services talk to each other.
   - Conventions you can observe in code (naming, error handling, logging, DTO or entity patterns, API response shape).
   - Hazards: generated files, migrations, legacy or PCI-sensitive areas, files not to touch.
3. **Write `<guidance file>`** (target under 120 lines): what the repo is, the commands table, architecture in a few lines, the top 5 to 10 conventions, hazards. Every line should change how an agent behaves. Cut anything generic ("write clean code").
4. **Write path-scoped rules** in `.claude/rules/<topic>.md` only where a convention applies to part of the tree. Use frontmatter:
   ```markdown
   ---
   paths:
     - "src/Api/**/*.php"
   ---
   - Controllers return `ApiResponse`; never return raw arrays.
   ```
5. **Write the hook commands**, if the user wants them:
   - `.claude/test-cmd` — the fastest command that catches most breakage, used by the stop-gate hook before any turn can finish.
   - `.claude/lint-cmd` — only needed when the per-edit checks cannot run on the host (see below). It receives the repo-relative path as `$1`.
   Verify each by running it once. Report the result.
6. **Show a summary** of what you created, which guidance file you chose and why, and the evidence for each rule.

## Containerised toolchains (no native php/python/java on the host)

Common when each project pins its own runtime version. The host may have no `php`, `python`, `mvn` or `node` at all. Handle it explicitly:

- **Find out how this project runs things** — from `<guidance file>`, the Makefile, `package.json` scripts, compose files, or `bin/` wrappers. Never invent a compose service name or a container path; read them from `compose.yaml` (`services:`, `volumes:`) or ask.
- **Write the containerised form into `.claude/test-cmd`**, e.g. `docker compose exec -T php vendor/bin/phpunit --stop-on-failure`.
- **Write `.claude/lint-cmd`** so per-edit checks work too, translating the repo-relative `$1` into the container path. Start from `${CLAUDE_PLUGIN_ROOT}/templates/lint-cmd.docker.example`; there is also `test-cmd.docker.example`.
- **Use `-T`** (`docker compose exec -T …`): hooks have no TTY and an interactive exec will hang or fail. If the stack may not be running, prefer `docker compose run --rm …`, or have the script skip cleanly when the service is down.
- **Record the commands in `<guidance file>`** too, so a human and any other agent see the same thing.
- Without `.claude/lint-cmd`, the post-edit hook simply skips tools it cannot find on the host — it does not report a false failure — so the stop gate becomes the real safety net. Say so in the summary.

## When hooks are disabled by policy (hookless mode)

Hookless mode applies when the caller says so, or when
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/hooks-policy.sh"` reports `hooks=disabled`
or `hooks=managed-only`. In that case, procedure step 3 also adds this section
to `<guidance file>` (through the normal diff-and-approve flow), worded so it
is also correct where hooks do run:

```markdown
## Quality gates
dev-flow's hooks enforce these where hooks are allowed; where an organization's policy blocks plugin hooks, this instruction is the only enforcement:
- After editing a file, run `bash .claude/lint-cmd <repo-relative-path>` (if `.claude/lint-cmd` exists) and fix failures before moving on.
- Before saying work is done, `bash .claude/test-cmd` must exit 0.
- Before changing `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md`, show the complete change and wait for an explicit yes.
```

In hookless mode, `.claude/lint-cmd` is worth writing even on a host
toolchain, not only a containerised one: the native per-edit checks live only
in the hook, so without a written `.claude/lint-cmd` nothing checks individual
files at all.

## Changing existing guidance or rule files

**Always show the user what will change and get an explicit yes before touching `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md`.** These files carry standing instructions; changing them silently is never acceptable, however small the change.

A `pre-write-guard` hook enforces this mechanically — it is not optional and not merely this instruction. It covers `Write`, `Edit` **and** `MultiEdit`, so a targeted edit is gated exactly like a whole-file replace. Any change to an existing guarded file is blocked, and the hook's message hands you the precise change and an exact `mkdir`/`printf` command creating a single-use approval marker bound to that change.

When hooks are disabled by policy there is no such hook. The instruction above, and any `ask` permission rules `/dev-flow:init-hooks` set up, are then the only gate, so showing the full change first is on you.

When blocked:
1. Show the user the change from the hook message verbatim. Wait for an explicit yes/no in this turn. Do not retry in the meantime.
2. If they approve, run the exact command the hook gave you, then retry the same call unchanged. It will succeed and the marker is consumed.
3. If they want something different, revise and expect a fresh block — each distinct change needs its own approval, and the marker is invalidated if the file changed meanwhile.

**Propose the complete intended result in ONE call.** Do not dribble a rewrite out as a series of small edits: the user should review one coherent change, not approve five fragments. Never try to route around the gate (splitting the change, switching tools, deleting and recreating the file, disabling the hook).

## Rules

- Do not invent conventions. If two files disagree, say so instead of picking one.
- Keep rules short and imperative. Link to docs instead of copying them.
- Prefer adding to the existing guidance file over restructuring it; a large rewrite needs the user's approval through the diff flow above.
