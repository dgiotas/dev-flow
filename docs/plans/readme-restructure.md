# Plan: README restructure + one-liner install, version pinning, uninstall script

Spec: `docs/specs/readme-restructure.md`. Read it first, especially "Current behaviour"
(what was verified live) and "Open questions". This plan assumes the bracketed defaults
there: repo stays public, `DEV_FLOW_VERSION`, tag format `dev-flow--v<ver>`, no tag
backfill, separate `uninstall.sh`, no License section, Changelog pointing at tags, no
badges. **If the user's answers differ, stop and re-plan the affected tasks.**

There is no test framework in this repo (`AGENTS.md` "Commands"). The repo-wide check is
`bash .claude/test-cmd` (jq JSON validation + `bash -n` on every `*.sh`). Every task pairs
that with an explicit behavioural check from the Task 0 rig.

Conventions:
- `$R` = `/Users/dgiotas/Projects/personal/dev-flow`
- `$H` = `/tmp/devflow-readme` (test rig, **not** in the repo, never committed)
- `FAKE` = `PATH=$H/bin:$PATH FAKE_LOG=$H/claude.log` (prefix for stubbed runs)

**Hard rules for every task:**
1. Never run `install.sh` or `uninstall.sh` for real against your own Claude config.
   The dev-flow plugin running this session **is** the thing they install and remove.
   Use the fake-`claude` rig (`FAKE` prefix), or for a real run export a throwaway
   `CLAUDE_CONFIG_DIR=$(mktemp -d)` first. That isolation was verified: the real
   `~/.claude/plugins/known_marketplaces.json` was untouched.
2. `README.md` edits: move existing text, do not rephrase any caveat containing
   "verified", "unverified", "not yet" or "haven't". The `preserve` check enforces this.
3. Never `git push`, create tags, or merge. Task 13's release steps are for the user.

---

## Task 0: Test rig (fake `claude`/`npm`/`codegraph` + README check script)

**Files:** `$H/bin/claude`, `$H/bin/npm`, `$H/bin/codegraph`, `$H/check.sh` (all outside
the repo).

**Test first:** none. This task *is* the test rig.

**Change:**
- `$H/bin/claude` (chmod +x): appends `"$*"` as one line to `${FAKE_LOG:-$H/claude.log}`,
  then:
  ```bash
  case "$1 $2" in
    "plugin list") for p in ${FAKE_PLUGINS:-}; do printf '  ❯ %s\n' "$p"; done ;;
    "plugin marketplace")
      case "$3" in
        list) for m in ${FAKE_MARKETPLACES:-}; do printf '  ❯ %s\n' "$m"; done ;;
        add)  if [ "${FAKE_ADD_FAIL:-0}" = 1 ]; then
                echo 'Cannot add marketplace "dev-flow-marketplace": its network source differs'; exit 1
              fi ;;
      esac ;;
  esac
  exit "${FAKE_STATUS:-0}"
  ```
  (`❯` + name matches the real list format that install.sh parses with
  `awk '{print $NF}'`, `install.sh:200-201`.)
- `$H/bin/npm` and `$H/bin/codegraph` (chmod +x): append `"$0 $*"` to `$H/tools.log`, exit 0.
- `$H/check.sh <group>...`: groups `preserve install uninstall tables docs1 docs2 outline
  stale all`. Prints `MISSING: …` / `STALE: …` / `OUTLINE: …` lines and exits 1 if any
  assertion fails, otherwise prints `PASS <groups>`. Helpers:
  ```bash
  R=/Users/dgiotas/Projects/personal/dev-flow/README.md; fail=0
  no_code() { awk '/^```/{c=!c; next} !c' "$R"; }
  section() { awk -v h="$1" '/^```/{c=!c} !c && $0==h {on=1; next} !c && on && /^## /{exit} on' "$R"; }
  has()       { grep -qF -- "$1" "$R" || { echo "MISSING: $1"; fail=1; }; }
  lacks()     { ! grep -qF -- "$1" "$R" || { echo "STALE: $1"; fail=1; }; }
  sec_has()   { section "$1" | grep -qF -- "$2" || { echo "MISSING in $1: $2"; fail=1; }; }
  sec_lacks() { ! section "$1" | grep -qF -- "$2" || { echo "UNEXPECTED in $1: $2"; fail=1; }; }
  ```
  Assertions per group:
  - **preserve** (must pass on today's README too): `has` each of
    `ALLOW-CLAUDE-MD-EDIT`, `DEV_FLOW_STOP_GATE_MAX`, `.claude/test-cmd-retries`,
    `lint-cmd.docker.example`, `test-cmd.docker.example`, `docker compose exec -T`,
    `guidance-target.sh`, `1,875`, `Skills 15`, `claude mcp list`,
    `npx claude-mem uninstall`, `/powerline`, `--plugin-dir ./plugins/dev-flow`,
    `.claude/.approved-writes/`, `.claude/stop-gate-giveup.log`, `node -e`,
    `/reload-plugins`, `ln -s AGENTS.md CLAUDE.md`. Plus:
    `grep -oiE 'not (yet )?verified|unverified|haven.t verified|not yet (run|observed)' "$R" | wc -l`
    must be `>= 5`.
  - **install**: `has` `## Why dev-flow`, `### Prerequisites`, `### Installation`,
    `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash`,
    `| DEV_FLOW_VERSION=1.12.0 bash`, `| bash -s -- --with-memory`,
    `bash <(curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh)`,
    `git clone https://github.com/dgiotas/dev-flow.git`,
    `/plugin marketplace add dgiotas/dev-flow`, `dev-flow--v`,
    `<summary>Installer flags</summary>`, `<summary>What the installer does</summary>`,
    `<summary>Try without installing</summary>`.
  - **uninstall**: `has`
    `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash`,
    `| bash -s -- --remove-tools`, `--remove-superpowers`,
    `<summary>Uninstalling</summary>`, `<summary>Switching version / downgrading</summary>`,
    `### First Steps`, `Per-repo leftovers`, `claude mcp remove codegraph`;
    `sec_has "## Getting Started" "/dev-flow:onboard"`.
  - **tables**:
    `sec_has "## Ways of Working" "| Path | What it adds |"`;
    `sec_has "## Workflows" "| Command | Use it when | What it does |"`, and for each of
    ``/dev-flow:spec`` ``ok build`` ``/dev-flow:build`` ``/dev-flow:onboard``:
    `sec_has "## Workflows" "| \`$x"`;
    `sec_has "## Other Commands, Skills and Agents" "| Name | Kind | Purpose |"`, and for
    each of `/dev-flow:init-hooks /dev-flow:init-rules /dev-flow:init-codegraph
    spec-architect implementer reviewer code-intel investigate fix-bug verify-done
    setup-rules dead-code-audit git-workflow security-review db-migration
    post-edit-check stop-gate pre-write-guard`: `sec_has … "| \`$x"`; for each of
    `context7 semble chrome-devtools codegraph`: `sec_has … "$x"`; and `sec_lacks …` each
    of `/dev-flow:spec`, `/dev-flow:build`, `/dev-flow:onboard`.
  - **docs1**: `sec_has "## Documentation"` each of `### Pre-write guard`,
    `### AGENTS.md or CLAUDE.md`, `### Stop gate`, `### Per-repo config files`,
    `### Containerised toolchains`, `### MCP servers`.
  - **docs2**: `sec_has "## Documentation"` each of `### Model routing`,
    `### Memory (optional)`, `### Status line (optional)`, `### Updating`,
    `### Troubleshooting`, `### Known limits`, `| Reply \`ok build\` |`,
    `claude plugin marketplace update dev-flow-marketplace`, `uninstall.sh`;
    `sec_has "## Changelog" "https://github.com/dgiotas/dev-flow/tags"`;
    `sec_has "## Contributing" "claude plugin tag plugins/dev-flow"`;
    `sec_has "## Contributing" "bash .claude/test-cmd"`.
  - **outline**: `no_code | grep '^## ' | paste -sd'|' -` must equal exactly
    `## Why dev-flow|## Getting Started|## Ways of Working|## Workflows|## Other Commands, Skills and Agents|## Documentation|## Changelog|## Contributing`;
    `no_code | grep -c '^# '` must be `1`; `sec_has "## Getting Started"` each of
    `### Prerequisites`, `### Installation`, `### First Steps`.
  - **stale**: `lacks` `git clone <this repo>`, `(v1.11)`,
    `Host the marketplace in a private git repo`, `your-org/dev-flow-marketplace`,
    `/path/to/dev-flow-marketplace`, `## What's inside`, `## Daily use`,
    `## Colleague quick-start`, `## Uninstalling everything`.
  - **all** = every group above.

**Verify:**
```bash
bash $H/check.sh preserve              # expect: PASS preserve (baseline on today's README)
bash $H/check.sh install; echo $?      # expect: MISSING lines, exit 1 (red, as intended)
$H/bin/claude plugin list; echo $?     # expect: exit 0, no output
```

**Depends on:** none.

---

## Task 1: `install.sh` default source (fixes `curl | bash`)

**Files:** `install.sh`

**Test first** (fails today: `SRC` becomes the cwd, see spec):
```bash
cd /tmp && cat $R/install.sh | $FAKE bash -s -- --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow'
```

**Change:** replace `install.sh:58` (`SRC="${SRC:-$(cd … BASH_SOURCE …)}"`) with the
resolution in spec §A.1: `REPO="dgiotas/dev-flow"`, `script="${BASH_SOURCE[0]:-}"`, and
`here=` the script's dir only if `$(dirname "$script")/.claude-plugin/marketplace.json`
exists, then `SRC="${SRC:-${here:-$REPO}}"`. Keep `SRC=""` from the arg loop (`:43`) so an
explicit positional arg still wins. Update the usage text line
`marketplace-source: … (default: this folder)` in both the header comment (`:6`) and
`usage()` (`:29`) to `(default: this folder when run from a clone, else dgiotas/dev-flow)`.

**Verify:**
```bash
cd /tmp && cat $R/install.sh | $FAKE bash -s -- --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow'   # match
cd /tmp && $FAKE bash <(cat $R/install.sh) --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow'        # match
$FAKE bash $R/install.sh --dry-run -y 2>&1 | grep -F "<- $R"                                       # match (clone unchanged)
$FAKE bash $R/install.sh someorg/fork --dry-run -y 2>&1 | grep -F '<- someorg/fork'                # match
cd $R && bash .claude/test-cmd; echo $?                                                            # 0
```

**Depends on:** 0.

---

## Task 2: `install.sh` truncation guard

**Files:** `install.sh`

**Test first** (fails today: a truncated script still runs section 1):
```bash
head -n 300 $R/install.sh | $FAKE bash -s -- --dry-run -y 2>&1 | grep -c 'Prerequisites'   # today: 1; want: 0
```

**Change:** insert a line containing only `{` immediately before `set -u` (`install.sh:21`),
with a comment on the line above:
`# Whole script in one brace group: bash parses it fully before running anything, so a truncated curl | bash download runs nothing.`
Append a final line containing only `}`. Do not re-indent anything.

**Verify:**
```bash
head -n 300 $R/install.sh | $FAKE bash -s -- --dry-run -y 2>&1 | grep -c 'Prerequisites'   # 0
cd /tmp && cat $R/install.sh | $FAKE bash -s -- --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow'   # still matches
$FAKE bash $R/install.sh --help; echo $?                                                   # usage, 0
cd $R && bash .claude/test-cmd; echo $?                                                    # 0
```

**Depends on:** 1.

---

## Task 3: `install.sh` `DEV_FLOW_VERSION` pin

**Files:** `install.sh`

**Test first** (all fail today):
```bash
cd /tmp && cat $R/install.sh | DEV_FLOW_VERSION=1.12.0 $FAKE bash -s -- --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow#dev-flow--v1.12.0'
DEV_FLOW_VERSION=1.12 $FAKE bash $R/install.sh --dry-run -y; echo $?     # want 2
```

**Change:** replace the Task 1 `SRC=` line with a branch (spec §A.2):
```bash
if [ -n "${DEV_FLOW_VERSION:-}" ]; then
  ver="${DEV_FLOW_VERSION#v}"
  # validate: ^[0-9]+\.[0-9]+\.[0-9]+$ via [[ =~ ]]; else printf to stderr + exit 2
  src="${SRC:-$REPO}"      # a clone dir is ignored: pinning is a GitHub tag feature
  # if [ -d "$src" ]: stderr "DEV_FLOW_VERSION pins a GitHub tag; it can't be combined with the local path $src. Check out tag dev-flow--v$ver in your clone instead." ; exit 2
  SRC="$src#dev-flow--v$ver"
else
  SRC="${SRC:-${here:-$REPO}}"
fi
```
Error messages go to stderr and exit 2, like the existing `unknown option` path
(`install.sh:54`). Add to the header comment and to `usage()`:
`DEV_FLOW_VERSION=x.y.z  env var: install that tagged release (tag dev-flow--vx.y.z; available from 1.12.0)`.

**Verify:**
```bash
cd /tmp && cat $R/install.sh | DEV_FLOW_VERSION=1.12.0 $FAKE bash -s -- --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow#dev-flow--v1.12.0'   # match
DEV_FLOW_VERSION=v1.12.0 $FAKE bash $R/install.sh --dry-run -y 2>&1 | grep -F '<- dgiotas/dev-flow#dev-flow--v1.12.0'                    # match (clone ignored)
DEV_FLOW_VERSION=1.12.0 $FAKE bash $R/install.sh someorg/fork --dry-run -y 2>&1 | grep -F '<- someorg/fork#dev-flow--v1.12.0'           # match
DEV_FLOW_VERSION=1.12   $FAKE bash $R/install.sh --dry-run -y; echo $?                                                                # 2
DEV_FLOW_VERSION=1.12.0 $FAKE bash $R/install.sh "$R" --dry-run -y 2>&1 | grep -F 'dev-flow--v1.12.0 in your clone'                    # match; exit 2
$FAKE bash $R/install.sh --dry-run -y 2>&1 | grep -F "<- $R"                                                                           # unpinned unchanged
cd $R && bash .claude/test-cmd; echo $?                                                                                               # 0
```

**Depends on:** 2.

---

## Task 4: `install.sh` source-conflict hint + usage one-liners

**Files:** `install.sh`

**Test first** (fails today, no hint):
```bash
: > $H/claude.log
FAKE_MARKETPLACES=dev-flow-marketplace FAKE_ADD_FAIL=1 $FAKE bash $R/install.sh --skip-superpowers --skip-codegraph -y 2>&1 | grep -F 'uninstall.sh'
$FAKE bash $R/install.sh --help | grep -F 'curl -fsSL'
```

**Change:**
- At `install.sh:382`, the `run_step 120 "add marketplace dev-flow ($SRC)" …` line, add
  `|| { has_marketplace dev-flow-marketplace && { note "dev-flow-marketplace is already registered from a different source or version."; note "Run uninstall.sh first (see README > Uninstalling), then re-run this installer."; }; }`.
  Keep it on as few lines as reads cleanly. `has_marketplace` uses the pre-flight cache,
  which is correct here: it answers "was it already registered before this run".
- `usage()`: add three lines:
  `One-liner:  curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash`,
  `  flags:    … | bash -s -- --with-memory`,
  `  checklist: bash <(curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh)`.
  Mirror them in the header comment.

**Verify:**
```bash
FAKE_MARKETPLACES=dev-flow-marketplace FAKE_ADD_FAIL=1 $FAKE bash $R/install.sh --skip-superpowers --skip-codegraph -y 2>&1 | grep -cF 'uninstall.sh'   # >=1
FAKE_MARKETPLACES=""                   FAKE_ADD_FAIL=1 $FAKE bash $R/install.sh --skip-superpowers --skip-codegraph -y 2>&1 | grep -cF 'uninstall.sh'   # 0
FAKE_MARKETPLACES=""                                   $FAKE bash $R/install.sh --skip-superpowers --skip-codegraph -y 2>&1 | grep -F 'Done'          # "0 failures"
$FAKE bash $R/install.sh --help | grep -cF 'raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh'   # >=2
cd $R && bash .claude/test-cmd; echo $?                                                                   # 0
```

**Depends on:** 3.

---

## Task 5: `uninstall.sh`: default removal + `--dry-run`

**Files:** `uninstall.sh` (new, repo root)

**Test first** (fails: file missing):
```bash
$FAKE bash $R/uninstall.sh --dry-run; echo $?     # today: "No such file", 127
```

**Change:** create `uninstall.sh` per spec §B, default path only (flags come in Task 6),
~80 lines:
- Shebang + header comment (usage, one-liner
  `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash`,
  what it never touches). Then `{` on its own line, `set -u`,
  `export GIT_TERMINAL_PROMPT=0`, and at EOF `}` (same truncation guard as Task 2).
- `usage()` heredoc. Arg loop: `--remove-tools`, `--remove-superpowers` (parse now, set
  vars, act in Task 6), `--dry-run`, `-h|--help` (usage, exit 0), anything else ⇒
  `unknown option` on stderr + usage + exit 2.
- `command -v claude` or print `claude CLI not found` and exit 1.
- Caches, exactly as `install.sh:198-201`: `MKT_CACHE`, `PLG_CACHE`, `has_marketplace`,
  `has_plugin` (drop `cap`/`timeout`; plain `… 2>/dev/null </dev/null || true`).
- Output helpers: `ok`, `skip`, `fail` (sets `N_FAIL`), `note`. Plain text, same
  `  [ok]   ` / `  [skip] ` / `  [FAIL] ` prefixes as install.sh.
- `remove_plugin <id>` / `remove_marketplace <name>`: if not present ⇒ `skip "<x> not installed"`.
  If `DRY_RUN=1` ⇒ print `  would run: claude plugin uninstall <id>` and return. Otherwise
  run `claude plugin uninstall "$1" </dev/null 2>&1` (or `claude plugin marketplace remove`).
  On success `ok`. On failure `fail` plus the last 8 output lines indented `         | `
  (same as `install.sh:178`).
- Main: `remove_plugin dev-flow@dev-flow-marketplace`, then
  `remove_marketplace dev-flow-marketplace`. End with `note "Restart Claude Code."`, then
  `exit 1` if `N_FAIL>0` else `exit 0`. In dry-run, print
  `Dry run: nothing removed.` and exit 0.

**Verify:**
```bash
: > $H/claude.log
FAKE_PLUGINS="dev-flow@dev-flow-marketplace superpowers@superpowers-marketplace" \
FAKE_MARKETPLACES="dev-flow-marketplace superpowers-marketplace" $FAKE bash $R/uninstall.sh; echo $?   # 0
grep -nE 'uninstall|remove' $H/claude.log
#   expect exactly, in this order:  plugin uninstall dev-flow@dev-flow-marketplace
#                                   plugin marketplace remove dev-flow-marketplace
#   and no superpowers line
: > $H/claude.log
FAKE_PLUGINS="dev-flow@dev-flow-marketplace" FAKE_MARKETPLACES="dev-flow-marketplace" $FAKE bash $R/uninstall.sh --dry-run | grep -c 'would run'   # 2
grep -cE 'uninstall|remove' $H/claude.log                                                  # 0
FAKE_PLUGINS="" FAKE_MARKETPLACES="" $FAKE bash $R/uninstall.sh | grep -c '\[skip\]'; echo ${PIPESTATUS[0]}   # 2, exit 0
FAKE_PLUGINS="dev-flow@dev-flow-marketplace" FAKE_STATUS=1 $FAKE bash $R/uninstall.sh; echo $?   # 1 (FAIL shown)
$FAKE bash $R/uninstall.sh --bogus; echo $?                                                 # 2
cat $R/uninstall.sh | $FAKE bash -s -- --dry-run; echo $?                                   # 0
head -n 40 $R/uninstall.sh | $FAKE bash 2>&1 | grep -c 'would run\|\[ok\]\|\[skip\]'        # 0 (guard)
cd $R && bash .claude/test-cmd; echo $?                                                     # 0
```

**Depends on:** 0.

---

## Task 6: `uninstall.sh`: `--remove-tools`, `--remove-superpowers`, manual follow-ups, real isolated run

**Files:** `uninstall.sh`

**Test first** (fails: flags parsed but do nothing):
```bash
: > $H/claude.log; : > $H/tools.log
FAKE_PLUGINS="dev-flow@dev-flow-marketplace claude-powerline@claude-powerline superpowers@superpowers-marketplace" \
FAKE_MARKETPLACES="dev-flow-marketplace claude-powerline superpowers-marketplace" \
$FAKE bash $R/uninstall.sh --remove-tools --remove-superpowers
grep -E 'uninstall|remove' $H/claude.log | grep -c 'powerline\|superpowers'   # want 4
grep -F 'uninstall -g @colbymchenry/codegraph' $H/tools.log
```

**Change:**
- `--remove-tools`: `remove_plugin claude-powerline@claude-powerline`,
  `remove_marketplace claude-powerline`. Then, if `command -v codegraph` and
  `command -v npm`, run `npm uninstall -g @colbymchenry/codegraph </dev/null` through the
  same ok/fail/dry-run handling (generalise with a `run <label> <cmd…>` helper if that
  keeps it shorter). Otherwise `skip "codegraph binary not found"`.
- `--remove-superpowers`: `remove_plugin superpowers@superpowers-marketplace`,
  `remove_marketplace superpowers-marketplace`.
- Order: dev-flow, then superpowers, then tools.
- After all removals, always print a "Not done by this script (see README > Uninstalling):"
  block of `note` lines: `claude-mem: npx claude-mem uninstall`,
  `legacy global CodeGraph MCP (pre-1.11.0): claude mcp remove codegraph`,
  `statusLine in ~/.claude/settings.json (if you used claude-powerline)`,
  `per-repo files: .claude/test-cmd, lint-cmd, rules, .codegraph/`.
- Add both flags to `usage()` and the header comment, with the spec §B descriptions.

**Verify:**
```bash
# the test-first commands now pass; plus:
: > $H/claude.log; FAKE_PLUGINS="dev-flow@dev-flow-marketplace" FAKE_MARKETPLACES="dev-flow-marketplace" $FAKE bash $R/uninstall.sh | grep -F 'npx claude-mem uninstall'   # match
grep -E 'uninstall|remove' $H/claude.log | grep -c 'powerline\|superpowers'   # 0 without flags
# real, isolated end to end (network; never without CLAUDE_CONFIG_DIR):
export CLAUDE_CONFIG_DIR=$(mktemp -d)
claude plugin marketplace add dgiotas/dev-flow </dev/null && claude plugin install -y dev-flow@dev-flow-marketplace </dev/null
bash $R/uninstall.sh; echo $?                                         # 0, two [ok]
claude plugin list </dev/null | grep -c dev-flow                      # 0
claude plugin marketplace list </dev/null | grep -c dev-flow          # 0
rm -rf "$CLAUDE_CONFIG_DIR"; unset CLAUDE_CONFIG_DIR
cd $R && bash .claude/test-cmd; echo $?                               # 0
```

**Depends on:** 5.

---

## Task 7: README header, Why, Prerequisites, Installation

**Files:** `README.md`

**Test first:** `bash $H/check.sh install` fails (MISSING lines).

**Change:** replace `README.md:1-15` and `:34-43` (quick-start, flags, manual install,
prerequisites). Leave `:17-32` (restart/onboard) in place for Task 8. New content, top down:
1. Header block:
   ```
   <div align="center">

   # dev-flow

   ### Spec-then-build for Claude Code: a strong model plans and reviews, a cheaper one codes

   Quality-gate hooks, a guard on your guidance files, bundled MCP servers and nine dev skills, in one plugin.<br>
   **Planned work. Enforced gates. Reviewed diffs.**

   </div>
   ```
2. `## Why dev-flow`: 5–8 lines of prose built from `README.md:3` and the plugin.json
   description. It must say: agents code fast but skip planning and checks; dev-flow
   makes Opus write a spec + test-first plan you approve, has Sonnet implement it task by
   task, and has Opus review the diff; hooks block unapproved edits to
   AGENTS.md/CLAUDE.md/rules and block "done" while `.claude/test-cmd` fails; built to sit
   alongside obra/superpowers. No new claims beyond what the README already states.
3. `## Getting Started`, then `### Prerequisites`: move `README.md:43` (keep the
   `--plugin-dir` sentence out; it goes in the details below). Add `curl` for the one-liner.
4. `### Installation`, in this order:
   - one-liner in a `bash` block:
     `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash`,
     then one sentence: installs Superpowers + dev-flow + CodeGraph non-interactively.
     Optional add-ons via `… | bash -s -- --with-memory` (show that full line). For the
     interactive checklist:
     `bash <(curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh)`.
   - **Specific version** subsection (bold lead-in, not a heading):
     `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | DEV_FLOW_VERSION=1.12.0 bash`.
     Say: installs git tag `dev-flow--v1.12.0` (from 1.12.0 on, list at
     https://github.com/dgiotas/dev-flow/tags). An unknown version fails with git's
     `Remote branch … not found`. Switching an existing install: see "Switching version"
     (Task 8).
   - **From a clone**: `git clone https://github.com/dgiotas/dev-flow.git && cd dev-flow && bash install.sh`
     plus `README.md:13` (checklist / `--dry-run` behaviour) verbatim.
   - **Manual** (in a session): `README.md:36-41` with `/path/to/dev-flow-marketplace`
     replaced by `dgiotas/dev-flow`; append one line "pin with `dgiotas/dev-flow#dev-flow--v1.12.0`".
   - `<details><summary>Installer flags</summary>`: `README.md:15` as a 2-column table
     `| Flag | Effect |` (one row per flag, from `usage()` / header in install.sh),
     plus a `DEV_FLOW_VERSION` row.
   - `<details><summary>What the installer does</summary>`: a numbered list of
     install.sh's sections 1–6 (`install.sh:182,370,386,403,417,441`), one line each.
   - `<details><summary>Try without installing</summary>`:
     `claude --plugin-dir ./plugins/dev-flow` from a clone.
   Use a blank line after each `<summary>` line and before `</details>`, or GitHub will
   not render the markdown inside.

**Verify:**
```bash
bash $H/check.sh install preserve    # PASS install preserve
cd $R && bash .claude/test-cmd; echo $?   # 0
```

**Depends on:** 4 (the README documents install.sh behaviour; text must match `--help`).

---

## Task 8: README Uninstalling, Switching version, First Steps

**Files:** `README.md`

**Test first:** `bash $H/check.sh uninstall` fails.

**Change:**
- Inside `### Installation`, after "Try without installing", add
  `<details><summary>Switching version / downgrading</summary>`: a marketplace can't be
  re-added from a different source or tag. Quote the refusal text ("its network source
  differs…"). So run `uninstall.sh`, then the installer with the wanted
  `DEV_FLOW_VERSION` (or none for latest main). Per-repo files are untouched.
- Then `<details><summary>Uninstalling</summary>`:
  - `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash`.
    Say it removes only the dev-flow plugin + marketplace (and the bundled MCP servers with
    them, per `README.md:284-285`).
  - `… | bash -s -- --remove-tools` (claude-powerline + CodeGraph binary),
    `--remove-superpowers`, `--dry-run`, each one line. From a clone: `bash uninstall.sh …`.
  - "Manual leftovers": move `README.md:276-329` here, cut down. Drop steps 2, 3 and 5's
    plugin/marketplace commands (the script does these). Keep step 1 (inspect), step 4
    (legacy CodeGraph MCP), step 5's statusLine/json cleanup, step 6 (claude-mem), the
    settings.json note, **Per-repo leftovers** block, git revert note, backup note, and
    the "Verified: …" paragraph verbatim.
  - Delete the old `## Uninstalling everything `install.sh` added` section.
- `### First Steps` (after Installation): move `README.md:17-32` (restart + verify,
  `/dev-flow:onboard`, the manual sequence, the guard-fires-by-design paragraph with its
  "not yet run end to end" caveat) verbatim.

**Verify:**
```bash
bash $H/check.sh install uninstall preserve   # PASS
cd $R && bash .claude/test-cmd; echo $?       # 0
```

**Depends on:** 6, 7.

---

## Task 9: README Ways of Working + the two command tables

**Files:** `README.md`

**Test first:** `bash $H/check.sh tables` fails.

**Change:** after `## Getting Started`, add three sections and delete `## What's inside`
(`README.md:101-126`) and `## Daily use` (`:236-244`), whose content they absorb.
- `## Ways of Working`: one sentence ("Three peer paths. The hooks (guard, per-edit
  checks, stop gate) apply on all of them.") and a `| Path | What it adds |` table:
  1. `Plain request`: skills fire from the request itself. Include the examples in
     `README.md:244`.
  2. `` `/dev-flow:spec` → reply `ok build` ``: plan, approve, build in the same
     conversation; orchestration stays on the session model.
  3. `` `/dev-flow:spec` → `/dev-flow:build <slug>` ``: same, but orchestration switches
     to Sonnet.
  Then the `text` example block from `README.md:238-242`.
- `## Workflows` (the **main commands** table), `| Command | Use it when | What it does |`:
  - `` `/dev-flow:spec <feature>` `` | you want an approved plan before any code |
    Opus `spec-architect` investigates, writes `docs/specs/<slug>.md` + `docs/plans/<slug>.md`
    with test-first tasks and open questions. No code.
  - `` `ok build` `` (reply after spec) | the plan is right; keep going in this conversation |
    runs the build procedure inline: orchestration on the current model, coding on Sonnet
    `implementer`, review on Opus `reviewer`.
  - `` `/dev-flow:build <slug>` `` | you want the build phase orchestrated by the cheaper model |
    Sonnet runs tasks via `implementer` on a branch, then `verify-done`, then Opus
    `reviewer`. Never merges or pushes (`commands/build.md` steps 2–7).
  - `` `/dev-flow:onboard` `` | first time in a repo | CodeGraph index, then guidance file
    + rules, then verified hook commands, pausing at every guarded write.
  Below the table, one line: model pinning per stage is documented in frontmatter but not
  verified live. See Model routing.
- `## Other Commands, Skills and Agents` (the **second** table), `| Name | Kind | Purpose |`:
  rows from `README.md:107-109,111-126` **minus** spec/build/onboard, with the Kind column
  moved second. Each cell starts with the backticked name, e.g.
  `` | `/dev-flow:init-hooks` | Command | … | ``, `` | `code-intel` | Skill | … | ``.
  Keep the MCP row. Keep each Purpose to one sentence.

**Verify:**
```bash
bash $H/check.sh tables install uninstall preserve   # PASS
cd $R && bash .claude/test-cmd; echo $?              # 0
```

**Depends on:** 8.

---

## Task 10: README Documentation, part 1 (gates, guidance files, containers, MCP)

**Files:** `README.md`

**Test first:** `bash $H/check.sh docs1` fails.

**Change:** add `## Documentation` after the second table, with one intro line. Move these
existing sections under it, **demoted one level** (`##`→`###`, `###`→`####`), in this
order, text unchanged except heading names:
1. `### Pre-write guard` ← `## Pre-write guard: guidance files are never changed silently` (`:141-155`)
2. `### AGENTS.md or CLAUDE.md` ← `:45-80` (its `###` subheading becomes `####`)
3. `### Stop gate` ← `## Stop gate: retries and giving up` (`:199-207`)
4. `### Per-repo config files` ← `## The three per-repo config files` (`:157-197`)
5. `### Containerised toolchains` ← `## Containerised toolchains (…)` (`:82-99`)
6. `### MCP servers` ← `## MCP servers: what needs installing` (`:128-139`). Change
   "see *Prerequisites* above" so it still points at Getting Started > Prerequisites.

**Verify:**
```bash
bash $H/check.sh docs1 tables install uninstall preserve   # PASS
cd $R && bash .claude/test-cmd; echo $?                    # 0
```

**Depends on:** 9.

---

## Task 11: README Documentation, part 2 + Changelog + Contributing

**Files:** `README.md`

**Test first:** `bash $H/check.sh all` fails (docs2, outline, stale).

**Change:** continue `## Documentation` with, in order (demoted as in Task 10):
7. `### Model routing` ← `:260-268`, followed by the `ok build` comparison
   (`:246-258`) as `#### \`ok build\` vs \`/dev-flow:build\``. Keep the "haven't verified
   that live" sentence verbatim.
8. `### Memory (optional)` ← `:209-214`. Change "`bash install.sh --with-memory`" to also
   show `… | bash -s -- --with-memory`.
9. `### Status line (optional)` ← `:216-234`.
10. `### Updating` (new, replaces `:270-272`): `claude plugin marketplace update
    dev-flow-marketplace`, `claude plugin update dev-flow@dev-flow-marketplace`,
    `/reload-plugins` (from `:343-347`). Third-party marketplaces don't auto-update by
    default (from `:342`). A pinned install stays on its tag. To change version or
    source, run `uninstall.sh`, then reinstall (link the Switching version details).
11. `### Troubleshooting` ← `:331-356`. Add one entry: **"Failed to add marketplace …
    network source differs"**: already registered from a clone path or another version;
    run `uninstall.sh` then reinstall.
12. `### Known limits` ← `:358-370`.

Then:
- `## Changelog`: "Releases are git tags named `dev-flow--v<version>`:
  https://github.com/dgiotas/dev-flow/tags. Per-change detail is in the commit history
  and `docs/specs/`."
- `## Contributing`: from `AGENTS.md` "Commands" + the release line. Try locally with
  `claude --plugin-dir ./plugins/dev-flow`, validate with `bash .claude/test-cmd`,
  release = bump `version` in `plugins/dev-flow/.claude-plugin/plugin.json`, merge to
  main, then `claude plugin tag plugins/dev-flow --push` (creates and pushes
  `dev-flow--v<version>`, validating the manifest). Issues/PRs:
  https://github.com/dgiotas/dev-flow/issues.
- Delete every old top-level section now fully moved. After this task the only `##`
  headings are the eight in the `outline` group.

**Verify:**
```bash
bash $H/check.sh all                       # PASS all
cd $R && bash .claude/test-cmd; echo $?    # 0
grep -c '<details>' $R/README.md; grep -c '</details>' $R/README.md   # equal, >=5
```

**Depends on:** 10.

---

## Task 12: AGENTS.md layout and release line (guarded file)

**Files:** `AGENTS.md` (never `CLAUDE.md`, which is a symlink; the guard refuses it)

**Test first:**
```bash
grep -c 'uninstall.sh' $R/AGENTS.md            # today 0; want >=1
grep -c 'claude plugin tag' $R/AGENTS.md       # today 0; want >=1
```

**Change:** `pre-write-guard` will block the edit and show a diff. Relay it to the user
verbatim and wait for approval (see `AGENTS.md` Conventions). Keep edits minimal:
- Layout: after the `install.sh` bullet add
  `` - `uninstall.sh` — removes dev-flow (opt-in `--remove-tools` / `--remove-superpowers`); `curl | bash`-safe like `install.sh`. ``
  and append to the `install.sh` bullet: `defaults to the dgiotas/dev-flow GitHub source when piped (curl | bash); DEV_FLOW_VERSION pins a dev-flow--v<ver> tag.`
- Commands table "Release a change" row: after "bump `version` … push", insert
  "then `claude plugin tag plugins/dev-flow --push` on main".

**Verify:**
```bash
grep -c 'uninstall.sh' $R/AGENTS.md; grep -c 'claude plugin tag' $R/AGENTS.md   # >=1 each
cd $R && bash .claude/test-cmd; echo $?                                          # 0
```

**Depends on:** 6.

---

## Task 13: Version bump, full acceptance run, release hand-off

**Files:** `plugins/dev-flow/.claude-plugin/plugin.json`

**Test first:**
```bash
cd $R && claude plugin tag plugins/dev-flow --dry-run 2>&1 | grep -F 'dev-flow--v1.12.0'   # today shows v1.11.0: fails
```

**Change:** `"version": "1.11.0"` → `"version": "1.12.0"`. Nothing else.

**Verify:**
```bash
cd $R && bash .claude/test-cmd; echo $?                                             # 0
claude plugin validate $R                                                           # ✔ Validation passed
claude plugin tag plugins/dev-flow --dry-run 2>&1 | grep -F 'dev-flow--v1.12.0'     # match (dry run only; do NOT create)
bash $H/check.sh all                                                                # PASS all
# real, isolated, unpinned one-liner simulation from the local file (installs current GitHub main):
export CLAUDE_CONFIG_DIR=$(mktemp -d)
cd /tmp && cat $R/install.sh | bash -s -- --skip-superpowers --skip-codegraph -y 2>&1 | tail -3   # "0 failures"
claude plugin list </dev/null | grep -F 'dev-flow@dev-flow-marketplace'                             # present
bash $R/uninstall.sh; echo $?                                                                        # 0
rm -rf "$CLAUDE_CONFIG_DIR"; unset CLAUDE_CONFIG_DIR
```
Then stop and hand these **user-run** release steps to the user (do not run them):
1. Merge the branch to `main` and push.
2. On `main`: `claude plugin tag plugins/dev-flow --push`.
3. Post-release check (isolated):
   `CLAUDE_CONFIG_DIR=$(mktemp -d) bash -c 'curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | DEV_FLOW_VERSION=1.12.0 bash -s -- --skip-superpowers --skip-codegraph -y && claude plugin marketplace list </dev/null'`
   ⇒ `Source: GitHub (dgiotas/dev-flow@dev-flow--v1.12.0)`, and `claude plugin list`
   shows `Version: 1.12.0`.

**Depends on:** 11, 12.

---

## Acceptance criteria (for `verify-done`)

- [ ] `bash .claude/test-cmd` exits 0.
- [ ] `claude plugin validate /Users/dgiotas/Projects/personal/dev-flow` passes.
- [ ] `bash /tmp/devflow-readme/check.sh all` prints `PASS` (outline order, both tables,
      install/uninstall/version text, preserved caveats ≥5, no stale strings).
- [ ] `cat install.sh | <fake PATH> bash -s -- --dry-run -y` plans `<- dgiotas/dev-flow`;
      from the clone it plans `<- <repo path>` (unchanged).
- [ ] `DEV_FLOW_VERSION=1.12.0` plans `<- dgiotas/dev-flow#dev-flow--v1.12.0`; `1.12` and
      local-path+version exit 2.
- [ ] `head -n 300 install.sh | bash` and `head -n 40 uninstall.sh | bash` run nothing.
- [ ] Source-conflict failure prints the `uninstall.sh` hint only when the marketplace was
      already registered.
- [ ] `uninstall.sh` default removes only dev-flow (plugin, then marketplace), skips absent
      items with exit 0, exits 1 on failure, 2 on unknown flag; `--dry-run` runs nothing;
      `--remove-tools` / `--remove-superpowers` add exactly their items.
- [ ] Isolated real run (`CLAUDE_CONFIG_DIR` temp dir): install via piped `install.sh` then
      `uninstall.sh` leaves `claude plugin list` / `marketplace list` without dev-flow.
- [ ] `plugin.json` version is `1.12.0`; `claude plugin tag plugins/dev-flow --dry-run`
      names `dev-flow--v1.12.0`.
- [ ] `AGENTS.md` mentions `uninstall.sh` and `claude plugin tag` (edited via the guard,
      user-approved); `CLAUDE.md` untouched.
- [ ] No push, tag or merge performed by the build; the release steps are handed to the user.
