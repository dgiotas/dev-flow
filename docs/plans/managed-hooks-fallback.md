# Plan: managed-hooks fallback ("hookless mode")

Spec: `docs/specs/managed-hooks-fallback.md`

This repo has no unit-test framework. Here "test first" means running the
given assertion, seeing it **fail** (a non-zero exit or `FAIL`), making the
change, and then seeing it pass. The repo-wide checks are `bash .claude/test-cmd`
(jq JSON validation plus `bash -n`) and `bash .claude/lint-cmd <path>`.

**Posture:** do not commit, push, merge, tag or run `claude plugin update`
unless the user asks. Never add AI-attribution trailers to commits or PR text
in this repo. Do not edit `CLAUDE.md`. It is a symlink to `AGENTS.md`.

**Confirmed decisions** (spec, "Decisions"): the guard-substitute permission
rules go in the repo's shared, committed `.claude/settings.json`; no git
pre-commit hook; the "Quality gates" guidance section is added in hookless
mode only; the version is `1.13.0`. These are settled. Implement them as
written. If something in a task seems to conflict with them, stop and ask.
Do not improvise.

Helper used by the markdown tasks (run from the repo root):

```bash
has() { grep -qF -- "$2" "$1" && echo "PASS: $1 has '$2'" || { echo "FAIL: $1 lacks '$2'"; return 1; }; }
lacks() { grep -qF -- "$2" "$1" && { echo "FAIL: $1 still has '$2'"; return 1; } || echo "PASS: $1 lacks '$2'"; }
```

---

## Task 1: Add the detector `scripts/hooks-policy.sh`

**Files:** create `plugins/dev-flow/scripts/hooks-policy.sh`

**Depends on:** none

**Test first:** save as `$TMPDIR/hp-test.sh` (scratch, not committed) and run
`bash $TMPDIR/hp-test.sh`. It fails now because the script does not exist.

```bash
set -u
S="$PWD/plugins/dev-flow/scripts/hooks-policy.sh"
T=$(mktemp -d); mkdir -p "$T/m/managed-settings.d"
run() { DEV_FLOW_MANAGED_DIR="$T/m" DEV_FLOW_MANAGED_PLIST="$T/${1:-none}.plist" bash "$S"; }
ok() { if run "${2:-}" | grep -qx "$1"; then echo "PASS $1"; else echo "FAIL $1"; run "${2:-}"; exit 1; fi; }
ok 'hooks=not-found'
ok 'permission_rules=not-found'
echo '{"allowManagedHooksOnly":true}' > "$T/m/managed-settings.json"
ok 'hooks=managed-only'
ok "hooks_source=$T/m/managed-settings.json"
echo '{"disableAllHooks":true}' > "$T/m/managed-settings.d/10-a.json"
ok 'hooks=disabled'
echo '{"allowManagedPermissionRulesOnly":true}' > "$T/m/managed-settings.d/20-b.json"
ok 'permission_rules=managed-only'
echo 'not json' > "$T/m/managed-settings.d/30-bad.json"
ok 'hooks=disabled'
rm -f "$T/m/managed-settings.json" "$T/m/managed-settings.d/"*
if command -v plutil >/dev/null; then
  echo '{"allowManagedHooksOnly":true}' > "$T/p.json"
  plutil -convert xml1 -o "$T/p.plist" "$T/p.json"
  ok 'hooks=managed-only' p
fi
echo ALL-PASS
```

**Change:** create the script. Use `guidance-target.sh` for style (header
comment, `set -u`, `key=value` output, `summary=` last).
- Header comment: what it reports and why. It explains a dead guard probe by
  reading the on-disk Claude Code managed settings. Server-managed (claude.ai)
  policy is not visible to it. The two env vars exist only as test seams.
- `command -v jq` missing → print `error=jq-missing`, `exit 1`.
- `case "$(uname -s)" in Darwin) def="/Library/Application Support/ClaudeCode";; *) def="/etc/claude-code";; esac`
- `dir="${DEV_FLOW_MANAGED_DIR:-$def}"`,
  `plist="${DEV_FLOW_MANAGED_PLIST:-/Library/Managed Preferences/com.anthropic.claudecode.plist}"`
- State: `hooks=not-found hooks_source="" perms=not-found perms_source=""`.
- `check() { src="$1"; json="$2"; ... }`. Take the JSON as an argument, not
  stdin, so the state variables survive (no subshell). Logic:
  - if `jq -e '.disableAllHooks == true'` succeeds on the JSON, set
    `hooks=disabled; hooks_source=$src` (this always overrides);
  - else if `hooks = not-found` and `jq -e '.allowManagedHooksOnly == true'`
    succeeds, set `hooks=managed-only; hooks_source=$src`;
  - if `perms = not-found` and `jq -e '.allowManagedPermissionRulesOnly == true'`
    succeeds, set `perms=managed-only; perms_source=$src`.
  - Send jq's stderr to `/dev/null`. Invalid JSON just fails the test.
- Loop `for f in "$dir/managed-settings.json" "$dir"/managed-settings.d/*.json`
  and call `check "$f" "$(cat "$f")"` only when `[ -r "$f" ]`.
- If `[ -r "$plist" ]` and `command -v plutil`, run
  `j=$(plutil -convert json -o - "$plist" 2>/dev/null)`, then `check "$plist" "$j"` if non-empty.
- Print `hooks=`, `hooks_source=` (only if not `not-found`),
  `permission_rules=`, `permission_rules_source=` (only if managed-only), then
  one `summary=` line:
  - disabled: `Managed settings set disableAllHooks: no hooks run, including dev-flow's. Continue in hookless mode.`
  - managed-only: `Managed settings set allowManagedHooksOnly: plugin hooks are blocked unless an admin force-enables dev-flow@dev-flow-marketplace in managed enabledPlugins. Continue in hookless mode.`
  - not-found: `No hook restriction in on-disk managed settings. A server-managed (claude.ai) policy is not visible here: check /status -> Setting sources.`
  - When perms is managed-only, append: ` Project/local permission rules are ignored (allowManagedPermissionRulesOnly), so the guard substitute is instruction-only.`
- End with `exit 0`. Aim for about 50 lines.

**Verify:**
```bash
bash $TMPDIR/hp-test.sh            # expect ALL-PASS
bash .claude/lint-cmd plugins/dev-flow/scripts/hooks-policy.sh; echo "lint=$?"   # expect lint=0
bash .claude/test-cmd; echo "test=$?"                                            # expect test=0
bash plugins/dev-flow/scripts/hooks-policy.sh                                    # on this machine: hooks=not-found, exit 0
```

---

## Task 2: init-hooks step 0, diagnose a dead probe instead of stopping

**Files:** `plugins/dev-flow/commands/init-hooks.md` (step 0 only, lines 10-43)

**Depends on:** 1

**Test first:**
```bash
f=plugins/dev-flow/commands/init-hooks.md
has $f 'scripts/hooks-policy.sh' && has $f 'hookless mode' && has $f 'f=.claude/settings.json' \
 && has $f 'Edit(.claude/rules/**)' && has $f 'Edit(/CLAUDE.md)' && has $f 'enabledPlugins' \
 && lacks $f 'settings.local.json'
# expect FAIL on the first check
```

**Change:** edit only step 0.
- In 0.2, change "Delete … **whether or not it blocked**" to: delete it
  afterwards whether or not it blocked. If the guard blocked the delete too,
  leave it and give the user `rm .claude/rules/devflow-guard-probe.md`.
- Replace 0.3 ("If the `Edit` was not blocked, stop and report") with a new
  **"3. If the `Edit` was not blocked, find out why"** that contains, in order:
  1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/hooks-policy.sh"` and show its output.
  2. `hooks=disabled` or `hooks=managed-only`: the organization's managed
     settings block dev-flow's hooks. Say so, quoting `summary` and
     `hooks_source`. Tell the user the real fix is an admin force-enabling
     `dev-flow@dev-flow-marketplace` with `[true]` in managed `enabledPlugins`,
     because hooks of force-enabled plugins are exempt. Then continue in
     **hookless mode** (defined below). Do not tell them to update the plugin.
  3. `hooks=not-found`: ask the user one question with two answers. (a) A
     stale copy: give the existing update block (keep the current
     `claude plugin marketplace update …` / `claude plugin update …` /
     `/reload-plugins` lines and the note about non-auto-updating
     marketplaces), then stop. (b) The org policy comes from a source the
     script cannot read: `/status` → "Setting sources" shows
     `Enterprise managed settings (remote)` or similar. Continue in hookless
     mode.
  4. Never try to re-enable hooks by editing any settings file.
- Add a sub-heading **"Hookless mode"** at the end of step 0:
  - Meaning: no pre-write guard, no per-edit check, no stop gate. The
    remaining steps still write and verify `.claude/test-cmd` and
    `.claude/lint-cmd`, which the `implementer` agent and `verify-done` skill
    run explicitly.
  - Guard substitute: if `permission_rules=managed-only`, say the guard is
    instruction-only on this machine and write nothing. Otherwise run
    `guidance-target.sh`. Show the user these rules and get an explicit yes
    first:
    `permissions.ask`: `Edit(AGENTS.md)`, `Edit(CLAUDE.md)`, `Edit(.claude/rules/**)`,
    plus `permissions.deny`: `Edit(/CLAUDE.md)` only when `never_edit=CLAUDE.md`.
    Then merge them into the repo's shared `.claude/settings.json` with this
    exact snippet. It creates the file from `{}` only if it is absent (no
    dev-flow step writes this file today, so in many target repos it will be
    new; this dev-flow repo has none either). If the file exists, it keeps
    every existing key (`permissions.allow`, `env`, `enabledPlugins`, …),
    appends to `ask`/`deny`, and dedupes:
    ```bash
    f=.claude/settings.json; mkdir -p .claude; [ -f "$f" ] || echo '{}' > "$f"
    jq --argjson ask '["Edit(AGENTS.md)","Edit(CLAUDE.md)","Edit(.claude/rules/**)"]' \
      '.permissions.ask = (((.permissions.ask // []) + $ask) | unique)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    # only when never_edit=CLAUDE.md:
    jq '.permissions.deny = (((.permissions.deny // []) + ["Edit(/CLAUDE.md)"]) | unique)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    ```
  - Two or three sentences on why: `ask` rules raise Claude Code's own
    permission prompt (showing the change) for every Write/Edit to those
    files, and apply without workspace trust. They go in the shared,
    committed settings file on purpose, as an always-on backstop for everyone
    in the repo; anyone whose dev-flow hooks do run will get the guard's block
    and this prompt for the same edit, and that redundancy is accepted. They
    do not cover Bash writes, and they only load in sessions started at the
    repo root (project settings have no parent-directory fallback).
  - Tell the user that committing this file changes permission behaviour for
    everyone who pulls the repo, so they should review the diff before
    committing. Do not commit it.

**Verify:**
```bash
f=plugins/dev-flow/commands/init-hooks.md
has $f 'scripts/hooks-policy.sh' && has $f 'hookless mode' && has $f 'f=.claude/settings.json' \
 && has $f 'Edit(.claude/rules/**)' && has $f 'Edit(/CLAUDE.md)' && has $f 'enabledPlugins' \
 && lacks $f 'settings.local.json' \
 && has $f 'claude plugin marketplace update dev-flow-marketplace'
# expect all PASS
# the snippet must work: run it in a scratch dir, twice (idempotent), against an existing file with other keys
d=$(mktemp -d) && cd "$d" && mkdir .claude && echo '{"env":{"X":"1"},"permissions":{"allow":["Bash(ls)"]}}' > .claude/settings.json \
 && for i in 1 2; do f=.claude/settings.json; jq --argjson ask '["Edit(AGENTS.md)","Edit(CLAUDE.md)","Edit(.claude/rules/**)"]' '.permissions.ask = (((.permissions.ask // []) + $ask) | unique)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done \
 && jq -e '(.permissions.ask|length)==3 and .permissions.allow==["Bash(ls)"] and .env.X=="1"' .claude/settings.json; cd - >/dev/null
# expect: true
# and when the file is absent (created from {}):
d=$(mktemp -d) && cd "$d" && f=.claude/settings.json; mkdir -p .claude; [ -f "$f" ] || echo '{}' > "$f"; \
 jq --argjson ask '["Edit(AGENTS.md)","Edit(CLAUDE.md)","Edit(.claude/rules/**)"]' '.permissions.ask = (((.permissions.ask // []) + $ask) | unique)' "$f" > "$f.tmp" && mv "$f.tmp" "$f" \
 && jq -e '(.permissions.ask|length)==3' "$f"; cd - >/dev/null
# expect: true
```

---

## Task 3: init-hooks steps 4, 5 and 7 in hookless mode

**Files:** `plugins/dev-flow/commands/init-hooks.md` (steps 4, 5, 7 only)

**Depends on:** 2

**Test first:**
```bash
f=plugins/dev-flow/commands/init-hooks.md
has $f 'In hookless mode, always write' && has $f 'In hookless mode, skip this step' \
 && has $f 'review the `.claude/settings.json` diff before committing'
# expect FAIL
```

**Change:**
- Step 4: add a final paragraph: "In hookless mode, always write
  `.claude/lint-cmd` when the repo has any per-file check (host or container):
  the built-in native checks only run inside the hook, so without it nothing
  checks individual files." Keep the existing host/container rules for what
  goes inside it.
- Step 5: add "In hookless mode, skip this step: there is no stop gate to
  retry. Say so in the report."
- Step 7: add a first bullet: "Hookless mode, if it applied: the reason (the
  `hooks-policy.sh` summary or the user's answer), the permission rules
  added to the shared `.claude/settings.json` (or why none were), that the
  three gates are now enforced only by instructions, and the admin fix
  (managed `enabledPlugins` force-enable)." Change the gitignore bullet so
  that in hookless mode it is replaced by: "The rules were added to the
  shared, committed `.claude/settings.json`: review the `.claude/settings.json`
  diff before committing it, because it changes permission behaviour for
  anyone who pulls the repo." The hook state files are never created then, so
  the hook-state gitignore reminder is dropped.

**Verify:** rerun the test-first line and expect all PASS. Also run
`lacks plugins/dev-flow/commands/init-hooks.md 'stop and report. The guard is not live'`
and `lacks plugins/dev-flow/commands/init-hooks.md 'settings.local.json'`,
and expect PASS for both (the old hard stop is gone after task 2).

---

## Task 4: onboard, continue in hookless mode

**Files:** `plugins/dev-flow/commands/onboard.md`

**Depends on:** 2, 3

**Test first:**
```bash
f=plugins/dev-flow/commands/onboard.md
has $f 'hookless mode' && has $f '.claude/settings.json' && has $f 'Quality gates' \
 && lacks $f 'If the probe is not blocked, stop and give' && lacks $f 'settings.local.json'
# expect FAIL
```

**Change:**
- "How this runs" (lines 10-14): add one sentence. On a machine where the
  organization's managed settings block plugin hooks, there is no guard and
  this command runs in hookless mode (see step 0).
- "Who owns what" table: change the first row's artifact to
  "guard liveness proof and hookless-mode diagnosis". Add a row:
  shared `.claude/settings.json` permission rules (hookless mode only), owner
  "`/dev-flow:init-hooks` step 0, performed in step 0 here", others "—".
- Step 0: replace "If the probe is not blocked, stop and give that command's
  remediation instead of continuing." with "If the probe is not blocked,
  follow that step's diagnosis. Stop only where it says stop; otherwise
  continue in hookless mode. Defer its permission-rules confirmation to step
  0.5." Narrow the deletion exception so it applies only when the probe
  **was** blocked. If it was not blocked, delete the probe yourself, since
  nothing guards it.
- Step 0.5: add "In hookless mode, the announcement also states the reason,
  the exact permission rules proposed for the shared, committed
  `.claude/settings.json` (or that permission rules are managed-only), that
  these apply to everyone who pulls the repo once committed, and that step 2
  will add a
  'Quality gates' section to the guidance file. Write the rules right after
  the go-ahead, before step 1." This keeps it the only up-front confirmation.
- Step 2: add "In hookless mode, tell the skill so, so that it adds its
  Quality gates section."
- "If a step is blocked by the pre-write-guard": add a paragraph, "In
  hookless mode there is no guard to block you. Before any change to an
  existing `AGENTS.md`/`CLAUDE.md`/`.claude/rules/*.md`, show the complete
  change in chat and wait for an explicit yes that turn, then make the call
  in one piece. Claude Code's permission prompt (from the `ask` rules) follows
  unless permission rules are managed-only." The same never-route-around
  rules apply.
- Report: add "State hookless mode and its reason if it applied." The
  gitignore reminder follows init-hooks step 7: in hookless mode it is
  replaced by "review the `.claude/settings.json` diff before committing it".

**Verify:** rerun the test-first block and expect all PASS. Also:
`has plugins/dev-flow/commands/onboard.md 'rm .claude/rules/devflow-guard-probe.md'`
must PASS (the blocked-case hand-off is kept).

---

## Task 5: setup-rules Quality gates section in hookless mode

**Files:** `plugins/dev-flow/skills/setup-rules/SKILL.md` (body only; frontmatter unchanged)

**Depends on:** 1

**Test first:**
```bash
f=plugins/dev-flow/skills/setup-rules/SKILL.md
has $f 'Quality gates' && has $f 'hooks-policy.sh' && has $f 'bash .claude/lint-cmd <repo-relative-path>'
# expect FAIL
```

**Change:**
- Add a section "## When hooks are disabled by policy (hookless mode)" after
  "Containerised toolchains". Hookless mode applies when the caller says so,
  or when `bash "${CLAUDE_PLUGIN_ROOT}/scripts/hooks-policy.sh"` reports
  `hooks=disabled` or `hooks=managed-only`. In that case, procedure step 3
  also adds this section to `<guidance file>` (through the normal
  diff-and-approve flow), worded so it is also correct where hooks do run:
  ```markdown
  ## Quality gates
  dev-flow's hooks enforce these where hooks are allowed; where an organization's policy blocks plugin hooks, this instruction is the only enforcement:
  - After editing a file, run `bash .claude/lint-cmd <repo-relative-path>` (if `.claude/lint-cmd` exists) and fix failures before moving on.
  - Before saying work is done, `bash .claude/test-cmd` must exit 0.
  - Before changing `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md`, show the complete change and wait for an explicit yes.
  ```
  Also say that in hookless mode `.claude/lint-cmd` is worth writing even
  on a host toolchain, because the native per-edit checks live only in the hook.
- In "Changing existing guidance or rule files", after "A `pre-write-guard`
  hook enforces this mechanically", add: "When hooks are disabled by policy
  there is no such hook. The instruction above, and any `ask` permission rules
  `/dev-flow:init-hooks` set up, are then the only gate, so showing the full
  change first is on you."
- Do not touch the `description` frontmatter (see `.claude/rules/skills.md`).

**Verify:** rerun the test-first block and expect all PASS. Also
`f=plugins/dev-flow/skills/setup-rules/SKILL.md; diff <(head -4 $f) <(git show HEAD:$f | head -4) && echo PASS-frontmatter-unchanged`.

---

## Task 6: implementer and verify-done run lint-cmd and test-cmd explicitly

**Files:** `plugins/dev-flow/agents/implementer.md`, `plugins/dev-flow/skills/verify-done/SKILL.md` (bodies only)

**Depends on:** none

**Test first:**
```bash
has plugins/dev-flow/agents/implementer.md 'bash .claude/lint-cmd' \
 && has plugins/dev-flow/agents/implementer.md 'bash .claude/test-cmd' \
 && has plugins/dev-flow/skills/verify-done/SKILL.md 'bash .claude/lint-cmd'
# expect FAIL
```

**Change:**
- `implementer.md` procedure step 4: append "If `.claude/lint-cmd` exists, run
  `bash .claude/lint-cmd <repo-relative-path>` for each file you changed. If
  `.claude/test-cmd` exists, run `bash .claude/test-cmd`. Both must exit 0
  before you report. Do not rely on hooks to run them; they may be disabled
  by policy."
- `verify-done/SKILL.md` checklist step 3: add "If `.claude/lint-cmd` exists,
  run `bash .claude/lint-cmd <repo-relative-path>` for each touched file." at
  the start of that step.
- Leave the frontmatter of both files unchanged.

**Verify:** rerun the test-first block and expect all PASS.
`bash .claude/test-cmd; echo $?` → `0`.

---

## Task 7: README, the new "Managed settings" section

**Files:** `README.md` (Documentation section only; insert after "### Stop gate", before "### Per-repo config files")

**Depends on:** 1-6

**Test first:**
```bash
has README.md '### Managed settings: hooks disabled by your organization' && has README.md 'allowManagedHooksOnly' \
 && has README.md '"dev-flow@dev-flow-marketplace": [true]' && has README.md 'hooks-policy.sh'
# expect FAIL
```

**Change:** add the subsection (target 30-45 lines) containing:
1. What happens: with `allowManagedHooksOnly: true` in managed settings,
   plugin hooks are blocked, so none of the three dev-flow hooks run.
   (Also true for `disableAllHooks` in managed settings.) Side effects: the
   claude-powerline status line doesn't show (`statusLine` is narrowed to
   managed settings), and claude-mem (hook-based) doesn't record. MCP servers,
   skills, agents and commands are unaffected. Link
   https://code.claude.com/docs/en/hooks.
2. The real fix, for the admin: force-enable the plugin in managed settings,
   because hooks of force-enabled plugins are exempt:
   ```json
   { "enabledPlugins": { "dev-flow@dev-flow-marketplace": [true] } }
   ```
   If the org uses `strictKnownMarketplaces`, the dev-flow marketplace must be
   listed there too. Link the settings reference. Mark this: "per the Claude
   Code docs; not verified in a managed session".
3. Otherwise, hookless mode: `/dev-flow:onboard` and `/dev-flow:init-hooks`
   detect the dead guard probe, run `scripts/hooks-policy.sh` (which reads
   `managed-settings.json`, `managed-settings.d/` and the macOS managed-prefs
   plist; not server-managed policy, so check `/status` → Setting sources) and
   continue. Then a table:

   | Hook | Hookless substitute | Strength |
   |---|---|---|
   | pre-write guard | `ask` rules in the shared, committed `.claude/settings.json` for `Edit(AGENTS.md)`, `Edit(CLAUDE.md)`, `Edit(.claude/rules/**)` (+ `deny Edit(/CLAUDE.md)` when it's a pointer), plus a guidance instruction | Claude Code permission prompt on every Write/Edit, for everyone in the repo (people whose hooks run get this on top of the guard); not Bash writes; ignored under `allowManagedPermissionRulesOnly` |
   | per-edit check | `.claude/lint-cmd`, always written in hookless mode, run by `implementer`, `verify-done` and the guidance "Quality gates" section | instruction-level |
   | stop gate | `.claude/test-cmd`, run by `implementer`, `verify-done`, `reviewer` and the guidance section | instruction-level; nothing blocks the end of a plain turn |
4. One-line honesty note: hookless mode is weaker. The model can skip an
   instruction, and only the admin fix restores the mechanical gates.
5. One sentence: the `ask` rules are committed to the repo on purpose as a
   shared backstop, so review that diff before committing; contributors
   whose hooks run will see a permission prompt in addition to the guard.

**Verify:** rerun the test-first block and expect all PASS.
`lacks README.md 'settings.local.json'` must PASS (README has no such
mention today; this keeps it that way). Also
`grep -c '^### ' README.md` is exactly one more than before (`git show HEAD:README.md | grep -c '^### '`).

---

## Task 8: README cross-references

**Files:** `README.md` (lines ~14, ~204, Troubleshooting guard entry ~468, Known limits ~486)

**Depends on:** 7

**Test first:**
```bash
[ "$(grep -c 'Managed settings: hooks disabled by your organization' README.md)" -ge 4 ] && echo PASS || echo FAIL
# expect FAIL (the section heading from task 7 gives 1)
```

**Change:** add a short link to the new section (anchor
`#managed-settings-hooks-disabled-by-your-organization`, link text
containing the heading) in:
- the "Why dev-flow" paragraph (after "…blocks "done" while `.claude/test-cmd` fails."): one clause saying that where an org's managed settings block plugin hooks, dev-flow falls back to explicit checks;
- "Ways of Working" line "The hooks … apply on all of them": append "unless your organization's managed settings block plugin hooks — see …";
- Troubleshooting "The pre-write guard never fires …": add a final sentence. If `/status` shows `Enterprise managed settings` and updating doesn't help, the cause is policy, so see ….;
- Known limits: one bullet saying hookless mode is instruction-level, with the link.

**Verify:** rerun the test-first line and expect PASS.

---

## Task 9: AGENTS.md layout bullet (guarded file)

**Files:** `AGENTS.md` only. **Never** `CLAUDE.md`, which is a symlink.

**Depends on:** 1

**Test first:** `has AGENTS.md 'scripts/hooks-policy.sh'`. Expect FAIL.

**Change:** after the `guidance-target.sh` bullet (line 25), add one bullet:
"`plugins/dev-flow/scripts/hooks-policy.sh` — reports whether on-disk managed
settings block hooks (`allowManagedHooksOnly`/`disableAllHooks`) or
project permission rules; used by `init-hooks`/`onboard` step 0 to enter
hookless mode after a dead guard probe." If the pre-write guard blocks the
edit, show the user the change verbatim, wait for an explicit yes, run the
exact marker command it gives, and retry unchanged. Do not route around it.

**Verify:** `has AGENTS.md 'scripts/hooks-policy.sh'` gives PASS.
`git diff --stat AGENTS.md CLAUDE.md` shows only `AGENTS.md`, with 1 insertion.

---

## Task 10: Release bump

**Files:** `plugins/dev-flow/.claude-plugin/plugin.json`

**Depends on:** 1-9

**Test first:** `jq -e '.version == "1.13.0"' plugins/dev-flow/.claude-plugin/plugin.json`
prints `false` and exits 1.

**Change:** set `"version": "1.13.0"`. Nothing else. Do not tag or push. The
release step (`claude plugin tag plugins/dev-flow --push` on `main`) is the
user's.

**Verify:** the test-first command prints `true`, and `bash .claude/test-cmd; echo $?`
prints `0`.

---

## Acceptance criteria (for `verify-done`)

- [ ] `bash .claude/test-cmd` exits 0.
- [ ] The task 1 scratch test prints `ALL-PASS`. `bash plugins/dev-flow/scripts/hooks-policy.sh` exits 0 and prints `hooks=`, `permission_rules=` and `summary=` lines.
- [ ] Every `has`/`lacks` check in tasks 2-9 passes.
- [ ] `onboard.md` no longer contains a hard stop on an unblocked probe. It stops only via init-hooks' "stale copy" branch.
- [ ] `init-hooks.md` still contains the stale-copy update block (`claude plugin marketplace update dev-flow-marketplace`).
- [ ] The frontmatter of `setup-rules`, `verify-done`, `implementer` and `onboard` is unchanged (`git diff` shows no `---` block edits).
- [ ] `hooks/hooks.json` and `hooks/scripts/*.sh` are unchanged: `git diff --quiet HEAD -- plugins/dev-flow/hooks && echo PASS`.
- [ ] `CLAUDE.md` is unchanged and still a symlink: `[ -L CLAUDE.md ] && git diff --quiet HEAD -- CLAUDE.md && echo PASS`.
- [ ] `plugin.json` version is `1.13.0`.
- [ ] No changed file names `settings.local.json` as the rules destination: `! grep -n 'settings.local.json' plugins/dev-flow/commands/init-hooks.md plugins/dev-flow/commands/onboard.md plugins/dev-flow/skills/setup-rules/SKILL.md README.md && echo PASS`.
- [ ] Task 2's jq snippet keeps existing keys and is idempotent against an existing `.claude/settings.json`, and creates the file from `{}` when absent (both scratch checks print `true`).
- [ ] This repo has no `.claude/settings.json` after the build (no task writes one here): `[ ! -e .claude/settings.json ] && echo PASS`.
- [ ] Not verifiable here, so report it as not verified: a live run of `/dev-flow:onboard` on the managed laptop. Expected result: step 0 reports hookless mode (or asks, if `/status` shows a remote source), the repo's shared `.claude/settings.json` gains the three `ask` rules after approval (existing keys kept, nothing committed), the report tells the user to review that diff before committing, `.claude/test-cmd`/`.claude/lint-cmd` are written and verified, and an `Edit` to an existing `AGENTS.md` raises Claude Code's permission prompt.
