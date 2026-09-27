# dev-flow: private Claude Code plugin (v1.5.1)

A spec-then-build workflow with **model routing** (a strong model plans and reviews, a cheaper one codes), quality-gate hooks, bundled MCP servers and nine dev skills. Built to sit alongside obra/superpowers.

## Colleague quick-start (5 minutes)

```bash
git clone <this repo> dev-flow-marketplace && cd dev-flow-marketplace
bash install.sh                 # checks prerequisites, installs Superpowers + dev-flow (+ optional CodeGraph)
bash install.sh --with-memory   # same, plus claude-mem for cross-session recall (see Memory below)
```

Flags: `--with-memory`, `--skip-superpowers`, `--skip-codegraph`, `--help`. Re-running is safe. Every step is time-limited and shows its own output on failure, so it reports errors instead of stalling.

Restart Claude Code, then verify with `/plugin`, `/mcp`, `/agents`, `/hooks`. Then, once per repo you work in:

```text
/dev-flow:init-rules php        # or java | python | node | all: copies verified rule templates into .claude/rules
"Set up CLAUDE.md for this repo"   # setup-rules skill
echo 'vendor/bin/phpunit --stop-on-failure' > .claude/test-cmd   # your fast check; enables the stop gate
cd <repo> && codegraph init     # optional: structure index (add .codegraph/ to .gitignore)
```

Manual install instead of the script:

```text
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
/plugin marketplace add /path/to/dev-flow-marketplace      # or your-org/dev-flow-marketplace
/plugin install dev-flow@dev-flow-marketplace
```

Required: Claude Code, `jq`, `git`. Optional: Node 18+ and `uv` (only for the Context7 / DevTools / Semble MCP servers), `npm` (CodeGraph), native language tools (see *Containerised toolchains* — you do **not** need them installed on the host). Hooks run through `bash`, so no `chmod` is needed. To try it without installing: `claude --plugin-dir ./plugins/dev-flow`.

## AGENTS.md or CLAUDE.md

`setup-rules` and `/dev-flow:init-rules` check the repo root and **follow the convention already there** instead of imposing one:

| Found in repo | What gets written |
|---|---|
| `AGENTS.md` | That file is the source of truth — guidance goes there, no competing `CLAUDE.md` is created |
| `CLAUDE.md` only | `CLAUDE.md` |
| Both | It asks which is canonical, and won't duplicate rules across both |
| Neither | It asks; default is `AGENTS.md` plus a pointer |

Claude Code reliably reads `CLAUDE.md`; whether it natively reads `AGENTS.md` depends on your version, so the skill doesn't assume it. When `AGENTS.md` is canonical it adds a pointer and tells you which it used — either a symlink (`ln -s AGENTS.md CLAUDE.md`, works on any version) or a `CLAUDE.md` containing just `@AGENTS.md` (Claude Code's import syntax, version-dependent). `pre-write-guard` protects `AGENTS.md` exactly like `CLAUDE.md`.

## Containerised toolchains (no native php / python / java on the host)

Normal when each project pins its own runtime version in Docker. Nothing here needs language tools on the host:

- **Per-edit checks (`post-edit-check`)**: native tools it cannot find are **skipped, never failed** — a host without `php` does not produce "command not found" blocks on every edit. (This was a real bug before v1.5; it used to block.)
- **To actually run checks in the container**, create `.claude/lint-cmd` in the repo. The hook calls it with the **repo-relative path** of the edited file as `$1`, and it fully replaces the native checks. It owns translating that into the container path — the part the hook cannot guess. Start from `plugins/dev-flow/templates/lint-cmd.docker.example`:

  ```bash
  # .claude/lint-cmd
  set -u
  inside="/var/www/html/$1"
  docker compose exec -T php php -l "$inside" || exit 1
  ```

- **The stop gate** already takes an arbitrary command, so containers work there with no change: put `docker compose exec -T php vendor/bin/phpunit --stop-on-failure` in `.claude/test-cmd` (template: `test-cmd.docker.example`).
- **Always use `-T`.** Hooks have no TTY, so an interactive `docker compose exec` will hang or fail. If the stack may be down, use `docker compose run --rm …`, or skip cleanly as the template does.
- **Java**: per-file compilation isn't useful, so `.java` edits do nothing per-edit by design — put `./mvnw -q -o test -DskipITs` in `.claude/test-cmd` instead.
- `setup-rules` reads how your project documents its commands (`AGENTS.md`, Makefile, compose files) and writes both hook files in containerised form, then runs them once to verify. It is instructed never to guess a service name or container path.

## What's inside

| Kind | Name | Purpose |
|---|---|---|
| Command | `/dev-flow:spec <feature>` | Opus plans: writes `docs/specs/<slug>.md` and `docs/plans/<slug>.md`. No code. |
| Command | `/dev-flow:build <slug>` | Sonnet orchestrates and implements task by task, then verify, then Opus review. |
| Command | `/dev-flow:init-rules <stack>` | Adapts stack rule templates into the repo's `.claude/rules`. |
| Agent | `spec-architect` (Opus) | Investigates and writes spec and plan. |
| Agent | `implementer` (Sonnet) | Implements one plan task test-first, escalates with `BLOCKED`. |
| Agent | `reviewer` (Opus) | Read-only diff review against spec. |
| Skill | `code-intel` | Picks Semble, CodeGraph, Context7, DevTools or `rg`. |
| Skill | `investigate` | Read-only, cited codebase Q&A. |
| Skill | `fix-bug` | Red test, root cause, minimal fix, verify. |
| Skill | `verify-done` | Evidence before saying "done". |
| Skill | `setup-rules` | Generates `CLAUDE.md` and rules from the repo. |
| Skill | `dead-code-audit` | Report-only cleanup audit. |
| Skill | `git-workflow` | Branches, commits, PR text, review feedback. Never pushes unasked. |
| Skill | `security-review` | Auth, injection, secrets, PCI-adjacent and dependency checklist. Report-only. |
| Skill | `db-migration` | Expand/migrate/contract, backfills, rollback. Never runs against shared DBs. |
| Hook | `post-edit-check` | Syntax and lint on each edited file (PHP, Python, TS/JS, JSON). |
| Hook | `stop-gate` | Runs `.claude/test-cmd` before Claude can finish, retrying up to 3 times before giving up (see below). |
| Hook | `pre-write-guard` | Blocks silent overwrites of `AGENTS.md` / `CLAUDE.md` / `.claude/rules/*.md` (see below). |
| MCP | context7, semble, chrome-devtools | Bundled in `.mcp.json`, start automatically. CodeGraph is set up by `install.sh`. |

## Pre-write guard: CLAUDE.md and rules are never silently overwritten

This is a mechanical gate, not just an instruction the model might forget. `pre-write-guard` runs before every `Write` call. If the target is `CLAUDE.md` or `.claude/rules/*.md`, the file already exists, and the proposed content differs from what's on disk, the write is **blocked** (exit 2) and the message sent back to Claude contains:

- a unified diff of old vs. proposed content,
- an instruction to show that diff to you verbatim and wait for an explicit yes/no,
- the exact `mkdir`/`printf` command that creates a single-use approval marker keyed to the sha256 of that exact proposed content.

Only after that marker exists does the retried Write succeed — and it's consumed on use, so a different revision needs a fresh diff and a fresh marker. Identical content (no real change) and brand-new files pass straight through. Guarded paths: `AGENTS.md`, `CLAUDE.md`, `.claude/rules/*.md`. I tested the full cycle (block → approve → retry succeeds → marker consumed → a further change blocks again) directly against the script; I have not yet seen it fire inside a live Claude Code session.

Add `.claude/.approved-writes/` to `.gitignore`.

## Stop gate: retries and giving up

`stop-gate` blocks Claude from finishing while `.claude/test-cmd` fails, up to a cap, then gives up loudly instead of blocking forever:

- Each failure increments a counter in `.claude/.stop-gate-state` and is reported back to Claude as `attempt N/max`.
- After the cap (default **3**) it stops blocking, but writes a hard-to-miss `Quality gate: giving up...` banner to `.claude/stop-gate-giveup.log` and tells Claude to report the failure to you instead of finishing quietly.
- A pass at any point clears the counter. The next failure after a give-up starts a fresh cycle at attempt 1.
- Change the cap per repo: put a number in `.claude/test-cmd-retries`, or set `DEV_FLOW_STOP_GATE_MAX` in your shell.
- Add `.claude/.stop-gate-state` and `.claude/stop-gate-giveup.log` to `.gitignore`.

## Memory

Nothing is installed by default; `CLAUDE.md`, `.claude/rules`, and the specs/plans in `docs/` are the durable, reviewed record and need no extra tool. For personal cross-session recall, `bash install.sh --with-memory` installs [claude-mem](https://github.com/thedotmack/claude-mem). Before using it on anything sensitive:
- Open its config and select the **local/offline** provider — recent versions can default some integrations to a hosted service.
- It captures tool output via hooks, so review what it stores before pointing it at the PCI-adjacent app or anything with secrets.
- It records whatever Claude concluded, not just what you confirmed, so treat its recall as a lead to verify, not a fact — put anything that must be trusted into `CLAUDE.md` instead.

## Daily use

```text
/dev-flow:spec add rate limiting to the ticket search API
   -> review and edit docs/plans/<slug>.md, answer the open questions
   -> reply "ok build", or run /dev-flow:build <slug> yourself
```

Everything else triggers from plain requests: "how does X work" (investigate), "this is broken" (fix-bug), "commit this" (git-workflow), "review this for security", "is this migration safe", "verify it's done".

## `ok build`: two ways to start the build phase

`/dev-flow:spec` ends by asking you to either reply **`ok build`** or run `/dev-flow:build <slug>` yourself. They are not equivalent:

| | Reply `ok build` | Run `/dev-flow:build <slug>` |
|---|---|---|
| Orchestration (reading the plan, dispatching tasks, running the loop) | Stays on whichever model is running the session — Opus, since that's what `/dev-flow:spec` pinned | Switches to Sonnet, per that command's own `model:` frontmatter |
| Actual coding (`implementer` subagent) | Sonnet | Sonnet |
| Final review (`reviewer` subagent) | Opus | Opus |

So `ok build` saves you retyping the slug and slash command, at the cost of the orchestration chatter running on the pricier model. The coding itself is Sonnet either way, since that's pinned on the `implementer` agent regardless of who invoked it. `/dev-flow:spec` says this out loud before proceeding. This depends on Claude Code actually pinning a command's model on explicit invocation, as its frontmatter documents — I haven't verified that live in this sandbox (same caveat as the model-routing section below).

Also: `spec-architect`, `implementer` and `reviewer` are subagents, and a subagent cannot itself spawn further subagents. So the `ok build` path (running build.md's procedure inline in the same conversation) and the `/dev-flow:build` path both work the same way here — the orchestrator is always the top-level session, never a subagent, so this isn't affected by that limit.

## Model routing

| Stage | Model |
|---|---|
| `/dev-flow:spec` and `spec-architect` | Opus |
| `/dev-flow:build` orchestration and `implementer` | Sonnet |
| `reviewer` | Opus |

Agent-level `model:` pins each stage even if the session started on another model. To change it, edit the `model:` line in `agents/*.md` and `commands/*.md` (`opus`, `sonnet`, `haiku`, a full model ID, or `inherit`).

## Updating and sharing

Host the marketplace in a private git repo. Colleagues run `/plugin marketplace add org/repo`. To release a change: bump `version` in `plugins/dev-flow/.claude-plugin/plugin.json`, push, and they run `/plugin update`.

## Uninstalling everything `install.sh` added

Run in this order. Subcommand names verified against `claude plugin --help` / `claude mcp --help`; `claude plugin uninstall` also answers to `remove`, and `marketplace remove` to `rm`.

```bash
# 1. See what is actually installed before removing anything
claude plugin list
claude plugin marketplace list
claude mcp list

# 2. The plugins (this also removes the bundled context7 / semble /
#    chrome-devtools MCP servers, since those are plugin-scoped via .mcp.json)
claude plugin uninstall dev-flow@dev-flow-marketplace
claude plugin marketplace remove dev-flow-marketplace

# 3. Superpowers, only if you no longer want it (it is independent of dev-flow)
claude plugin uninstall superpowers@superpowers-marketplace
claude plugin marketplace remove superpowers-marketplace

# 4. CodeGraph — it registered itself in ~/.claude.json, outside the plugin.
#    Confirm the exact server name from `claude mcp list` first.
claude mcp remove codegraph
npm uninstall -g @colbymchenry/codegraph

# 5. claude-mem, only if you installed it with --with-memory.
#    It installs its own hooks and a background worker, so use its own uninstaller:
npx claude-mem uninstall        # if this fails, see https://github.com/thedotmack/claude-mem
claude mcp list                 # then remove any leftover entry it registered
```

Then check `~/.claude/settings.json` for any leftover `hooks` entries mentioning `claude-mem` or `codegraph` (dev-flow's own hooks live inside the plugin and disappear with it), and restart Claude Code.

**Per-repo leftovers.** Uninstalling the plugin does not touch files it wrote into your repos. Remove per repo as wanted:

```bash
rm -f  .claude/test-cmd .claude/test-cmd-retries .claude/lint-cmd
rm -rf .claude/.approved-writes .claude/.stop-gate-state .claude/stop-gate-giveup.log
rm -rf .claude/rules            # only if these were generated and you don't want them
rm -rf .codegraph               # CodeGraph index
# docs/specs and docs/plans are your own work product — keep them
```

`AGENTS.md` / `CLAUDE.md` edits are in git, so revert those with `git diff` / `git checkout --` as normal.

If you kept a backup before first installing (`cp -r ~/.claude ~/.claude.bak-<date>`, `cp ~/.claude.json ~/.claude.json.bak-<date>`), restoring those is the fastest full reset.

Verified: steps 2 and 3 were run for real (both plugins uninstalled and both marketplaces removed cleanly, confirmed with `claude plugin list` / `marketplace list`). Steps 4 and 5 (CodeGraph, claude-mem) are **not** verified — they depend on what those tools registered on your machine, so check `claude mcp list` between steps rather than trusting the commands blindly.

## Troubleshooting

**`install.sh` freezes / hangs with no output.** Fixed in v1.5.1 — upgrade. The cause: `claude plugin install` requires `-y` when stdout is not a TTY (which is always true inside a script), and v1.5 and earlier also sent output to `/dev/null`, so the confirmation prompt was invisible while the command waited for a keystroke. It looked frozen but was asking a question you couldn't see. The installer now passes `-y`, runs every command with `</dev/null` so nothing can block on a hidden prompt, sets `GIT_TERMINAL_PROMPT=0` so a private-repo clone errors instead of waiting for credentials, and wraps each step in `timeout` so a stall becomes a visible `TIMED OUT` warning. If you are stuck on an older copy, run the commands by hand: `claude plugin marketplace add <path>` then `claude plugin install -y dev-flow@dev-flow-marketplace`.

**A step reports TIMED OUT.** Run that one command on its own to see what it wants — usually network (`npm install -g`, a GitHub clone) or credentials for a private marketplace repo. `--skip-superpowers` and `--skip-codegraph` let you get the rest installed meanwhile.

**Installed but nothing appears.** Restart Claude Code, then `claude plugin list` and `claude plugin details dev-flow`. The inventory should read: Skills 12 (9 skills + the 3 commands), Agents 3, Hooks 3 (PreToolUse, PostToolUse, Stop), MCP servers 3.

**Context cost.** `claude plugin details dev-flow` reports roughly **1,700 always-on tokens** per session for the whole plugin, with each skill's body loaded only when it fires. Worth checking yourself if you stack several plugins.

## Known limits

- Install, component registration (`claude plugin details`) and the uninstall sequence below are now verified by actually running them. What is still **not** verified is the workflow itself in a live session: `/dev-flow:spec` → `/dev-flow:build`, the hooks firing inside a real turn, and whether a command's `model:` frontmatter pins the model as documented. Trial it on a small task before rolling out.
- CodeGraph and Semble build indexes on first use and can be slow on large repos.
- The stop gate does nothing without a per-repo `.claude/test-cmd`; the retry/give-up mechanism above is new and tested standalone (not yet inside a live Claude Code stop-hook cycle).
- The pre-write guard covers only the `Write` tool (whole-file replace) on `AGENTS.md`, `CLAUDE.md` and `.claude/rules/*.md`; targeted `Edit`/`MultiEdit` calls on those files are not gated, since they carry their own explicit old/new text rather than silently replacing the file.
- With a containerised toolchain and no `.claude/lint-cmd`, per-edit checks skip silently — which means the stop gate (`.claude/test-cmd`) is your only automated check, so it is worth setting up properly there.
- Whether Claude Code loads `AGENTS.md` natively is version-dependent and unverified here; that is why `setup-rules` adds a `CLAUDE.md` symlink or import pointer rather than assuming.
- Rule templates are starting points: `init-rules` verifies them against the repo, but review the result.
- No persistent memory (add `claude-mem` separately if wanted) and no usage dashboard.
- `security-review` and `db-migration` give structured checks, not compliance certification or a substitute for DBA and security sign-off.
- `ok build` is pattern-matched by the model reading `spec.md`'s own instructions, not by the Claude Code harness — it (and near-equivalents like "build it") gets recognised because the command tells the model to look for an approval reply, not because of any special runtime feature.
