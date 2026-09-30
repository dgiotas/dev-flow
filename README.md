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
rm -rf .claude/.approved-writes .claude/.stop-gate-state .claude/stop-gate-giveup.log
rm -rf .claude/rules            # only if these were generated and you don't want them
rm -rf .codegraph               # CodeGraph index
# docs/specs and docs/plans are your own work product — keep them
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

Three peer paths. The hooks (guard, per-edit checks, stop gate) apply on all of them, unless your organization's managed settings block plugin hooks — see [Managed settings: hooks disabled by your organization](#managed-settings-hooks-disabled-by-your-organization).

| Path | What it adds |
|---|---|
| Plain request | Skills fire from the request itself — "how does X work" (investigate), "this is broken" (fix-bug), "commit this" (git-workflow), "review this for security", "is this migration safe", "verify it's done". |
| `/dev-flow:spec` → reply `ok build` | Plan, approve, build in the same conversation; orchestration stays on the session model. |
| `/dev-flow:spec` → `/dev-flow:build <slug>` | Same, but orchestration switches to Sonnet. |

```text
/dev-flow:spec add rate limiting to the ticket search API
   -> review and edit docs/plans/<slug>.md, answer the open questions
   -> reply "ok build", or run /dev-flow:build <slug> yourself
```

## Workflows

| Command | Use it when | What it does |
|---|---|---|
| `/dev-flow:spec <feature>` | you want an approved plan before any code | Opus `spec-architect` investigates, writes `docs/specs/<slug>.md` + `docs/plans/<slug>.md` with test-first tasks and open questions. No code. |
| `ok build` (reply after spec) | the plan is right; keep going in this conversation | Runs the build procedure inline: orchestration on the current model, coding on Sonnet `implementer`, review on Opus `reviewer`. |
| `/dev-flow:build <slug>` | you want the build phase orchestrated by the cheaper model | Sonnet runs tasks via `implementer` on a branch, then `verify-done`, then Opus `reviewer`. Never merges or pushes (`commands/build.md` steps 2–7). |
| `/dev-flow:onboard` | first time in a repo | CodeGraph index, then guidance file + rules, then verified hook commands, pausing at every guarded write. |

Model pinning per stage is documented in frontmatter but not verified live — see Model routing.

## Other Commands, Skills and Agents

| Name | Kind | Purpose |
|---|---|---|
| `/dev-flow:init-rules <stack>` | Command | Adapts stack rule templates into the repo's `.claude/rules`. |
| `/dev-flow:init-hooks` | Command | Derives `.claude/test-cmd` / `lint-cmd` from your AGENTS.md, Makefile, manifests or CI, then verifies them. |
| `/dev-flow:init-codegraph` | Command | Builds/refreshes the local CodeGraph index for this repo. |
| `spec-architect` (Opus) | Agent | Investigates and writes spec and plan. |
| `implementer` (Sonnet) | Agent | Implements one plan task test-first, escalates with `BLOCKED`. |
| `reviewer` (Opus) | Agent | Read-only diff review against spec. |
| `code-intel` | Skill | Picks Semble, CodeGraph, Context7, DevTools or `rg`. |
| `investigate` | Skill | Read-only, cited codebase Q&A. |
| `fix-bug` | Skill | Red test, root cause, minimal fix, verify. |
| `verify-done` | Skill | Evidence before saying "done". |
| `setup-rules` | Skill | Generates `CLAUDE.md` and rules from the repo. |
| `dead-code-audit` | Skill | Report-only cleanup audit. |
| `git-workflow` | Skill | Branches, commits, PR text, review feedback. Never pushes unasked. |
| `security-review` | Skill | Auth, injection, secrets, PCI-adjacent and dependency checklist. Report-only. |
| `db-migration` | Skill | Expand/migrate/contract, backfills, rollback. Never runs against shared DBs. |
| `post-edit-check` | Hook | Syntax and lint on each edited file (PHP, Python, TS/JS, JSON). |
| `stop-gate` | Hook | Runs `.claude/test-cmd` before Claude can finish, retrying up to 3 times before giving up (see below). |
| `pre-write-guard` | Hook | Gates every change (Write/Edit/MultiEdit, plus Bash commands that look like they write the file directly) to `AGENTS.md` / `CLAUDE.md` / `.claude/rules/*.md`, and refuses edits to a `CLAUDE.md` that only points at `AGENTS.md` (see below). |
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

- Each failure increments a counter in `.claude/.stop-gate-state` and is reported back to Claude as `attempt N/max`.
- After the cap (default **3**) it stops blocking, but writes a hard-to-miss `Quality gate: giving up...` banner to `.claude/stop-gate-giveup.log` and tells Claude to report the failure to you instead of finishing quietly.
- A pass at any point clears the counter. The next failure after a give-up starts a fresh cycle at attempt 1.
- Change the cap per repo: put a number in `.claude/test-cmd-retries`, or set `DEV_FLOW_STOP_GATE_MAX` in your shell.
- Add `.claude/.stop-gate-state` and `.claude/stop-gate-giveup.log` to `.gitignore`.

### Managed settings: hooks disabled by your organization

If your organization sets `allowManagedHooksOnly: true` (or `disableAllHooks: true`) in Claude Code managed settings, plugin hooks are blocked — none of dev-flow's three hooks (pre-write guard, per-edit check, stop gate) run. Side effects: the optional claude-powerline status line doesn't show either (`statusLine` is narrowed to managed settings under the same policy), and claude-mem, which is hook-based, doesn't record. MCP servers, skills, agents and commands are unaffected — only hooks and the status line are blocked. See [the hooks docs](https://code.claude.com/docs/en/hooks).

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
| stop gate | `.claude/test-cmd`, run by `implementer`, `verify-done`, `reviewer` and the guidance section | instruction-level; nothing blocks the end of a plain turn |

Hookless mode is weaker: the model can skip an instruction, and only the admin fix above restores the mechanical gates.

The `ask` rules are committed to the repo on purpose, as a shared backstop for everyone who works there — review that diff before committing it, since contributors whose hooks run will see a permission prompt in addition to the guard.

### Per-repo config files

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

### Model routing

| Stage | Model |
|---|---|
| `/dev-flow:spec` and `spec-architect` | Opus |
| `/dev-flow:build` orchestration and `implementer` | Sonnet |
| `reviewer` | Opus |

Agent-level `model:` pins each stage even if the session started on another model. To change it, edit the `model:` line in `agents/*.md` and `commands/*.md` (`opus`, `sonnet`, `haiku`, a full model ID, or `inherit`).

#### `ok build` vs `/dev-flow:build`

`/dev-flow:spec` ends by asking you to either reply **`ok build`** or run `/dev-flow:build <slug>` yourself. They are not equivalent:

| | Reply `ok build` | Run `/dev-flow:build <slug>` |
|---|---|---|
| Orchestration (reading the plan, dispatching tasks, running the loop) | Stays on whichever model is running the session — Opus, since that's what `/dev-flow:spec` pinned | Switches to Sonnet, per that command's own `model:` frontmatter |
| Actual coding (`implementer` subagent) | Sonnet | Sonnet |
| Final review (`reviewer` subagent) | Opus | Opus |

So `ok build` saves you retyping the slug and slash command, at the cost of the orchestration chatter running on the pricier model. The coding itself is Sonnet either way, since that's pinned on the `implementer` agent regardless of who invoked it. `/dev-flow:spec` says this out loud before proceeding. This depends on Claude Code actually pinning a command's model on explicit invocation, as its frontmatter documents — I haven't verified that live in this sandbox (same caveat as the model-routing section below).

Also: `spec-architect`, `implementer` and `reviewer` are subagents, and a subagent cannot itself spawn further subagents. So the `ok build` path (running build.md's procedure inline in the same conversation) and the `/dev-flow:build` path both work the same way here — the orchestrator is always the top-level session, never a subagent, so this isn't affected by that limit.

### Memory (optional)

Nothing is installed by default; `CLAUDE.md`, `.claude/rules`, and the specs/plans in `docs/` are the durable, reviewed record and need no extra tool. For personal cross-session recall, `bash install.sh --with-memory` (or `… | bash -s -- --with-memory` for the one-liner) installs [claude-mem](https://github.com/thedotmack/claude-mem). Before using it on anything sensitive:
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

**Installed but nothing appears.** Restart Claude Code, then `claude plugin list` and `claude plugin details dev-flow`. The inventory should read: Skills 15 (9 skills + the 6 commands), Agents 3, Hooks 3 (PreToolUse, PostToolUse, Stop), MCP servers 4.

**Context cost.** `claude plugin details dev-flow` reports roughly **1,875 always-on tokens** per session for the whole plugin, with each skill's body loaded only when it fires. Worth checking yourself if you stack several plugins.

**CodeGraph tools return nothing.** The repo has no index — run `/dev-flow:init-codegraph` (or `codegraph init`). If a duplicate `codegraph` server appears alongside `plugin:dev-flow:codegraph` from a previous global install, remove it: `claude mcp remove codegraph`.

### Known limits

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
- Hookless mode (see [Managed settings: hooks disabled by your organization](#managed-settings-hooks-disabled-by-your-organization)) is instruction-level, not mechanical: it relies on the model following `.claude/lint-cmd`/`.claude/test-cmd` and the guidance file rather than a hook blocking the action.

## Changelog

Releases are git tags named `dev-flow--v<version>`: https://github.com/dgiotas/dev-flow/tags. Per-change detail is in the commit history and `docs/specs/`.

## Contributing

| Task | Command |
|---|---|
| Try the plugin locally without installing | `claude --plugin-dir ./plugins/dev-flow` |
| Validate the repo (JSON + shell syntax) | `bash .claude/test-cmd` |
| Check one file after an edit | `bash .claude/lint-cmd <repo-relative-path>` |
| Release a change | bump `version` in `plugins/dev-flow/.claude-plugin/plugin.json`, merge to `main`, then `claude plugin tag plugins/dev-flow --push` (creates and pushes the `dev-flow--v<version>` tag, validating the manifest) |

Issues and PRs: https://github.com/dgiotas/dev-flow/issues.
