# Spec: interactive `install.sh`

Status: draft, awaiting answers to Open questions
Scope: `install.sh` (repo root) only, plus doc updates in `README.md` / `AGENTS.md`.

## Goal

Make `bash install.sh` feel like a real installer on a terminal:

1. A **pre-flight list** of everything that will be added, shown before anything is
   installed, built from the actual commands the script runs.
2. A **checklist prompt** so the user picks components instead of remembering flags.
3. A **live progress indicator** while the flow runs.
4. **Colour-coded outcomes**: green = success, yellow = already present / soft warning,
   red = real failure.

## Non-goals

- No new external dependency (no `dialog`, `whiptail`, `gum`, no `tput`-only features).
  Pure bash + ANSI escapes, matching the existing `\033[1A\033[2K` trick at
  `install.sh:56`.
- No change to *what* gets installed, in what order, or with what commands.
- No change to the script's exit contract (see Risks).
- Not a TUI. No mouse, no arrow keys, no alternate screen buffer.
- Still one file, still `bash install.sh` (no `chmod`, no shebang reliance).

## Current behaviour

`install.sh` is 155 lines, `set -u`, no `set -e`.

| Concern | Where | Behaviour today |
|---|---|---|
| Flag parsing | `install.sh:25-35` | `--with-memory`, `--with-powerline`, `--skip-superpowers`, `--skip-codegraph`, `-h/--help`, any other arg becomes `SRC` (marketplace source, default = script dir) |
| Help text | `install.sh:31` | `sed -n '2,7p' "${BASH_SOURCE[0]}"` — prints lines 2-7 of itself; **breaks silently if the header grows** |
| Status output | `install.sh:37-40` | `ok` → `  [ok]   `, `warn` → `  [warn] `, `bad` → `  [MISSING] ` + sets `MISSING=1`. No colour. |
| Step runner | `install.sh:45-67` | `run_step <timeout> <label> <cmd...>`: prints `  ...   <label>`, runs with `</dev/null` under `timeout` if available, redraws the line with `\033[1A\033[2K` **only when `[ -t 1 ]`**, then `ok` on 0, `warn ... TIMED OUT` on 124, `warn ... exit N` otherwise, plus `tail -8` of captured output indented with `         | `. |
| 1) Prerequisites | `:69-78` | required: `claude`, `jq`, `git` (→ `bad`, exit 1). optional: `node`, `uvx`, `php`, `docker`, `timeout` (→ `warn`, or silent for docker). |
| 2) Plugins | `:80-90` | unless `--skip-superpowers`: marketplace `obra/superpowers-marketplace` + plugin `superpowers@superpowers-marketplace`. Always: marketplace `$SRC` + plugin `dev-flow@dev-flow-marketplace`. |
| 3) CodeGraph | `:92-108` | skip on flag; needs `npm`; `command -v codegraph` → `ok "codegraph already present"` else `npm install -g @colbymchenry/codegraph`; then `codegraph install`; prints the per-repo `codegraph init` hint. |
| 4) Memory | `:110-122` | only with `--with-memory`; needs `npx`; `npx --yes claude-mem install`; then three `warn` lines about the hosted-provider default. |
| 5) powerline | `:124-144` | only with `--with-powerline`; `warn` if `~/.claude/settings.json` already has `.statusLine` (prints it via `jq -c`); marketplace `Owloops/claude-powerline` + plugin `claude-powerline@claude-powerline`; then 5 lines of manual-`/powerline` instructions. |
| 6) Verify | `:146-154` | `run_step 60 "claude plugin list" ... \|\| true`, then the "Done." block and the four per-repo lines (`setup-rules`, `.claude/test-cmd`, `.claude/lint-cmd`, `.claude/test-cmd-retries`). |
| Exit code | `:78` only | `exit 1` only for a MISSING prerequisite. A failed `run_step` does **not** fail the script. |

Marketplace name for the local source is `dev-flow-marketplace`, from
`.claude-plugin/marketplace.json:2` — the `$SRC` path is the *source*, the *name* is
fixed. That distinction matters for "already added" detection.

## Proposed design

Six additive layers. Each is independently revertible; the existing command sequence
is untouched.

### 1. Mode detection

```
NON_INTERACTIVE=0        # set by -y / --yes / --non-interactive
FLAGS_SET=0              # set by any selection-relevant flag
INTERACTIVE=0/1
```

`INTERACTIVE=1` iff: `[ -t 0 ]` **and** `[ -t 1 ]` **and** `NON_INTERACTIVE=0` **and**
`${CI:-}` is empty. Everything visual (colour, bar, prompt, line redraw) is gated on
`INTERACTIVE`, except the line redraw which keeps its own `[ -t 1 ]` guard so a
`--yes` run on a real terminal still looks like today's output.

Colour is gated on `INTERACTIVE` **and** empty `${NO_COLOR:-}` **and** no `--no-color`.

When `INTERACTIVE=0` the output is byte-for-byte today's output, plus the new plain
"Plan" block (§4).

### 2. Colour + output funnel

```
C_OK='\033[0;32m'  C_WARN='\033[0;33m'  C_BAD='\033[0;31m'
C_DIM='\033[2m'    C_BOLD='\033[1m'     C_OFF='\033[0m'
```
All empty strings when colour is off.

Status helpers, all routed through one funnel `emit <text>` so the progress bar can be
lifted out of the way exactly once per printed line:

| helper | prefix | colour | meaning |
|---|---|---|---|
| `ok`   | `  [ok]   `    | green  | step succeeded |
| `have` | `  [have] `    | yellow | already present / idempotent no-op (**new**) |
| `warn` | `  [warn] `    | yellow | soft warning, optional tool missing, timeout |
| `fail` | `  [FAIL] `    | red    | step exited non-zero, not a timeout (**new**) |
| `bad`  | `  [MISSING] ` | red    | required prerequisite absent |
| `skip` | `  [skip] `    | dim    | component the user deselected or flag-skipped (**new**) |
| `note` | `         `    | dim    | continuation / hint lines (today's bare `echo "         ..."`) |

`[MISSING]` keeps its longer, misaligned prefix on purpose: the string is quoted in
`README.md:304`-area troubleshooting and in the script's own "Fix the MISSING items"
message. Deselected components are **dim, not yellow** — a deliberate user choice is
not a warning. (Flagged in Open questions.)

`run_step` changes only in its tail: status 0 → `ok`; 124 → `warn ... TIMED OUT` (as
today); any other non-zero → `fail "<label> -- exit N"` in red. The `tail -8` output
block still prints, through `emit`.

Counters `N_OK` / `N_WARN` / `N_FAIL` increment inside the helpers and feed the final
summary line (§6).

### 3. State detection (drives the yellow "already present" states)

One-shot caches, populated **after** the prerequisite section (needs `claude` on PATH),
each with a hard `timeout 30` and `</dev/null`:

```
MKT_CACHE=$(claude plugin marketplace list 2>/dev/null || true)
PLG_CACHE=$(claude plugin list 2>/dev/null || true)
```

Verified output shape on this machine:

```
Configured marketplaces:

  ❯ claude-powerline
    Source: GitHub (Owloops/claude-powerline)
```
```
Installed plugins:

  ❯ dev-flow@dev-flow-marketplace
    Version: 1.4.0
```

Predicates take the **last whitespace-separated field** of each line and compare
exactly, which avoids matching `Version:`/`Scope:`/`Status:` lines and avoids grepping
for the `❯` glyph:

```
has_marketplace <name>        # e.g. dev-flow-marketplace, superpowers-marketplace
has_plugin <name@marketplace> # e.g. superpowers@superpowers-marketplace
```

Both must degrade to "unknown → assume absent": if `claude` errors or the format
changes, the caches are empty, no `[have]` annotation is shown, and the real
`marketplace add` / `plugin install` commands still run — they are already idempotent,
so nothing breaks. This is a cosmetic optimisation, never a correctness gate.

Per-component detection:

| component | already-present test |
|---|---|
| superpowers marketplace | `has_marketplace superpowers-marketplace` |
| superpowers plugin | `has_plugin superpowers@superpowers-marketplace` |
| dev-flow marketplace | `has_marketplace dev-flow-marketplace` |
| dev-flow plugin | `has_plugin dev-flow@dev-flow-marketplace` |
| CodeGraph | `command -v codegraph` (already in the script at `:96`) |
| claude-mem | **none** — no reliable probe; see Open questions |
| powerline marketplace/plugin | `has_marketplace claude-powerline` / `has_plugin claude-powerline@claude-powerline` |
| powerline statusLine | existing `jq -e '.statusLine' ~/.claude/settings.json` at `:128` → stays yellow |

Where a `[have]` is detected the step is **still executed** (cheap, idempotent, and the
add/install may upgrade) but its success line reads `[have] <label> (already present)`
in yellow instead of green. Exception: the existing CodeGraph branch at `:96-101`
already skips the `npm install -g` when the binary exists — that stays a real skip and
becomes `have`.

### 4. Pre-flight plan block

Printed after `1) Prerequisites` (read-only) and after the checklist prompt resolves,
before `2) Plugins`. Header `Plan` (unnumbered, so the existing 1-6 numbering is
untouched). Every line is a real command or artefact from the script:

```
Plan  (12 steps)
  superpowers      marketplace obra/superpowers-marketplace
                   plugin      superpowers@superpowers-marketplace
  dev-flow         marketplace dev-flow-marketplace  <- /path/to/src
                   plugin      dev-flow@dev-flow-marketplace
  codegraph        npm install -g @colbymchenry/codegraph        [have]
                   codegraph install   (registers an MCP server in ~/.claude.json)
  claude-mem       npx --yes claude-mem install                  [skip]
  claude-powerline marketplace Owloops/claude-powerline          [skip]
                   plugin      claude-powerline@claude-powerline
                   manual follow-up: run /powerline inside Claude Code
  verify           claude plugin list
```

`[have]` yellow, `[skip]` dim, nothing = will be done. In non-interactive mode the same
block prints without colour and without the step count line ornamentation.

### 5. Checklist prompt

Shown only when `INTERACTIVE=1` **and** `FLAGS_SET=0`. Selection-relevant flags are
`--with-memory`, `--with-powerline`, `--skip-superpowers`, `--skip-codegraph`; the
positional marketplace source is **not** selection-relevant and does not suppress the
prompt.

```
Select components  (dev-flow itself is always installed)

  1  [x]  Superpowers        obra/superpowers-marketplace       recommended
  -  [x]  dev-flow           this marketplace                   required
  2  [ ]  CodeGraph          structure / caller analysis         optional
  3  [ ]  claude-mem         cross-session memory                optional, reads tool output
  4  [ ]  claude-powerline   status line                         cosmetic

  Numbers toggle (e.g. "2" or "2 4").  a = all,  d = defaults,  Enter = install,  q = quit
>
```

- Defaults mirror today's flag defaults: Superpowers on, dev-flow on, CodeGraph on
  (today it runs unless `--skip-codegraph`), memory off, powerline off.
  Note the request calls CodeGraph "optional" — it is optional *to select*, but its
  default stays **checked** so a plain `bash install.sh` installs exactly what it
  installs today. (Flagged in Open questions.)
- Repaint in place with `\033[<n>A` + per-line `\r\033[2K`, `n` = known line count.
- `read -r -t 120 reply`; on timeout or EOF: print a yellow note and proceed with the
  current selection. Never hang.
- `q` / EOF-with-no-selection → `exit 0` with "nothing installed".
- Unknown input → yellow one-line hint, repaint, no state change.
- Selection writes back into the existing `SKIP_SUPERPOWERS` / `SKIP_CODEGRAPH` /
  `WITH_MEMORY` / `WITH_POWERLINE` variables, so sections 2-5 are untouched.

### 6. Progress indicator

`STEP_TOTAL` is computed once, after selection, by counting the `run_step` calls the
chosen path will make:

| component | steps |
|---|---|
| superpowers | 2 |
| dev-flow | 2 (always) |
| CodeGraph | 0 if unselected or no `npm`; 1 if `codegraph` already present (`codegraph install` only); else 2 |
| claude-mem | 1 if selected and `npx` present, else 0 |
| powerline | 2 if selected, else 0 |
| verify | 1 |

Bar, redrawn on the last line, ~24 cells fixed width:

```
  [########----------------]  7/12  install dev-flow
```

Glyphs: `█`/`░` when `${LC_ALL:-${LC_CTYPE:-${LANG:-}}}` matches `UTF-8`, else `#`/`-`.
Label truncated to keep the line under 80 columns.

Mechanics — three helpers, `BAR_VISIBLE` tracks whether the bar currently occupies the
cursor's line:

- `bar_show` — no-op unless `INTERACTIVE`; prints the bar with **no trailing newline**.
- `bar_clear` — `\r\033[2K`, leaves the cursor at column 0 of the bar line.
- `emit <text>` — `bar_clear`; `printf '%s\n'`; `bar_show`. Every status helper and
  every hint line goes through it, so the bar is always the bottom-most line.
- `step_done` — increments `STEP_DONE`, clamped at `STEP_TOTAL` (the CodeGraph count is
  an estimate; clamping prevents `13/12`).

`run_step` then reads: `emit "  ...   <label>"` → run → `step_done` → if `INTERACTIVE`,
`bar_clear` then `\033[1A\r\033[2K` to eat the `...` line → status line via `emit`.
When `INTERACTIVE=0` the `[ -t 1 ]` redraw guard behaves exactly as today.

Final summary, after `6) Verify`:

```
Done  12 ok, 2 warnings, 0 failures
```
Green when `N_FAIL=0` and `N_WARN=0`, yellow when only warnings, red when any failure.
Then the unchanged "Restart Claude Code…" and per-repo block.

### 7. Flags and help

New:

| flag | effect |
|---|---|
| `-y`, `--yes`, `--non-interactive` | force `INTERACTIVE=0` even on a TTY |
| `--no-color` | disable colour only (bar and prompt unaffected) |
| `--dry-run` | run sections 1) Prerequisites and the state caches as normal (so `[have]`/missing-tool detection stays accurate), still show the checklist prompt when interactive, print the `Plan` block for the resolved selection, then **exit 0 immediately** — sections 2)-6) never run, so no command that installs or modifies anything is invoked |

`-h/--help` stops using `sed -n '2,7p'` and becomes a `usage()` heredoc, because the
header comment block grows in this change and the hard-coded line range would silently
print the wrong thing. Also honours `NO_COLOR` and `CI` from the environment.

Unrecognised `--*` arguments currently fall into `SRC` (`install.sh:32`), so a typo'd
flag silently becomes the marketplace source. Tighten: `--*` that is unknown → red
error + `usage` + `exit 2`; bare words still become `SRC`.

## Data flow

```
argv ──▶ parse (FLAGS_SET, NON_INTERACTIVE, DRY_RUN, SRC)
      ──▶ mode detect (INTERACTIVE, colour on/off, bar glyphs)
      ──▶ 1) Prerequisites          (unchanged commands, coloured output; exit 1 on MISSING)
      ──▶ state caches (MKT_CACHE, PLG_CACHE)
      ──▶ checklist prompt          (only if INTERACTIVE && !FLAGS_SET) ──▶ writes WITH_*/SKIP_*
      ──▶ STEP_TOTAL
      ──▶ Plan block
      ──▶ if DRY_RUN: note "Dry run: nothing installed." ──▶ exit 0
      ──▶ 2)..6)                    (unchanged commands; emit/bar/colour wrappers)
      ──▶ summary + per-repo block
```

No files, no schemas, no settings are written by this change. `install.sh` remains the
only touched executable, and it still writes nothing itself — the tools it invokes do.

## Risks

- **Escape-sequence litter in logs.** Mitigated by gating every escape on
  `INTERACTIVE`, and by keeping the existing `[ -t 1 ]` guard on the `\033[1A` redraw.
  Must be verified with `bash install.sh -y | cat` and with output redirected to a file.
- **Bar/line accounting drift.** If any code path prints with bare `echo`/`printf`
  instead of `emit`, the bar is orphaned mid-screen and the `\033[1A` eats the wrong
  line. Mitigation: convert *every* output line in the script to `emit`/`note`; grep for
  residual bare `echo`/`printf` as an acceptance check.
- **`claude` CLI output format change** breaks the `[have]` annotations. Mitigated by
  design: detection is cosmetic, never gates a command.
- **Prompt hanging** in a semi-interactive environment. Mitigated by `read -t 120` plus
  the `CI` and dual-`-t` checks.
- **Backward compatibility of scripted use.** `bash install.sh --skip-superpowers
  --skip-codegraph`, `bash install.sh org/repo --with-memory`, and piped/CI invocations
  must behave exactly as today. Guarded by `FLAGS_SET` and by keeping the
  numbered-section structure and message strings.
- **Exit code.** Unchanged on purpose: only a MISSING prerequisite exits non-zero. A red
  `[FAIL]` still exits 0. Making failures fatal would break existing callers and is out
  of scope — the red colour plus the summary line is the signal.

## Edge cases

- `timeout` absent (macOS without coreutils): already handled at `:49-53`; the state-cache
  calls must use the same guarded pattern, not a bare `timeout`.
- Terminal narrower than the bar: fixed 24 cells + truncated label keeps it under 80;
  no `tput cols` dependency.
- `NO_COLOR=1` on a TTY: prompt and bar still work, no colour.
- `CI=true` on a TTY: fully unattended.
- Deselect everything: dev-flow still installs (it is not togglable).
- Re-run on a fully installed machine: expect an all-yellow run, zero red, exit 0.
- Non-UTF-8 locale: ASCII bar glyphs.
- `bash install.sh -h` must work with no TTY and no `claude` installed.

## Migration / rollback

No state, no config, no version bump semantics. Rollback = `git revert` of the single
`install.sh` commit. `plugins/dev-flow/.claude-plugin/plugin.json` `version` does **not**
need bumping — `install.sh` is not part of the shipped plugin (`AGENTS.md:27` lists it as
the onboarding script, and `marketplace.json` ships only `./plugins/dev-flow`).

Docs to follow the change: `README.md:13` (flag list) and `README.md:5-11` quick-start,
plus `AGENTS.md:27` one-liner.

## Decisions (resolved before build)

1. **CodeGraph default:** pre-checked in the checklist, preserving today's default-on behaviour.
2. **`claude-mem` detection:** none — no reliable probe exists; always green/red, never `[have]`.
3. **Deselected-component colour:** dim `[skip]`, not yellow.
4. **Prompt keybindings:** number-toggle + `a`/`d`/Enter/`q` (not arrow-keys/space).
5. **`--dry-run`:** added as a real flag (see §7) rather than relying on the test harness alone.
6. **Arg parsing:** unknown `--flag` → `exit 2` (tightened from today's silent fallback to `SRC`).
7. **Colour codes:** plain SGR 31/32/33 + dim, no bright variants, no `tput`.
