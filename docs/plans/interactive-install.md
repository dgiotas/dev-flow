# Plan: interactive `install.sh`

Spec: `docs/specs/interactive-install.md`. Read it first — its "Decisions" section
resolves what used to be open questions, including a real `--dry-run` flag (§7 of the
spec), added after the spec/plan were first written.

There is no test framework in this repo (`AGENTS.md:14`). The repo-wide check is
`bash .claude/test-cmd` (jq JSON validation + `bash -n` on every `*.sh`). Every task
below therefore pairs that with an explicit manual scenario.

**Hard rule for every task:** `install.sh` really installs things. Do not verify by
running the real installer repeatedly. Use the fake-PATH harness from Task 1 for all
behavioural checks, and do at most one real end-to-end run in Task 10.

Conventions used below:
- `$R` = repo root `/Users/dgiotas/Projects/personal/dev-flow`
- `$H` = harness dir `/tmp/devflow-itest`
- "plain output" = no ANSI escape bytes; check with
  `... | LC_ALL=C grep -c $'\033'` expecting `0`.

---

## Task 1 — Build the fake-PATH verification harness

**Files:** `$H/bin/claude`, `$H/bin/npm`, `$H/bin/npx`, `$H/bin/codegraph`, `$H/run.sh`
(all under `/tmp/devflow-itest`, **not** in the repo — do not commit these).

**Test first:** none (this task *is* the test rig).

**Change:** create executable stubs that print realistic output and exit with a
controllable status, so every colour path can be forced without touching the machine.

- `claude` — dispatch on `"$1 $2"`:
  - `plugin marketplace list` → the verified header + `  ❯ <name>` /
    `    Source: ...` lines for each name in `$FAKE_MARKETPLACES` (space separated).
  - `plugin list` → header + `  ❯ <name@mkt>` / `    Version: 1.0.0` for each entry in
    `$FAKE_PLUGINS`.
  - `plugin marketplace add` / `plugin install` → echo the argv, `sleep ${FAKE_DELAY:-0}`,
    exit `${FAKE_STATUS:-0}`.
  - Honour `FAKE_HANG=1` by sleeping 999 (to exercise the `timeout` → yellow path).
- `npm`, `npx`, `codegraph` — echo argv, exit `${FAKE_STATUS:-0}`.
- `$H/run.sh` — `PATH="$H/bin:/usr/bin:/bin" bash "$R/install.sh" "$@"`, so the real
  `claude`/`npm` can never be reached. `jq` and `git` must still resolve: symlink the
  real ones into `$H/bin` (`ln -sf "$(command -v jq)" "$H/bin/jq"`, same for `git`,
  `timeout` if present).

**Verify:**
```bash
bash /tmp/devflow-itest/run.sh -h            # once Task 2 lands; before that:
FAKE_MARKETPLACES="dev-flow-marketplace" /tmp/devflow-itest/bin/claude plugin marketplace list
FAKE_STATUS=7 /tmp/devflow-itest/bin/claude plugin install -y x@y; echo "exit=$?"   # → 7
```
Expected: marketplace listing matches the shape in the spec's "State detection" section;
the second command exits 7.

**Depends on:** —

---

## Task 2 — `usage()` heredoc, `-y`/`--no-color`, `FLAGS_SET`, strict arg parsing

**Files:** `$R/install.sh` (header comment `:2-16`, flag loop `:25-35`)

**Test first:**
```bash
bash /tmp/devflow-itest/run.sh --help | head -20        # must list the new flags
bash /tmp/devflow-itest/run.sh --typo 2>&1; echo "exit=$?"   # must be exit 2, not "SRC=--typo"
```
Both fail before the change (help shows the stale `sed` slice; `--typo` is silently
accepted as the marketplace source).

**Change:**
1. Add to the header comment block the new flags, so the documented usage stays in one
   place. Add `-y|--yes|--non-interactive`, `--no-color` and `--dry-run` to the `Usage:`
   lines.
2. Replace `-h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0 ;;` with
   `-h|--help) usage; exit 0 ;;` and define `usage()` above the loop as a
   `cat <<'EOF'` heredoc carrying the flag table. Delete the `sed` call entirely — no
   line-range coupling left.
3. New vars before the loop: `NON_INTERACTIVE=0`, `NO_COLOR_FLAG=0`, `FLAGS_SET=0`,
   `DRY_RUN=0`.
4. Cases: `-y|--yes|--non-interactive) NON_INTERACTIVE=1 ;;`,
   `--no-color) NO_COLOR_FLAG=1 ;;`, `--dry-run) DRY_RUN=1 ;;`. The four existing
   selection flags additionally set `FLAGS_SET=1`. `--no-color`, `-y` and `--dry-run` do
   **not** set `FLAGS_SET` — a dry run still shows the checklist when interactive, per
   spec §7.
5. Replace the catch-all `*) SRC="$arg" ;;` with
   `--*) printf 'unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;` followed by
   `*) SRC="$arg" ;;`.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
bash /tmp/devflow-itest/run.sh --help | grep -c -- '--non-interactive'   # → 1
bash /tmp/devflow-itest/run.sh --help | grep -c -- '--dry-run'           # → 1
bash /tmp/devflow-itest/run.sh --typo >/dev/null 2>&1; echo "exit=$?"    # → exit=2
bash /tmp/devflow-itest/run.sh -h >/dev/null; echo "exit=$?"             # → exit=0
```

**Depends on:** 1

---

## Task 3 — Mode detection (`INTERACTIVE`) and the colour palette

**Files:** `$R/install.sh` (new block immediately after the flag loop / `SRC` default at `:35`)

**Test first:**
```bash
# non-TTY must report non-interactive; TTY must report interactive
echo | bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph 2>&1 | LC_ALL=C grep -c $'\033'   # → 0
```

**Change:** add, with no behaviour change yet beyond variable definitions:

```
INTERACTIVE=0
if [ "$NON_INTERACTIVE" = 0 ] && [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ]; then INTERACTIVE=1; fi

USE_COLOR=0
if [ "$INTERACTIVE" = 1 ] && [ "$NO_COLOR_FLAG" = 0 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1; fi

if [ "$USE_COLOR" = 1 ]; then
  C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_BAD=$'\033[0;31m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m';    C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_BAD=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi
```

Nothing consumes these yet. Keep `set -u` safe: all six are always assigned.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
# temporary probe, remove after checking:
INTERACTIVE_PROBE=1 bash -c 'source <(sed -n "/^INTERACTIVE=0/,/^fi$/p" '"$R"'/install.sh)' 2>/dev/null; echo "sourced=$?"
```
Expected: `test-cmd` passes; the block is syntactically self-contained.

**Depends on:** 2

---

## Task 4 — Colour the status helpers, add `have`/`fail`/`skip`/`note`, add counters

**Files:** `$R/install.sh` (`:37-40` helpers; `run_step` tail `:57-66`; every call site of
`ok`/`warn`/`bad` and every bare `echo "  ..."` / `echo "         ..."` line in sections
1-6)

**Test first:**
```bash
# green + yellow + red in one run, on a TTY
FAKE_MARKETPLACES="" FAKE_PLUGINS="" bash /tmp/devflow-itest/run.sh --skip-codegraph          # expect green [ok]
FAKE_STATUS=7 bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph              # expect red [FAIL] ... exit 7
FAKE_HANG=1 bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph                # expect yellow [warn] ... TIMED OUT
```
Before the change all three print uncoloured `[ok]`/`[warn]`.

**Change:**
1. Counters `N_OK=0 N_WARN=0 N_FAIL=0` next to the existing `MISSING=0`.
2. Signatures (all take one label argument, print one line):
   - `ok <label>`   → `  ${C_OK}[ok]${C_OFF}   <label>`, `N_OK++`
   - `have <label>` → `  ${C_WARN}[have]${C_OFF} <label>`, `N_WARN++`
   - `warn <label>` → `  ${C_WARN}[warn]${C_OFF} <label>`, `N_WARN++`
   - `fail <label>` → `  ${C_BAD}[FAIL]${C_OFF} <label>`, `N_FAIL++`
   - `bad <label>`  → `  ${C_BAD}[MISSING]${C_OFF} <label>`, `MISSING=1`
   - `skip <label>` → `  ${C_DIM}[skip]${C_OFF} <label>`
   - `note <text>`  → `         ${C_DIM}<text>${C_OFF}`
   - `section <n> <title>` → blank line + `${C_BOLD}<n>) <title>${C_OFF}`
   Keep the literal strings `[ok]`, `[warn]`, `[MISSING]` byte-identical inside the
   colour wrappers.
3. `run_step` tail: `status -eq 0` → `ok`; `status -eq 124` → `warn "$label -- TIMED OUT
   after ${t}s (skipped; run it manually to see what it wants)"` (string unchanged);
   otherwise → `fail "$label -- exit $status"`. The `tail -8 | sed 's/^/         | /'`
   block is unchanged.
4. Convert the existing bare `echo`/`printf` informational lines to `note`/`skip`/
   `section`: `:69`, `:80`, `:87`, `:92`, `:94`, `:104`, `:110`, `:121`, `:124`, `:137-141`,
   `:143`, `:146`. Leave `:149-154` (the trailing "Done." / per-repo block) as plain
   `echo` for now — Task 9 handles it.
5. Do **not** change any command, timeout, order or message wording.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph 2>&1 | LC_ALL=C grep -c $'\033'   # → 0
FAKE_STATUS=7 bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph 2>&1 | grep -c 'FAIL'  # → >=1
diff <(bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph 2>&1) \
     <(git -C $R stash list >/dev/null; echo skip)   # informational: eyeball against the pre-change output you saved
```
Save the pre-change baseline first: `bash /tmp/devflow-itest/run.sh --skip-superpowers
--skip-codegraph -y > /tmp/devflow-itest/baseline.txt 2>&1` **before** editing, then
after the change confirm the only diffs are the `[FAIL]` rename and nothing else.

**Depends on:** 3

---

## Task 5 — `emit` funnel

**Files:** `$R/install.sh` (helpers block; `run_step`)

**Test first:**
```bash
bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph > /tmp/devflow-itest/after5.txt 2>&1
diff /tmp/devflow-itest/baseline.txt /tmp/devflow-itest/after5.txt   # → no differences
```
This is a pure refactor: the output must not move by one byte in non-interactive mode.

**Change:** introduce
```
BAR_VISIBLE=0
bar_show()  { :; }   # real body lands in Task 8
bar_clear() { :; }   # real body lands in Task 8
emit() { bar_clear; printf '%s\n' "$1"; bar_show; }
```
and route every one of the helpers from Task 4 (`ok`/`have`/`warn`/`fail`/`bad`/`skip`/
`note`/`section`) plus `run_step`'s `  ...   <label>` line and its `tail -8` block through
`emit`. After this task there must be **no** bare `printf`/`echo` of a status or hint line
left in sections 1-6.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
diff /tmp/devflow-itest/baseline.txt /tmp/devflow-itest/after5.txt && echo IDENTICAL
grep -n "^\s*\(echo\|printf\)" $R/install.sh   # only usage(), the trailing block, and emit itself
```

**Depends on:** 4

---

## Task 6 — State detection caches and the yellow "already present" paths

**Files:** `$R/install.sh` (new block after section 1's `MISSING` exit at `:78`; call sites
in sections 2, 3, 5)

**Test first:**
```bash
# nothing installed → green
FAKE_MARKETPLACES="" FAKE_PLUGINS="" bash /tmp/devflow-itest/run.sh -y --skip-codegraph | grep '\[ok\]'
# everything installed → yellow [have]
FAKE_MARKETPLACES="superpowers-marketplace dev-flow-marketplace" \
FAKE_PLUGINS="superpowers@superpowers-marketplace dev-flow@dev-flow-marketplace" \
  bash /tmp/devflow-itest/run.sh -y --skip-codegraph | grep -c 'have'   # → 4
```

**Change:**
1. After the prerequisite gate, populate caches using the *same* `timeout`-guarded
   pattern as `run_step` (a tiny `cap <secs> <cmd...>` helper, or an inline
   `command -v timeout` branch — do not call bare `timeout`):
   `MKT_CACHE=$(cap 30 claude plugin marketplace list 2>/dev/null || true)` and
   `PLG_CACHE=$(cap 30 claude plugin list 2>/dev/null || true)`.
2. Predicates:
   `has_marketplace() { printf '%s\n' "$MKT_CACHE" | awk '{print $NF}' | grep -qxF "$1"; }`
   and `has_plugin()` over `$PLG_CACHE`. Empty cache → always false.
3. New wrapper `run_step_known <already:0|1> <timeout> <label> <cmd...>`: runs `run_step`
   as usual, but when the command succeeds **and** `already=1`, emit
   `have "<label> (already present)"` instead of `ok`. Simplest implementation: pass a
   global `STEP_ALREADY=0|1` that `run_step` reads and resets, avoiding a second
   near-duplicate function.
4. Wire it up: superpowers marketplace/plugin, dev-flow marketplace/plugin, powerline
   marketplace/plugin. Change `ok "codegraph already present"` (`:97`) to
   `have "codegraph already present"`. Leave the existing `statusLine` `warn` (`:129-131`)
   as-is — already yellow.
5. Do not gate any command on detection. Everything still runs.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
FAKE_MARKETPLACES="dev-flow-marketplace" FAKE_PLUGINS="dev-flow@dev-flow-marketplace" \
  bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph | grep -c 'already present'   # → 2
# format-change resilience: stub prints garbage
FAKE_MARKETPLACES="" FAKE_PLUGINS="" bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph; echo "exit=$?"  # → exit=0, all [ok]
```

**Depends on:** 5

---

## Task 7 — Pre-flight Plan block and `STEP_TOTAL`

**Files:** `$R/install.sh` (new `plan_block()` + `count_steps()` before section 2)

**Test first:**
```bash
bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph | sed -n '/^Plan/,/^2)/p'
```
Must list exactly: `dev-flow` marketplace + plugin, `codegraph [skip]`,
`claude-mem [skip]`, `claude-powerline [skip]`, `verify`. Nothing generic, nothing
invented. Before the change there is no `Plan` section at all.

**Change:**
1. `count_steps()` → sets `STEP_TOTAL` per the table in the spec's §6 (superpowers 2,
   dev-flow 2, codegraph 0/1/2, memory 0/1, powerline 2, verify 1). `STEP_DONE=0`.
2. `plan_block()` → prints the `Plan  (N steps)` header via `emit`, then one `emit` line
   per real artefact, exactly the items in the spec's §4 sample, annotating `[have]`
   (yellow, from Task 6's predicates) and `[skip]` (dim, deselected/flag-skipped).
3. Call `count_steps; plan_block` after the prerequisite gate and after the caches, i.e.
   between section 1 and section 2. Section numbering 1-6 is unchanged; `Plan` is
   unnumbered.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
bash /tmp/devflow-itest/run.sh -y | grep -A20 '^Plan'
bash /tmp/devflow-itest/run.sh -y | grep -c 'obra/superpowers-marketplace'   # → >=2 (plan + step)
bash /tmp/devflow-itest/run.sh -y --with-memory --with-powerline | grep -c 'skip'   # fewer skips than default run
```

**Depends on:** 6

---

## Task 8 — Progress bar

**Files:** `$R/install.sh` (`bar_show`/`bar_clear` bodies from Task 5, `step_done`,
`run_step` redraw)

**Test first:**
```bash
# on a real TTY: bar must appear, advance, and leave no residue
FAKE_DELAY=1 bash /tmp/devflow-itest/run.sh --skip-codegraph
# piped: zero escapes, zero bar characters
FAKE_DELAY=0 bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph -y | LC_ALL=C grep -c $'\033'   # → 0
diff /tmp/devflow-itest/baseline.txt <(bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph 2>&1 | grep -v '^Plan' )  # only the Plan block differs
```

**Change:**
1. Glyphs: `BAR_FULL='█' BAR_EMPTY='░'` when
   `${LC_ALL:-${LC_CTYPE:-${LANG:-}}}` matches `*UTF-8*`, else `#` and `-`.
2. `bar_show` — no-op unless `INTERACTIVE=1` and `STEP_TOTAL>0`; builds a 24-cell bar,
   prints `  [<bar>]  <STEP_DONE>/<STEP_TOTAL>  <BAR_LABEL>` truncated to 78 chars with
   **no newline**; `BAR_VISIBLE=1`.
3. `bar_clear` — if `BAR_VISIBLE=1`: `printf '\r\033[2K'`; `BAR_VISIBLE=0`.
4. `step_done` — `STEP_DONE=$((STEP_DONE+1))`; clamp to `STEP_TOTAL`.
5. `run_step`: set `BAR_LABEL="$label"` before running; after the command call
   `step_done`; replace the single `[ -t 1 ] && printf '\033[1A\033[2K'` with:
   if `INTERACTIVE=1` → `bar_clear; printf '\033[1A\r\033[2K'`; else keep the existing
   `[ -t 1 ] && printf '\033[1A\033[2K'` verbatim so `-y` on a TTY looks like today.
6. Final `bar_clear` before the trailing block.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
FAKE_DELAY=1 bash /tmp/devflow-itest/run.sh --skip-codegraph          # watch on a TTY: bar advances, no leftover bar line at the end
bash /tmp/devflow-itest/run.sh -y > /tmp/devflow-itest/f.txt 2>&1; LC_ALL=C grep -c $'\033' /tmp/devflow-itest/f.txt   # → 0
LANG=C bash /tmp/devflow-itest/run.sh --skip-codegraph               # ASCII bar glyphs, no mojibake
```
Expected: the number in `N/M` never exceeds `M`, and no `[` bar fragment survives past
the last step.

**Depends on:** 7

---

## Task 9 — Interactive checklist prompt + final summary line

**Files:** `$R/install.sh` (new `select_components()` before `count_steps`; trailing block
`:146-154`)

**Test first:**
```bash
# TTY, no flags → checklist appears; "3 4" then Enter selects memory + powerline
bash /tmp/devflow-itest/run.sh
# TTY + a selection flag → no checklist, flags honoured exactly
bash /tmp/devflow-itest/run.sh --with-memory | head -5
# non-TTY → no checklist, no hang
echo | bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph
printf '' | CI=true bash /tmp/devflow-itest/run.sh | tail -3
# --dry-run: checklist still shown if interactive, then exit 0 before any install command
bash /tmp/devflow-itest/run.sh --dry-run --skip-superpowers --skip-codegraph
```

**Change:**
1. `select_components()` — runs only when `INTERACTIVE=1 && FLAGS_SET=0` (note:
   `DRY_RUN` does not suppress this — a dry run still lets the user pick components so
   the printed Plan reflects a real choice). Renders the 5-row checklist from the spec's
   §5, defaults Superpowers/dev-flow/CodeGraph checked, memory/powerline unchecked;
   dev-flow's row shows `-` instead of a number and toggling it prints a yellow
   "dev-flow is required" note.
   Loop: `read -r -t 120 reply` → numbers toggle, `a` = all on, `d` = defaults,
   empty = accept, `q` = `emit "nothing installed"; exit 0`, anything else = yellow hint.
   Repaint in place with `\033[<n>A` then `\r\033[2K` per line, `n` = the known row count.
   On `read` timeout or EOF: yellow note, accept current selection, return.
2. Write the result back into `SKIP_SUPERPOWERS` / `SKIP_CODEGRAPH` / `WITH_MEMORY` /
   `WITH_POWERLINE`. Sections 2-5 are not touched.
3. Call order: section 1 → caches → `select_components` → `count_steps` → `plan_block` →
   **if `DRY_RUN=1`: `note "Dry run: nothing installed. Re-run without --dry-run to
   apply."; exit 0`** → section 2. The dry-run exit happens strictly after `plan_block`
   so the user sees exactly what would run, and strictly before any `run_step` call, so
   no install/add command is ever invoked.
4. Final summary after section 6, before "Done.": one `emit` line
   `Done  <N_OK> ok, <N_WARN> warnings, <N_FAIL> failures`, green if
   `N_FAIL=0 && N_WARN=0`, yellow if only warnings, red if any failure. Keep the existing
   "Restart Claude Code…" and per-repo `note` lines verbatim (convert them to `note`).
   Exit code stays as today: non-zero only for a MISSING prerequisite. (Not reached on a
   `--dry-run` exit.)

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
bash /tmp/devflow-itest/run.sh            # TTY: type "3 4" Enter → Plan shows claude-mem and claude-powerline without [skip]
bash /tmp/devflow-itest/run.sh            # TTY: type "q" Enter → exits 0, installs nothing
bash /tmp/devflow-itest/run.sh --with-memory >/dev/null; echo "exit=$?"     # → 0, no prompt
echo | bash /tmp/devflow-itest/run.sh --skip-superpowers --skip-codegraph; echo "exit=$?"   # → 0, no prompt, plain output
FAKE_STATUS=7 bash /tmp/devflow-itest/run.sh -y --skip-superpowers --skip-codegraph | tail -5   # red summary, "failures" > 0
bash /tmp/devflow-itest/run.sh --dry-run -y --skip-superpowers --skip-codegraph > /tmp/devflow-itest/dryrun.txt 2>&1; echo "exit=$?"   # → 0
grep -c 'Dry run' /tmp/devflow-itest/dryrun.txt          # → 1
grep -c '^Plan' /tmp/devflow-itest/dryrun.txt            # → 1
grep -c '2) Plugins' /tmp/devflow-itest/dryrun.txt       # → 0 (section 2 never ran)
```

**Depends on:** 8

---

## Task 10 — One real end-to-end run + docs

**Files:** `$R/README.md` (quick-start `:5-11`, flag line `:13`), `$R/AGENTS.md` (`:27`)

**Test first:**
```bash
cd $R && bash install.sh            # the real thing, on a TTY, on a machine that already
                                    # has everything → expect an all-yellow [have] run, 0 red
cd $R && bash install.sh -y | cat   # unattended, plain, no escapes
```

**Change:**
1. `README.md` quick-start: mention that a plain `bash install.sh` now prompts for
   components on a terminal, and that flags / CI / `-y` skip the prompt. Mention
   `--dry-run` for previewing the plan without installing anything.
2. `README.md:13` flag list: add `-y` / `--non-interactive`, `--no-color`, `--dry-run`.
3. `AGENTS.md:27`: extend the `install.sh` one-liner to note the interactive checklist and
   the colour/plain dual mode. **`AGENTS.md` is gated by `pre-write-guard.sh`**
   (`AGENTS.md:34`) — get the diff approved before writing it, and never touch the
   `CLAUDE.md` symlink (`AGENTS.md:35`).
4. Do **not** bump `plugins/dev-flow/.claude-plugin/plugin.json` — `install.sh` is not
   shipped inside the plugin.
5. Per `AGENTS.md:37`, the commit message must carry **no** AI-attribution trailer.

**Verify:**
```bash
cd $R && bash .claude/test-cmd && echo TESTCMD-OK
cd $R && bash install.sh -y > /tmp/devflow-itest/real.txt 2>&1; echo "exit=$?"   # → 0
LC_ALL=C grep -c $'\033' /tmp/devflow-itest/real.txt                             # → 0
grep -c 'non-interactive' $R/README.md                                           # → >=1
rm -rf /tmp/devflow-itest                                                        # harness is throwaway
```

**Depends on:** 9

---

## Acceptance criteria (for `verify-done`)

1. `cd $R && bash .claude/test-cmd` exits 0.
2. `bash install.sh -h` exits 0, needs no TTY and no `claude`, and lists
   `--with-memory`, `--with-powerline`, `--skip-superpowers`, `--skip-codegraph`,
   `-y/--non-interactive`, `--no-color`, `--dry-run`.
3. No `sed -n '2,7p'` (or any self-reading line range) remains in `install.sh`.
4. `bash install.sh --typo` exits 2 and does not treat `--typo` as the marketplace source.
5. `bash install.sh -y 2>&1 | LC_ALL=C grep -c $'\033'` → `0`. Same for
   `echo | bash install.sh` and for `CI=true bash install.sh`.
6. Neither `echo | bash install.sh ...` nor `CI=true bash install.sh` prompts or hangs;
   both complete unattended.
7. On a TTY with no selection flags, a checklist appears with dev-flow non-togglable;
   Enter proceeds, `q` exits 0 having installed nothing.
8. On a TTY, passing any of the four selection flags skips the checklist and produces
   exactly today's selection behaviour.
9. A `Plan` block precedes section `2) Plugins` in every mode and names only real
   artefacts: `obra/superpowers-marketplace`, `superpowers@superpowers-marketplace`,
   `dev-flow-marketplace`, `dev-flow@dev-flow-marketplace`,
   `npm install -g @colbymchenry/codegraph`, `codegraph install`,
   `npx --yes claude-mem install`, `Owloops/claude-powerline`,
   `claude-powerline@claude-powerline`, `claude plugin list`.
10. Colour mapping holds on a TTY: green `[ok]` on success, yellow `[have]` for already
    present, yellow `[warn]` for a timeout / missing optional tool / existing
    `statusLine`, red `[FAIL]` for a non-timeout non-zero exit, red `[MISSING]` for a
    missing required prerequisite.
11. Progress bar advances on a TTY, never exceeds `N/N`, and leaves no residual bar line
    after the last step.
12. Sections `1)`-`6)` keep their numbers, titles, command sequence, timeouts and the
    trailing per-repo `setup-rules` / `test-cmd` / `lint-cmd` / `test-cmd-retries` lines.
13. Exit code contract unchanged: non-zero only for a MISSING prerequisite; a red
    `[FAIL]` still exits 0.
14. Re-running `bash install.sh -y` twice in a row is idempotent and the second run shows
    yellow `[have]` where the first showed green.
15. No new external tool dependency: `grep -E 'dialog|whiptail|gum|tput' install.sh`
    returns nothing.
16. `git status` shows only `install.sh`, `README.md`, `AGENTS.md` and the two `docs/`
    files changed; no harness files committed; `plugin.json` version untouched.
17. `bash install.sh --dry-run` exits 0, prints the `Plan` block, and never runs section
    `2)` onward — no `claude plugin marketplace add`, `claude plugin install -y`,
    `npm install -g`, `codegraph install`, `npx --yes claude-mem install`, or
    `claude plugin marketplace add Owloops/claude-powerline` is invoked. Verified against
    the fake-PATH harness: none of those argv-echo lines appear in `--dry-run` output.
