# Spec: compaction snapshot (PreCompact save, SessionStart restore)

## Problem

`/dev-flow:spec` writes `docs/specs/<slug>.md` and `docs/plans/<slug>.md`, and
`/dev-flow:build <slug>` then works through the plan one task at a time. When
the context window fills, Claude Code compacts the conversation and that
working state is lost: which plan was active, how far through it the session
was, the git state, and what was blocked. After compaction the session often
resumes confused or redoes work.

## Goal

- A `PreCompact` hook, `pre-compact-snapshot.sh`, writes a small, content-free
  state file, `.claude/.devflow-state.json`, in the project root.
- A `SessionStart` hook, `session-start-restore.sh`, reads that file. If it is
  fresh (saved less than 24 hours ago) and parses, the hook injects a plain-text
  summary of at most 15 lines into the session's context.
- Neither hook can block anything. Every failure path (no jq, no plan, not a
  git repo, unreadable or unwritable directory, malformed JSON) ends in exit 0.
- The README documents the feature, including what it deliberately does not
  capture, and adds the state file to its gitignore guidance.

## Non-goals

- Capturing anything from the conversation, the transcript, prompts, file
  contents, or `custom_instructions`. The payload's free-text fields are never
  read.
- Changing how `/dev-flow:build` or the `implementer` agent records progress.
  Nothing in the workflow ticks tasks or writes `BLOCKED` into the plan file
  today (see *Current behaviour*). This feature reads what is there. It does not
  start writing it (see Open question 1).
- A manual or instruction-level substitute in hookless mode (see design §6).
- An opt-out switch, a configurable freshness window, or snapshot history.
- Changing `stop-gate.sh` (see Open question 2 for the one case where that
  would be needed).

## Current behaviour

- `plugins/dev-flow/hooks/hooks.json:1-27` wires three events: `PreToolUse`
  (`pre-write-guard.sh`, matcher `Write|Edit|MultiEdit|Bash`), `PostToolUse`
  (`post-edit-check.sh`, matcher `Write|Edit|MultiEdit`) and `Stop`
  (`stop-gate.sh`, no matcher). Every entry is
  `{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh\"" }`.
  There is no `PreCompact` or `SessionStart` entry.
- Hook script conventions (`.claude/rules/hook-scripts.md:5-10`): `set -u`,
  read stdin once with `input=$(cat)`, pull fields with `jq -r '... // empty'`,
  `cd "${CLAUDE_PROJECT_DIR:-.}"` before repo-relative paths, skip (never fail)
  on missing tools. `.claude/rules/hook-scripts.md:6` says "stdout is ignored by
  the harness". That is true for the three existing events, but **not for
  `SessionStart`**, where stdout becomes context (see *Platform facts*).
- Project root: every existing hook uses `CLAUDE_PROJECT_DIR`, with `.` as the
  fallback (`stop-gate.sh:10`, `post-edit-check.sh:18`,
  `pre-write-guard.sh:123`). None reads the payload's `cwd`.
- `stop-gate.sh:8` reads stdin only to satisfy the contract ("consumed for API
  compliance; not otherwise used").
- Stop-gate state (`stop-gate.sh:23-24,33-37,47-49,61-69`):
  - `.claude/.stop-gate-state` holds a bare decimal attempt counter. It is
    written on each failed run (`:49`) and deleted on pass (`:43`) or give-up
    (`:61`). It is read back with `tr -dc '0-9'` (`:35`).
  - `.claude/stop-gate-giveup.log` is **appended** (`tee -a`, `:69`) with a
    banner and the last 60 lines of test output. It records **no timestamp and
    no session id**. Whether it was written "in this session" therefore cannot
    be determined from what the stop gate writes (see design §3).
- The `implementer` escalates by replying `BLOCKED: <reason>`
  (`plugins/dev-flow/agents/implementer.md:22`). `build.md:14` stops and reports
  to the user when that happens. **Neither writes `BLOCKED` into the plan
  file.** A `BLOCKED` line appears in a plan only if a person or agent puts it
  there.
- Plan format: every plan in `docs/plans/` uses `## Task N` headings (for
  example `docs/plans/managed-hooks-fallback.md:30,107,...`) with **no
  per-task completion marker**. Four of the six existing plans also end with
  an "Acceptance criteria" checklist of `- [ ]` items
  (`docs/plans/managed-hooks-fallback.md:486-498`). Nothing ticks them during
  a build. No plan contains `- [x]` (checked 2026-10-02: `grep -c` gives 0 in
  all six).
- `.gitignore:1-3` already lists `.claude/.approved-writes/`,
  `.claude/.stop-gate-state` and `.claude/stop-gate-giveup.log`. `AGENTS.md:45`
  (Hazards) says to keep hook state files gitignored.
- README gitignore guidance appears in three places: `README.md:318` (Stop
  gate), `README.md:384` (Per-repo config files), and `README.md:158` (the
  per-repo leftovers `rm` line in Uninstalling). `init-hooks.md:179` and
  `onboard.md:122-124` repeat the reminder at the end of those commands.
- Hookless mode (`README.md:320-342`, `docs/specs/managed-hooks-fallback.md`):
  when managed settings block plugin hooks, *no* dev-flow hook runs, and
  `init-hooks`/`onboard` continue with instruction-level substitutes for the
  three gates (`README.md:334-338`). That is a per-gate substitute table, not a
  generic "run every hook by hand" mechanism.
- `README.md:322` says "none of dev-flow's three hooks", `README.md:502` says
  the inventory shows "Hooks 3 (PreToolUse, PostToolUse, Stop)", and
  `AGENTS.md:23-24` says hooks.json wires three events / "the three hooks".
  All three become stale with this change.
- Environment: Claude Code `2.1.280` (`claude --version`, 2026-10-02). The
  host has `/bin/bash` 3.2.57 and `jq-1.7.1-apple` at `/usr/bin/jq`, so the
  scripts must stay bash-3.2 compatible (no `mapfile`, no `${x,,}`).
  `date -r <file>` prints a file's mtime on macOS and GNU date alike (checked
  here). `jq`'s `fromdateiso8601` parses `YYYY-MM-DDTHH:MM:SSZ` (checked
  here).

## Platform facts (Step 1 verification)

Source: https://code.claude.com/docs/en/hooks, fetched 2026-10-02 (sections
"When each event fires", "Matcher patterns", "Common input fields",
"PreCompact", "PostCompact", "SessionStart", "SessionStart decision control",
"Add context for Claude", "Exit code 0", "Exit code 2 behavior per event",
"JSON output"). Checked against the documentation only, not yet observed in a
live session (the evidence task runs the scripts directly).

- **Both events exist.** The event table lists `SessionStart` (per session),
  `PreCompact` (sequential), and also `PostCompact` (async), among about 30
  events. No fallback to `Stop` is needed.
- **PreCompact payload.** Common fields `session_id`, `transcript_path`,
  `cwd`, `hook_event_name` (plus optional `prompt_id`, `scratchpad_dir`,
  `permission_mode`, `agent_id`, `agent_type`), and two event fields:
  - `trigger`: `"manual"` (`/compact`) or `"auto"` (context size);
  - `custom_instructions`: an object with optional `user` / `project` /
    `local` strings. This is **free text**, so it is never read.
- **PreCompact matcher** values: `manual`, `auto`. We register with **no
  matcher**, so both are covered.
- **PreCompact can block.** "Exit code 2 behavior per event": `PreCompact`,
  "Yes", "Blocks compaction". JSON `{"decision":"block"}` also blocks.
  Therefore the snapshot script **never exits 2 and never prints to stdout**
  (its stdout is sent to `/dev/null` inside the script), so it cannot
  accidentally emit a decision object. On exit 0, plain stdout goes to the
  debug log only.
- **SessionStart payload.** Common fields plus `source` (`startup`, `resume`,
  `clear`, `compact`, `fork`), and optional `model`, `agent_type`,
  `session_title`.
- **SessionStart matchers**: `startup`, `resume`, `clear`, `compact`, `fork`.
  `compact` fires "after compaction" (auto or manual).
- **SessionStart cannot block.** Exit 2 "Shows stderr to user only". We
  still always exit 0.
- **Context injection, confirmed from the docs, not guessed.** Exit 0 with
  this JSON on stdout:
  ```json
  { "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "<text>" } }
  ```
  The docs also state that plain (non-JSON) stdout on `SessionStart` "already
  reaches Claude", so JSON is not strictly required. We use the JSON form
  because it is the documented structured mechanism, the user asked for it,
  and `jq -n --arg` gives correct escaping. The text arrives as a system
  reminder "at the start of the conversation, before the first prompt".
- **Size cap**: each `additionalContext` is capped at 10,000 characters. 15
  lines of at most about 210 characters is well under that.
- **Phrasing**: the docs advise writing `additionalContext` as factual
  statements, because imperative "system instruction" phrasing can trigger
  prompt-injection defences. The summary is worded as facts.
- **Environment**: `CLAUDE_PROJECT_DIR` ("the project root where the session
  started") and `CLAUDE_PLUGIN_ROOT` are available to hook commands. The
  default command timeout is 600 s for both events.
- Stdout handling: "Starts with `{` and ends with `}`" is parsed as JSON. The
  restore script prints exactly one JSON object or nothing.

## Proposed design

### 1. State file schema (`.claude/.devflow-state.json`)

```json
{
  "schema_version": "1",
  "saved_at": "2026-10-02T10:00:00Z",
  "plan": { "file": "docs/plans/test-feature.md", "slug": "test-feature", "done": 2, "total": 4 },
  "git": { "branch": "feature/test-feature", "head": "a1b2c3d", "staged": 1, "unstaged": 1, "untracked": 1 },
  "stop_gate": { "state": 2, "giveup_logged_at": null },
  "blocked": ["BLOCKED: something"]
}
```

- `saved_at`: `date -u +%Y-%m-%dT%H:%M:%SZ` (UTC with `Z`, so jq's
  `fromdateiso8601` parses it portably).
- `plan.file` is repo-relative (`docs/plans/<name>.md`). It is never absolute.
- `plan.done` / `plan.total` are numbers or both `null` (§2).
- `git` is `null` outside a git work tree. `branch` is `null` when detached
  (`HEAD`) or unresolvable. `head` is `null` before the first commit.
- `stop_gate.state` is the integer in `.claude/.stop-gate-state` (digits only,
  as in `stop-gate.sh:35`), or `null` when the file is absent or empty.
- `stop_gate.giveup_logged_at` is the giveup log's mtime as UTC ISO-8601, or
  `null` (§3).
- `blocked` is an array (possibly empty) of at most 10 strings.

Nothing else is written. In particular: no `trigger`, `session_id`,
`transcript_path`, `cwd` or `custom_instructions`.

### 2. `pre-compact-snapshot.sh`

Shape (bash 3.2, about 70 lines):

```bash
set -u
input=$(cat) # consumed for API compliance; not otherwise used
snapshot() ( ... )            # subshell: set -u aborts or any error stay contained
snapshot >/dev/null 2>&1      # nothing on stdout, ever: no accidental decision JSON
exit 0
```

Inside `snapshot`:
1. `command -v jq` or return. **Without jq, no snapshot is written.**
   Hand-building JSON with arbitrary `BLOCKED` text in bash is exactly the
   escaping risk we avoid. This is the graceful degradation.
2. `cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0`. This is the same root rule as
   every existing hook (`stop-gate.sh:10`). The payload `cwd` is not used: it
   can be a subdirectory, and the existing hooks don't use it.
3. **Active plan**: `plan=$(ls -t docs/plans/*.md 2>/dev/null | head -1)`.
   `ls -t` sorts by mtime on both BSD and GNU, and avoids `stat -f` vs
   `stat -c`. If there is no plan (no directory, no `.md`), **exit without
   writing**. A snapshot without a plan has nothing worth restoring. Any
   existing state file is left alone; it still ages out after 24 h.
   `slug=$(basename "$plan" .md)`.
4. **Checklist counts.** Rule: a checklist item is a line matching
   `^[[:space:]]*[-*] \[[ xX]\]` (a GitHub task-list item). `total` counts
   them; `done` counts those matching `^[[:space:]]*[-*] \[[xX]\]`. If
   `total` is 0, both are `null`. Why this format: it is the only
   machine-readable completion marker in markdown, it is unambiguous, and
   `grep -c` counts it the same way on BSD and GNU. `## Task N` headings carry
   no completion state, so they cannot give "completed". **Caveat** (Open
   question 1): in dev-flow's own plans the only checkboxes are the
   acceptance criteria, so for those plans this counts acceptance items (for
   example "0 of 13"), not tasks. The restore text therefore says "checklist
   items", never "tasks".
5. **Git** (only if `git rev-parse --is-inside-work-tree` succeeds):
   - branch: `git symbolic-ref --short -q HEAD` (works before the first
     commit; empty when detached, giving `null`);
   - head: `git rev-parse --short HEAD` (fails before the first commit,
     giving `null`);
   - counts: `git --no-optional-locks status --porcelain`, then awk on the
     two status columns: `??` gives untracked; otherwise X≠space gives staged
     and Y≠space gives unstaged (a file can count in both). `--no-optional-locks`
     keeps the hook from taking `index.lock` while the user's own git
     commands may be running. Only counts are kept; the file names never
     leave awk.
6. **Stop gate**: `state` from `tr -dc '0-9' < .claude/.stop-gate-state`.
   `giveup_logged_at` from `date -u -r .claude/stop-gate-giveup.log +%Y-%m-%dT%H:%M:%SZ`
   when the file exists.
7. **Blocked**: one jq pass over the plan as raw text:
   `jq -R -s 'split("\n") | map(select(contains("BLOCKED")) | gsub(<abs-path-regex>; "<path>") | .[0:200]) | .[0:10]'`.
   The match is literal and case-sensitive. Redaction runs **before**
   truncation. Truncation is by codepoint (jq string slice), so multibyte
   text is never cut mid-character.
8. Assemble with `jq -n --arg/--argjson ...`, write to
   `.claude/.devflow-state.json.tmp`, then `mv` over the real file, so a
   crash mid-write never leaves a half-written file for restore to read.
   `mkdir -p .claude` first. If the directory is unwritable the write fails
   inside the subshell, and the script still exits 0.

**Absolute-path redaction in BLOCKED lines.** The privacy constraint ("no
absolute paths") is explicit, and truncation alone does not meet it, because
a `BLOCKED:` line can easily name `/Users/me/repo/src/x.php`. Rule: any run
of non-delimiter characters that starts with `/` at the start of the line or
after whitespace or one of `"'`(=:` becomes `<path>`:
`gsub("(?<![^\\s\"'`(=:])/[^\\s\"'`)]*"; "<path>")` (Oniguruma lookbehind,
supported by jq 1.6+). `and/or` and `src/x.php` are left alone, because the
`/` follows a word character. Residual risk: a path in a form the rule
doesn't recognise (for example a Windows `C:\...` path, or one glued to a
word character such as `dir=x/Users/me`) passes through, and `BLOCKED`
text is free prose written by whoever wrote it. That is the limit the user
set ("BLOCKED lines are the limit").

### 3. "giveup.log written in this session": cannot be determined reliably

`stop-gate.sh:62-69` appends a banner with no timestamp and no session id.
The hook payload's `session_id` cannot be matched against anything in the
log. The session start time is not in the PreCompact payload. The transcript
format is undocumented, and its first lines carry `"timestamp": null` (checked
on a local transcript, metadata keys only). So a true "this session" boolean
would be a guess.

The closest honest field, used here: **`giveup_logged_at`**, the log's last
modification time (UTC ISO-8601, from `date -u -r`). The restore text states
it as a fact ("the stop gate's give-up log was last written at T"), and the
reader can compare it with `saved_at`. A true per-session boolean needs
`stop-gate.sh` to record the session id. That is Open question 2, and it is
not done here.

### 4. `session-start-restore.sh`

Shape:

```bash
set -u
input=$(cat) # consumed for API compliance; not otherwise used
restore() ( ... )             # prints one JSON object on success, nothing otherwise
restore 2>/dev/null
exit 0
```

Inside `restore`:
1. `command -v jq` or exit (silent).
2. `cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0`; `f=.claude/.devflow-state.json`;
   `[ -f "$f" ] || exit 0`.
3. Freshness and schema in one check:
   `jq -e '.schema_version == "1" and ((now - (.saved_at | fromdateiso8601)) < 86400)' "$f"`.
   If this fails (malformed JSON, a wrong or missing `saved_at`, an old file,
   or an unknown schema), exit 0 silently.
4. Build the text with a single `jq -r` program. Any jq error (for example
   `plan` missing) means exit 0 silently. Lines, in order, each omitted when
   noted:
   ```
   dev-flow state saved before the last context compaction at <saved_at>; docs/plans is the source of truth.
   Active plan: <plan.file> (slug <slug>); <N> of <M> checklist items checked.     # or "checklist progress not countable."
   Git: branch <branch|detached> at <head|no commits>; <s> staged, <u> unstaged, <t> untracked files.   # omitted when git is null
   Stop gate: <state> failed attempt(s) recorded; give-up log last written at <ts>.  # each clause only if non-null; line omitted if both null
   Blocked lines in the plan:                                                        # omitted when blocked is empty
   - <blocked[0]> … up to 10
   ```
   That gives a maximum of 1+1+1+1+1+10 = **15 lines**. Every value
   interpolated from the file is passed through jq's string handling. Nothing
   is `eval`'d.
5. Print `jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'`.

The restore never deletes or rewrites the state file.

### 5. Registration (`hooks/hooks.json`)

Add two keys after `Stop`, in the existing style:

```json
"PreCompact": [
  { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/pre-compact-snapshot.sh\"" } ] }
],
"SessionStart": [
  { "matcher": "startup|resume|compact",
    "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-start-restore.sh\"" } ] }
]
```

- PreCompact gets no matcher, so manual and auto compaction are both covered.
- SessionStart uses `startup|resume|compact`. `compact` is the core case.
  `startup`/`resume` are included because the user's 24-hour freshness window
  only makes sense if a *later* session can pick the snapshot up. `clear` is
  excluded, because `/clear` is a deliberate wipe and re-injecting would undo
  it. `fork` is excluded, because a fork already carries the conversation.
  This choice is Open question 3.
- No explicit `timeout`, matching the existing entries.

### 6. Hookless mode

In hookless mode no plugin hook runs (`README.md:322`), so neither script
runs. No state file is written and nothing is injected. The feature is
simply absent, which is the same "optional" behaviour as the other hooks.
There is no meaningful instruction-level substitute: auto-compaction is
triggered by the harness, not by the model, so the model cannot be told to
"snapshot first". The hookless table (`README.md:334-338`) gets one row
saying exactly that, with the plan file in `docs/plans/` as the durable
record. `init-hooks`/`onboard` need no change for hookless mode.

### 7. Documentation and release

- README:
  - A new `### Compaction snapshot` subsection under Documentation, after
    `### Stop gate` and before `### Managed settings…`. It covers what is
    captured, the exact fields, when it is restored, an example of the
    injected text, **what it deliberately does not capture**, the
    `giveup_logged_at` limitation, the checklist caveat, the
    BLOCKED-in-plan caveat, and "verified by running the scripts directly;
    not yet observed in a live compaction".
  - Two rows in the "Other Commands, Skills and Agents" table
    (`pre-compact-snapshot`, `session-start-restore`).
  - A hookless-table row.
  - `README.md:322`: "three hooks (…)" becomes "hooks (pre-write guard,
    per-edit check, stop gate, compaction snapshot)".
  - `README.md:502`: the inventory line becomes `Hooks 5 (…, PreCompact,
    SessionStart)`. Unverified until installed (the order printed by
    `claude plugin details` may differ).
  - One Known-limits bullet.
- Gitignore guidance: add `.claude/.devflow-state.json` next to the existing
  state files at `README.md:384` (the all-files sentence) and `README.md:158`
  (the per-repo leftovers `rm` line). The new section carries its own "Add …
  to `.gitignore`" line, the way `### Pre-write guard` does at
  `README.md:271`. The Stop gate bullet at `README.md:318` stays, listing
  only that hook's files. Also add the file to this repo's `.gitignore`, and
  (Open question 4) to the `init-hooks.md:179` / `onboard.md:123` reminders. Why it matters beyond
  tidiness: `stop-gate.sh:17-18` treats any untracked file as "something
  changed", so an un-ignored state file makes the stop gate run
  `.claude/test-cmd` on otherwise pure-Q&A turns.
- `AGENTS.md` (guarded; `CLAUDE.md` is a symlink, never edit it): the
  Layout lines 23-24 (five events, "the five hooks") and Hazards line 45 (add
  the state file).
- `.claude/rules/hook-scripts.md:6` (guarded): qualify "stdout is ignored"
  with "except `SessionStart`, where stdout is injected as context", and
  "Exit 2 = block" with "never on PreCompact/SessionStart here". Without this
  the rule actively misleads the next edit of the restore script.
- Version `1.13.0` becomes `1.14.0` (a minor bump: new feature, no breaking
  change).

## Data flow

```
compaction (auto|manual)
  -> PreCompact -> pre-compact-snapshot.sh
       stdin payload (ignored) ; cd $CLAUDE_PROJECT_DIR
       ls -t docs/plans/*.md | head -1  -> none? exit 0 (no write)
       grep -c checklist ; git status --porcelain | awk counts ; stop-gate files ; jq BLOCKED filter
       jq -n > .claude/.devflow-state.json.tmp ; mv -> .claude/.devflow-state.json
       exit 0, stdout empty                      (compaction proceeds)
  -> compaction runs
  -> SessionStart(source=compact) -> session-start-restore.sh
       state fresh (<24h) and schema 1? -> jq builds <=15 lines -> {"hookSpecificOutput":{...}}
       otherwise: no output
       exit 0                                    (session proceeds)
later: new session (startup|resume) within 24h -> same restore path
```

## Risks and edge cases

- **Wrong "active plan".** mtime picks the most recently *written* plan.
  Building plan A after writing plan B snapshots B. The restore text names
  the file, and says `docs/plans` is the source of truth, so the session can
  correct it. Accepted; anything smarter (matching the branch name) is
  speculation.
- **Counts mislead for dev-flow's own plans.** Acceptance checkboxes are
  never ticked, so you see "0 of N checklist items checked". This is worded
  as checklist items, not tasks (Open question 1).
- **BLOCKED usually empty.** The workflow never writes BLOCKED into the plan
  (Current behaviour). This works as specified, but delivers little unless
  someone records blockers in the plan (Open question 1).
- **Untracked state file triggers the stop gate.** This is mitigated by the
  gitignore guidance (§7).
- **Stale injection.** A snapshot up to 24 h old can describe a branch or
  plan the user has since left. The text carries `saved_at` and says the plan
  file is authoritative.
- **Privacy.** The only free text stored is BLOCKED lines from the plan,
  path-redacted and truncated. The evidence task greps the state file for the
  fixture's absolute path, `$HOME`, `/Users/`, `/private/`, `/var/`, and
  sentinel strings planted in a source file, in the non-BLOCKED plan body, in
  `custom_instructions`, in `session_id` and in `transcript_path`, and
  checks that no JSON string value starts with `/`. The branch name is stored
  verbatim (allowed by the user).
- **Never block.** Both bodies run in a subshell with stderr discarded. The
  snapshot's stdout also goes to `/dev/null`. The script's last statement is
  `exit 0`. An unbound variable under `set -u` kills only the subshell.
- **Slow git.** `git status` on a huge repo delays compaction, up to the 600 s
  default timeout. This is accepted; it is the same command the stop gate
  already runs every turn.
- **Concurrent sessions in one repo** overwrite each other's snapshot. The
  `mv` is atomic, so a reader sees one complete file or the other.
- **bash 3.2 / BSD userland.** Only `ls -t`, `grep -c`, `awk`, `tr`,
  `date -u -r`, `basename`, `mkdir`, `mv` and `jq` are used.

## Migration and rollback

- Nothing to migrate. On upgrade the two hooks start running. A repo without
  `docs/plans/` never gets a state file.
- Rollback: revert the release commit and re-tag. Leftover
  `.claude/.devflow-state.json` files are inert without the restore hook and
  can be deleted (`rm -f .claude/.devflow-state.json`, added to the README's
  per-repo leftovers line).

## Open questions

1. **Plan progress and BLOCKED have no writer today.** dev-flow plans use
   `## Task N` headings without completion marks, the only checkboxes are
   never-ticked acceptance criteria, and `BLOCKED:` goes to chat
   (`implementer.md:22`, `build.md:14`), not into the plan. As specified, the
   snapshot will usually show "0 of N checklist items checked" and no blocked
   lines for plugin-generated plans. Proposed: ship as specified (it works
   for any plan that does use task-list checkboxes or BLOCKED lines), and
   document the caveat. The alternative, having `build.md` tick a per-task
   checkbox and append BLOCKED lines to the plan, is a separate feature. Do
   you want that, now or later?
2. **"giveup.log written in this session"** cannot be determined from what
   `stop-gate.sh` writes. Proposed: record `giveup_logged_at` (mtime) instead.
   The alternative is a one-line change to `stop-gate.sh` that stamps the
   payload `session_id` into its banner, after which the snapshot can compare
   ids and give a true boolean. Accept the mtime field?
3. **SessionStart matcher.** Proposed: `startup|resume|compact`, excluding
   `clear` and `fork`. Alternatively use `compact` only, if the 24-hour window
   was meant just as a staleness guard and not to carry state into new
   sessions.
4. **Gitignore reminders outside the README.** You asked for the README. The
   same reminder lists live in `init-hooks.md:179` and `onboard.md:123`.
   Proposed: add the file there too (plan task 8). Drop that task if you want
   the README only.
5. **Absolute-path redaction in BLOCKED lines** goes slightly beyond
   "truncated to 200 chars". It is there to meet the "no absolute paths"
   constraint. Keep it?
