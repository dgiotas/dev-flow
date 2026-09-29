# dev-flow: private Claude Code plugin (v1.10)

A spec-then-build workflow with **model routing** (a strong model plans and reviews, a cheaper one codes), quality-gate hooks, bundled MCP servers and nine dev skills. Built to sit alongside obra/superpowers.

## Colleague quick-start (5 minutes)

```bash
git clone <this repo> dev-flow-marketplace && cd dev-flow-marketplace
bash install.sh                 # checks prerequisites, installs Superpowers + dev-flow (+ optional CodeGraph)
bash install.sh --with-memory   # same, plus claude-mem for cross-session recall (see Memory below)
```

On a terminal, a plain `bash install.sh` shows an interactive checklist to pick components; passing any selection flag or running non-interactively (`-y`/`--non-interactive`, CI, or piped input) skips the prompt. `--dry-run` does not skip the prompt: on an interactive terminal it still shows the checklist, then exits after printing the Plan instead of installing anything.

Flags: `--with-memory`, `--with-powerline`, `--skip-superpowers`, `--skip-codegraph`, `-y`/`--yes`/`--non-interactive`, `--no-color`, `--dry-run`, `--help`. Re-running is safe. Every step is time-limited and shows its own output on failure, so it reports errors instead of stalling.

Restart Claude Code, then verify with `/plugin`, `/mcp`, `/agents`, `/hooks`. Then, once per repo you work in:

```text
/dev-flow:init-hooks            # reads your AGENTS.md/Makefile/CI, writes + verifies .claude/test-cmd (and lint-cmd)
/dev-flow:init-rules php        # or java | python | node | all: copies verified rule templates into .claude/rules
"Set up AGENTS.md for this repo" # setup-rules skill (guidance file + rules + hook commands in one go)
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

`setup-rules` and `/dev-flow:init-rules` run a detector first and follow the convention already in the repo instead of imposing one:

```bash
bash plugins/dev-flow/scripts/guidance-target.sh    # prints link_kind / canonical / edit / never_edit
```

| Found in repo | What gets edited |
|---|---|
| `CLAUDE.md` is a **symlink** to `AGENTS.md`, a **hard link** to it, or **imports** it (`@AGENTS.md`) | **`AGENTS.md` only — `CLAUDE.md` is never touched** |
| `AGENTS.md` only | `AGENTS.md` (+ a `CLAUDE.md` pointer so Claude Code loads it) |
| `CLAUDE.md` only | `CLAUDE.md` |
| Both, unlinked | It asks which is canonical, and won't duplicate rules across both |
| Neither | It asks; default is `AGENTS.md` plus a pointer |

### When CLAUDE.md is only a pointer, editing it is refused outright

This is enforced, not advisory. If `CLAUDE.md` is linked to `AGENTS.md` in any of those three ways, `pre-write-guard` **refuses** every `Write`/`Edit`/`MultiEdit` to it and redirects to `AGENTS.md` — with no approve-and-retry path, because there is nothing worth approving:

- **symlink or hard link** — writing to `CLAUDE.md` rewrites `AGENTS.md` *through the link*, so a diff shown for one file lands in the other. That is the dangerous case.
- **`@AGENTS.md` import** — anything added there is duplicated or lost.

Detection covers relative and broken symlinks, hard links (by inode), and an `@AGENTS.md` mention anywhere in the file (`@AGENTS.md`, `@./AGENTS.md`, `@docs/AGENTS.md`, or inline in a sentence). An independent `CLAUDE.md` with no link is *not* refused — it goes through normal diff-and-approve gating.

Escape hatch, for the one legitimate case (you want to fix the pointer line itself). The model is told not to create this itself:

```bash
mkdir -p .claude/.approved-writes && touch .claude/.approved-writes/ALLOW-CLAUDE-MD-EDIT
```

It is single-use and only downgrades the refusal to the normal diff-and-approve gate.

Verified against all of it: symlink, hard link, `@AGENTS.md` import, an inline import mention, a broken symlink, an independent `CLAUDE.md`, and the override — and confirmed that with a symlink in place `AGENTS.md` was left byte-for-byte untouched rather than silently rewritten.

Claude Code reliably reads `CLAUDE.md`; whether it natively reads `AGENTS.md` depends on your version, so the skill doesn't assume it. When `AGENTS.md` is canonical and no pointer exists yet, it adds one and tells you which — a symlink (`ln -s AGENTS.md CLAUDE.md`, any version) or a `CLAUDE.md` containing just `@AGENTS.md` (import syntax, version-dependent).

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
| Command | `/dev-flow:init-hooks` | Derives `.claude/test-cmd` / `lint-cmd` from your AGENTS.md, Makefile, manifests or CI, then verifies them. |
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
| Hook | `pre-write-guard` | Gates every change (Write/Edit/MultiEdit, plus Bash commands that look like they write the file directly) to `AGENTS.md` / `CLAUDE.md` / `.claude/rules/*.md`, and refuses edits to a `CLAUDE.md` that only points at `AGENTS.md` (see below). |
| MCP | context7, semble, chrome-devtools | Bundled in `.mcp.json`, start automatically. CodeGraph is set up by `install.sh`. |

## Pre-write guard: guidance files are never changed silently

A mechanical gate, not just an instruction the model might skip. `pre-write-guard` runs before every `Write`, `Edit`, `MultiEdit` **and** `Bash`. If the target is `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md` and the file already exists, the change is **blocked** (exit 2) and the message sent back to Claude contains:

- the precise change — a unified diff for a whole-file `Write`, or the exact before/after text for a targeted `Edit`/`MultiEdit`,
- an instruction to show it to you verbatim and wait for an explicit yes/no,
- the exact `mkdir`/`printf` command creating a single-use approval marker bound to that change.

Only then does the retried call succeed, and the marker is consumed — so any revision needs a fresh approval. The marker hash binds path + exact change + the file's current content, so it can't be reused for a different change and is invalidated if the file moved on underneath it. No-op changes and brand-new files pass straight through.

If `jq` is missing, the guard exits 2 with a clear message naming the missing dependency, rather than allowing the write.

Verified by running the script against all of it: `Edit`, `MultiEdit` and `Write` each block; approve-then-retry succeeds and consumes the marker; a different change blocks again; a stale marker after the file changed blocks again; unguarded files and no-ops pass. Not yet observed firing inside a live Claude Code session.

Add `.claude/.approved-writes/` to `.gitignore`.

## The three per-repo config files

None are created by installing; they are per repo, and everything works without them (the gates just stay inactive). Three ways to make them: `/dev-flow:init-hooks` (derives them from what the repo documents, then verifies), the `setup-rules` skill (same thing as part of a larger setup), or by hand — they are plain text.

| File | Format | Purpose | Commit it? |
|---|---|---|---|
| `.claude/test-cmd` | shell script body, run as `bash .claude/test-cmd` from the repo root; exit 0 = pass | The stop gate. Runs before Claude may finish any turn that changed files. | Yes — shared team gate |
| `.claude/lint-cmd` | shell script body; receives the **repo-relative path of the edited file as `$1`** | Per-edit check. Replaces the built-in native checks — only needed for containerised or custom toolchains. | Yes |
| `.claude/test-cmd-retries` | a single number, e.g. `3` | How many times the stop gate blocks before giving up loudly. Default 3 when absent. | Personal preference |

No shebang and no `chmod` needed — both are invoked through `bash`.

By hand:

```bash
# host toolchain
printf 'vendor/bin/phpunit --stop-on-failure && vendor/bin/phpstan analyse --no-progress\n' > .claude/test-cmd

# containerised toolchain (-T because hooks have no TTY)
printf 'docker compose exec -T php vendor/bin/phpunit --stop-on-failure\n' > .claude/test-cmd
cat > .claude/lint-cmd <<'EOF'
set -u
inside="/var/www/html/$1"
case "$1" in
  *.php) docker compose exec -T php php -l "$inside" || exit 1 ;;
esac
EOF

printf '2\n' > .claude/test-cmd-retries     # optional; default is 3
```

Then verify the way `/dev-flow:init-hooks` does — a gate you have not seen fail is not a gate:

```bash
bash .claude/test-cmd; echo "expect 0 -> $?"
bash .claude/lint-cmd src/Some/File.php; echo "expect 0 -> $?"
printf '<?php bad syntax ' > tmp-check.php
bash .claude/lint-cmd tmp-check.php; echo "expect non-zero -> $?"; rm tmp-check.php
```

Keep `test-cmd` fast (ideally under ~60s): unit tests, lint and type checks — not integration or e2e suites. Add `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log` and `.claude/.approved-writes/` to `.gitignore`.

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

## Status line (claude-powerline, cosmetic)

`bash install.sh --with-powerline` adds [Owloops/claude-powerline](https://github.com/Owloops/claude-powerline) — a powerline-style status line for Claude Code. Purely cosmetic; nothing else here depends on it.

The installer adds its marketplace and installs the plugin (both verified working). **One step stays manual**, because it is an interactive wizard a script cannot drive:

```text
/powerline        # run this inside Claude Code
```

That writes `~/.claude/claude-powerline.json` and wires `statusLine` into your settings. The plugin ships exactly one component — that wizard command.

- **It replaces any status line you already have.** The installer detects an existing `statusLine` in `~/.claude/settings.json`, prints it, and tells you to back it up first.
- **Needs a Nerd Font** for the glyphs, or the segments render as boxes — use `--charset=text` instead.
- Themes: `dark` (default), `light`, `nord`, `tokyo-night`, `rose-pine`, `gruvbox`, `custom`. Styles: `minimal`, `powerline`, `capsule`, `tui`. Visual configurator at powerline.owloops.com.
- Skipping the wizard, the manual equivalent is a `statusLine` entry in `settings.json`:
  ```json
  { "statusLine": { "type": "command", "command": "npx -y @owloops/claude-powerline@latest --style=powerline" } }
  ```

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

# 5. claude-powerline, only if you installed it with --with-powerline
claude plugin uninstall claude-powerline@claude-powerline
claude plugin marketplace remove claude-powerline
#    Then remove the statusLine it added, or restore your backup:
#      jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json
#      rm -f ~/.claude/claude-powerline.json

# 6. claude-mem, only if you installed it with --with-memory.
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

Verified: steps 2, 3 and 5 were run for real (dev-flow, Superpowers and claude-powerline all uninstalled and their marketplaces removed cleanly, confirmed with `claude plugin list` / `marketplace list`). Steps 4 and 6 (CodeGraph, claude-mem) are **not** verified — they depend on what those tools registered on your machine, so check `claude mcp list` between steps rather than trusting the commands blindly. The `settings.json` / `claude-powerline.json` cleanup in step 5 is also unverified; check the file before and after.

## Troubleshooting

**`install.sh` freezes / hangs with no output.** Fixed in v1.5.1 — upgrade. The cause: `claude plugin install` requires `-y` when stdout is not a TTY (which is always true inside a script), and v1.5 and earlier also sent output to `/dev/null`, so the confirmation prompt was invisible while the command waited for a keystroke. It looked frozen but was asking a question you couldn't see. The installer now passes `-y`, runs every command with `</dev/null` so nothing can block on a hidden prompt, sets `GIT_TERMINAL_PROMPT=0` so a private-repo clone errors instead of waiting for credentials, and wraps each step in `timeout` so a stall becomes a visible `TIMED OUT` warning. If you are stuck on an older copy, run the commands by hand: `claude plugin marketplace add <path>` then `claude plugin install -y dev-flow@dev-flow-marketplace`.

**`setup-rules` changed AGENTS.md / CLAUDE.md without asking me.** Fixed in v1.8 — upgrade. Before that, `pre-write-guard` only matched the `Write` tool, so a targeted `Edit`/`MultiEdit` on an existing guidance file bypassed the gate entirely and the "show a diff and ask" step was only an instruction the model could skip. The hook now matches `Write|Edit|MultiEdit|Bash`. If a change still lands unannounced, check:
```
jq '.hooks.PreToolUse' ~/.claude/plugins/cache/*/dev-flow/*/hooks/hooks.json
claude plugin list | grep -A3 dev-flow
```
`/dev-flow:init-hooks` now proves the guard end to end, so run that first.

**The pre-write guard never fires / an edit to AGENTS.md went through.** You are almost certainly running a stale cached copy of the plugin. Before v1.8 the `PreToolUse` matcher was `Write` alone, so every `Edit` bypassed it entirely, and the guard did not cover `AGENTS.md` at all — only `CLAUDE.md` and `.claude/rules/*.md`. A plugin installed once stays frozen: a marketplace added from a local directory or a non-Anthropic GitHub repo has auto-update **off** by default, and even after an update the running session keeps the old plugin path until `/reload-plugins`. Check with `claude plugin list` and the cache path above, then fix it:
```
claude plugin marketplace update dev-flow-marketplace
claude plugin update dev-flow@dev-flow-marketplace
/reload-plugins        # or start a new session
```
From v1.10.0 the block message's second line names the version that fired, so a stale copy is self-reporting.

**A step reports TIMED OUT.** Run that one command on its own to see what it wants — usually network (`npm install -g`, a GitHub clone) or credentials for a private marketplace repo. `--skip-superpowers` and `--skip-codegraph` let you get the rest installed meanwhile.

**Installed but nothing appears.** Restart Claude Code, then `claude plugin list` and `claude plugin details dev-flow`. The inventory should read: Skills 13 (9 skills + the 4 commands), Agents 3, Hooks 3 (PreToolUse, PostToolUse, Stop), MCP servers 3.

**Context cost.** `claude plugin details dev-flow` reports roughly **1,700 always-on tokens** per session for the whole plugin, with each skill's body loaded only when it fires. Worth checking yourself if you stack several plugins.

## Known limits

- Install, component registration (`claude plugin details`) and the uninstall sequence below are now verified by actually running them. What is still **not** verified is the workflow itself in a live session: `/dev-flow:spec` → `/dev-flow:build`, the hooks firing inside a real turn, and whether a command's `model:` frontmatter pins the model as documented. Trial it on a small task before rolling out.
- CodeGraph and Semble build indexes on first use and can be slow on large repos.
- The stop gate does nothing without a per-repo `.claude/test-cmd`; the retry/give-up mechanism above is new and tested standalone (not yet inside a live Claude Code stop-hook cycle).
- With a containerised toolchain and no `.claude/lint-cmd`, per-edit checks skip silently — which means the stop gate (`.claude/test-cmd`) is your only automated check, so it is worth setting up properly there.
- Whether Claude Code loads `AGENTS.md` natively is version-dependent and unverified here; that is why `setup-rules` adds a `CLAUDE.md` symlink or import pointer rather than assuming.
- The `ALLOW-CLAUDE-MD-EDIT` override is a guardrail, not a security boundary: the hook cannot tell who created the file, it only checks that it exists. The skill is instructed not to create it.
- `Write`/`Edit` are gated mechanically; the `Bash` bypass is now closed for the common shapes (heredoc, `>`/`>>`, `tee`, `sed -i`/`perl -i`, `cp`, `mv`, `install`, `rm`/`unlink`/`shred`, `dd`, `truncate`, `git restore`/`git checkout -- `, `python -c`). This is command-text matching, a guardrail, not a boundary — obfuscated command text (a variable, a script file, base64), `node -e`/`ruby -e` one-liners that write files, and a directory-target `cp`/`mv` (e.g. `cp x.md .claude/rules/` without naming the destination file, so the guard never sees a `.md` filename to match) all still get through. The guard overall remains a guardrail against model error, not a security boundary.
- Rule templates are starting points: `init-rules` verifies them against the repo, but review the result.
- No persistent memory (add `claude-mem` separately if wanted) and no usage dashboard.
- `security-review` and `db-migration` give structured checks, not compliance certification or a substitute for DBA and security sign-off.
- `ok build` is pattern-matched by the model reading `spec.md`'s own instructions, not by the Claude Code harness — it (and near-equivalents like "build it") gets recognised because the command tells the model to look for an approval reply, not because of any special runtime feature.
