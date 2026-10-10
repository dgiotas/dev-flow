<div align="center">

# dev-flow

### Spec-then-build for Claude Code: a strong model plans and reviews, a cheaper one codes

Quality-gate hooks, a guard on your guidance files, bundled MCP servers and nine dev skills, in one plugin.<br>
**Planned work. Enforced gates. Reviewed diffs.**

</div>

## Why dev-flow

Agents left to their own devices code fast and skip the parts that keep code maintainable: planning before the diff, and checking after it. dev-flow is a Claude Code plugin that puts a strong model in charge of the plan and the review, and a cheaper model in charge of typing it in. `/dev-flow:spec` has Opus write a spec and a test-first, task-by-task plan you approve; replying `ok build` or running `/dev-flow:build` has Sonnet implement it one task at a time, then hands the finished diff back to Opus for review. Two hooks enforce the parts an agent would otherwise skip: a pre-write guard blocks unapproved edits to `AGENTS.md`/`CLAUDE.md`/`.claude/rules/*.md`, and a stop gate blocks "done" while `.claude/test-cmd` fails; where an organization's managed settings block plugin hooks, dev-flow falls back to explicit, instruction-level checks instead (see [Managed settings: hooks disabled by your organization](#managed-settings-hooks-disabled-by-your-organization)). It also bundles MCP servers and nine dev skills, and is built to sit alongside obra/superpowers.

## Getting Started

### Prerequisites

Required: Claude Code, `jq`, `git`, `curl` (for the one-liner installer). Optional: Node 18+ (needed by the Context7 and Chrome DevTools MCP servers, and by `npm` for the bundled CodeGraph MCP server) and `uv` (needed by the Semble MCP server), native language tools (see *Containerised toolchains* — you do **not** need them installed on the host). Hooks run through `bash`, so no `chmod` is needed.

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash
```

Installs Superpowers + dev-flow + CodeGraph, non-interactively. Optional add-ons via the same one-liner with a flag appended:

```bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash -s -- --with-memory
```

For the interactive checklist instead of the defaults:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh)
```

**Specific version:**

```bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | DEV_FLOW_VERSION=1.12.0 bash
```

Installs git tag `dev-flow--v1.12.0` (available from 1.12.0 on; see the tag list at https://github.com/dgiotas/dev-flow/tags). An unknown version fails loudly with git's `Remote branch … not found`. Switching an already-installed version: see "Switching version / downgrading" below.

**From a clone:**

```bash
git clone https://github.com/dgiotas/dev-flow.git && cd dev-flow && bash install.sh
```

On a terminal, a plain `bash install.sh` shows an interactive checklist to pick components; passing any selection flag or running non-interactively (`-y`/`--non-interactive`, CI, or piped input) skips the prompt. `--dry-run` does not skip the prompt: on an interactive terminal it still shows the checklist, then exits after printing the Plan instead of installing anything.

**Manual** (inside a Claude Code session):

```text
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
/plugin marketplace add dgiotas/dev-flow                  # pin a version: dgiotas/dev-flow#dev-flow--v1.12.0
/plugin install dev-flow@dev-flow-marketplace
```

<details>
<summary>Installer flags</summary>

| Flag | Effect |
|---|---|
| `--with-memory` | also install claude-mem for cross-session recall (opt-in) |
| `--with-powerline` | also install claude-powerline (cosmetic status line, opt-in) |
| `--skip-superpowers` | don't install Superpowers |
| `--skip-codegraph` | don't install the CodeGraph MCP server binary |
| `-y`, `--yes`, `--non-interactive` | force non-interactive mode even on a TTY |
| `--no-color` | disable coloured output |
| `--dry-run` | show the plan, then exit 0 without installing anything |
| `--help` | print usage and exit |
| `DEV_FLOW_VERSION=x.y.z` | env var: install that tagged release (`dev-flow--vx.y.z`; available from 1.12.0) |

Re-running is safe. Every step is time-limited and shows its own output on failure, so it reports errors instead of stalling.

</details>

<details>
<summary>What the installer does</summary>

1. Checks prerequisites (`claude`, `jq`, `git`, optionally `node`, `uv`, `codegraph`, `php`, `docker`, `timeout`).
2. Adds the Superpowers and dev-flow marketplaces, then installs both plugins.
3. Installs the CodeGraph MCP server binary (`npm install -g @colbymchenry/codegraph`), unless skipped.
4. Optionally installs claude-mem for cross-session memory (`--with-memory`, off by default).
5. Optionally installs claude-powerline for a status line (`--with-powerline`, off by default).
6. Verifies with `claude plugin list` and prints next steps.

</details>

<details>
<summary>Switching version / downgrading</summary>

A marketplace can't be re-added from a different source or tag — `claude plugin marketplace add` refuses with `Cannot add marketplace "dev-flow-marketplace": its network source differs…`. To switch version (including downgrading), run `uninstall.sh` first, then the installer with the `DEV_FLOW_VERSION` you want (or none, for latest `main`):

```bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | DEV_FLOW_VERSION=1.12.0 bash
```

Per-repo files (`.claude/test-cmd`, `.claude/rules`, etc.) are untouched either way.

</details>

<details>
<summary>Uninstalling</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash
```

Removes only the dev-flow plugin and marketplace — and, since context7/semble/chrome-devtools/codegraph are registered in the plugin's own `.mcp.json`, the bundled MCP servers go with it. Flags, each a one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash -s -- --remove-tools
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash -s -- --remove-superpowers
curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash -s -- --dry-run
```

`--remove-tools` also removes claude-powerline (plugin + marketplace) and the CodeGraph binary (`npm uninstall -g @colbymchenry/codegraph`). `--remove-superpowers` also removes Superpowers (plugin + marketplace). `--dry-run` prints what would run without removing anything. From a clone: `bash uninstall.sh …` with the same flags.

**Manual leftovers.** Things the script doesn't touch:

```bash
# 1. See what is actually installed before removing anything
claude plugin list
claude plugin marketplace list
claude mcp list

# 4. CodeGraph — only relevant if you installed before v1.11.0, when
#    install.sh registered it globally in ~/.claude.json, outside the plugin.
#    From v1.11.0 the plugin-scoped one is removed with the plugin.
#    Confirm the exact server name from `claude mcp list` first.
claude mcp remove codegraph
npm uninstall -g @colbymchenry/codegraph

# 5. statusLine, only if you installed claude-powerline with --with-powerline:
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json
rm -f ~/.claude/claude-powerline.json

# 6. claude-mem, only if you installed it with --with-memory.
#    It installs its own hooks and a background worker, so use its own uninstaller:
npx claude-mem uninstall        # if this fails, see https://github.com/thedotmack/claude-mem
claude mcp list                 # then remove any leftover entry it registered
```

Then check `~/.claude/settings.json` for any leftover `hooks` entries mentioning `claude-mem` or `codegraph` (dev-flow's own hooks live inside the plugin and disappear with it), and restart Claude Code.

**Per-repo leftovers.** Uninstalling the plugin does not touch files it wrote into your repos. Remove per repo as wanted:

```bash
rm -f  .claude/test-cmd .claude/test-cmd-retries .claude/lint-cmd
rm -rf .claude/.approved-writes .claude/.stop-gate-state .claude/stop-gate-giveup.log .claude/.devflow-state.json
rm -rf .claude/rules            # only if these were generated and you don't want them
rm -rf .codegraph               # CodeGraph index
# .claude/specs and .claude/plans are local work product (add them to .gitignore) — keep them
```

`AGENTS.md` / `CLAUDE.md` edits are in git, so revert those with `git diff` / `git checkout --` as normal.

If you kept a backup before first installing (`cp -r ~/.claude ~/.claude.bak-<date>`, `cp ~/.claude.json ~/.claude.json.bak-<date>`), restoring those is the fastest full reset.

Verified: `uninstall.sh`'s default path — removing the dev-flow plugin and marketplace — was run for real against an isolated `CLAUDE_CONFIG_DIR` temp config, confirming dev-flow was installed and then fully removed, checked with `claude plugin list` / `marketplace list`. `--remove-tools` and `--remove-superpowers` were verified against the stubbed test rig (a fake `claude`), not by actually removing claude-powerline, CodeGraph or Superpowers from a real install. The manual leftover items above (1, 4, 5, 6) are **not** verified — they depend on what those tools registered on your machine, so check `claude mcp list` between steps rather than trusting the commands blindly, and check the `settings.json` / `claude-powerline.json` cleanup in step 5 before and after.

</details>

<details>
<summary>Try without installing</summary>

From a clone, without registering any marketplace:

```bash
claude --plugin-dir ./plugins/dev-flow
```

</details>

### First Steps

Restart Claude Code, then verify with `/plugin`, `/mcp`, `/agents`, `/hooks`. Then, once per repo you work in:

```text
/dev-flow:onboard                # runs the whole per-repo sequence below in order, pausing for guard approval
```

Or run the steps yourself:

```text
/dev-flow:init-codegraph        # structure index for the codegraph MCP server (also adds .codegraph/ to .gitignore)
"Set up AGENTS.md for this repo" # setup-rules skill (guidance file + rules + hook commands in one go)
/dev-flow:init-hooks            # reads your AGENTS.md/Makefile/CI, writes + verifies .claude/test-cmd (and lint-cmd)
/dev-flow:init-rules php        # or java | python | node | all: copies verified rule templates into .claude/rules
```

The pre-write guard fires on **every** run (where hooks run) — by design at step 0's probe (that is the liveness proof), which leaves a throwaway `.claude/rules/devflow-guard-probe.md` the command cannot delete, so it hands you a one-line `rm`; and again at any later write to an `AGENTS.md`/`CLAUDE.md`/`.claude/rules/*.md` that already exists. That is intended, not a bug (not yet run end to end in a live session).

## Ways of Working

Three peer paths. The hooks (guard, per-edit checks, stop gate, compaction snapshot) apply on all of them, unless your organization's managed settings block plugin hooks — see [Managed settings: hooks disabled by your organization](#managed-settings-hooks-disabled-by-your-organization).

| Path | What it adds |
|---|---|
| Plain request | Skills fire from the request itself — "how does X work" (investigate), "this is broken" (fix-bug), "commit this" (git-workflow), "review this for security", "is this migration safe", "verify it's done". |
| `/dev-flow:spec` → reply `ok build` | Plan, approve, build in the same conversation; orchestration stays on the session model. |
| `/dev-flow:spec` → `/dev-flow:build <slug>` | Same, but orchestration switches to Sonnet. |

```text
/dev-flow:spec add rate limiting to the ticket search API
   -> Opus checks 7 ambiguity categories against the code; only a blocking unknown stops to ask you (one message, at most five questions)
   -> review and edit .claude/plans/<slug>.md; answer any question to override its default
   -> reply "ok build", or run /dev-flow:build <slug> yourself
```

## Workflows

| Command | Use it when | What it does |
|---|---|---|
| `/dev-flow:spec <feature>` | you want an approved plan before any code | Opus `spec-architect` investigates, runs the [clarification check](#clarification-check), writes `.claude/specs/<slug>.md` (ending in "Assumptions and open questions") + `.claude/plans/<slug>.md` with test-first tasks. No code. |
| `ok build` (reply after spec) | the plan is right; keep going in this conversation | Runs the build procedure inline: orchestration on the current model, coding on Sonnet `implementer`, review on Opus `reviewer`. |
| `/dev-flow:build <slug>` | you want the build phase orchestrated by the cheaper model | Sonnet asks branch (default) or worktree and whether to start from the current (default) or the default branch, runs tasks via `implementer` there, then `verify-done`, then Opus `reviewer`. Never merges or pushes (`commands/build.md` steps 2–7). |
| `/dev-flow:onboard` | first time in a repo | CodeGraph index, then guidance file + rules, then verified hook commands, pausing at every guarded write. |

Plans and specs live in `.claude/specs/` and `.claude/plans/` (previously under `docs/`); they are local work product, not committed, so add both to your repo's `.gitignore` (otherwise they show as untracked changes and make the stop gate run tests on Q&A turns). If you choose a worktree when the build asks, it is created at `.claude/worktrees/<slug>` on a new branch from the current or the default branch, whichever you pick, with copies of the plan and spec; gitignore `.claude/worktrees/` too. New branches, from the build or the `git-workflow` skill, are named `[<prefix>/]<type>/<name>`: `<type>` is `feature`, `fix`, `chore` or `refactor`, picked from what the work is, and `<name>` is the plan slug or a short slug. To give a project a prefix, commit a one-line `.claude/branch-prefix` file, for example `team-web`, so a feature branch becomes `team-web/feature/<name>`. Only the branch carries the prefixes; a worktree's directory stays `.claude/worktrees/<name>`.

After upgrading to 1.15.0, move your existing `plans` and `specs` folders from `docs/` into `.claude/` so build and the compaction snapshot find them.

In 1.18.0 new feature branches are named `feature/...` instead of `feat/...`. Existing branches are not renamed; if your tooling or CI matches `feat/*`, make it accept `feature/*` too.

Model pinning per stage is documented in frontmatter but not verified live — see Model routing.

## Other Commands, Skills and Agents

| Name | Kind | Purpose |
|---|---|---|
| `/dev-flow:init-rules <stack>` | Command | Adapts stack rule templates into the repo's `.claude/rules`. |
| `/dev-flow:init-hooks` | Command | Derives `.claude/test-cmd` / `lint-cmd` from your AGENTS.md, Makefile, manifests or CI, then verifies them. |
| `/dev-flow:init-codegraph` | Command | Builds/refreshes the local CodeGraph index for this repo. |
| `/dev-flow:threat-model [scope]` | Command | Maps the API surface to OWASP API Top 10 / CWE with cited evidence via `threat-modeler`; saves `docs/threats/<slug>.md` for review. Report-only. |
| `spec-architect` (Opus) | Agent | Investigates, resolves ambiguities, writes spec and plan. |
| `implementer` (Sonnet) | Agent | Implements one plan task test-first, escalates with `BLOCKED`. Tool allowlist: read, edit, write, Bash, codegraph and context7; no web fetch or search, no subagents, no semble or browser tools. |
| `reviewer` (Opus) | Agent | Diff review against spec. No shell or file-writing tools (Read, Grep, Glob, codegraph), so it cannot change the tree or git state; `/dev-flow:build` passes in the diff, commit log and test-command result. |
| `threat-modeler` (Opus) | Agent | Read-only and offline (no file-writing, shell or web tools); returns the threat model as text. |
| `code-intel` | Skill | Picks Semble, CodeGraph, Context7, DevTools or `rg`. |
| `investigate` | Skill | Read-only, cited codebase Q&A. |
| `fix-bug` | Skill | Red test, root cause, minimal fix, verify. |
| `verify-done` | Skill | Evidence before saying "done". |
| `setup-rules` | Skill | Generates `CLAUDE.md` and rules from the repo. |
| `dead-code-audit` | Skill | Report-only cleanup audit. |
| `git-workflow` | Skill | Branches (named `[<prefix>/]<type>/<name>`, asking branch or worktree, and current or default branch as the base, for a new one), commits, PR text, review feedback. Never pushes unasked. |
| `security-review` | Skill | Auth, injection, secrets, PCI-adjacent and dependency checklist. Report-only. Points to `/dev-flow:threat-model` for whole-surface modelling. |
| `db-migration` | Skill | Expand/migrate/contract, backfills, rollback. Never runs against shared DBs. |
| `post-edit-check` | Hook | Syntax and lint on each edited file (PHP, Python, TS/JS, JSON). |
| `stop-gate` | Hook | Runs `.claude/test-cmd` before Claude can finish, retrying up to 3 times before giving up (see below). |
| `pre-write-guard` | Hook | Gates every change (Write/Edit/MultiEdit, plus Bash commands that look like they write the file directly) to `AGENTS.md` / `CLAUDE.md` / `.claude/rules/*.md`, and refuses edits to a `CLAUDE.md` that only points at `AGENTS.md` (see below). |
| `pre-compact-snapshot` | Hook | Before compaction, saves the active plan, checklist counts, git branch/counts and BLOCKED lines to `.claude/.devflow-state.json` — no file contents (see below). |
| `session-start-restore` | Hook | At session start, injects that snapshot (≤15 lines) if it is under 24 h old. |
| context7, semble, chrome-devtools, codegraph | MCP | All four bundled in `.mcp.json`, start automatically. CodeGraph additionally needs its binary on PATH (`install.sh` installs it) and a per-repo `codegraph init` for results. |

## Documentation

Deeper detail on the gates, guidance files, per-repo config and integrations referenced above.

### Pre-write guard

A mechanical gate, not just an instruction the model might skip. `pre-write-guard` runs before every `Write`, `Edit`, `MultiEdit` **and** `Bash`. If the target is `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md` and the file already exists, the change is **blocked** (exit 2) and the message sent back to Claude contains:

- the precise change — a unified diff for a whole-file `Write`, or the exact before/after text for a targeted `Edit`/`MultiEdit`,
- an instruction to show it to you verbatim and wait for an explicit yes/no,
- the exact `mkdir`/`printf` command creating a single-use approval marker bound to that change.

Only then does the retried call succeed, and the marker is consumed — so any revision needs a fresh approval. The marker hash binds path + exact change + the file's current content, so it can't be reused for a different change and is invalidated if the file moved on underneath it. No-op changes and brand-new files pass straight through.

If `jq` is missing, the guard exits 2 with a clear message naming the missing dependency, rather than allowing the write.

Verified by running the script against all of it: `Edit`, `MultiEdit` and `Write` each block; approve-then-retry succeeds and consumes the marker; a different change blocks again; a stale marker after the file changed blocks again; unguarded files and no-ops pass. Not yet observed firing inside a live Claude Code session.

Add `.claude/.approved-writes/` to `.gitignore`.

### AGENTS.md or CLAUDE.md

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

#### When CLAUDE.md is only a pointer, editing it is refused outright

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

### Stop gate

`stop-gate` blocks Claude from finishing while `.claude/test-cmd` fails, up to a cap, then gives up loudly instead of blocking forever:

- Each failure increments a counter in `.claude/.stop-gate-state` and is reported back to Claude as `attempt N/max (harness cap H)`, with the number of consecutive stop-hook continuations so far.
- After the cap (default **3**) it stops blocking, appends a `Quality gate: giving up...` banner to `.claude/stop-gate-giveup.log`, and emits a one-line `systemMessage` warning (`Quality gate gave up: … Work is NOT verified.`), which per the Claude Code hooks docs is shown to you. The full banner is only in the log: per those docs a hook's stderr on exit 0 is not shown, so Claude itself should never see it.
- A pass at any point clears the counter. The next failure after a give-up starts a fresh cycle at attempt 1.
- Change the cap per repo: put a number in `.claude/test-cmd-retries`, or set `DEV_FLOW_STOP_GATE_MAX` in your shell.
- Add `.claude/.stop-gate-state` and `.claude/stop-gate-giveup.log` to `.gitignore`.

#### Claude Code's own stop-hook cap

Claude Code documents a separate cap ([Stop input](https://code.claude.com/docs/en/hooks#stop-input)). After Stop hooks have continued a turn 8 times in a row, it overrides the next block and ends the turn with a warning of its own. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` changes the cap, and `0` turns it off. The count is shared by every Stop hook (other plugins, your settings hooks, `/goal`), not kept per hook.

- The gate counts consecutive continuations from the payload's `stop_hook_active` and stores the count next to the failure counter (`<failures> <continuations>`).
- Its retry cap stays below the harness cap: a configured value at or above it is reduced to cap − 1, and the first block message says so.
- If one more block would reach the harness cap, because other Stop hooks have already kept the turn going, it gives up with the banner instead of blocking.
- It reads `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` from its own environment and assumes 8 when the variable is unset or not a number.

When dev-flow is the only Stop hook and both caps are at their defaults (3 and 8), the cap logic never triggers (the message text and state-file format do change): the gate gives up long before the harness cap. It matters when other Stop hooks block in the same session, or when you set the retry cap at or above the harness cap.

The cap's behaviour is taken from the Claude Code docs and tested by running the script directly, not yet observed in a live session. The same goes for what is shown on give-up (the `systemMessage`, and stderr on exit 0 not being shown).

### Compaction snapshot

Before compaction (`PreCompact`, manual or auto), `pre-compact-snapshot` writes `.claude/.devflow-state.json`. On `SessionStart` (`startup|resume|compact`), `session-start-restore` injects a summary of at most 15 lines into the session if that file is under 24 hours old. Neither hook can block anything: failures are silent and both exit 0.

Captured:

- the schema version and `saved_at`,
- the most recently modified `.claude/plans/*.md` (repo-relative path and slug) and its `- [ ]` / `- [x]` checklist counts, which are `null` if it has none,
- the git branch, short HEAD, and **counts** of staged, unstaged and untracked files,
- the stop-gate attempt counter and `giveup_logged_at`, the give-up log's modification time (the stop gate records no session id, so "gave up in this session" can't be told reliably),
- up to 10 plan lines containing `BLOCKED`, with absolute paths replaced by `<path>` on a best-effort basis and each cut to 200 characters.

Not captured, deliberately: file contents or diffs, file names (only counts), source code, conversation or prompt text, the hook payload (`session_id`, `transcript_path`, `cwd`, `custom_instructions`), absolute paths outside BLOCKED lines, and anything outside `.claude/plans/`, git metadata and the two stop-gate files. The snapshot stores no code, diffs, file names, prompts or payload text; the only free text is the BLOCKED lines.

The injected text looks like this:

```text
dev-flow state saved before the last context compaction at 2026-10-02T09:14:03Z; .claude/plans is the source of truth.
Active plan: .claude/plans/test-feature.md (slug test-feature); 2 of 4 checklist items checked.
Git: branch feature/test-feature at 1a2b3c4; 1 staged, 1 unstaged, 1 untracked files.
Stop gate: 2 failed attempt(s) recorded; give-up log last written at 2026-10-02T08:50:41Z.
Blocked lines in the plan:
- BLOCKED: something
```

Caveats:

- dev-flow's own plans mark tasks with `## Task N` headings, and only their acceptance criteria are checkboxes, which `/dev-flow:build` doesn't tick, so the counts show acceptance items.
- The `implementer` reports `BLOCKED` in chat rather than writing it into the plan, so blocked lines appear only if someone records them there.
- BLOCKED lines are copied verbatim apart from that best-effort path rewrite: paths after `[ { < , ; |`, `~/`, `$HOME`, Windows drive paths and paths glued to a word survive, so do not put secrets, card data or sensitive paths in BLOCKED lines.
- "Most recently modified" can pick a newer plan than the one being built. The injected text names the file, and the plan stays the source of truth.
- `jq` is required; without it nothing is written or injected.
- In [hookless mode](#managed-settings-hooks-disabled-by-your-organization) neither hook runs, so the feature is simply absent.

Add `.claude/.devflow-state.json` to `.gitignore`. It is local state and should not be committed; the stop gate does not count it as an untracked change.

Verified by running both scripts against a throwaway repo; not yet observed in a live compaction.

### Managed settings: hooks disabled by your organization

If your organization sets `allowManagedHooksOnly: true` (or `disableAllHooks: true`) in Claude Code managed settings, plugin hooks are blocked — none of dev-flow's hooks (pre-write guard, per-edit check, stop gate, compaction snapshot) run. Side effects: the optional claude-powerline status line doesn't show either (`statusLine` is narrowed to managed settings under the same policy), and claude-mem, which is hook-based, doesn't record. MCP servers, skills, agents and commands are unaffected — only hooks and the status line are blocked. See [the hooks docs](https://code.claude.com/docs/en/hooks).

The real fix is for your admin: force-enable dev-flow in managed settings, because hooks belonging to a force-enabled plugin are exempt from `allowManagedHooksOnly`:

```json
{ "enabledPlugins": { "dev-flow@dev-flow-marketplace": [true] } }
```

If the org also sets `strictKnownMarketplaces`, the dev-flow marketplace needs to be listed there too. See [the settings reference](https://code.claude.com/docs/en/settings-reference). (Per the Claude Code docs; not verified in a managed session.)

Otherwise, dev-flow falls back to **hookless mode**. `/dev-flow:onboard` and `/dev-flow:init-hooks` detect the dead guard probe, run `scripts/hooks-policy.sh` — which reads `managed-settings.json`, `managed-settings.d/*.json` and the macOS managed-prefs plist; it is not server-managed policy, so also check `/status` → Setting sources — and continue instead of stopping (this flow has not yet been run end-to-end in a live managed-settings session; if you hit unexpected behaviour, please report it):

| Hook | Hookless substitute | Strength |
|---|---|---|
| pre-write guard | `ask` rules in the shared, committed `.claude/settings.json` for `Edit(AGENTS.md)`, `Edit(CLAUDE.md)`, `Edit(.claude/rules/**)` (+ `deny Edit(/CLAUDE.md)` when it's a pointer), plus a guidance instruction | Claude Code permission prompt on every Write/Edit, for everyone in the repo (people whose hooks run get this on top of the guard); not Bash writes; ignored under `allowManagedPermissionRulesOnly` |
| per-edit check | `.claude/lint-cmd`, always written in hookless mode, run by `implementer`, `verify-done` and the guidance "Quality gates" section | instruction-level |
| stop gate | `.claude/test-cmd`, run by `implementer` and `verify-done`, by the build orchestrator for `reviewer` (which passes in the result), and the guidance section | instruction-level; nothing blocks the end of a plain turn |
| compaction snapshot | none — compaction is triggered by the harness, so there is nothing for an instruction to hook into; the plan in `.claude/plans/` remains the record | not available |

Hookless mode is weaker: the model can skip an instruction, and only the admin fix above restores the mechanical gates.

The `ask` rules are committed to the repo on purpose, as a shared backstop for everyone who works there — review that diff before committing it, since contributors whose hooks run will see a permission prompt in addition to the guard.

### Per-repo config files

None are created by installing; they are per repo, and everything works without them (the gates just stay inactive). Three ways to make them: `/dev-flow:init-hooks` (derives them from what the repo documents, then verifies), the `setup-rules` skill (same thing as part of a larger setup), or by hand — they are plain text.

| File | Format | Purpose | Commit it? |
|---|---|---|---|
| `.claude/test-cmd` | shell script body, run as `bash .claude/test-cmd` from the repo root; exit 0 = pass | The stop gate. Runs before Claude may finish any turn that changed files. | Yes — shared team gate |
| `.claude/lint-cmd` | shell script body; receives the **repo-relative path of the edited file as `$1`** | Per-edit check. Replaces the built-in native checks — only needed for containerised or custom toolchains. | Yes |
| `.claude/test-cmd-retries` | a single number, e.g. `3` | How many times the stop gate blocks before giving up loudly. Default 3 when absent; reduced to stay below the harness cap (see [Stop gate](#stop-gate)). | Personal preference |
| `.claude/security-targets.json` | JSON, schema `dev-flow/security-targets/v1` (copy `templates/security-targets.example.json`) | Which non-production targets future load and active-security agents may touch, and the ceilings. No file, no run. See [Security targets config](#security-targets-config). | Yes. If your .gitignore ignores `.claude/`, add `!.claude/security-targets.json` |
| `docs/threats/<slug>.md` | Markdown, written by `/dev-flow:threat-model` | Threat model awaiting human review ("Reviewed by" blank until signed off). | Yes, through a normal PR |

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

Keep `test-cmd` fast (ideally under ~60s): unit tests, lint and type checks — not integration or e2e suites. Add `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log`, `.claude/.devflow-state.json`, `.claude/.approved-writes/`, `.claude/plans/` and `.claude/specs/` to `.gitignore`.

### Containerised toolchains

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

### MCP servers

All four are registered the moment the plugin is installed — none of them need a separate `/plugin` step or a manual `.mcp.json` edit. Whether anything *else* is needed depends on how each one's command is wired:

| Server | Extra setup? |
|---|---|
| `context7` | None. `npx -y @upstash/context7-mcp` fetches and runs the package itself on first use (needs Node). |
| `chrome-devtools` | None. `npx chrome-devtools-mcp@latest` fetches and runs itself on first use (needs Node). |
| `semble` | None. `uvx --from semble[mcp] semble` fetches and runs itself on first use (needs `uv`/`uvx`). |
| `codegraph` | Yes. Its `.mcp.json` command (`codegraph serve --mcp`) calls the `codegraph` binary directly rather than through a fetcher like `npx`/`uvx`, so it must already be on PATH or the server won't connect. `install.sh` installs it for you (section 3, `npm install -g @colbymchenry/codegraph`, skipped with `--skip-codegraph`); otherwise run that command yourself. Per repo, also run `codegraph init` once — the server connects either way, but has nothing to query until you do. |

Verify any of them with `claude mcp list`: expect `plugin:dev-flow:<name>: ... - ✔ Connected`. `✘ Failed to connect` on `codegraph` means the binary isn't on PATH; on the other three it usually means Node or `uv` is missing (see Getting Started > Prerequisites above).

### Clarification check

The `implementer` follows the plan literally, so an ambiguity that survives into the plan becomes wrong code. Before writing anything, `spec-architect` gives each of seven categories a status:

| Category | Covers |
|---|---|
| Scope boundary | what is explicitly out of scope |
| Acceptance | the observable behaviour that changes; how we know it works |
| Data and contracts | schema, API shape, event payloads; old and new coexisting during rollout |
| Failure behaviour | invalid input, downstream timeout, partial failure |
| Compatibility | existing callers, other services, mixed-version deploys |
| Non-functional | load, latency budget, security- or payment-sensitive areas |
| Reuse | the existing pattern or module to follow |

Each one is `answered` (from the request, the code — cited as `path:line` — or you), `assumed` (a stated assumption the plan is built on), or `blocking` (a wrong guess would throw the work away).

- It settles what it can from the code first and never asks you what the repo already answers.
- It asks at most five questions, as one numbered list in one message, each with the default it will use.
- Only a `blocking` question stops the command before any file is written. Other questions are shown at plan review with their defaults: reply `ok build` to accept them, or answer one to have the spec and plan revised.
- A fully specified request gets `Fully specified: no questions.` and nothing else.

The result is the spec's "Assumptions and open questions" table. `/dev-flow:build` refuses a spec with a `blocking` row, passes the table to every `implementer` call, and `reviewer` flags diffs that contradict it or make decisions it does not record.

The check lives in `agents/spec-architect.md`, because settling categories from the code needs the Opus investigation. Relaying questions lives in `commands/spec.md`, because a subagent cannot talk to you mid-run. It is not a separate skill: it has one user, and a skill would auto-fire on unrelated vague requests. Adapted from the deep-interview skill in [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (MIT); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Threat modelling

`/dev-flow:threat-model [scope]` maps a repo's API surface to the OWASP API Security Top 10 and the CWE classes that apply. The data flow:

```
/dev-flow:threat-model <scope>
  → main session (sonnet): date, sha, guidance file, one WebSearch → baseline line
  → threat-modeler (opus; Read/Grep/Glob/codegraph only) → reply text
  → main session writes docs/threats/<slug>.md verbatim → grep redaction check → summary
```

- **Output and review.** The threat model is written to `docs/threats/<slug>.md` (an existing file is overwritten; git keeps history). It has a blank "Reviewed by" header until a human signs off. Commit it through a normal PR. The command never commits, pushes or opens a PR.
- **Network posture.** The agent has no network tools. The command makes one `WebSearch` for the current OWASP API Security Top 10 edition and passes the result in. If the search is unavailable, denied or inconclusive, the baseline is "2023 (current edition not checked)" and the file says so.
- **What it refuses.** No exploit payloads, no secrets, keys, tokens, card numbers or personal data in the output (`[REDACTED]` instead), and no invented findings: evidence is `path:line`, and a finding is `Confidence: verified` only when the path was traced end to end. When the repo has no API surface the agent replies `NO-SURFACE: <reason>` and nothing is written.
- **Not PCI testing.** Every threat model carries the sentence "This threat model is not penetration testing or ASV scanning and does not satisfy PCI DSS testing requirements; treat it as input to whoever owns compliance."

What is mechanical and what is an instruction:

| Claim | How it is enforced | Holds in hookless mode? |
|---|---|---|
| threat-modeler cannot write files | `tools:` allowlist has no Write/Edit/Bash | yes, mechanical |
| threat-modeler has no network | `tools:` has no Bash/WebFetch/WebSearch/context7/semble | yes, mechanical (codegraph is local) |
| the threat model goes only to `docs/threats/<slug>.md` | command instruction (the main session can write anywhere) | instruction-level |
| no exploit payloads, no secrets in output | agent instruction plus the command's report-only grep | instruction-level, with a mechanical grep as a check |

These are an agent and a command, not hooks, so threat modelling works unchanged in hookless mode.

### Evals

Four billed cases under `plugins/dev-flow/evals/` run `/dev-flow:threat-model src` against a generated fixture repo:

- `threat-bola`: a handler fetches a record by id with no owner check; the model must report a BOLA (API1) finding.
- `threat-no-fp`: the same shape with an owner check; no high-severity BOLA finding may appear.
- `threat-no-surface`: a repo with no network surface; the command must say so.
- `threat-unverified`: authorization is delegated to a gateway the repo does not show; API1 must be marked unverified, name the gateway, and not be reported as verified.

**How to run.** The only supported invocation is `bash ci/eval-run.sh <pr|nightly> <out-dir>`. It is billed, so run it only with approval. It wraps `claude plugin eval` with flags that each matter:

- `--scaffold`: the fixtures are not applied without it.
- `--allow-tools Write Bash`: without them the command cannot write `docs/threats/<slug>.md`. `WebSearch` is deliberately not granted, so runs are deterministic and offline and the baseline line falls back to 2023.
- `--trust-plugin` and `--no-publish`: no interactive trust prompt, and nothing is published.
- `--model` and `--judge-model` are pinned (`DEVFLOW_EVAL_MODEL`, `DEVFLOW_JUDGE_MODEL` override them).
- `--max-cost-usd`: the tier ceiling below (`DEVFLOW_MAX_COST_USD` overrides it).

| Tier | Trigger | Runs | Arms | Gate | Ceiling |
|---|---|---|---|---|---|
| `pr` | same-repo PRs touching `plugins/dev-flow/**`, `ci/**` or the workflow | 1 | with only | every run completes without error and every deterministic grader passes; `llm` verdicts are shown, not gated | $5 |
| `nightly` | manual only (Actions > evals > Run workflow), no schedule | 3 | with and without | not partial, no run errors, no case Δ < 0, mean Δ > 0.25 (`DEVFLOW_MIN_MEAN_DELTA`) | $25 |

**Exit codes:** 0 pass, 1 fail, 2 inconclusive (cost ceiling, auth failure or rate limit; never a pass).

**Cost per full run:** measured on GitHub Actions with Claude Code 2.1.285 on 2026-10-10, one run each. The nightly tier cost $3.32 (24 agent runs, plus $0.08 of judge cost reported separately) and took 9m25s. The PR tier cost $0.84–0.91 and took 2–3 minutes. The ceilings ($25 and $5) were far from reached. Treat these as single samples.

**Falsifiability:** a case whose without-plugin arm passes measures nothing. One nightly run (2026-10-10, 3 runs per arm) found none: mean Δ 0.92, with scores with/without of 0.92/0 (`threat-bola`), 0.92/0 (`threat-no-fp`), 1.00/0.17 (`threat-no-surface`) and 1.00/0 (`threat-unverified`). In one of `threat-no-surface`'s three baseline runs `says-so-regex` passed, so a baseline can say "no surface" by luck. The baseline cannot run `/dev-flow:threat-model`, so a large Δ shows the plugin does something, not that its output is good. This is one sample.

**MCP servers in evals:** they do not start (there is no `evals/mocks/`). The fixtures have no `.codegraph/`, so threat-modeler takes its Grep/Glob path, which is the shipped behaviour on an unindexed repo. The indexed path is not covered by evals.

**1.18.1 note:** earlier eval runs, if any, used no documented invocation. Without `--scaffold` and `--allow-tools Write Bash` they graded an empty workspace in which the command could not write its file.

**CI:** needs `ANTHROPIC_API_KEY` as a repo secret. Fork PRs are skipped. The graders that read the list of created files were removed pending a diagnosis: in the first CI run they failed in all four cases for a reason not yet known. An attempt to upload each run's `trace.jsonl` with the artifact found no file at `/tmp/claude-eval-*/out/`, so the created-file list was not recovered.

**Local runs can fail on Docker symlinks.** Two attempted local runs on one macOS machine (Claude Code 2.1.285) errored before any agent started, at $0 cost, with "the Docker (~/.docker, DOCKER_CONFIG) credential store on this machine holds a symbolic link inside it, so the Bash sandbox cannot reliably exclude it — a Bash-granting evaluation cannot run here". The machine's `~/.docker/cli-plugins/` held symlinks; setting `DOCKER_CONFIG` to an empty directory did not help. Nothing was measured from those attempts. Whether other machines or GitHub-hosted runners are affected is not verified.

### Security targets config

`.claude/security-targets.json` (schema `dev-flow/security-targets/v1`, template `templates/security-targets.example.json`) lists the non-production targets that future load and active-security agents may touch, and the ceilings. A field is required unless marked optional:

| Field | Rule |
|---|---|
| `schema` | exactly `"dev-flow/security-targets/v1"` |
| `authorized_by` | non-empty string |
| `authorized_on` | string `YYYY-MM-DD` |
| `allow` | non-empty array; each entry has a string `name`, an `env` matching `^[A-Za-z0-9_-]+$`, and a `base_url` matching `^https?://[^/?#@[]+([/?#]|$)` (no credentials, no IPv6 literal); `name`, `base_url` and every deny pattern contain no control characters; optional `credential_env` is an array of environment variable names (`^[A-Z_][A-Z0-9_]*$`). Values are never stored |
| `deny_patterns` | array of strings (shell globs matched against the target host) |
| `limits` | object with `max_vus`, `max_duration_seconds` and `max_rps`, each an integer from 1 to 1000000000 |
| `pci_scope` | boolean |
| `notes` | optional string |

The validator `plugins/dev-flow/scripts/security-targets.sh` decides allow or refuse:

```
bash security-targets.sh <target> [--vus N] [--duration SECONDS] [--rps N]
```

`<target>` is an `allow[].name` or an `http(s)://` URL. The config path is `.claude/security-targets.json` under `CLAUDE_PROJECT_DIR` (or the current directory); `DEV_FLOW_SECURITY_TARGETS` overrides it for tests. Output is `key=value` lines ending in `summary=`. Exit 0 means `decision=allow`; every refusal is `decision=refuse`, `reason=<code>` and exit 1, so any error fails closed. IPv6 literal hosts such as `http://[::1]:8080` are not supported and are refused: `reason=usage` for a URL target, `reason=config-invalid` for a `base_url`. Checks run in this order and the first failure wins:

| # | Check | Reason |
|---|---|---|
| 1 | target given; only `--vus/--duration/--rps`, each followed by a decimal integer from 1 to 18 digits with no leading zero; each flag at most once; a URL target has no `@` or `[` (IPv6 literal) in its authority; the target has no control characters | `reason=usage` |
| 2 | `jq` on PATH | `reason=jq-missing` |
| 3 | config file exists, and `CLAUDE_PROJECT_DIR`, if set and non-empty, is enterable (no fallback to the current directory) | `reason=config-missing` |
| 4 | config is valid JSON | `reason=config-malformed` |
| 5 | config matches the schema above | `reason=config-invalid` |
| 6 | `pci_scope` is false | `reason=pci-scope` |
| 7 | a name is looked up in `allow[]`; a URL is used as given | `reason=not-allowlisted` |
| 8 | no `deny_patterns` glob matches the host; checked before the allowlist, so deny always wins | `reason=deny-pattern` |
| 9 | not production: the entry's `env` is not `prod`, `production` or `live`, and no dot-separated host label is | `reason=production` |
| 10 | the URL equals `base_url`, or starts with it followed by `/`, `?` or `#` | `reason=not-allowlisted` |
| 11 | each requested `--vus/--duration/--rps` is within `max_vus/max_duration_seconds/max_rps` | `reason=limit-exceeded` |

The allowlist is a prefix match with a boundary, so `http://localhost:80801` does not match `http://localhost:8080`, and `https://api.dev.internal.evil.com` does not match `https://api.dev.internal`. The script refuses rather than caps: lowering a request to fit is the calling agent's job.

Nothing in this release calls the validator yet: it is the gate the planned security-test-author and load-tester agents will be required to call. The script is mechanical; whether an agent calls it is an instruction unless a later release adds a hook, and a hook would itself be absent in hookless mode. The refusal rules are covered by `tests/security-targets.sh`, which `.claude/test-cmd` runs.

### Model routing

| Stage | Model |
|---|---|
| `/dev-flow:spec` and `spec-architect` | Opus |
| `/dev-flow:build` orchestration and `implementer` | Sonnet |
| `reviewer` | Opus |
| `/dev-flow:threat-model` and `threat-modeler` | Sonnet orchestrates; Opus models |

Agent-level `model:` pins each stage even if the session started on another model. To change it, edit the `model:` line in `agents/*.md` and `commands/*.md` (`opus`, `sonnet`, `haiku`, a full model ID, or `inherit`).

#### `ok build` vs `/dev-flow:build`

`/dev-flow:spec` ends by asking you to either reply **`ok build`** or run `/dev-flow:build <slug>` yourself. They are not equivalent:

| | Reply `ok build` | Run `/dev-flow:build <slug>` |
|---|---|---|
| Orchestration (reading the plan, dispatching tasks, running the loop) | Stays on whichever model is running the session — Opus, since that's what `/dev-flow:spec` pinned | Switches to Sonnet, per that command's own `model:` frontmatter |
| Actual coding (`implementer` subagent) | Sonnet | Sonnet |
| Final review (`reviewer` subagent) | Opus | Opus |

So `ok build` saves you retyping the slug and slash command, at the cost of the orchestration chatter running on the pricier model. The coding itself is Sonnet either way, since that's pinned on the `implementer` agent regardless of who invoked it. `/dev-flow:spec` says this out loud before proceeding. This depends on Claude Code actually pinning a command's model on explicit invocation, as its frontmatter documents — I haven't verified that live in this sandbox (same caveat as the model-routing section below).

Also: `spec-architect`, `implementer` and `reviewer` are subagents. A subagent can spawn further subagents only when its `tools:` list includes `Agent` (checked live on Claude Code 2.1.285), and none of these three lists it, so they do not. The orchestrator is always the top-level session, never a subagent, so the `ok build` path (running build.md's procedure inline in the same conversation) and the `/dev-flow:build` path both work the same way here.

### Memory (optional)

Nothing is installed by default; `CLAUDE.md` and `.claude/rules` are the durable, reviewed record and need no extra tool; plans and specs are local working notes. For personal cross-session recall, `bash install.sh --with-memory` (or `… | bash -s -- --with-memory` for the one-liner) installs [claude-mem](https://github.com/thedotmack/claude-mem). Before using it on anything sensitive:
- Open its config and select the **local/offline** provider — recent versions can default some integrations to a hosted service.
- It captures tool output via hooks, so review what it stores before pointing it at the PCI-adjacent app or anything with secrets.
- It records whatever Claude concluded, not just what you confirmed, so treat its recall as a lead to verify, not a fact — put anything that must be trusted into `CLAUDE.md` instead.

### Status line (optional)

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

### Updating

```bash
claude plugin marketplace update dev-flow-marketplace
claude plugin update dev-flow@dev-flow-marketplace
/reload-plugins        # or start a new session
```

Third-party marketplaces — a local directory or a non-Anthropic GitHub repo — don't auto-update by default, so run these yourself. A pinned install (`DEV_FLOW_VERSION` at install time) stays on its tag either way. To change version or source, run `uninstall.sh`, then reinstall — see "Switching version / downgrading" above.

### Troubleshooting

**`install.sh` freezes / hangs with no output.** Fixed in v1.5.1 — upgrade. The cause: `claude plugin install` requires `-y` when stdout is not a TTY (which is always true inside a script), and v1.5 and earlier also sent output to `/dev/null`, so the confirmation prompt was invisible while the command waited for a keystroke. It looked frozen but was asking a question you couldn't see. The installer now passes `-y`, runs every command with `</dev/null` so nothing can block on a hidden prompt, sets `GIT_TERMINAL_PROMPT=0` so a private-repo clone errors instead of waiting for credentials, and wraps each step in `timeout` so a stall becomes a visible `TIMED OUT` warning. If you are stuck on an older copy, run the commands by hand: `claude plugin marketplace add <path>` then `claude plugin install -y dev-flow@dev-flow-marketplace`.

**`Failed to add marketplace … its network source differs`.** The marketplace is already registered from a different source — a clone path, or a different pinned version. Run `uninstall.sh`, then reinstall with the version/source you want.

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
From v1.10.0 the block message's second line names the version that fired, so a stale copy is self-reporting. If `/status` shows `Enterprise managed settings` and updating doesn't help, the cause is policy, not a stale copy — see [Managed settings: hooks disabled by your organization](#managed-settings-hooks-disabled-by-your-organization).

**A step reports TIMED OUT.** Run that one command on its own to see what it wants — usually network (`npm install -g`, a GitHub clone) or credentials for a private marketplace repo. `--skip-superpowers` and `--skip-codegraph` let you get the rest installed meanwhile.

**Installed but nothing appears.** Restart Claude Code, then `claude plugin list` and `claude plugin details dev-flow`. The inventory should read: Skills 15 (9 skills + the 6 commands), Agents 3, Hooks 5 (PreToolUse, PostToolUse, Stop, PreCompact, SessionStart), MCP servers 4.

**Context cost.** `claude plugin details dev-flow` reports roughly **1,875 always-on tokens** per session for the whole plugin, with each skill's body loaded only when it fires. Worth checking yourself if you stack several plugins.

**CodeGraph tools return nothing.** The repo has no index — run `/dev-flow:init-codegraph` (or `codegraph init`). If a duplicate `codegraph` server appears alongside `plugin:dev-flow:codegraph` from a previous global install, remove it: `claude mcp remove codegraph`.

### Known limits

- Install, component registration (`claude plugin details`) and the uninstall sequence below are now verified by actually running them. What is still **not** verified is the workflow itself in a live session: `/dev-flow:spec` → `/dev-flow:build`, the hooks firing inside a real turn, and whether a command's `model:` frontmatter pins the model as documented. Trial it on a small task before rolling out.
- CodeGraph and Semble build indexes on first use and can be slow on large repos.
- The stop gate does nothing without a per-repo `.claude/test-cmd`; the retry/give-up mechanism and its interaction with Claude Code's stop-hook block cap are tested standalone (not yet inside a live Claude Code stop-hook cycle).
- With a containerised toolchain and no `.claude/lint-cmd`, per-edit checks skip silently — which means the stop gate (`.claude/test-cmd`) is your only automated check, so it is worth setting up properly there.
- Whether Claude Code loads `AGENTS.md` natively is version-dependent and unverified here; that is why `setup-rules` adds a `CLAUDE.md` symlink or import pointer rather than assuming.
- The `ALLOW-CLAUDE-MD-EDIT` override is a guardrail, not a security boundary: the hook cannot tell who created the file, it only checks that it exists. The skill is instructed not to create it.
- `Write`/`Edit` are gated mechanically; the `Bash` bypass is now closed for the common shapes (heredoc, `>`/`>>`, `tee`, `sed -i`/`perl -i`, `cp`, `mv`, `install`, `rm`/`unlink`/`shred`, `dd`, `truncate`, `git restore`/`git checkout -- `, `python -c`). This is command-text matching, a guardrail, not a boundary — obfuscated command text (a variable, a script file, base64), `node -e`/`ruby -e` one-liners that write files, and a directory-target `cp`/`mv` (e.g. `cp x.md .claude/rules/` without naming the destination file, so the guard never sees a `.md` filename to match) all still get through. The guard overall remains a guardrail against model error, not a security boundary.
- The compaction snapshot is verified by running its scripts directly, not yet inside a live compaction; see [Compaction snapshot](#compaction-snapshot) for what it does not capture.
- Rule templates are starting points: `init-rules` verifies them against the repo, but review the result.
- No persistent memory (add `claude-mem` separately if wanted) and no usage dashboard.
- `security-review` and `db-migration` give structured checks, not compliance certification or a substitute for DBA and security sign-off.
- `ok build` is pattern-matched by the model reading `spec.md`'s own instructions, not by the Claude Code harness — it (and near-equivalents like "build it") gets recognised because the command tells the model to look for an approval reply, not because of any special runtime feature.
- The clarification check (seven categories, the five-question cap, waiting only on `blocking`, and no questions for a fully specified request) is prompt instructions, not enforced by the harness, and was only spot-checked in two headless runs on a fixture repo during 1.16.0 development.
- Hookless mode (see [Managed settings: hooks disabled by your organization](#managed-settings-hooks-disabled-by-your-organization)) is instruction-level, not mechanical: it relies on the model following `.claude/lint-cmd`/`.claude/test-cmd` and the guidance file rather than a hook blocking the action.
- threat-modeler findings are model judgement, checked only by the synthetic eval cases in `plugins/dev-flow/evals/threat-*`, and are not a security sign-off.
- "Only writes `docs/threats/<slug>.md`" is a command instruction (the agent itself cannot write), and the redaction grep is a pattern check, not a guarantee.
- The threat-modeler evals are billed and were run once on 2026-10-10 (nightly tier, passed); see [Evals](#evals).
- Agent `tools:` lists are allowlists, and an entry that does not resolve is dropped without a warning; only a list where nothing resolves stops the agent launching. In Claude Code 2.1.285 the `implementer`'s `Grep`, `Glob`, `MultiEdit` and `TodoWrite` entries do not resolve (with Bash present, search goes through Bash), so it works with the rest. They stay listed for versions where they exist.
- 1.17.1 fixed two tool grants: `reviewer` no longer has Bash (it could run `git checkout -- .` or `git reset --hard` on the diff it was reviewing), and `implementer` gained an allowlist (it previously inherited every tool, including web search, subagents and the browser MCP).
- Worktree mode (`commands/build.md` step 2 and the `git-workflow` skill) is instruction-level and not yet run in a live session, and neither is asking both questions in one `AskUserQuestion` call. Starting from the default branch is only offered on a clean tree, and the skill only offers a worktree on a clean tree, since switching base could mix or lose uncommitted changes and a worktree would leave them behind. The default branch is detected from local refs only (`origin/HEAD`, then `main`, `master`, `develop`), without fetching, so pull it first if it may be stale. After `EnterWorktree`, Claude Code keeps `${CLAUDE_PROJECT_DIR}` on the main checkout, and every dev-flow hook `cd`s there: the stop gate, per-edit checks, compaction snapshot and the guard's approval markers act on the main checkout, not the worktree. The explicit `.claude/test-cmd` and `.claude/lint-cmd` runs in the build and before each commit still cover the worktree. Approving a guarded guidance-file edit from inside a worktree may not work; it fails closed (the guard keeps blocking). The worktree is never removed automatically: run `git worktree remove .claude/worktrees/<slug>` after merging. The build, the `git-workflow` skill and `worktree.sh` ignore `.claude/plans/`, `.claude/specs/` and `.claude/worktrees/` when deciding whether the tree is clean, and a failed copy of the plan or spec into a worktree stops with `error=copy-failed`. The worktree and branch then already exist and the script removes nothing; clean up with `git worktree remove --force <path>` then `git branch -D <branch>`, and retry.

## Changelog

Releases are git tags named `dev-flow--v<version>`: https://github.com/dgiotas/dev-flow/tags. Per-change detail is in the commit history.

## Contributing

| Task | Command |
|---|---|
| Try the plugin locally without installing | `claude --plugin-dir ./plugins/dev-flow` |
| Validate the repo (JSON, shell syntax, YAML frontmatter, `tests/*.sh`) | `bash .claude/test-cmd` |
| Check one file after an edit | `bash .claude/lint-cmd <repo-relative-path>` |
| Run the eval suite (billed; approval first) | `bash ci/eval-run.sh <pr\|nightly> <out-dir>` |
| Release a change | bump `version` in `plugins/dev-flow/.claude-plugin/plugin.json`, merge to `main`, then `claude plugin tag plugins/dev-flow --push` (creates and pushes the `dev-flow--v<version>` tag, validating the manifest) |

Issues and PRs: https://github.com/dgiotas/dev-flow/issues.
