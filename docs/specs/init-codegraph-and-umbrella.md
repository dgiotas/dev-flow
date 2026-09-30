# Spec: `/dev-flow:init-codegraph` and a `/dev-flow:onboard` umbrella

Plan: `docs/plans/init-codegraph-and-umbrella.md`
Branch: `feature/mcp-codegraph-registration` (continues on the same branch — the CodeGraph
MCP registration already on it is the direct prerequisite for this work: registering the
server is what makes a per-repo index worth creating).

## Goal

1. Add `plugins/dev-flow/commands/init-codegraph.md` — a single-concern command that gives
   the already-registered `codegraph` MCP server something to query in the current repo.
2. Add `plugins/dev-flow/commands/onboard.md` — one umbrella onboarding command that runs the
   per-repo setup steps in a correct, de-duplicated order, so "what do I do after
   installing the plugin?" has a single answer.
3. Update `README.md` so the quick-start and the component inventory match reality, point
   `install.sh`'s per-repo hint at the umbrella, and bump the plugin version so
   `/plugin update` actually ships it.

## Non-goals

- No change to `init-hooks.md`, `init-rules.md` or `skills/setup-rules/SKILL.md` content.
  The umbrella *invokes* them; it does not fork or reword them. (It does tell each one what
  to skip — see *Artifact ownership* — but that instruction lives in `onboard.md`.)
- No new hook, no change to `hooks/hooks.json`, no change to `pre-write-guard.sh`. In
  particular: no mechanism to pre-approve or batch guard approvals.
- Not re-documenting `codegraph`'s own CLI. `init-codegraph` covers `init` only; `sync`,
  `index`, `explore` etc. stay the `code-intel` skill's business.
- No shell scripts. Both new files are agent-readable Markdown instruction files, matching
  the existing commands.
- `install.sh` gains **no new behaviour**. It already installs the binary
  (`install.sh:386-401`) and already prints the per-repo hint at `install.sh:397`; only that
  one `note` line's text changes, to point at `/dev-flow:onboard` with the raw
  `codegraph init` kept in parentheses as the non-session fallback (Resolved decision 4).
  No new step, no restructuring of section 3.

## Current behaviour

### Per-repo onboarding is three unconnected entry points, none of which touch CodeGraph

| Entry point | File | Writes |
|---|---|---|
| `/dev-flow:init-hooks` | `plugins/dev-flow/commands/init-hooks.md` | `.claude/test-cmd`, `.claude/lint-cmd` (conditional), `.claude/test-cmd-retries` (only on `retries=N`) |
| `/dev-flow:init-rules <stack>` | `plugins/dev-flow/commands/init-rules.md` | `.claude/rules/<template>.md` from `templates/rules/*.md` |
| `setup-rules` skill (natural language) | `plugins/dev-flow/skills/setup-rules/SKILL.md` | guidance file (`AGENTS.md`/`CLAUDE.md`), `.claude/rules/<topic>.md`, `.claude/test-cmd`, `.claude/lint-cmd` |

`README.md:19-24` documents them as four separate lines the user is expected to run by hand,
the fourth being a raw `cd <repo> && codegraph init`.

### Overlap analysis: `setup-rules` vs `init-hooks` + `init-rules`

The parent session's reading — that `setup-rules` is a superset — is **half right**. By
*artifact* it overlaps heavily; by *depth* and by *provenance* it does not. Evidence:

| Artifact | `init-hooks` | `init-rules` | `setup-rules` |
|---|---|---|---|
| guidance file (`AGENTS.md`/`CLAUDE.md`) | never | never | **only producer** (`SKILL.md:45`) |
| `.claude/rules/*.md` | never | stack templates, verified line by line (`init-rules.md:8,10,11`) | inspection-derived, path-scoped, per topic (`SKILL.md:46-53`) |
| `.claude/test-cmd` | **authoritative**: source-ranked discovery (`init-hooks.md:44-54`), host-vs-container decision (`:56-63`), fast-vs-slow selection criteria (`:69-74`) | only "offer to create if missing" (`init-rules.md:12`) | writes it, "if the user wants them" (`SKILL.md:54-57`) |
| `.claude/lint-cmd` | conditional, **and proves it can fail** on a deliberately broken temp file (`init-hooks.md:91`) | offered (`:12`) | conditional, verified by one passing run (`SKILL.md:57`) |
| `.claude/test-cmd-retries` | **only producer** (`init-hooks.md:82-84`) | never | never |
| pre-write-guard liveness proof | **only producer**, and it is step 0 (`init-hooks.md:10-42`) | never | never |
| guidance-target detection (`guidance-target.sh`) | never | yes (`init-rules.md:9`) | yes (`SKILL.md:10-35`) |

Conclusions that drive the design:

1. **No step is redundant.** `setup-rules` is the only source of the guidance file;
   `init-hooks` is the only source of the guard proof, `test-cmd-retries`, and the only one
   that verifies a lint gate can actually fail; `init-rules` is the only consumer of the
   shipped templates.
2. **The real collision is `.claude/test-cmd` / `.claude/lint-cmd`**, written by all three
   with three different levels of rigour. Running them in sequence means the weaker writer
   can overwrite the stronger one's verified result — and `setup-rules` writing them after
   `init-hooks` is exactly that regression.
3. **The soft collision is `.claude/rules/`.** Filenames rarely clash (`php-api.md` vs a
   topic name like `api-responses.md`), so nothing is *overwritten*; the risk is the same
   convention being asserted twice, in two files, possibly with different command strings.
4. `init-hooks.md:48` reads the guidance file as the *first* authority for commands, and
   `init-rules.md:9-10` consults it too. So whichever step writes the guidance file must run
   **before** the two that read it.

### The pre-write-guard makes an unattended umbrella run impossible

`hooks/hooks.json` matches `Write|Edit|MultiEdit|Bash` on `pre-write-guard.sh`. The script
marks a path guarded when its basename is `AGENTS.md`/`CLAUDE.md` or it is under
`.claude/rules/` (`pre-write-guard.sh:128-132`) and blocks any change to an **existing**
one with `BLOCKED: <tool> would change an existing protected file: <rel>`
(`pre-write-guard.sh:269-271`), handing back the exact change plus a single-use marker
command. Brand-new files pass through. So:

- **First run on a virgin repo**: mostly unblocked — every guarded file is new.
- **Second run, or any repo that already has `AGENTS.md`/`CLAUDE.md`/`.claude/rules/*.md`**:
  every write into those paths stops and waits for a human yes. Both `setup-rules`
  (`SKILL.md:71-82`) and `init-rules` (`init-rules.md:11`) already document that flow.

There is no override path from inside a command, and there must not be. The umbrella is
therefore specified as an **interactive, interruptible, resumable** sequence, not a batch job.

### `init-rules` requires an explicit stack

`argument-hint: <php|java|python|node|all>` (`init-rules.md:3`), and step 1 maps the argument
to template files. An umbrella has no argument unless the user gives one.

### Inventory counts in the README are asserted, and verified by a real command

`README.md:342` asserts `Skills 13 (9 skills + the 4 commands)`; `README.md:344` asserts
`~1,700 always-on tokens`. Verified live during this investigation:

```
$ claude plugin details dev-flow
dev-flow 1.10.1
  Skills (13)  build, code-intel, db-migration, dead-code-audit, fix-bug, git-workflow,
               init-hooks, init-rules, investigate, security-review, setup-rules, spec, verify-done
  Agents (3) …  Hooks (3) …  MCP servers (4) …
  Always-on:   ~1,760 tok
```

So commands *are* counted as Skills, the count is 13 today, and the always-on figure has
already drifted from the README's "~1,700" to ~1,760. Adding two commands makes it **15
(9 skills + 6 commands)** and will raise the always-on figure again. `dev-flow-marketplace`
is sourced from `Directory (/Users/dgiotas/Projects/personal/dev-flow)`, so the same command
can re-verify the new counts locally after a marketplace+plugin update.

### `codegraph init`: observed behaviour (scratch repos, `codegraph` 1.6.0)

Run in `…/scratchpad/cgtest` and `…/scratchpad/cg2`, both throwaway `git init` repos:

- `command -v codegraph` → `/opt/homebrew/bin/codegraph`; `codegraph --version` → `1.6.0`.
- **Before init**: `codegraph status --json` → `{"initialized":false,…,"indexPath":"<repo>/.codegraph","lastIndexed":null}`, **exit 0**.
  Plain `codegraph status` prints `⚠ Not initialized` / `ℹ Run "codegraph init" to initialize`, also exit 0.
  So the initialised check is `codegraph status --json` → `.initialized`, which is more
  honest than testing for the directory (a half-finished init leaves the directory behind).
- **`codegraph init -y`** on a 1-file JS repo: exit **0**, output ends
  `◆ Initialized in <path>` / `◆ Indexed 1 files` / `● 3 nodes, 3 edges in 126ms` / `└ Done`.
- **Without `-y`, stdin closed**: also exit 0, no prompt, same output. `-y` is still
  specified, because `--help` documents it as "skip every prompt … for scripts", and the
  repo's own convention is `</dev/null` on every install step (`install.sh` uses it
  throughout). Belt and braces, zero cost.
- **Re-running `codegraph init -y`**: exit **0**, prints `▲ Already initialized in <path>` /
  `● Use "codegraph index" to re-index or "codegraph sync" to update`. Safe no-op, so the
  "re-running is safe" convention holds even without the status pre-check.
- **After init**: `codegraph status --json` → `"initialized":true` plus `fileCount`,
  `nodeCount`, `edgeCount`, `lastIndexed`, `pendingChanges:{added,modified,removed}`.
- **No background daemon lingered** after init (`pgrep -fl codegraph` found only the
  invoking shell).
- **`.gitignore` still matters.** `init` writes `.codegraph/.gitignore` containing `*` and
  `!.gitignore`, so the database can never be committed — but `git status --porcelain` still
  showed `?? .codegraph/` afterwards, because that inner `.gitignore` is deliberately not
  self-ignored. Appending `.codegraph/` to the repo's own `.gitignore` removed the entry
  from `git status`. Both states observed. This is the grounded justification for step 4 of
  the new command, and it is worth saying *why* in the report (keeps `git status` clean; the
  index itself was never at risk).
- `codegraph init --help` also documents `-f/--force` ("Initialize even if the path looks
  like your home directory or a filesystem root") — so the command must resolve the repo
  root with `git rev-parse --show-toplevel` and run there, never in `$HOME`, and must not
  reach for `-f`.

## Proposed design

### A. `plugins/dev-flow/commands/init-codegraph.md`

Frontmatter: `description` only. No `argument-hint` (no arguments). No `model:` — matching
`init-hooks.md` and `init-rules.md`, which both omit it; only `spec.md`/`build.md` pin a
model, because they are the routed stages.

Body, numbered steps in the sibling style ("read, do not guess", explicit verification):

0. Resolve the repo root (`git rev-parse --show-toplevel`) and work there. If not inside a
   git repo, say so and stop — never run `codegraph init` in `$HOME` or `/`, and never pass
   `-f` to make it possible.
1. `command -v codegraph`. If absent: report `npm install -g @colbymchenry/codegraph` (or
   `bash install.sh`, section 3) and **stop cleanly** — not an error. CodeGraph is optional
   everywhere else in this plugin (`README.md:127`, `install.sh:387-400`), and the MCP server
   is already registered either way; it just has nothing to answer with.
2. `codegraph status --json` → if `.initialized` is true, skip the init and say so, quoting
   `lastIndexed` and `fileCount`. If `pendingChanges` is non-zero, mention `codegraph sync`
   as the user's next step — do not run it (staying single-concern, and sync is the
   `code-intel` skill's territory).
3. Otherwise run `codegraph init -y </dev/null` at the repo root. Expect exit 0 and a
   `Initialized in <path>` / `Indexed N files` / `N nodes, N edges` tail. Report the counts.
   If exit is non-zero, report the output verbatim and stop — do not retry with `-f`.
4. `.gitignore`: append `.codegraph/` only if not already matched (check first — the entry
   may exist in any form). Explain in the report that `init` already writes
   `.codegraph/.gitignore` so the database was never committable; the repo-level entry is
   what keeps `.codegraph/` out of `git status`.
5. Report: binary path and version, whether an index already existed, the file/node/edge
   counts, whether `.gitignore` was touched, and one line on what this unlocks
   (`codegraph_explore` / `codegraph_node` via the `plugin:dev-flow:codegraph` MCP server;
   verify with `claude mcp list`).

Target length: comparable to `init-rules.md` (~2 KB), not `init-hooks.md` (~7 KB).

### B. `plugins/dev-flow/commands/onboard.md` — the umbrella

Named `onboard`, not `init`: it is not one of the `init-*` family, it is the thing that runs
them, and `/dev-flow:onboard` cannot be confused with `/dev-flow:init-codegraph`,
`/dev-flow:init-hooks` or `/dev-flow:init-rules` in the command palette (Resolved decision 3).

**Resolution of the overlap: option (c) — run all four, in dependency order, with one named
owner per artifact and explicit skip instructions** (Resolved decision 1). Not (a) "accept
the overlap" (that lets
`setup-rules` clobber `init-hooks`' verified `test-cmd`), and not (b) "pick one of
{templates, inspection}" (as posed it is unsound: only `setup-rules` writes the guidance
file, so the template-only branch would leave a repo with rules and hooks but no `AGENTS.md`
— the single most valuable artifact — and the inspection-only branch would throw away the
shipped templates and never write `test-cmd-retries` or prove the guard is live).

**Artifact ownership** (stated in the command body as a table, so the agent cannot drift):

| Artifact | Owner step | Other steps must |
|---|---|---|
| guard liveness proof | step 0 of the umbrella | `init-hooks` step 0 is skipped — already done |
| `.codegraph/`, `.gitignore` entry | `init-codegraph` | — |
| guidance file | `setup-rules` | — |
| `.claude/rules/<topic>.md` (inspection) | `setup-rules` | — |
| `.claude/rules/<template>.md` (stack) | `init-rules` | skip a template whose content `setup-rules` already covered; never restate the same convention in two files |
| `.claude/test-cmd`, `.claude/lint-cmd`, `.claude/test-cmd-retries` | `init-hooks` | `setup-rules` is told to skip its step 5 (`SKILL.md:54-57` is already conditional on "if the user wants them"); `init-rules` is told to skip its step 5 (`init-rules.md:12` is already only an offer) |

**Order and why:**

0. **Prove the pre-write guard is live, once.** Lifted from `init-hooks.md:10-42` by
   reference, not by copy: the umbrella instructs the agent to perform that command's step 0
   and stop if the probe is not blocked. Rationale — it is a precondition for every later
   step that writes a guarded file, it is cheap, and duplicating it three times would create
   and delete the probe file three times. Also report the plugin root/version once here.
1. **`init-codegraph` first.** It is the only step that writes nothing guarded, so it can
   never stall; it is fast; and a fresh index makes the *later* inspection steps better
   (`setup-rules` step 1 inspection, `init-hooks` step 1 command discovery, and the
   `code-intel` skill for the rest of the session). Running it last — as `README.md:23`
   implies today — wastes it.
2. **`setup-rules`, scoped to guidance + inspection rules** (skip its hook-command step).
   Must precede `init-hooks`/`init-rules` because both read the guidance file as their first
   authority (`init-hooks.md:48`, `init-rules.md:9`).
3. **`init-hooks`, skipping its step 0.** Now has the guidance file to read, and owns the
   hook commands with its full verification (including proving `lint-cmd` can fail).
   Pass through any `retries=N` / `force-container` / `force-host` from the umbrella's
   arguments.
4. **`init-rules <stack>` last**, as a top-up: only the templates that add something step 2
   did not already cover, deduped against the rules just written. Skip the step entirely, with
   a reason, when no stack was detected or when every candidate template is already covered.

**Interruption / resume contract**, stated explicitly in the body:

- Announce the ordered step list up front with detected stack and guidance target, and get
  the user's go-ahead before writing anything. That is the **only** confirmation the command
  asks for of its own accord — no per-step "shall I continue?" prompt (Resolved decision 2);
  the guard stops below are the unavoidable exception.
- Run one step at a time; report per-step outcome before starting the next.
- When a step is blocked by the pre-write-guard: stop, show the change from the hook message
  verbatim, wait for an explicit yes in that turn, run the exact marker command the hook
  gave, retry the same call unchanged, then continue. Never batch approvals, never create a
  marker pre-emptively, never split a change to slip past the gate, never create
  `ALLOW-CLAUDE-MD-EDIT`.
- Expect this on any repo that already has `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md`
  — including every second run. An uninterrupted pass is the *exception*, not the norm.
- Re-running the umbrella is safe: every step is idempotent or gated. If a step was
  abandoned, re-running resumes from the first artifact that is missing or stale; report
  which steps were no-ops.
- Final report: one line per step (done / skipped + why / blocked-and-approved / blocked-and-
  abandoned), the files written, and the remaining manual follow-ups (gitignore the hooks'
  state files, commit advice — as `init-hooks.md:100-101` already prescribes).

**Arguments.** `argument-hint: [php|java|python|node|all] [retries=N] [force-container] [force-host]`
— all optional; the stack token is passed to `init-rules`, the rest to `init-hooks`.
When no stack is given, **auto-detect from manifests and state the evidence**, then confirm
with the user in the step-list announcement. Justification: these are prompt files for an
agent, not shell scripts, and every sibling already inspects — `init-rules.md:8` defines
`all` as "every one that matches languages actually present in this repo", and
`setup-rules` step 1 inspects manifests anyway. Detection is therefore consistent, costs
nothing, and the announcement step makes a wrong guess correctable before any write. Ask the
user only when detection finds nothing or is genuinely ambiguous.

### C. README, the `install.sh` hint, and version

- `README.md:19-24` quick-start block → `/dev-flow:onboard` as the single line, with the four
  underlying commands listed beneath as the manual/step-by-step alternative, plus one
  sentence that the guard will interrupt the run and that this is by design.
- `README.md:93-116` inventory table → add `| Command | /dev-flow:init-codegraph | … |` and
  `| Command | /dev-flow:onboard | … |`.
- `README.md:342` → `Skills 15 (9 skills + the 6 commands)`, and the always-on figure at
  `README.md:344` refreshed — both taken from a real `claude plugin details dev-flow` run
  after a marketplace+plugin update, never incremented by assumption.
- `README.md:346` troubleshooting ("CodeGraph tools return nothing … run `codegraph init`")
  → point at `/dev-flow:init-codegraph`.
- `README.md:1` title says `v1.10` → `v1.11`.
- `install.sh:397` — the `note` line currently reads
  `per repo, once:  cd <repo> && codegraph init   (add .codegraph/ to .gitignore)`. It becomes
  a pointer to `/dev-flow:onboard` (which covers the index *and* the `.gitignore` entry *and*
  the rest of the per-repo setup), with `codegraph init` kept in parentheses for someone who
  is not in a Claude Code session. One line, same `note` helper, same position in section 3.
- **Version: minor bump, `1.10.1` → `1.11.0`.** Justified: two new user-facing commands are
  added functionality with no breaking change and no removal — semver MINOR. A patch bump
  would misrepresent it, and because the version bump *is* this repo's only release signal
  (AGENTS.md *Hazards*), the number is also the changelog colleagues see in
  `/plugin update`. `1.10.1` on this branch is an unreleased patch relative to `main`'s
  `1.10.0`; `1.11.0` supersedes it cleanly, so only the one file changes.
- `plugin.json` `description` needs no change: "nine dev skills" is still true (these are
  commands), and "commands to derive and verify the per-repo hook commands" still holds.

## Data flow

`/dev-flow:onboard [stack] [retries=N] [force-*]`
→ guard probe (one throwaway `.claude/rules/devflow-guard-probe.md`, deleted either way)
→ `codegraph status --json` / `codegraph init -y` / `.gitignore`
→ `guidance-target.sh` → guidance file + `.claude/rules/<topic>.md` (guard-gated)
→ discovery across `AGENTS.md`/Makefile/manifests/CI → `.claude/test-cmd` (+ `lint-cmd`,
  `test-cmd-retries`), each run once to verify
→ `templates/rules/*.md` → `.claude/rules/<template>.md` (guard-gated)
→ report.

No schema or API changes. No new files outside `plugins/dev-flow/commands/`.

## Risks and edge cases

| Risk | Mitigation |
|---|---|
| `setup-rules` writes `test-cmd` anyway and clobbers the verified one | Umbrella explicitly tells it to skip its step 5 and names `init-hooks` as the owner; its own wording is already conditional (`SKILL.md:54`) |
| Long interactive run; user walks away mid-sequence | Idempotent + resumable by design; per-step reporting; nothing is left half-written except by an explicit abandon |
| Guard blocks on run 2 and the agent tries to be helpful | Body forbids marker pre-creation, change-splitting, tool-switching and `ALLOW-CLAUDE-MD-EDIT` verbatim, mirroring `SKILL.md:82` |
| Stack auto-detection guesses wrong | Announced with evidence before any write; user corrects in one word |
| `codegraph` absent | Step 1 stops cleanly; the other three steps still run (CodeGraph is optional) |
| `codegraph init` in `$HOME` | Repo root resolved via `git rev-parse --show-toplevel`; `-f` forbidden |
| Two new commands raise always-on token cost | Keep both bodies short; re-read the real figure from `plugin details` and update `README.md:344` rather than guessing |
| Umbrella drifts from the three files it delegates to | It delegates by reference (run the command / invoke the skill), never by copying their steps — the one exception is guard-proof step 0, which it invokes by reference too |
| Colleagues never see it | Version bumped to `1.11.0`; a local-directory marketplace does not auto-update, so the README's existing update instructions apply |

## Migration and rollback

Nothing to migrate: two additive files plus docs. Existing `/dev-flow:init-hooks`,
`/dev-flow:init-rules` and `setup-rules` keep working unchanged and stay documented, so
anyone with muscle memory or a script is unaffected. Rollback is `git revert` of the commit
(or deleting the two `.md` files and restoring the version); nothing in a consumer repo
depends on either command existing.

## Resolved decisions (signed off — no open questions remain)

1. **Overlap resolution: option (c), as written.** Run all four in the order
   0 guard → `init-codegraph` → `setup-rules` (guidance + inspection rules only) →
   `init-hooks` (owns the hook commands, its step 0 skipped) → `init-rules` (deduplicated
   top-up templates), with one named owner per artifact. Specifically confirmed:
   (a) `init-hooks` — not `setup-rules` — owns `.claude/test-cmd` / `.claude/lint-cmd`;
   (b) `init-rules` **stays in the umbrella**, running after `setup-rules` as a deduplicated
   top-up — not dropped, not left standalone.
2. **One confirmation, at the start.** The umbrella announces the whole ordered step list
   once (with detected stack and guidance target) and asks for a single go-ahead. No
   per-step confirmation before each write-heavy step; the pre-write-guard stops remain the
   only other interruptions.
3. **Name: `/dev-flow:onboard`** (file `plugins/dev-flow/commands/onboard.md`). It is not a
   prefix of its siblings, so the palette ambiguity that motivated this question does not
   arise. `/dev-flow:init-codegraph`, `/dev-flow:init-hooks` and `/dev-flow:init-rules` keep
   their existing names — only the umbrella is named `onboard`.
4. **`install.sh:397` is updated** to point at `/dev-flow:onboard`, keeping the raw
   `codegraph init` in parentheses as the non-session fallback. This is in scope for this
   change (see section C), not deferred.

## Acceptance criteria

- [ ] `plugins/dev-flow/commands/init-codegraph.md` exists, has valid frontmatter with a
      `description`, no `argument-hint`, and covers: repo-root resolution, `command -v`
      graceful stop, `codegraph status --json` pre-check, `codegraph init -y`, idempotent
      `.gitignore` append, report.
- [ ] `plugins/dev-flow/commands/onboard.md` exists with `description` + `argument-hint`, and
      contains: the ordered step list, the artifact-ownership table, the explicit
      "`init-hooks` step 0 is already done" and "`setup-rules`/`init-rules` skip their
      hook-command step" instructions, the guard interrupt-and-resume contract, and the
      stack auto-detection rule.
- [ ] Neither new file references a nonexistent skill, command, template or script path.
- [ ] `bash .claude/test-cmd` exits 0.
- [ ] `plugins/dev-flow/.claude-plugin/plugin.json` version is `1.11.0`.
- [ ] `claude plugin details dev-flow` (after `claude plugin marketplace update
      dev-flow-marketplace && claude plugin update dev-flow@dev-flow-marketplace`) lists
      `onboard` and `init-codegraph` and reports `Skills (15)`.
- [ ] `README.md` line 1 says `v1.11`; the quick-start shows `/dev-flow:onboard`; the
      inventory table has both new command rows; `README.md:342`'s count and `:344`'s token
      figure match the real `plugin details` output.
- [ ] `install.sh:397`'s per-repo hint names `/dev-flow:onboard` and keeps `codegraph init`
      in parentheses; `bash -n install.sh` exits 0.
- [ ] No changes to `hooks/`, `agents/`, `skills/`, `templates/`, or to `install.sh` beyond
      that single `note` line.
