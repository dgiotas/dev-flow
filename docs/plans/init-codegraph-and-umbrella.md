# Plan: `/dev-flow:init-codegraph` and a `/dev-flow:onboard` umbrella

Spec: `docs/specs/init-codegraph-and-umbrella.md`
Slug: `init-codegraph-and-umbrella`
Branch: `feature/mcp-codegraph-registration` (continue on it)

## Before you start

**Nothing is blocked — the spec's four questions are all answered** (see its
*Resolved decisions*). The settled points that shape this plan:

1. Option (c) overlap resolution, as written: `init-hooks` owns
   `.claude/test-cmd` / `.claude/lint-cmd`; `init-rules` stays in the umbrella as
   a deduplicated top-up after `setup-rules`.
2. One confirmation, at the start (the announced step list), plus the unavoidable
   pre-write-guard stops. No per-step prompt.
3. The umbrella is **`/dev-flow:onboard`**, file
   `plugins/dev-flow/commands/onboard.md`. `/dev-flow:init-codegraph`,
   `/dev-flow:init-hooks` and `/dev-flow:init-rules` keep their names.
4. `install.sh:397`'s per-repo hint **is** updated (Task 8 is required, not
   optional).

All nine tasks are in scope. All paths are relative to the repo root
`/Users/dgiotas/Projects/personal/dev-flow`. Prefix any command with
`export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"` if it reports
`command not found`; on this machine `codegraph` is `/opt/homebrew/bin/codegraph`
(v1.6.0).

**Pre-write guard**: no task here writes `AGENTS.md`, `CLAUDE.md` or
`.claude/rules/*.md`, so the guard is not involved in *executing* this plan.
(`CLAUDE.md` is a symlink to `AGENTS.md` — do not touch it.) The throwaway
`.claude/rules/devflow-guard-probe.md` is only *described* in Task 3's prose, as
something the umbrella will do at run time — do not create it while writing the
plan's files.

**Every task is Markdown prose, or a one-line edit to `plugin.json`, `README.md`
or `install.sh`.** Do not write shell scripts. Do not invent behaviour for
`codegraph` — Task 1 is where you observe it.

---

## Task 1 — Capture the baseline evidence (evidence first, no edits)

**Files**: none. Write scratch output under the session scratchpad, not the repo.

**Evidence to capture** — run all of these and keep the output; later tasks cite it:

```bash
bash .claude/test-cmd; echo "test-cmd exit=$?"
ls plugins/dev-flow/commands
claude plugin details dev-flow | sed -n '1,12p'
grep -n 'Skills 13\|always-on tokens\|codegraph init' README.md
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json
```

**Expected (verified 2026-09-29)**:
- `test-cmd exit=0`
- commands: `build.md init-hooks.md init-rules.md spec.md` (4 files)
- `claude plugin details dev-flow` → `dev-flow 1.10.1`, `Skills (13)`,
  `Always-on:   ~1,760 tok`
- `README.md:342` contains `Skills 13 (9 skills + the 4 commands)`;
  `README.md:344` contains `~1,700 always-on tokens`; `README.md:23` and `:346`
  contain a bare `codegraph init`
- version `1.10.1`

Record the real `Always-on` number — Task 6 needs it again *after* the change.

**Verify**: all five commands produce output matching the above; note any drift.

**Depends on**: nothing.

---

## Task 2 — Write `plugins/dev-flow/commands/init-codegraph.md`

**Files**: create `plugins/dev-flow/commands/init-codegraph.md`.

**Evidence first (re-confirm on this machine before writing — do not trust the
spec's transcript blindly)**, in a throwaway repo under the scratchpad, never in
this repo and never in `$HOME`:

```bash
SP="$TMPDIR/cg-probe"; rm -rf "$SP"; mkdir -p "$SP"; cd "$SP"; git init -q
printf 'export function add(a,b){return a+b}\n' > a.js
codegraph status --json; echo "status_exit=$?"
codegraph init -y </dev/null 2>&1 | tail -8; echo "init ran"
codegraph status --json | jq '{initialized,fileCount,nodeCount}'
codegraph init -y </dev/null >/dev/null 2>&1; echo "rerun_exit=$?"
git status --porcelain
```

Expect: `initialized:false` then `true`; both init runs exit 0; the second prints
`Already initialized`; `git status` shows `?? .codegraph/` (the reason step 4 of
the new command exists). Delete `$SP` afterwards.

**Change**: a short command file (aim for 40-60 lines, i.e. comparable to
`init-rules.md`, not `init-hooks.md`) in the exact style of its siblings —
numbered `##` steps, imperative, "read, do not guess", one explicit verification
step, one report step. Frontmatter is `description:` only; no `argument-hint`,
no `model:` (match `init-hooks.md`/`init-rules.md`, which omit `model:`).

Content per the spec's section A, in order: 0 resolve repo root with
`git rev-parse --show-toplevel` and refuse to run outside a git repo or in `$HOME`
(and never pass `-f`); 1 `command -v codegraph` → if missing, print
`npm install -g @colbymchenry/codegraph` (or `bash install.sh`) and stop cleanly,
stating CodeGraph is optional and the MCP server is registered regardless;
2 `codegraph status --json` → if `.initialized`, skip and report `lastIndexed` /
`fileCount`, and suggest `codegraph sync` (do not run it) when `pendingChanges`
is non-zero; 3 `codegraph init -y </dev/null` at the repo root, expect exit 0 and
report the file/node/edge counts, on non-zero report verbatim and stop;
4 idempotently append `.codegraph/` to the repo's `.gitignore`, checking first,
and explain in the report that `init` already writes `.codegraph/.gitignore` (so
the database was never committable) and the repo-level entry is what keeps
`git status` clean; 5 report, ending with how to use it
(`plugin:dev-flow:codegraph` MCP tools, `claude mcp list` to confirm).

Do not restate `codegraph --help`. No other `codegraph` subcommand is documented
here.

**Verify**:
```bash
bash .claude/test-cmd; echo "exit=$?"                     # expect 0
head -4 plugins/dev-flow/commands/init-codegraph.md       # expect ---/description:/---
wc -l plugins/dev-flow/commands/init-codegraph.md         # expect < 70
grep -c 'CLAUDE_PLUGIN_ROOT' plugins/dev-flow/commands/init-codegraph.md  # expect 0
```

**Depends on**: Task 1.

---

## Task 3 — Write `plugins/dev-flow/commands/onboard.md` (the umbrella)

**Files**: create `plugins/dev-flow/commands/onboard.md`. The name is settled —
`onboard`, not `init`; do not create `commands/init.md`.

**Evidence first**: re-read all three delegated files end to end and confirm the
line references the spec relies on still hold — paste the four `path:line` hits:

```bash
sed -n '10,12p;44,48p;82,84p' plugins/dev-flow/commands/init-hooks.md
sed -n '8,12p' plugins/dev-flow/commands/init-rules.md
sed -n '54,57p;71,82p' plugins/dev-flow/skills/setup-rules/SKILL.md
```

Expect: `init-hooks.md:10` = the step-0 guard-proof heading; `:48` = "AGENTS.md,
then CLAUDE.md" as the first command authority; `:82-84` = `test-cmd-retries`;
`init-rules.md:12` = the "offer to create `.claude/test-cmd`" step;
`SKILL.md:54-57` = the hook-command step; `:71-82` = the blocked-write flow. If
any has moved, update the spec's citations before writing.

**Change**: a command file in the sibling style. Frontmatter:
```
description: <one sentence: run this repo's whole dev-flow onboarding in order — CodeGraph index, guidance file and rules, then verified hook commands — pausing for approval at every guarded write.>
argument-hint: [php|java|python|node|all] [retries=N] [force-container] [force-host]
```
No `model:`.

Body sections, in this order:

1. **How this runs** — it is interactive and interruptible, not a batch job;
   every step is idempotent so re-running resumes; the pre-write-guard *will*
   stop it on any repo that already has `AGENTS.md`, `CLAUDE.md` or
   `.claude/rules/*.md` (so on every second run), and that is by design.
2. **Who owns what** — reproduce the spec's artifact-ownership table, including
   the three skip instructions: `init-hooks` step 0 is already done; `setup-rules`
   skips its hook-command step (`SKILL.md:54-57`); `init-rules` skips its
   offer-to-create step (`init-rules.md:12`).
3. **Step 0 — prove the guard is live, once.** Instruct: perform
   `/dev-flow:init-hooks` step 0 as written there (probe
   `.claude/rules/devflow-guard-probe.md`, delete it either way, never probe
   `AGENTS.md`, never create a marker) and stop with that command's remediation
   if the probe is not blocked. Report the plugin root and version here, once.
   Do **not** copy the step's text — reference it.
4. **Step 0.5 — announce the plan.** Detect the stack from manifests and run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guidance-target.sh"`; print the ordered
   step list, the detected stack with its evidence, and the guidance target; get
   an explicit go-ahead before any write. Ask for the stack only if detection
   finds nothing or is ambiguous. State that this is the **only** confirmation the
   command asks for — after the go-ahead it runs all the steps without pausing
   again, except where the pre-write-guard blocks it.
5. **Steps 1-4** — one short block each, delegating by reference:
   1 `/dev-flow:init-codegraph`; 2 the `setup-rules` skill, guidance + path-scoped
   rules only; 3 `/dev-flow:init-hooks` with `retries=N`/`force-*` passed through
   and its step 0 skipped; 4 `/dev-flow:init-rules <stack>` as a deduplicated
   top-up, skipped with a stated reason when no stack was detected or every
   template is already covered. Each block states *why it is in that position*
   in one line (see the spec's ordering rationale) so the order is not reshuffled
   later by accident.
6. **If a step is blocked** — stop; show the hook's change verbatim; wait for an
   explicit yes in this turn; run the exact marker command the hook gave; retry
   the same call unchanged; continue to the next step. Forbid, in these words:
   batching approvals, pre-creating markers, splitting a change to get past the
   gate, switching tools, deleting and recreating a file, and creating
   `ALLOW-CLAUDE-MD-EDIT`.
7. **Report** — one line per step (done / skipped + why / blocked-then-approved /
   abandoned), files written, and the follow-ups `init-hooks.md:100-101` already
   prescribes (commit advice; gitignore `.claude/.stop-gate-state`,
   `.claude/stop-gate-giveup.log`, `.claude/.approved-writes/`).

Keep it under ~90 lines. It must contain no copy of another file's steps and no
shell beyond the two commands named above.

**Verify**:
```bash
bash .claude/test-cmd; echo "exit=$?"                                  # expect 0
head -5 plugins/dev-flow/commands/onboard.md                           # frontmatter present
wc -l plugins/dev-flow/commands/onboard.md                             # expect < 100
grep -o 'dev-flow:[a-z-]*' plugins/dev-flow/commands/onboard.md | sort -u
# expect exactly: dev-flow:init-codegraph, dev-flow:init-hooks, dev-flow:init-rules
# (the file need not name itself; if it does, dev-flow:onboard is the only extra allowed)
grep -c 'setup-rules' plugins/dev-flow/commands/onboard.md             # expect >= 2
ls plugins/dev-flow/commands/init.md 2>/dev/null; echo "stray init.md? exit=$?"
# expect "No such file" / exit != 0 — the umbrella is onboard.md, not init.md
```

**Depends on**: Task 2 (it references `/dev-flow:init-codegraph`).

---

## Task 4 — Prove both new files reference only things that exist

**Files**: none (read-only check).

**Change**: none. This is the verification that `.claude/test-cmd` cannot do,
since it only covers `*.json` and `*.sh`.

**Verify** — run all four and require a clean result:

```bash
# 1. every ${CLAUDE_PLUGIN_ROOT}/... path referenced anywhere still exists
grep -rhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/-]+' \
  plugins/dev-flow/commands plugins/dev-flow/skills plugins/dev-flow/agents \
  | sed 's|${CLAUDE_PLUGIN_ROOT}/||' | sort -u \
  | while read -r p; do [ -e "plugins/dev-flow/$p" ] && echo "OK   $p" || echo "MISS $p"; done

# 2. every /dev-flow:<cmd> mentioned has a commands/<cmd>.md
grep -rhoE '/dev-flow:[a-z-]+' plugins/dev-flow | sed 's|/dev-flow:||' | sort -u \
  | while read -r c; do [ -f "plugins/dev-flow/commands/$c.md" ] && echo "OK   $c" || echo "MISS $c"; done

# 3. frontmatter: first line is --- and a description: exists in every command
for f in plugins/dev-flow/commands/*.md; do
  [ "$(head -1 "$f")" = "---" ] && grep -q '^description:' "$f" && echo "OK   $f" || echo "BAD  $f"
done

# 4. repo test suite
bash .claude/test-cmd; echo "test-cmd exit=$?"
```

**Expected**: check 1 prints only `OK` (baseline is the four lines
`scripts/guidance-target.sh`, `templates/lint-cmd.docker.example`,
`templates/rules/`, `templates/test-cmd.docker.example`); checks 2 and 3 print
only `OK`, and check 2 now includes `init-codegraph` (plus `onboard` if the
umbrella names itself);
`test-cmd exit=0`. Any `MISS`/`BAD` means fix the file, not the check.

**Depends on**: Tasks 2, 3.

---

## Task 5 — Bump the plugin version to `1.11.0`

**Files**: `plugins/dev-flow/.claude-plugin/plugin.json` (the `version` field only).

**Evidence first**: `jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json`
→ `1.10.1`; `git show main:plugins/dev-flow/.claude-plugin/plugin.json | jq -r .version`
→ `1.10.0`. Two additive commands, nothing removed or renamed → semver MINOR, and
the bump is this repo's only release signal.

**Change**: `"version": "1.10.1"` → `"version": "1.11.0"`. Nothing else in the
file; the `description` stays as is ("nine dev skills" is still accurate — these
are commands).

**Verify**:
```bash
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json   # expect 1.11.0
bash .claude/test-cmd; echo "exit=$?"                          # expect 0 (validates the JSON)
```

**Depends on**: nothing (but do it before Task 6, which needs the new version
installed).

---

## Task 6 — Re-verify the component inventory against a real install

**Files**: none.

**Change**: none. This produces the numbers Task 7 writes into the README. Do not
let Task 7 guess them.

**Verify**:
```bash
claude plugin marketplace update dev-flow-marketplace
claude plugin update dev-flow@dev-flow-marketplace
claude plugin details dev-flow | sed -n '1,12p'
```

**Expected**: header reads `dev-flow 1.11.0`; the `Skills (…)` line is **15** and
lists `onboard` and `init-codegraph` alongside the existing 13; `Agents (3)`,
`Hooks (3)`, `MCP servers (4)` unchanged. Record the exact `Always-on: ~N tok`
figure — it was `~1,760` at `1.10.1` and will rise.

If `Skills` is not 15 or the new commands are missing, the files are not being
picked up (stale cache / `/reload-plugins` needed) — report that instead of
editing the README to match a wrong number.

**Depends on**: Tasks 2, 3, 5.

---

## Task 7 — Update `README.md`

**Files**: `README.md` only. (`AGENTS.md` is deliberately not touched — the
project instructions there describe four commands; see the note at the end of
this plan.)

**Evidence first**: `grep -n 'v1.10\|Skills 13\|always-on tokens\|codegraph init' README.md`
and the recorded output of Task 6. Every number written below must come from Task
6's output, not from arithmetic.

**Change**, five edits:
1. `README.md:1` — `(v1.10)` → `(v1.11)`.
2. `README.md:17-24` — the "once per repo you work in" block becomes a single
   `/dev-flow:onboard` line with a one-sentence description, then a short "or run the
   steps yourself" sub-block keeping the existing four lines with
   `/dev-flow:init-codegraph` replacing the bare `cd <repo> && codegraph init`,
   plus one sentence: the guard will interrupt the umbrella on a repo that already
   has guidance files, and that is intended.
3. `README.md:93-116` inventory table — add two `| Command |` rows after the
   `/dev-flow:init-hooks` row: `/dev-flow:init-codegraph` and `/dev-flow:onboard`
   (put the umbrella first if that reads better; keep the Command rows contiguous).
4. `README.md:342` — `Skills 13 (9 skills + the 4 commands)` → the real count from
   Task 6 (`Skills 15 (9 skills + the 6 commands)`), and `README.md:344`'s
   `~1,700 always-on tokens` → the real figure from Task 6.
5. `README.md:346` — "run `codegraph init`" → "run `/dev-flow:init-codegraph`
   (or `codegraph init`)".

Do not restate anything the README currently marks unverified as settled
(`README.md:319`, `:350`). The umbrella has not been run in a live session, so if
you add a line about it anywhere near *Known limits*, mark it unverified.

**Verify**:
```bash
grep -n 'v1.11' README.md | head -1
grep -n 'dev-flow:onboard' README.md          # quick-start + inventory row
grep -n 'dev-flow:init-codegraph' README.md   # quick-start + inventory row + troubleshooting
grep -n 'Skills 15' README.md
grep -rn 'Skills 13\|4 commands' README.md    # expect no output
grep -rn 'dev-flow:init\b' README.md          # expect no output (no bare `/dev-flow:init`)
bash .claude/test-cmd; echo "exit=$?"         # expect 0
```

**Depends on**: Task 6 (for the two numbers), Tasks 2-3 (for the command names).

---

## Task 8 — Update `install.sh`'s per-repo hint

**Files**: `install.sh` (the `note` line at `install.sh:397` only).

**Change**: `note "per repo, once:  cd <repo> && codegraph init   (add .codegraph/ to .gitignore)"`
→ point at `/dev-flow:onboard`, which covers the index *and* the `.gitignore`
entry *and* the rest of the per-repo setup, keeping the raw `codegraph init` in
parentheses as the fallback for someone not in a Claude Code session. Exactly one
line changes; same `note` helper, same position — do not restructure section 3,
do not add a step.

**Verify**:
```bash
bash -n install.sh; echo "syntax exit=$?"                       # expect 0
grep -n 'per repo' install.sh                                   # expect the new /dev-flow:onboard text
bash install.sh --dry-run -y --skip-superpowers 2>&1 | grep -i 'per repo'
git diff --stat install.sh                                      # expect 1 file, 1 insertion, 1 deletion
bash .claude/test-cmd; echo "exit=$?"                           # expect 0
```

**Expected**: the new hint names `/dev-flow:onboard` and still shows
`codegraph init` in parentheses; no other plan-output line changes.

**Depends on**: Task 3 (the hint names the umbrella, so the command must exist).

---

## Task 9 — Commit

**Files**: none beyond staging.

**Change**: one commit on `feature/mcp-codegraph-registration`. Do **not** push,
merge or open a PR without being asked. No AI-attribution trailer of any kind in
this repo (AGENTS.md *Conventions*).

**Verify**:
```bash
git status --porcelain
git diff --cached --stat
bash .claude/test-cmd; echo "exit=$?"
```

**Expected staged set**, seven paths:
`plugins/dev-flow/commands/init-codegraph.md` (new),
`plugins/dev-flow/commands/onboard.md` (new),
`plugins/dev-flow/.claude-plugin/plugin.json`, `README.md`, `install.sh`,
`docs/specs/init-codegraph-and-umbrella.md`,
`docs/plans/init-codegraph-and-umbrella.md`.
No `plugins/dev-flow/commands/init.md` — the umbrella is `onboard.md`.
The already-approved CodeGraph MCP registration changes on this branch come along
in the same or a preceding commit — do not revert them.

**Depends on**: Tasks 2-8.

---

## Note for whoever executes this

`AGENTS.md` (via the `CLAUDE.md` symlink) lists the commands as
"(`/dev-flow:spec`, `/dev-flow:build`, `/dev-flow:init-hooks`,
`/dev-flow:init-rules`)". That line becomes stale with this change — it should end
up naming six commands, the two new ones being `/dev-flow:init-codegraph` and
`/dev-flow:onboard`. It is **deliberately not a task here**: `AGENTS.md` is
guard-protected and needs the user's explicit diff approval, so raise it at the end
as a separate, one-line proposal rather than bundling it in.

## Acceptance criteria (for `verify-done`)

- [ ] `plugins/dev-flow/commands/init-codegraph.md` exists, `< 70` lines, valid
      frontmatter with `description` and no `argument-hint`.
- [ ] `plugins/dev-flow/commands/onboard.md` exists, `< 100` lines, has
      `description` + `argument-hint`, the ownership table, the three skip
      instructions, the guard interrupt/resume contract, the single-confirmation
      rule, and the stack auto-detection rule. No `commands/init.md` was created.
- [ ] Task 4's four checks all print only `OK` / exit 0.
- [ ] `jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json` → `1.11.0`.
- [ ] `claude plugin details dev-flow` → `dev-flow 1.11.0`, `Skills (15)`
      including `onboard` and `init-codegraph`, `Agents (3)`, `Hooks (3)`,
      `MCP servers (4)`.
- [ ] `README.md` says `v1.11`, shows `/dev-flow:onboard` in the quick-start, has
      both new inventory rows, and both
      `grep -rn 'Skills 13\|4 commands' README.md` and
      `grep -rn 'dev-flow:init\b' README.md` are empty.
- [ ] `install.sh`'s per-repo hint names `/dev-flow:onboard` with `codegraph init`
      in parentheses; `bash -n install.sh` exits 0; `git diff --stat install.sh`
      shows one changed line.
- [ ] `bash .claude/test-cmd` exits 0.
- [ ] `git diff --stat` touches only: the two new command files, `plugin.json`,
      `README.md`, `install.sh`, and the two `docs/` files.
- [ ] Nothing pushed, merged or force-pushed; no attribution trailer in the commit.
