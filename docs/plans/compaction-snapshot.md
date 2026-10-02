# Plan: compaction snapshot (PreCompact save, SessionStart restore)

Spec: `docs/specs/compaction-snapshot.md`

This repo has no unit-test framework. Here "test first" means running the
given assertion, seeing it **fail** (`FAIL`, `SOME-FAILED`, `false` or a
non-zero exit), making the change, and then seeing it pass. The repo-wide
checks are `bash .claude/test-cmd` (jq JSON validation plus `bash -n` on every
`.sh`) and `bash .claude/lint-cmd <path>`. Behavioural tests run from a
**scratch rig outside the repo** (task 1). That follows the precedent in
`docs/plans/managed-hooks-fallback.md` task 1 and `docs/plans/readme-restructure.md`
task 0. Nothing test-related is committed.

**Posture:** do not commit, push, merge, tag or run `claude plugin update`
unless the user asks. Never add AI-attribution trailers to commits or PR text
in this repo. Do not edit `CLAUDE.md`, which is a symlink to `AGENTS.md`.

**Before starting:** the spec's *Open questions* must be answered
(`build.md:11` stops on unresolved ones). The plan below implements the
proposed defaults:
- OQ1: ship as specified, plus a caveat in the docs.
- OQ2: `giveup_logged_at` (mtime) instead of a per-session boolean.
- OQ3: SessionStart matcher `startup|resume|compact`.
- OQ4: task 8 included.
- OQ5: absolute-path redaction included.

If an answer differs, the spec and plan are revised first. Do not improvise.

**Compatibility:** the scripts must run on macOS `/bin/bash` 3.2 and BSD
userland. No `mapfile`, no `${x,,}`, no `stat -c`/`stat -f`, no `date -d`.

Paths used below:

```bash
REPO=/Users/dgiotas/Projects/personal/dev-flow
RIG="${TMPDIR:-/tmp}/devflow-snap-test.sh"     # the scratch rig (task 1)
has()   { grep -qF -- "$2" "$1" && echo "PASS: $1 has '$2'" || { echo "FAIL: $1 lacks '$2'"; return 1; }; }
lacks() { grep -qF -- "$2" "$1" && { echo "FAIL: $1 still has '$2'"; return 1; } || echo "PASS: $1 lacks '$2'"; }
```

Run every command from `$REPO`.

---

## Task 1: Scratch test rig

**Files:** create `$RIG` (outside the repo, not committed). Nothing in the repo changes.

**Depends on:** none

**Test first:** this task *is* the test. The `self` group checks the fixture.
The `snap` group must fail now, because the scripts do not exist yet.

**Change:** write `$RIG` with exactly this content:

```bash
# Scratch rig for compaction-snapshot. Not committed. Usage: bash snap-test.sh <group>...
# Groups: self snap snap-edge restore restore-edge privacy all
set -u
R="${R:-/Users/dgiotas/Projects/personal/dev-flow}"
SNAP="$R/plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh"
REST="$R/plugins/dev-flow/hooks/scripts/session-start-restore.sh"
H="${H:-${TMPDIR:-/tmp}/devflow-snap-rig}"
mkdir -p "$H"; H=$(cd "$H" && pwd -P)
export GIT_CEILING_DIRECTORIES="$H"
fail=0
check() { d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $d"; else echo "FAIL $d"; fail=1; fi; }
S() { jq -e "$1" "$2/.claude/.devflow-state.json"; }
jqs() { printf '%s' "$1" | jq -e "$2"; }          # jq -e against a string
hasf() { printf '%s\n' "$1" | grep -qF -- "$2"; }  # fixed-string match in a string
lacksf() { ! hasf "$@"; }

payload() { jq -nc --arg cwd "$1" '{session_id:"SESSION-SENTINEL",transcript_path:"/Users/someone/.claude/projects/p/TRANSCRIPT-SENTINEL.jsonl",cwd:$cwd,hook_event_name:"PreCompact",trigger:"auto",custom_instructions:{project:"PROMPT-SENTINEL"}}'; }
snap()    { payload "$1" | CLAUDE_PROJECT_DIR="$1" bash "$SNAP"; }
restore() { jq -nc --arg cwd "$1" '{session_id:"s",transcript_path:"/x",cwd:$cwd,hook_event_name:"SessionStart",source:"compact"}' \
            | CLAUDE_PROJECT_DIR="$1" bash "$REST"; }
# PATH without jq: only the tools the scripts reach before their jq check.
nojq() { d="$H/nojq-bin"; rm -rf "$d"; mkdir -p "$d"
         for t in cat ls head basename grep git; do ln -s "$(command -v $t)" "$d/$t"; done; echo "$d"; }

mkfix() { # $1 = fixture dir: git repo on feature/test-feature, 1 staged, 1 unstaged, 1 untracked
  rm -rf "$1"; mkdir -p "$1/docs/plans" "$1/src"
  ( cd "$1" || exit 1
    git init -q && git symbolic-ref HEAD refs/heads/feature/test-feature
    printf 'SOURCE-SENTINEL card=4111111111111111\n' > src/app.php
    printf 'one\n' > src/b.php
    printf '# Plan: older\n- [x] old\n' > docs/plans/older.md
    { echo '# Plan: test feature'
      echo 'PLAN-BODY-SENTINEL'
      echo '- [x] Task 1: done'
      echo '- [ ] Task 2: pending'
      echo '  * [X] Task 3: done'
      echo '- [ ] Task 4: pending'
      echo 'BLOCKED: something'
      echo "BLOCKED: needs $1/src/app.php reviewed"
    } > docs/plans/test-feature.md
    git add -A && git -c user.name=t -c user.email=t@example.com commit -qm init
    touch -t 202001010000 docs/plans/older.md
    echo change >> src/b.php
    echo new > src/c.php && git add src/c.php
    echo u > notes.txt )
}

g_self() {
  F="$H/fix"; mkfix "$F"
  check "fixture: 3 porcelain lines" test "$(git -C "$F" status --porcelain | wc -l | tr -d ' ')" = 3
  check "fixture: older.md is older" test "$(ls -t "$F"/docs/plans/*.md | head -1)" = "$F/docs/plans/test-feature.md"
  check "nogit dir is not a work tree" sh -c "mkdir -p '$H/nogit' && ! git -C '$H/nogit' rev-parse --is-inside-work-tree"
}

g_snap() {
  F="$H/fix"; mkfix "$F"
  out=$(snap "$F"); rc=$?
  check "snap exit 0" test "$rc" = 0
  check "snap stdout empty" test -z "$out"
  check "state file written" test -f "$F/.claude/.devflow-state.json"
  check "no tmp file left" test ! -e "$F/.claude/.devflow-state.json.tmp"
  check "exact top-level keys" S '(keys) == ["blocked","git","plan","saved_at","schema_version","stop_gate"]' "$F"
  check "schema_version 1" S '.schema_version == "1"' "$F"
  check "saved_at ISO UTC, fresh" S '(.saved_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and (now - (.saved_at|fromdateiso8601)) < 120' "$F"
  check "plan" S '.plan == {file:"docs/plans/test-feature.md",slug:"test-feature",done:2,total:4}' "$F"
  sha=$(git -C "$F" rev-parse --short HEAD)
  check "git" S ".git == {branch:\"feature/test-feature\",head:\"$sha\",staged:1,unstaged:1,untracked:1}" "$F"
  check "stop_gate both null" S '.stop_gate == {state:null,giveup_logged_at:null}' "$F"
  check "blocked redacted" S '.blocked == ["BLOCKED: something","BLOCKED: needs <path> reviewed"]' "$F"
}

g_snap_edge() {
  F="$H/fix"
  mkfix "$F"; mkdir -p "$F/.claude"; printf '2\n' > "$F/.claude/.stop-gate-state"
  echo banner > "$F/.claude/stop-gate-giveup.log"; snap "$F"
  check "stop_gate state 2" S '.stop_gate.state == 2' "$F"
  check "giveup_logged_at ISO" S '.stop_gate.giveup_logged_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$F"

  mkfix "$F"; printf '# Plan\n## Task 1\nno boxes\n' > "$F/docs/plans/test-feature.md"; snap "$F"
  check "no checklist -> null counts" S '.plan.done == null and .plan.total == null and .plan.slug == "test-feature"' "$F"

  mkfix "$F"; { for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "BLOCKED: item $i"; done; printf 'BLOCKED: %0300d\n' 0; } > "$F/docs/plans/test-feature.md"; snap "$F"
  check "blocked capped at 10" S '(.blocked|length) == 10 and .blocked[9] == "BLOCKED: item 10"' "$F"
  mkfix "$F"; printf 'BLOCKED: %0300d\n' 0 > "$F/docs/plans/test-feature.md"; snap "$F"
  check "blocked truncated to 200" S '(.blocked[0]|length) == 200' "$F"

  D="$H/noplans"; rm -rf "$D"; mkdir -p "$D"
  out=$(snap "$D"); rc=$?
  check "no docs/plans: exit 0" test "$rc" = 0
  check "no docs/plans: no state, no stdout" test ! -e "$D/.claude/.devflow-state.json" -a -z "$out"

  D="$H/nogit"; rm -rf "$D"; mkdir -p "$D/docs/plans"; printf -- '- [ ] a\n' > "$D/docs/plans/p.md"
  out=$(snap "$D"); rc=$?
  check "not a git repo: exit 0" test "$rc" = 0
  check "not a git repo: git null" S '.git == null and .plan.slug == "p"' "$D"

  mkfix "$F"; p=$(payload "$F"); P=$(nojq)
  out=$(printf '%s' "$p" | env PATH="$P" CLAUDE_PROJECT_DIR="$F" /bin/bash "$SNAP"); rc=$?
  check "no jq: exit 0, no state" test "$rc" = 0 -a ! -e "$F/.claude/.devflow-state.json" -a -z "$out"

  mkfix "$F"; mkdir -p "$F/.claude"; chmod 500 "$F/.claude"
  out=$(snap "$F"); rc=$?; chmod 700 "$F/.claude"
  check "unwritable .claude: exit 0" test "$rc" = 0 -a -z "$out"

  out=$(printf 'not json' | CLAUDE_PROJECT_DIR="$H/fix" bash "$SNAP"); rc=$?
  check "garbage stdin: exit 0" test "$rc" = 0
  out=$(printf '{}' | CLAUDE_PROJECT_DIR="$H/does-not-exist" bash "$SNAP"); rc=$?
  check "missing project dir: exit 0" test "$rc" = 0
}

ctx() { restore "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

g_restore() {
  F="$H/fix"; mkfix "$F"; snap "$F"
  out=$(restore "$F"); rc=$?
  check "restore exit 0" test "$rc" = 0
  check "restore JSON shape" jqs "$out" 'keys == ["hookSpecificOutput"] and .hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext|type) == "string"'
  c=$(ctx "$F")
  check "mentions plan + progress" hasf "$c" 'Active plan: docs/plans/test-feature.md (slug test-feature); 2 of 4 checklist items checked.'
  check "mentions branch" hasf "$c" 'Git: branch feature/test-feature at '
  check "mentions blocked" hasf "$c" '- BLOCKED: something'
  check "<= 15 lines" test "$(printf '%s\n' "$c" | wc -l | tr -d ' ')" -le 15

  { for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "BLOCKED: item $i"; done; } > "$F/docs/plans/test-feature.md"
  printf '3' > "$F/.claude/.stop-gate-state"; echo b > "$F/.claude/stop-gate-giveup.log"; snap "$F"
  check "worst case exactly 15 lines" test "$(ctx "$F" | wc -l | tr -d ' ')" = 15
}

g_restore_edge() {
  F="$H/fix"; mkfix "$F"
  out=$(restore "$F"); rc=$?
  check "no state file: exit 0, silent" test "$rc" = 0 -a -z "$out"
  mkdir -p "$F/.claude"; printf '{not json' > "$F/.claude/.devflow-state.json"
  out=$(restore "$F"); rc=$?
  check "malformed: exit 0, silent" test "$rc" = 0 -a -z "$out"
  snap "$F"; jq '.saved_at = "2020-01-01T00:00:00Z"' "$F/.claude/.devflow-state.json" > "$H/s" && mv "$H/s" "$F/.claude/.devflow-state.json"
  out=$(restore "$F"); rc=$?
  check "older than 24h: exit 0, silent" test "$rc" = 0 -a -z "$out"
  snap "$F"; jq '.schema_version = "2"' "$F/.claude/.devflow-state.json" > "$H/s" && mv "$H/s" "$F/.claude/.devflow-state.json"
  out=$(restore "$F"); rc=$?
  check "unknown schema: exit 0, silent" test "$rc" = 0 -a -z "$out"
  snap "$F"; jq 'del(.plan)' "$F/.claude/.devflow-state.json" > "$H/s" && mv "$H/s" "$F/.claude/.devflow-state.json"
  out=$(restore "$F"); rc=$?
  check "missing plan key: exit 0, silent" test "$rc" = 0 -a -z "$out"
  snap "$F"; P=$(nojq)
  out=$(printf '{}' | env PATH="$P" CLAUDE_PROJECT_DIR="$F" /bin/bash "$REST"); rc=$?
  check "no jq: exit 0, silent" test "$rc" = 0 -a -z "$out"
  out=$(printf 'garbage' | CLAUDE_PROJECT_DIR="$H/does-not-exist" bash "$REST"); rc=$?
  check "missing project dir: exit 0, silent" test "$rc" = 0 -a -z "$out"
}

g_privacy() {
  F="$H/fix"; mkfix "$F"; snap "$F"; J="$F/.claude/.devflow-state.json"
  for s in "$F" "$H" "$HOME" /Users/ /home/ /private/ /var/ SOURCE-SENTINEL 4111 PLAN-BODY-SENTINEL PROMPT-SENTINEL SESSION-SENTINEL TRANSCRIPT-SENTINEL; do
    check "state lacks '$s'" lacksf "$(cat "$J")" "$s"
  done
  check "no string value starts with /" jq -e '[.. | strings | select(startswith("/"))] | length == 0' "$J"
  c=$(ctx "$F")
  check "injected text lacks fixture path" lacksf "$c" "$F"
}

[ $# -gt 0 ] || set -- all
for g in "$@"; do
  case "$g" in
    all) g_self; g_snap; g_snap_edge; g_restore; g_restore_edge; g_privacy ;;
    self|snap|restore|privacy) "g_$g" ;;
    snap-edge) g_snap_edge ;;
    restore-edge) g_restore_edge ;;
    *) echo "unknown group $g"; fail=1 ;;
  esac
done
[ "$fail" = 0 ] && echo ALL-PASS || { echo SOME-FAILED; exit 1; }
```

Notes for the implementer: do not "improve" the rig. It was dry-run against
a reference implementation of the spec on this host (all groups ALL-PASS).
The fixture deliberately plants sentinels (`SOURCE-SENTINEL`, `4111…`,
`PLAN-BODY-SENTINEL`, `PROMPT-SENTINEL`, `SESSION-SENTINEL`,
`TRANSCRIPT-SENTINEL`) and an absolute path inside a `BLOCKED` line. The
privacy group proves none of them reach the state file.

**Verify:**
```bash
bash "$RIG" self   # expect 3 PASS lines and ALL-PASS
bash "$RIG" snap   # expect "No such file or directory", FAIL lines and SOME-FAILED (exit 1), because the script does not exist yet
```

---

## Task 2: `pre-compact-snapshot.sh`

**Files:** create `plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh`

**Depends on:** 1

**Test first:** `bash "$RIG" snap snap-edge privacy` prints FAIL lines and
`SOME-FAILED`.

**Change:** create the script, about 55 lines. Follow `.claude/rules/hook-scripts.md`
and `stop-gate.sh` for style: a header comment, `set -u`, read stdin once,
and `cd "${CLAUDE_PROJECT_DIR:-.}"`. Structure:

```bash
#!/usr/bin/env bash
# PreCompact: <header, see below>
set -u
input=$(cat) # consumed for API compliance; not otherwise used

snapshot() (
  ...                          # body below; a subshell, so `exit` and set -u aborts stay inside
)

snapshot >/dev/null 2>&1       # never print: PreCompact stdout JSON could block compaction
exit 0
```

Header comment (4-8 lines), covering:
- what it writes (`.claude/.devflow-state.json`) and why (to survive
  compaction);
- that it captures only plan name/slug, checklist counts, git branch/sha/counts,
  stop-gate counter/give-up time, and redacted, truncated BLOCKED lines, with
  no file contents, prompts, payload text or absolute paths;
- that it **never blocks**: it always exits 0 and prints nothing. It does not
  read the payload, and writes nothing without jq or without a plan.

Body of `snapshot`, in this order:
1. `command -v jq >/dev/null 2>&1 || exit 0`
2. `cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0`
3. `plan=$(ls -t docs/plans/*.md 2>/dev/null | head -1)`, then
   `[ -n "$plan" ] && [ -f "$plan" ] || exit 0`, then `slug=$(basename "$plan" .md)`.
4. Counts. Do not name a variable `done` (it is a bash keyword):
   ```bash
   total=$(grep -cE '^[[:space:]]*[-*] \[[ xX]\]' "$plan")
   checked=$(grep -cE '^[[:space:]]*[-*] \[[xX]\]' "$plan")
   if [ "$total" -eq 0 ]; then total=null; checked=null; fi
   ```
5. Git: `git=null`. If `git rev-parse --is-inside-work-tree >/dev/null 2>&1` succeeds:
   ```bash
   branch=$(git symbolic-ref --short -q HEAD)
   head=$(git rev-parse --short HEAD 2>/dev/null)
   counts=$(git --no-optional-locks status --porcelain | awk '
     substr($0,1,2)=="??" { u++; next }
     { if (substr($0,1,1) != " ") s++; if (substr($0,2,1) != " ") w++ }
     END { printf "%d %d %d", s, w, u }')
   set -- $counts
   git=$(jq -n --arg b "$branch" --arg h "$head" --argjson s "$1" --argjson w "$2" --argjson u "$3" \
     '{branch: (if $b == "" then null else $b end), head: (if $h == "" then null else $h end),
       staged: $s, unstaged: $w, untracked: $u}')
   ```
6. Stop gate: `state=null`. If `.claude/.stop-gate-state` exists,
   `n=$(tr -dc '0-9' < .claude/.stop-gate-state)` and `[ -n "$n" ] && state="$n"`.
   `giveup=""`, then `[ -f .claude/stop-gate-giveup.log ] && giveup=$(date -u -r .claude/stop-gate-giveup.log +%Y-%m-%dT%H:%M:%SZ)`.
7. Blocked (redact, then truncate, then cap). Mind the shell quoting of the
   single quote inside the regex, which is written as `'"'"'` here:
   ```bash
   blocked=$(jq -R -s 'split("\n") | map(select(contains("BLOCKED"))
     | gsub("(?<![^\\s\"'"'"'`(=:])/[^\\s\"'"'"'`)]*"; "<path>") | .[0:200]) | .[0:10]' "$plan")
   ```
8. Write atomically:
   ```bash
   mkdir -p .claude
   jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg file "$plan" --arg slug "$slug" \
     --argjson checked "$checked" --argjson total "$total" --argjson git "$git" \
     --argjson state "$state" --arg giveup "$giveup" --argjson blocked "$blocked" \
     '{schema_version: "1", saved_at: $at,
       plan: {file: $file, slug: $slug, done: $checked, total: $total},
       git: $git,
       stop_gate: {state: $state, giveup_logged_at: (if $giveup == "" then null else $giveup end)},
       blocked: $blocked}' > .claude/.devflow-state.json.tmp \
     && mv .claude/.devflow-state.json.tmp .claude/.devflow-state.json
   ```

Do not read `$input`. Do not add a `trap`, logging, a timeout, or any field
not listed in the spec.

**Verify:**
```bash
bash "$RIG" snap snap-edge privacy                                   # expect ALL-PASS
bash .claude/lint-cmd plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh; echo "lint=$?"   # lint=0
bash .claude/test-cmd; echo "test=$?"                                # test=0
grep -c 'exit 2' plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh   # 0
```

---

## Task 3: `session-start-restore.sh`

**Files:** create `plugins/dev-flow/hooks/scripts/session-start-restore.sh`

**Depends on:** 2 (the rig's restore groups call the snapshot to build state)

**Test first:** `bash "$RIG" restore restore-edge` prints FAIL lines and
`SOME-FAILED`.

**Change:** create the script, about 35 lines.

```bash
#!/usr/bin/env bash
# SessionStart: <header, see below>
set -u
input=$(cat) # consumed for API compliance; not otherwise used

restore() (
  ...                          # prints one JSON object on success, nothing otherwise
)

restore 2>/dev/null
exit 0
```

Header comment (4-6 lines): it re-injects the snapshot written by
`pre-compact-snapshot.sh` as `additionalContext`, using the
`hookSpecificOutput` JSON documented at https://code.claude.com/docs/en/hooks
("SessionStart decision control"). It stays silent if the file is missing,
older than 24 h, has an unknown schema, or is unparseable. It never blocks
and always exits 0.

Body of `restore`:
1. `command -v jq >/dev/null 2>&1 || exit 0`
2. `cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0`; `f=.claude/.devflow-state.json`; `[ -f "$f" ] || exit 0`
3. `jq -e '.schema_version == "1" and (.plan.file | type) == "string" and ((now - (.saved_at | fromdateiso8601)) < 86400)' "$f" >/dev/null || exit 0`
4. Build the text. The wording is asserted by the rig, so keep it exact:
   ```bash
   ctx=$(jq -r '
     [ "dev-flow state saved before the last context compaction at \(.saved_at); docs/plans is the source of truth.",
       "Active plan: \(.plan.file) (slug \(.plan.slug)); "
         + (if .plan.total == null then "checklist progress not countable."
            else "\(.plan.done) of \(.plan.total) checklist items checked." end),
       (if .git == null then empty else
         "Git: branch \(.git.branch // "detached") at \(.git.head // "no commits"); \(.git.staged) staged, \(.git.unstaged) unstaged, \(.git.untracked) untracked files." end),
       (if .stop_gate.state == null and .stop_gate.giveup_logged_at == null then empty else
         "Stop gate: "
         + ([ (if .stop_gate.state == null then empty else "\(.stop_gate.state) failed attempt(s) recorded" end),
              (if .stop_gate.giveup_logged_at == null then empty else "give-up log last written at \(.stop_gate.giveup_logged_at)" end) ] | join("; "))
         + "." end),
       (if (.blocked | length) == 0 then empty else "Blocked lines in the plan:", (.blocked[0:10][] | "- \(.)") end)
     ] | join("\n")' "$f") || exit 0
   [ -n "$ctx" ] || exit 0
   ```
5. `jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'`

The text is factual, not imperative, as the docs advise. Do not add "you
must…" lines. Do not delete or modify the state file.

**Verify:**
```bash
bash "$RIG" all                                                       # expect ALL-PASS (every group)
bash .claude/lint-cmd plugins/dev-flow/hooks/scripts/session-start-restore.sh; echo "lint=$?"  # lint=0
bash .claude/test-cmd; echo "test=$?"                                 # test=0
grep -c 'exit 2' plugins/dev-flow/hooks/scripts/session-start-restore.sh   # 0
```

---

## Task 4: Register both hooks in `hooks.json`

**Files:** `plugins/dev-flow/hooks/hooks.json`

**Depends on:** 2, 3

**Test first:**
```bash
jq -e '(.hooks.PreCompact[0].hooks[0].command | endswith("/hooks/scripts/pre-compact-snapshot.sh\""))
   and (.hooks.PreCompact[0] | has("matcher") | not)
   and (.hooks.SessionStart[0].matcher == "startup|resume|compact")
   and (.hooks.SessionStart[0].hooks[0].command | endswith("/hooks/scripts/session-start-restore.sh\""))
   and ((.hooks | keys) == ["PostToolUse","PreCompact","PreToolUse","SessionStart","Stop"])' plugins/dev-flow/hooks/hooks.json
# expect: false / exit 1
```

**Change:** after the `Stop` array, add `PreCompact` (no matcher) and
`SessionStart` (matcher `"startup|resume|compact"`). Each has one
`{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh\"" }`
hook, with the same one-line-per-hook formatting and two-space indentation as
the existing entries (spec §5). Leave the three existing entries unchanged.

**Verify:**
```bash
# the test-first command now prints: true
git diff -U0 plugins/dev-flow/hooks/hooks.json | grep '^-' | grep -v '^---'   # only the closing "}" / "]" of Stop may appear, no existing hook line removed
bash .claude/test-cmd; echo "test=$?"   # test=0
claude plugin validate plugins/dev-flow; echo "validate=$?"   # "✔ Validation passed", validate=0
```

---

## Task 5: README: the new "Compaction snapshot" section

**Files:** `README.md` (Documentation section only: insert `### Compaction snapshot` after the `### Stop gate` block, which ends at the `.gitignore` bullet at line ~318, and before `### Managed settings: hooks disabled by your organization`)

**Depends on:** 4

**Test first:**
```bash
has README.md '### Compaction snapshot' && has README.md '.claude/.devflow-state.json' \
 && has README.md 'giveup_logged_at' && has README.md 'Not captured' && has README.md 'startup|resume|compact'
# expect FAIL on the first check
```

**Change:** add the subsection (target 30-45 lines), in the style of
`### Stop gate`: short paragraphs, bullets, one code block. It contains:
1. One paragraph: before compaction (`PreCompact`, manual or auto),
   `pre-compact-snapshot` writes `.claude/.devflow-state.json`. On
   `SessionStart` (`startup|resume|compact`), `session-start-restore` injects
   a summary of at most 15 lines if the file is under 24 h old. Neither hook
   can block; failures are silent and exit 0.
2. "Captured" bullets: schema version and `saved_at`; the most recently
   modified `docs/plans/*.md` (repo-relative path and slug) and its `- [ ]` /
   `- [x]` checklist counts, which are `null` if it has none; git branch,
   short HEAD, and staged/unstaged/untracked **counts**; the stop-gate attempt
   counter and `giveup_logged_at` (the give-up log's mtime: the stop gate
   records no session id, so "gave up in this session" can't be told
   reliably); up to 10 plan lines containing `BLOCKED`, with absolute paths
   replaced by `<path>` and each cut to 200 characters.
3. **"Not captured"** bullets, deliberately: file contents or diffs, file
   names (only counts), source code, conversation or prompt text, the hook
   payload (`session_id`, `transcript_path`, `cwd`, `custom_instructions`),
   absolute paths, and anything outside `docs/plans/`, git metadata and the
   two stop-gate files. One sentence on why: safe on PCI-scope codebases.
4. A fenced example of the injected text (copy the line formats from task 3,
   step 4).
5. Caveats: dev-flow's own plans mark tasks with `## Task N` headings and
   only their acceptance criteria are checkboxes, which `/dev-flow:build`
   doesn't tick, so counts show acceptance items; and the `implementer`
   reports `BLOCKED` in chat rather than writing it into the plan, so blocked
   lines appear only if someone records them there. "Most recently modified"
   can pick a newer plan than the one being built; the injected text names
   the file, and the plan stays the source of truth. jq is required; without
   it, nothing is written or injected.
6. In hookless mode neither hook runs, so the feature is simply absent.
   Link `#managed-settings-hooks-disabled-by-your-organization`.
7. "Add `.claude/.devflow-state.json` to `.gitignore`. It is local state; an
   un-ignored copy also counts as an untracked change, which makes the stop
   gate run on otherwise read-only turns."
8. A final line: "Verified by running both scripts against a throwaway repo
   (see `docs/plans/compaction-snapshot.md`); not yet observed in a live
   compaction."

**Verify:** rerun the test-first block and expect all PASS. Also
`[ $(grep -c '^### ' README.md) -eq $(( $(git show HEAD:README.md | grep -c '^### ') + 1 )) ] && echo PASS`.

---

## Task 6: README: tables, hook counts, hookless row, Known limits

**Files:** `README.md` (lines ~248-250 table, ~322, ~334-338 hookless table, ~502, Known limits ~508-521)

**Depends on:** 5

**Test first:**
```bash
has README.md '| `pre-compact-snapshot` | Hook |' && has README.md '| `session-start-restore` | Hook |' \
 && has README.md 'Hooks 5 (' && lacks README.md "none of dev-flow's three hooks" \
 && has README.md '| compaction snapshot |' && has README.md '(#compaction-snapshot)'
# expect FAIL
```

**Change:**
- "Other Commands, Skills and Agents" table: after the `pre-write-guard` row,
  add:
  - `` | `pre-compact-snapshot` | Hook | Before compaction, saves the active plan, checklist counts, git branch/counts and BLOCKED lines to `.claude/.devflow-state.json` — no file contents (see below). | ``
  - `` | `session-start-restore` | Hook | At session start, injects that snapshot (≤15 lines) if it is under 24 h old. | ``
- Line ~322: replace `none of dev-flow's three hooks (pre-write guard, per-edit check, stop gate) run`
  with `none of dev-flow's hooks (pre-write guard, per-edit check, stop gate, compaction snapshot) run`.
- Hookless table: add a last row
  `` | compaction snapshot | none — compaction is triggered by the harness, so there is nothing for an instruction to hook into; the plan in `docs/plans/` remains the record | not available | ``.
- Line ~502: `Hooks 3 (PreToolUse, PostToolUse, Stop)` becomes
  `Hooks 5 (PreToolUse, PostToolUse, Stop, PreCompact, SessionStart)`.
- Known limits: one bullet: "The compaction snapshot is verified by running
  its scripts directly, not yet inside a live compaction; see
  [Compaction snapshot](#compaction-snapshot) for what it does not capture."

**Verify:** rerun the test-first block and expect all PASS.
`grep -n 'three hooks' README.md` prints nothing.

---

## Task 7: Gitignore guidance (README and this repo)

**Files:** `README.md` (lines ~158 and ~384 only), `.gitignore`

**Depends on:** 5

**Test first:**
```bash
has README.md 'rm -rf .claude/.approved-writes .claude/.stop-gate-state .claude/stop-gate-giveup.log .claude/.devflow-state.json'
has README.md 'Add `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log`, `.claude/.devflow-state.json` and `.claude/.approved-writes/` to `.gitignore`.'
grep -qxF '.claude/.devflow-state.json' .gitignore && echo PASS || echo FAIL
# expect FAIL on all three
```

**Change:**
- `README.md:158` (Uninstalling, per-repo leftovers): append
  ` .claude/.devflow-state.json` to the end of the
  `rm -rf .claude/.approved-writes .claude/.stop-gate-state .claude/stop-gate-giveup.log` line.
- `README.md:384` (Per-repo config files, the last sentence of the paragraph
  that begins "Keep `test-cmd` fast"): change
  "Add `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log` and `.claude/.approved-writes/` to `.gitignore`."
  to
  "Add `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log`, `.claude/.devflow-state.json` and `.claude/.approved-writes/` to `.gitignore`."
- Leave the Stop gate bullet at `README.md:318` alone. It lists only the stop
  gate's own files, and the new section (task 5, item 7) carries its own
  gitignore line, mirroring how `### Pre-write guard` does it at
  `README.md:271`.
- `.gitignore`: append one line, `.claude/.devflow-state.json`.

**Verify:** all three test-first checks print PASS.
`git check-ignore -q .claude/.devflow-state.json && echo PASS` prints PASS.

---

## Task 8: Gitignore reminders in `init-hooks` and `onboard` (Open question 4)

**Files:** `plugins/dev-flow/commands/init-hooks.md` (line 179 only), `plugins/dev-flow/commands/onboard.md` (lines 122-124 only)

**Depends on:** none. Skip this task entirely if the user answered OQ4 "README only".

**Test first:**
```bash
has plugins/dev-flow/commands/init-hooks.md '.claude/.devflow-state.json' && has plugins/dev-flow/commands/onboard.md '.claude/.devflow-state.json'
# expect FAIL
```

**Change:**
- `init-hooks.md:179`: in "Remind me to gitignore the hooks' state files: …",
  insert `` `.claude/.devflow-state.json`, `` after
  `` `.claude/stop-gate-giveup.log`, ``. Change nothing else on the line.
- `onboard.md:122-124`: in "a gitignore reminder for `.claude/.stop-gate-state`,
  `.claude/stop-gate-giveup.log` and `.claude/.approved-writes/`", insert
  `` `.claude/.devflow-state.json`, `` after `` `.claude/stop-gate-giveup.log` ``
  (adjusting "and" so the list reads correctly). Leave the frontmatter alone.

**Verify:** rerun the test-first line and expect PASS for both.
`git diff --stat plugins/dev-flow/commands` shows 2 files, each with 1-2 lines changed.

---

## Task 9: `AGENTS.md` layout and hazards (guarded file)

**Files:** `AGENTS.md` only. **Never** `CLAUDE.md` (a symlink: the guard refuses it outright).

**Depends on:** 4

**Test first:**
```bash
has AGENTS.md 'pre-compact-snapshot' && has AGENTS.md '.claude/.devflow-state.json' && lacks AGENTS.md 'the three hooks'
# expect FAIL
```

**Change:** one `Edit` per line, or a single `MultiEdit`; prefer one call so
the user reviews one change:
- Line 23: `` wires `PreToolUse` (pre-write-guard), `PostToolUse` (post-edit-check) and `Stop` (stop-gate) to scripts in `hooks/scripts/`. `` becomes
  `` wires `PreToolUse` (pre-write-guard), `PostToolUse` (post-edit-check), `Stop` (stop-gate), `PreCompact` (pre-compact-snapshot) and `SessionStart` (session-start-restore) to scripts in `hooks/scripts/`. ``
- Line 24: `the three hooks, pure bash + jq.` becomes `the five hooks, pure bash + jq.`
- Line 45 (Hazards): after `` `.claude/stop-gate-giveup.log` `` add
  ``, and the compaction snapshot writes `.claude/.devflow-state.json` `` so
  that the sentence still ends "— keep those gitignored, …".

This is a **guarded write**. `pre-write-guard` will block the call and print
the diff and a marker command. Show the user the change verbatim, wait for an
explicit yes in that turn, run the exact marker command it gives, then retry
the same call unchanged. Do not split the change or route around the guard.
If the user declines, stop and report.

**Verify:** rerun the test-first block and expect all PASS.
`[ -L CLAUDE.md ] && git diff --quiet HEAD -- CLAUDE.md && echo PASS`.
`git diff --stat AGENTS.md` shows 1 file, 3 lines changed.

---

## Task 10: `.claude/rules/hook-scripts.md`, SessionStart stdout (guarded file)

**Files:** `.claude/rules/hook-scripts.md` (line 6 only)

**Depends on:** 3

**Test first:**
```bash
has .claude/rules/hook-scripts.md 'SessionStart' && has .claude/rules/hook-scripts.md 'PreCompact'
# expect FAIL
```

**Change:** replace line 6 with:

```
- Exit 0 = allow/pass silently. Exit 2 = block; put the message on stderr. No other exit code is meaningful to Claude Code. Stdout is ignored by the harness except on `SessionStart`, where it is injected as context (`session-start-restore.sh` prints a `hookSpecificOutput` JSON object). `PreCompact` and `SessionStart` hooks here must never exit 2 or print a decision: they always exit 0.
```

Leave the frontmatter (`paths:`) and every other line unchanged. This is a **guarded
write**: follow the same show-diff, explicit-yes, marker, retry procedure as
task 9.

**Verify:** rerun the test-first block and expect PASS.
`git diff --stat .claude/rules/hook-scripts.md` shows 1 line changed.

---

## Task 11: Release bump

**Files:** `plugins/dev-flow/.claude-plugin/plugin.json`

**Depends on:** 1-10

**Test first:** `jq -e '.version == "1.14.0"' plugins/dev-flow/.claude-plugin/plugin.json`
prints `false` and exits 1.

**Change:** set `"version": "1.14.0"` (currently `1.13.0`; a minor bump for a
new feature). Nothing else. Do not tag or push.

**Verify:** the test-first command prints `true`. `bash .claude/test-cmd; echo $?`
prints `0`.

---

## Task 12: Evidence run (the user's Step 4)

**Files:** none changed. This task only runs commands and pastes their
output into the final report.

**Depends on:** 1-11

**Test first:** n/a. This is the verification. Any `FAIL`, any non-zero
`exit=`, or any grep hit below is a failure. Stop and report it; do not
patch the evidence.

**Commands** (run each block and keep the raw output for the report):

```bash
# 0. full rig
bash "$RIG" all; echo "rig exit=$?"                       # expect ALL-PASS, rig exit=0

# 1. throwaway repo with a BLOCKED line and uncommitted changes
H=$(cd "${TMPDIR:-/tmp}" && pwd -P)/devflow-snap-evidence; rm -rf "$H"; mkdir -p "$H"
H="$H" bash "$RIG" self >/dev/null                         # builds $H/fix via mkfix
F="$H/fix"; git -C "$F" status --short                    # shows: M src/b.php (unstaged), A src/c.php (staged), ?? notes.txt
cat "$F/docs/plans/test-feature.md"

# 2. snapshot with a representative payload
P=plugins/dev-flow/hooks/scripts
jq -nc --arg cwd "$F" '{session_id:"abc123",transcript_path:"/Users/someone/.claude/projects/x/abc123.jsonl",cwd:$cwd,hook_event_name:"PreCompact",trigger:"auto",custom_instructions:{project:"Use TypeScript."}}' \
  | CLAUDE_PROJECT_DIR="$F" bash "$P/pre-compact-snapshot.sh"; echo "snapshot exit=$?"   # exit=0, no other output
cat "$F/.claude/.devflow-state.json"                      # show the JSON

# 3. restore: exact injected output
printf '{"hook_event_name":"SessionStart","source":"compact"}' | CLAUDE_PROJECT_DIR="$F" bash "$P/session-start-restore.sh" > "$H/out.json"; echo "restore exit=$?"
cat "$H/out.json"                                         # raw stdout (the JSON Claude Code reads)
jq -r '.hookSpecificOutput.additionalContext' "$H/out.json"   # the injected text, <=15 lines

# 4. degenerate cases, all must print exit=0
R() { printf '{}' | CLAUDE_PROJECT_DIR="$1" bash "$P/session-start-restore.sh"; echo "  exit=$?"; }
Sn() { printf '{}' | CLAUDE_PROJECT_DIR="$1" bash "$P/pre-compact-snapshot.sh"; echo "  exit=$?"; }
echo "no state file:";        rm -f "$F/.claude/.devflow-state.json"; R "$F"
echo "malformed state file:"; printf '{oops' > "$F/.claude/.devflow-state.json"; R "$F"
echo "older than 24h:";       Sn "$F" >/dev/null; jq '.saved_at="2020-01-01T00:00:00Z"' "$F/.claude/.devflow-state.json" > "$H/s" && mv "$H/s" "$F/.claude/.devflow-state.json"; R "$F"
echo "no docs/plans (snapshot):"; mkdir -p "$H/noplans"; Sn "$H/noplans"; ls -a "$H/noplans"
echo "no docs/plans (restore):";  R "$H/noplans"
echo "not a git repo (snapshot):"; mkdir -p "$H/nogit/docs/plans"; printf -- '- [ ] a\n' > "$H/nogit/docs/plans/p.md"; GIT_CEILING_DIRECTORIES="$H" Sn "$H/nogit"; jq -c .git "$H/nogit/.claude/.devflow-state.json"
echo "not a git repo (restore):";  GIT_CEILING_DIRECTORIES="$H" R "$H/nogit"
# expect: every line "exit=0", restore prints nothing in the first three cases, .git is null for nogit

# 5. privacy greps on a fresh snapshot (each must print nothing)
Sn "$F" >/dev/null; J="$F/.claude/.devflow-state.json"
grep -nF -- "$F" "$J"; grep -nF -- "$HOME" "$J"; grep -nE '"/|/Users/|/home/|/private/|/var/' "$J"
grep -nE 'SOURCE-SENTINEL|4111|PLAN-BODY-SENTINEL|abc123|TypeScript' "$J"
jq -e '[.. | strings | select(startswith("/"))] | length == 0' "$J"    # true
echo "privacy greps done"

# 6. validators
claude plugin validate .;               echo "validate root=$?"     # "✔ Validation passed", 0
claude plugin validate plugins/dev-flow; echo "validate plugin=$?"  # "✔ Validation passed", 0
bash .claude/test-cmd;                   echo "test-cmd=$?"          # 0
jq -r .version plugins/dev-flow/.claude-plugin/plugin.json           # 1.14.0
```

**Verify:** every expectation in the comments above holds. The report
includes, verbatim: the state JSON from block 2, the raw `out.json` and the
decoded text from block 3, the exit-code lines from block 4, the (empty)
grep output from block 5, and both `claude plugin validate` results.

---

## Acceptance criteria (for `verify-done`)

- [ ] `bash "$RIG" all` prints `ALL-PASS`.
- [ ] `bash .claude/test-cmd` exits 0.
- [ ] `claude plugin validate .` and `claude plugin validate plugins/dev-flow` both print `✔ Validation passed` and exit 0.
- [ ] Neither new script can exit 2: `! grep -n 'exit 2' plugins/dev-flow/hooks/scripts/pre-compact-snapshot.sh plugins/dev-flow/hooks/scripts/session-start-restore.sh && echo PASS`.
- [ ] Both scripts end with `exit 0` as their last line: `for f in pre-compact-snapshot session-start-restore; do tail -1 plugins/dev-flow/hooks/scripts/$f.sh; done` prints `exit 0` twice.
- [ ] Task 4's jq check on `hooks.json` prints `true`, and the three existing hook entries are byte-identical to `HEAD` (`git diff plugins/dev-flow/hooks/hooks.json` shows only additions, apart from the `Stop` array's closing bracket).
- [ ] `stop-gate.sh`, `pre-write-guard.sh` and `post-edit-check.sh` are unchanged: `git diff --quiet HEAD -- plugins/dev-flow/hooks/scripts/stop-gate.sh plugins/dev-flow/hooks/scripts/pre-write-guard.sh plugins/dev-flow/hooks/scripts/post-edit-check.sh && echo PASS`.
- [ ] Every `has`/`lacks` check in tasks 5-10 passes.
- [ ] `.gitignore` contains `.claude/.devflow-state.json`, and `git check-ignore -q .claude/.devflow-state.json` succeeds.
- [ ] `CLAUDE.md` is unchanged and still a symlink: `[ -L CLAUDE.md ] && git diff --quiet HEAD -- CLAUDE.md && echo PASS`.
- [ ] `plugin.json` version is `1.14.0`.
- [ ] Task 12's evidence is in the final report: state JSON, raw and decoded restore output, degenerate-case exit codes (all 0), empty privacy greps, validator output.
- [ ] Not verifiable here, so report it as not verified: a live compaction in a real session. That means running `/compact` in a repo with a `docs/plans/*.md`, confirming `.claude/.devflow-state.json` appears, and confirming the post-compaction session has the summary in context (and that `claude plugin details dev-flow` lists `Hooks 5` after updating the installed copy).
