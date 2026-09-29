# Plan: pre-write-guard not firing

Spec: `docs/specs/pre-write-guard-not-firing.md`

There is no unit-test framework in this repo. "Test first" here means: run the
exact stdin-JSON invocation given, observe the **wrong** exit code, then make the
change, then run it again and observe the **right** one. `.claude/test-cmd` (jq
JSON validation + `bash -n`) and `.claude/lint-cmd <path>` are the repo's checks.

**Posture:** report, do not push. Do not commit, merge, push or run
`claude plugin update` without the user asking. Never add AI-attribution trailers
to commit messages or PR descriptions in this repo.

---

## Fixture (build once, reuse in every task)

Run this before task 1 and keep the shell open, or re-run it per task. It creates
a throwaway repo **outside** this repository. Nothing here is committed.

```bash
T=$(mktemp -d) && echo "FIXTURE=$T"
mkdir -p "$T/repo/.claude/rules" "$T/bin"
printf '# Guidance\n\nOriginal line.\n' > "$T/repo/AGENTS.md"
printf '# Rule\n\noriginal rule\n'      > "$T/repo/.claude/rules/foo.md"
printf 'hello\n'                        > "$T/repo/src.txt"
ln -sf AGENTS.md "$T/repo/CLAUDE.md"
ln -sfn "$T/repo" "$T/link"
for t in bash basename cat cut diff grep head ls mkdir printf readlink rm shasum tr awk sed; do
  p=$(command -v "$t") && ln -sf "$p" "$T/bin/$t"
done
G=plugins/dev-flow/hooks/scripts/pre-write-guard.sh
```

All commands below are run from the repository root with `$T` and `$G` set.

---

## Task 1 — Guard must fail loudly when `jq` is missing

**Files:** `plugins/dev-flow/hooks/scripts/pre-write-guard.sh`

**Depends on:** —

**Test first** (currently exits **0**, i.e. the overwrite of `AGENTS.md` is
allowed — this is the bug):

```bash
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/repo/AGENTS.md","content":"pwned\\n"}}' "$T" \
 | env -i HOME="$HOME" PATH="$T/bin" CLAUDE_PROJECT_DIR="$T/repo" "$T/bin/bash" "$G" ; echo "exit=$?"
```

**Change:** immediately after `input=$(cat)`, before `hash_of()`, add a dependency
check. If `jq` is not on `PATH`, write one line to stderr naming the missing
dependency and the file it was protecting, and `exit 2`. Keep it to ~5 lines, no
new helper, `set -u`-safe:

```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: dev-flow pre-write-guard cannot run: 'jq' is not on PATH." >&2
  echo "It parses the hook payload, so it cannot tell whether this write touches a" >&2
  echo "protected guidance file. Install jq (brew install jq / apt install jq) and retry." >&2
  exit 2
fi
```

This deliberately departs from `.claude/rules/hook-scripts.md:9` ("missing host
tools are skipped, not failed"); that rule is about optional linters in
`post-edit-check.sh`. Do **not** edit that rules file — the spec records the
reasoning.

**Verify:**

```bash
bash .claude/lint-cmd plugins/dev-flow/hooks/scripts/pre-write-guard.sh ; echo "lint=$?"   # expect 0
# the test-first command above now: expect exit=2 and the BLOCKED message on stderr
# regression, jq present, unrelated file must still pass:
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/src.txt","old_string":"hello","new_string":"bye"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" ; echo "exit=$?"   # expect 0
```

---

## Task 2 — Guard must recognise `.claude/rules/*.md` however the path arrives

**Files:** `plugins/dev-flow/hooks/scripts/pre-write-guard.sh`

**Depends on:** 1

**Test first** — two invocations, both currently exit **0** (rules file
unguarded). Case A: `CLAUDE_PROJECT_DIR` is a symlink to the repo. Case B:
`CLAUDE_PROJECT_DIR` is unset.

```bash
# A
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/.claude/rules/foo.md","old_string":"original rule","new_string":"new rule"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/link" bash "$G" ; echo "A exit=$?"
# B
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/.claude/rules/foo.md","old_string":"original rule","new_string":"new rule"}}' "$T" \
 | (cd / && env -u CLAUDE_PROJECT_DIR bash "$OLDPWD/$G") ; echo "B exit=$?"
```

**Change:** in the block at lines 36–41 (`base=` … `[ "$guarded" = "1" ] || exit 0`):

1. After `rel="${file#"$PWD"/}"`, add a physical-path fallback so a symlinked
   project dir still yields a repo-relative path:
   `[ "$rel" = "$file" ] && rel="${file#"$(pwd -P)"/}"`
2. Add a second `case` that matches the guarded rules path on the raw
   `file_path`, independently of `$PWD`:
   `case "$file" in */.claude/rules/*.md|.claude/rules/*.md) guarded=1 ;; esac`

Keep the existing `basename` case for `AGENTS.md|CLAUDE.md` and the existing
`case "$rel"` — add, do not replace. Do not introduce `realpath` (not on stock
macOS). Total change ≈ 2 lines.

**Verify:**

```bash
bash .claude/lint-cmd plugins/dev-flow/hooks/scripts/pre-write-guard.sh ; echo "lint=$?"   # expect 0
# A and B above: both now expect exit=2, stderr starting "BLOCKED: Edit would change an existing protected file"
# regressions, all must be unchanged:
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/AGENTS.md","old_string":"Original line.","new_string":"X"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" >/dev/null 2>&1 ; echo "AGENTS exit=$?"        # expect 2
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/CLAUDE.md","old_string":"Original line.","new_string":"X"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" >/dev/null 2>&1 ; echo "CLAUDE exit=$?"        # expect 2 (REFUSED, symlink)
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/src.txt","old_string":"hello","new_string":"bye"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" >/dev/null 2>&1 ; echo "unrelated exit=$?"     # expect 0
printf '{"tool_name":"Edit","tool_input":{"file_path":".claude/rules/foo.md","old_string":"original rule","new_string":"new rule"}}' \
 | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" >/dev/null 2>&1 ; echo "relpath exit=$?"       # expect 2
```

---

## Task 3 — Guard must name the plugin version it is running from

**Files:** `plugins/dev-flow/hooks/scripts/pre-write-guard.sh`

**Depends on:** 1

This is what turns "the guard did not fire" into "the guard that fired is v1.4.0".

**Test first** (currently prints nothing matching, i.e. no version in the block
message):

```bash
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/AGENTS.md","old_string":"Original line.","new_string":"X"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" CLAUDE_PLUGIN_ROOT="$PWD/plugins/dev-flow" bash "$G" 2>&1 >/dev/null \
 | grep -c 'pre-write-guard v'    # expect 0 now, 1 after the change
```

**Change:** add one helper near `hash_of()`/`jqr()`:

```bash
# Identifies the exact installed copy that is running, so a stale cached plugin
# is visible in the block message instead of looking like a working guard.
whoami_line() {
  root="${CLAUDE_PLUGIN_ROOT:-}"
  if [ -n "$root" ] && [ -f "$root/.claude-plugin/plugin.json" ]; then
    v=$(jq -r '.version // "unknown"' "$root/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)
    printf 'dev-flow pre-write-guard v%s -- %s' "$v" "$root"
  else
    printf 'dev-flow pre-write-guard (CLAUDE_PLUGIN_ROOT unset)'
  fi
}
```

Then emit it as the second line of **both** stderr blocks — immediately after the
`REFUSED: …` line (~line 75) and after the `BLOCKED: …` line (~line 177):

```bash
printf '  (%s)\n' "$(whoami_line)" >&2   # inside the existing { … } >&2 group, without the redirect
```

(Inside the existing brace groups the `>&2` is already applied, so write
`printf '  (%s)\n' "$(whoami_line)"`.)

**Verify:**

```bash
bash .claude/lint-cmd plugins/dev-flow/hooks/scripts/pre-write-guard.sh ; echo "lint=$?"   # expect 0
# test-first command above: expect 1
# and the line must contain the current manifest version:
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/AGENTS.md","old_string":"Original line.","new_string":"X"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" CLAUDE_PLUGIN_ROOT="$PWD/plugins/dev-flow" bash "$G" 2>&1 >/dev/null | head -2
# expect line 2 like:   (dev-flow pre-write-guard v1.9.1 -- /…/plugins/dev-flow)
# unset-root path must not crash under set -u:
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/repo/AGENTS.md","old_string":"Original line.","new_string":"X"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" env -u CLAUDE_PLUGIN_ROOT bash "$G" >/dev/null 2>&1 ; echo "exit=$?"   # expect 2
```

---

## Task 4 — `/dev-flow:init-hooks` must prove the guard is live before anything else

**Files:** `plugins/dev-flow/commands/init-hooks.md`

**Depends on:** 3

**Test first** (the command says nothing about the guard today):

```bash
grep -ci 'pre-write guard' plugins/dev-flow/commands/init-hooks.md   # expect 0 now, >=1 after
```

**Change:** insert a new section **before** the existing `## 1. Find the commands`,
and add one bullet to `## 7. Report`. Do not renumber the existing sections —
call the new one `## 0. Prove the pre-write guard is live (do this first)`.

Contents, as instructions to the model running the command:

1. **Name the loaded copy.** State the plugin root path
   (`${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes it inline in command
   Markdown) and run `claude plugin list`. The last path segment of the plugin
   root is the loaded version. If it differs from the version `claude plugin
   list` reports, or is older than the marketplace's, say so and give the
   remediation in step 3.
2. **Probe it end to end, side-effect-free.** Create a throwaway guarded file
   `.claude/rules/devflow-guard-probe.md` with the `Write` tool (a brand-new
   guarded file is allowed by design), then issue an `Edit` on it changing one
   word. The guard must block that `Edit` with
   `BLOCKED: Edit would change an existing protected file`, and the second line
   of the block message names the version that fired. Delete
   `.claude/rules/devflow-guard-probe.md` afterwards, **whether or not it
   blocked**. Do not create an approval marker, and do not retry the edit.
   Probe the throwaway file, never `AGENTS.md` — if the guard is dead, a probe
   against `AGENTS.md` would damage real guidance.
3. **If the `Edit` was not blocked, stop and report.** The guard is not live in
   this repo. Give the user exactly these steps, in order:
   ```
   claude plugin marketplace update dev-flow-marketplace
   claude plugin update dev-flow@dev-flow-marketplace
   /reload-plugins        # or start a new session
   ```
   then re-run `/dev-flow:init-hooks`. Note that a marketplace added from a
   local directory or a non-Anthropic GitHub repo does not auto-update, so this
   is a manual step. Do not try to fix the hook by editing anything.

In `## 7. Report`, add: *"Whether the pre-write guard blocked the probe, and the
plugin version and root path it reported."*

**Verify:**

```bash
bash .claude/lint-cmd plugins/dev-flow/commands/init-hooks.md ; echo "lint=$?"   # expect 0
bash .claude/test-cmd ; echo "test=$?"                                            # expect 0
grep -c 'devflow-guard-probe' plugins/dev-flow/commands/init-hooks.md             # expect >=2
grep -c 'reload-plugins'      plugins/dev-flow/commands/init-hooks.md             # expect >=1
grep -n '^## 0\.' plugins/dev-flow/commands/init-hooks.md                         # expect one hit, before '## 1.'
head -5 plugins/dev-flow/commands/init-hooks.md   # frontmatter description/argument-hint must be intact
```

---

## Task 5 — README: fix the broken diagnostic and document the real failure mode

**Files:** `README.md`

**Depends on:** 4

**Test first** (the documented check does not work — run it verbatim):

```bash
bash -c "jq '.hooks.PreToolUse' ~/.claude/plugins/**/dev-flow/hooks/hooks.json" 2>&1 | head -1
# currently: jq: error: Could not open file …/plugins/**/dev-flow/hooks/hooks.json: No such file or directory
ls -d ~/.claude/plugins/cache/*/dev-flow/*/hooks/hooks.json   # this is the real path shape
```

**Change:**

1. Rewrite the `**setup-rules changed AGENTS.md / CLAUDE.md without asking me.**`
   entry (currently `README.md:308`). Replace the `**` glob command with the
   working form and point at the probe:
   ```bash
   jq '.hooks.PreToolUse' ~/.claude/plugins/cache/*/dev-flow/*/hooks/hooks.json
   claude plugin list | grep -A3 dev-flow
   ```
   and say that `/dev-flow:init-hooks` now proves the guard end to end.
2. Add a new troubleshooting entry immediately after it:
   **`The pre-write guard never fires / an edit to AGENTS.md went through.`**
   State the cause plainly: you are almost certainly running an older cached
   copy of the plugin. Before v1.8 the `PreToolUse` matcher was `Write` alone, so
   every `Edit` bypassed it, and the guard did not cover `AGENTS.md` at all —
   only `CLAUDE.md` and `.claude/rules/*.md`. A plugin installed once stays
   frozen: marketplaces added from a local directory or a non-Anthropic GitHub
   repo have auto-update off by default, and even after an update the running
   session keeps the old plugin path until `/reload-plugins`. Give the check
   (`claude plugin list`, and the cache path above) and the three-command fix
   from task 4 step 3. Mention that from v1.10.0 the block message's second line
   names the version that fired, so a stale copy is self-reporting.
3. In the **Pre-write guard** section (around `README.md:117-127`), add one line:
   the guard exits 2 with a clear message if `jq` is missing, rather than
   allowing the write.
4. In **Known limits**, add one line: `Write`/`Edit` are gated mechanically; a
   `Bash` command that rewrites a guidance file is *not* (unless task 7 lands),
   and the guard is a guardrail against model error, not a security boundary.

Do not restate anything `README.md` marks "not yet verified" as settled fact.
Leave those caveats alone.

**Verify:**

```bash
bash .claude/test-cmd ; echo "test=$?"                        # expect 0
grep -c 'plugins/\*\*/dev-flow' README.md                     # expect 0 (broken glob gone)
grep -c 'reload-plugins' README.md                            # expect >=1
grep -ci 'never fires' README.md                              # expect >=1
grep -c 'plugins/cache/\*/dev-flow' README.md                 # expect >=1 (working path shape present)
# and the command the README now documents must actually work:
jq '.hooks.PreToolUse' ~/.claude/plugins/cache/*/dev-flow/*/hooks/hooks.json | head -3   # must print JSON, not an error
```

---

## Task 6 — `AGENTS.md`: say that the release is not picked up automatically

**Files:** `AGENTS.md`

**Depends on:** 5

> **GATED EDIT.** `AGENTS.md` is protected by this very guard. The `Edit` will be
> blocked with exit 2. Follow the block message's own procedure: show the user the
> exact before/after text verbatim, wait for an explicit yes, then run the
> `mkdir -p … && printf … > …` command it prints, then retry the *same* edit
> unchanged. Do not split the change up, do not use `Bash` to write the file, and
> do not create the marker before the user has said yes.
> **Never edit `CLAUDE.md` in this repo — it is a symlink to `AGENTS.md`.**

**Test first:**

```bash
grep -c 'reload-plugins' AGENTS.md    # expect 0 now, >=1 after
```

**Change:** two minimal edits, no restructuring.

1. The Commands table row `| Release a change | bump \`version\` … colleagues run
   \`/plugin update\` |` (`AGENTS.md:12`) — extend to: bump `version`, push;
   colleagues run `claude plugin marketplace update` then `/plugin update`, then
   `/reload-plugins` or a new session.
2. The Hazards bullet at `AGENTS.md:42` — extend to say that non-Anthropic
   marketplaces do not auto-update, so an unbumped or un-updated plugin means
   colleagues keep running the copy they installed on day one, and its hooks
   silently behave like the old version.

**Verify:**

```bash
bash .claude/test-cmd ; echo "test=$?"          # expect 0
grep -c 'reload-plugins' AGENTS.md              # expect >=1
git diff --stat AGENTS.md                       # expect exactly 1 file, small diff
ls -l CLAUDE.md                                 # must still be a symlink -> AGENTS.md
ls .claude/.approved-writes/ 2>/dev/null        # expect empty: the marker was consumed
```

---

## Task 7 — OPTIONAL, needs an explicit yes first: close the `Bash` write bypass

**Files:** `plugins/dev-flow/hooks/hooks.json`,
`plugins/dev-flow/hooks/scripts/pre-write-guard.sh`, `README.md`

**Depends on:** 3

> **STOP.** This is Open question 1 in the spec. Do not start this task until the
> user has said yes. It makes the hook run on **every** `Bash` command, and it
> matches command text, which can produce false positives. If the user has not
> answered, skip to task 8 and report that this task was left undone.

**Test first** (currently exits **0** — a heredoc rewrite of `AGENTS.md` is
invisible to the guard):

```bash
printf '{"tool_name":"Bash","tool_input":{"command":"cat > %s/repo/AGENTS.md <<EOF\\npwned\\nEOF"}}' "$T" \
 | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" ; echo "exit=$?"
```

**Change:**

1. `hooks.json`: `PreToolUse` matcher becomes `"Write|Edit|MultiEdit|Bash"`.
   (Only letters and `|`, so Claude Code still treats it as an exact
   pipe-separated list, not a regex.)
2. `pre-write-guard.sh`: add `Bash` to the `case "$tool"` allow-list at line 29,
   and handle it **before** the `file_path` extraction (a Bash payload has no
   `.tool_input.file_path`). Block only when the command text names a guarded
   file **and** contains a write construct; otherwise `exit 0`:

   ```bash
   if [ "$tool" = "Bash" ]; then
     cmd=$(jqr '.tool_input.command // empty')
     printf '%s' "$cmd" | grep -qE '(AGENTS|CLAUDE)\.md|\.claude/rules/[^[:space:]]*\.md' || exit 0
     printf '%s' "$cmd" | grep -qE '>>?[[:space:]]*[^|&;]*\.md|<<-?[[:space:]]*[A-Za-z_"'"'"']|(^|[|&;[:space:]])(tee|dd|truncate|cp|mv|install)([[:space:]]|$)|sed[[:space:]]+[^|&;]*-i|perl[[:space:]]+-[a-z]*i|python[0-9.]*[[:space:]]+-c' || exit 0
     { echo "BLOCKED: this Bash command looks like it writes a protected guidance file."
       printf '  (%s)\n' "$(whoami_line)"
       echo "AGENTS.md, CLAUDE.md and .claude/rules/*.md are only changed through the Write"
       echo "or Edit tool, so the guard can show the user the exact diff first."
       echo "Re-issue this change with the Write or Edit tool instead."
     } >&2
     exit 2
   fi
   ```

   Keep the message short — it must not read as something to work around.
3. `README.md`: update the Known-limits line added in task 5 to say the bypass is
   now closed for the common shapes, and that command-text matching is a
   guardrail, not a boundary — obfuscated command text still gets through.

**Verify** — the blocking set and, just as important, the non-blocking set. If
**any** of the "expect 0" cases blocks, stop and report rather than loosening the
pattern:

```bash
b() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
      | CLAUDE_PROJECT_DIR="$T/repo" bash "$G" >/dev/null 2>&1 ; echo "$? <- $1" ; }
# expect 2:
b "cat > $T/repo/AGENTS.md <<EOF"
b "tee $T/repo/AGENTS.md"
b "sed -i '' s/a/b/ $T/repo/AGENTS.md"
b "mv /tmp/x $T/repo/AGENTS.md"
b "echo hi >> $T/repo/.claude/rules/foo.md"
# expect 0:
b "cat $T/repo/AGENTS.md"
b "grep -n Original $T/repo/AGENTS.md"
b "git diff AGENTS.md"
b "ls -la $T/repo/.claude/rules"
b "npm test"
b "git status"
bash .claude/test-cmd ; echo "test=$?"   # expect 0
```

---

## Task 8 — Version bump (the release mechanism) and hand-off

**Files:** `plugins/dev-flow/.claude-plugin/plugin.json`, `README.md`

**Depends on:** 6 (and 7 if it was taken)

Without this, `/plugin update` sees no change and none of the above reaches
anyone — this is the exact trap that caused the bug.

**Test first:**

```bash
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json   # expect 1.9.1 now
head -1 README.md                                              # expect "# dev-flow: private Claude Code plugin (v1.9)"
```

**Change:**

1. `plugins/dev-flow/.claude-plugin/plugin.json`: `version` `1.9.1` → `1.10.0`.
   Leave every other field alone.
2. `README.md` line 1: `(v1.9)` → `(v1.10)`.

**Verify:**

```bash
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json   # expect 1.10.0
claude plugin validate ./plugins/dev-flow                      # expect "Validation passed"
bash .claude/test-cmd ; echo "test=$?"                         # expect 0
git status --short                                             # review every changed file
```

**Then report to the user and stop.** Do not commit, push or update the plugin
unless asked. The changes are inert until the user runs, in their shell:

```bash
claude plugin marketplace update dev-flow-marketplace
claude plugin update dev-flow@dev-flow-marketplace
```

then `/reload-plugins` or a new session, and finally `/dev-flow:init-hooks` in
one consuming repo to see the probe block. Tell them their current loaded version
is what `claude plugin list` reports — it was **1.4.0** at the time of the
investigation.

---

## Acceptance criteria (for `verify-done`)

Build the fixture first (see top of this file), then:

- [ ] `bash .claude/test-cmd` exits 0.
- [ ] `claude plugin validate ./plugins/dev-flow` prints `Validation passed`.
- [ ] `jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json` is `1.10.0`
      and `head -1 README.md` says `v1.10`.
- [ ] `Edit` on `AGENTS.md` exits 2 — and stderr line 2 matches
      `dev-flow pre-write-guard v1.10.0`.
- [ ] `Edit` on `CLAUDE.md` (symlink to `AGENTS.md`) exits 2 with `REFUSED:`.
- [ ] `Edit` on `.claude/rules/foo.md` exits 2 with `CLAUDE_PROJECT_DIR` set to
      the repo, set to a **symlink** to the repo, and **unset**.
- [ ] `Write` on `AGENTS.md` with `jq` removed from `PATH` exits 2, not 0.
- [ ] `Edit` on an unrelated file exits 0, and a no-op `Edit` (old == new) exits 0.
- [ ] `Write` creating a **new** guarded file exits 0 (unchanged by design).
- [ ] Approve-and-retry still works: run a blocked `Edit`, execute the exact
      `mkdir -p … && printf … > …` command it printed, re-run the same payload →
      exit 0, and the marker file is gone afterwards.
- [ ] `grep -c 'plugins/\*\*/dev-flow' README.md` is 0.
- [ ] `plugins/dev-flow/commands/init-hooks.md` has a `## 0.` section before
      `## 1.`, mentions `devflow-guard-probe` at least twice and
      `reload-plugins` at least once; its YAML frontmatter is intact.
- [ ] `AGENTS.md` mentions `reload-plugins`; `CLAUDE.md` is still a symlink to
      `AGENTS.md`; `.claude/.approved-writes/` is empty (marker consumed).
- [ ] If task 7 was taken: every "expect 2" Bash case blocks and every "expect 0"
      Bash case passes; `hooks.json` matcher is `Write|Edit|MultiEdit|Bash`.
      If it was not taken, that is reported explicitly as skipped.
- [ ] Nothing was committed, pushed or merged, and no plugin was updated, unless
      the user asked.
