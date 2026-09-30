# Spec: managed-hooks fallback ("hookless mode")

## Problem

On a laptop where Claude Code is managed by an organization with
`allowManagedHooksOnly: true`, dev-flow installs fine, but none of its three
hooks run (the pre-write guard, the per-edit check, the stop gate).
`/dev-flow:onboard` then stops at step 0 because the guard probe is not
blocked, and tells the user to update the plugin. Updating cannot help, because
the cause is policy, not a stale copy. The user asked whether dev-flow can run
without hooks.

## Goal

- `/dev-flow:onboard` and `/dev-flow:init-hooks` recognise "hooks are disabled
  by policy", say so, and **continue** instead of stopping. They still write
  and verify `.claude/test-cmd` / `.claude/lint-cmd`, which are plain scripts
  that work without hooks.
- Each of the three gates gets a non-hook substitute that is as strong as
  Claude Code allows without hooks:
  - stop gate and per-edit check: run explicitly by the `implementer` agent,
    the `verify-done` skill, and (in hookless mode) an instruction in the
    repo's guidance file;
  - pre-write guard: permission `ask` rules for the guarded files (and a
    `deny` rule for a pointer `CLAUDE.md`) in the repo's shared, committed
    `.claude/settings.json`, plus the guidance instruction.
- The README explains the managed-settings case, what hookless mode does and
  does not enforce, and the better fix: an admin force-enabling dev-flow in
  managed `enabledPlugins`, which exempts its hooks from the policy.

## Non-goals

- Changing any hook script or `hooks.json`. The hooks stay as they are for
  machines where they run.
- Trying to get around or weaken the organization's policy.
- Reading server-managed (claude.ai console) policy. It is not on disk in a
  documented, readable form.
- Windows managed-settings sources (registry). The plugin is bash-only.
- A git pre-commit hook. Decided against (Decision 2).
- Covering the `disableAllHooks` key set in the user's *own* settings. It is
  handled by the same "ask the user" branch as any other unexplained dead
  probe.

## Current behaviour

- `plugins/dev-flow/hooks/hooks.json:1-27` wires the three hooks. They are
  plugin hooks, so `allowManagedHooksOnly` blocks all three (see *Platform
  facts*).
- `plugins/dev-flow/commands/onboard.md:27-40` (step 0) runs
  `/dev-flow:init-hooks` step 0's probe. At `onboard.md:32-33` it says: "If
  the probe is not blocked, stop and give that command's remediation instead
  of continuing". That is a **hard stop**. It is the step the user hit. The
  exact sentence the user quoted ("None of dev-flow's hooks run for you …")
  is not in the repo. It is the model's paraphrase of this stop.
- `plugins/dev-flow/commands/init-hooks.md:33-43` (step 0.3): the only
  remediation it offers is "update the marketplace, update the plugin,
  `/reload-plugins`, and re-run". Under policy that loops forever.
- `onboard.md:12-14` and `onboard.md:85-91` assume the guard exists ("will
  stop this run"; the marker-approval flow).
- `onboard.md:34-40`: the model must never delete the probe itself, because
  the guard blocks `rm`. With no guard running, that restriction is pointless.
- `init-hooks.md:76-80` (step 4): `.claude/lint-cmd` is written only for
  containerised or custom toolchains. Otherwise the built-in native checks
  are used, and those exist **only inside** `hooks/scripts/post-edit-check.sh:31-65`,
  so without hooks there is no per-file check at all.
- `init-hooks.md:82-84` (step 5, retries) and `init-hooks.md:101` (the
  gitignore reminder for hook state files) only mean something when hooks run.
- `plugins/dev-flow/hooks/scripts/stop-gate.sh:12-13,39` is the only thing
  that runs `.claude/test-cmd` at the end of a turn.
- `plugins/dev-flow/skills/verify-done/SKILL.md:13` already runs
  `.claude/test-cmd` if present. `:14` lists generic static checks but not
  `.claude/lint-cmd`.
- `plugins/dev-flow/agents/implementer.md:14` runs "the task's verify command
  and the tests for the touched module". It does not mention `.claude/test-cmd`
  or `.claude/lint-cmd`.
- `plugins/dev-flow/agents/reviewer.md:20` already runs `.claude/test-cmd`.
- `plugins/dev-flow/commands/build.md:15` already runs `verify-done` at the
  end. So once `implementer` and `verify-done` run the checks, `build.md`
  needs no change.
- `plugins/dev-flow/skills/setup-rules/SKILL.md:73-75` says the guard enforces
  the diff-and-approve rule "mechanically — it is not optional". Under policy
  that is false. `:69` calls the stop gate "the real safety net".
- `plugins/dev-flow/scripts/guidance-target.sh` is the existing detector
  pattern: `key=value` lines plus `summary=`, and `error=` with exit 1.
- `README.md:14`, `README.md:204` ("The hooks … apply on all of them"),
  `README.md:468-474` (guard-never-fires troubleshooting, which only covers a
  stale copy), and `README.md:486` (Known limits) say nothing about managed
  policy.
- No dev-flow command or skill writes a project `.claude/settings.json` today
  (the only `settings.json` references in `plugins/`, `README.md` and
  `install.sh` are to the user-level `~/.claude/settings.json`). So the
  guard-substitute merge is the first thing dev-flow writes there. In a target
  repo the file may or may not already exist, and may already hold other keys
  (`permissions.allow`, `env`, `enabledPlugins`, …) that must be kept.
- In **this** repo, `.claude/settings.json` does not exist (checked
  2026-09-30; `.claude/` tracks only `lint-cmd`, `test-cmd` and `rules/`). If
  hookless mode ever ran against this repo, the merge would create the file
  from `{}`. This repo's git history has a single author (Dimitris Giotas),
  so here nobody else would be affected by a shared rule. Consumer repos where
  colleagues install dev-flow are the case where sharing matters.

## Platform facts (from official docs, fetched 2026-09-30)

Verified against the documentation text only, not in a live managed session:

- `allowManagedHooksOnly` (managed-only key): "Your user, project, local, and
  plugin hooks are blocked. Hooks from plugins force-enabled in managed
  settings `enabledPlugins` are exempt." The same policy also narrows
  `statusLine` to managed settings. That breaks the optional
  claude-powerline add-on. claude-mem uses hooks, so it stops working too.
  (https://code.claude.com/docs/en/hooks)
- Force-enable syntax in managed settings: `"enabledPlugins": { "<id>": [true] }`.
  For dev-flow the id is `dev-flow@dev-flow-marketplace`
  (`.claude-plugin/marketplace.json` `name`). If the org sets
  `strictKnownMarketplaces`, the marketplace also has to be allowed there.
  (https://code.claude.com/docs/en/settings-reference)
- Permission rules are a separate mechanism. `allowManagedPermissionRulesOnly`
  is a separate managed key. Only when it is set are project and local
  `allow`/`ask`/`deny` rules ignored.
  (https://code.claude.com/docs/en/settings-reference)
- Rule evaluation order is deny, then ask, then allow, across all scopes. An
  `ask` rule prompts even if an allow rule matches.
  (https://code.claude.com/docs/en/permissions)
- "`deny` and `ask` rules apply right away." They do not wait for workspace
  trust. (https://code.claude.com/docs/en/settings)
- File rules are checked against `Edit(path)` and `Read(path)` only. An
  `Edit(...)` rule also covers Write. `Write(...)` and `MultiEdit(...)` path
  rules are accepted but never consulted. In deny/ask rules, a relative
  pattern such as `Edit(AGENTS.md)` or `Edit(.claude/rules/**)` matches at any
  depth. `Edit(/CLAUDE.md)` in project settings (`.claude/settings.json`)
  resolves to `<primary working directory>/CLAUDE.md`.
  (https://code.claude.com/docs/en/permissions)
- Project `.claude/settings.json` loads from the current working directory's
  `.claude/` folder, with no parent-directory fallback. A session started in a
  subdirectory of the repo does not load it.
  (https://code.claude.com/docs/en/permissions)
- `deny` and `ask` rules in a project's `.claude/settings.json` are not held
  back by the workspace trust dialog, "since they only restrict". Only
  `allow` rules and `additionalDirectories` wait for trust.
  (https://code.claude.com/docs/en/permissions)
- If the path Claude asks to edit is itself a symlink, the Edit and Write
  tools refuse and point Claude at the target. This natively covers the
  symlinked-`CLAUDE.md` case. (https://code.claude.com/docs/en/permissions)
- A plugin cannot ship permission rules. The plugin `settings` key only
  honours `agent` and `subagentStatusLine`.
  (https://code.claude.com/docs/en/plugins-reference)
- On-disk managed sources: `managed-settings.json` plus `managed-settings.d/*.json`
  in `/Library/Application Support/ClaudeCode/` (macOS) or `/etc/claude-code/`
  (Linux/WSL), and a macOS configuration profile in the `com.anthropic.claudecode`
  preferences domain. Server-managed settings are fetched remotely.
  `/status` → "Setting sources" names the source in force (`(remote)`,
  `(plist)`, `(file)`, …). (https://code.claude.com/docs/en/managed-settings)
- **Unverified here:** that a machine-wide configuration profile lands at
  `/Library/Managed Preferences/com.anthropic.claudecode.plist`. This is the
  standard macOS location for managed preferences, but the Claude Code docs
  name only the domain.
- Git hooks are outside Claude Code's settings entirely, so the policy cannot
  block them. A pre-commit hook was considered on that basis and declined
  (Decision 2).

## Proposed design

### 1. Detector script: `plugins/dev-flow/scripts/hooks-policy.sh`

Same shape as `guidance-target.sh`. It reads the on-disk managed sources and
reports whether they restrict hooks or permission rules. It only *explains* a
dead probe. The probe stays the source of truth for "are hooks live". That
means a force-enabled plugin (hooks exempt) never gets misreported: its probe
is blocked, so the detector never runs.

- Sources, in order: `$dir/managed-settings.json`, then
  `$dir/managed-settings.d/*.json`, then the plist (converted with
  `plutil -convert json -o -`, only if `plutil` exists).
  `dir` defaults by `uname -s` (Darwin → `/Library/Application Support/ClaudeCode`,
  anything else → `/etc/claude-code`). Tests override it with
  `DEV_FLOW_MANAGED_DIR`. The plist path defaults to
  `/Library/Managed Preferences/com.anthropic.claudecode.plist` and tests
  override it with `DEV_FLOW_MANAGED_PLIST`. These two env vars exist only as
  test seams.
- Unreadable, missing or invalid-JSON sources are skipped.
- Output (`key=value`, always exit 0; `error=jq-missing` and exit 1 if `jq` is
  absent):
  ```
  hooks=disabled|managed-only|not-found
  hooks_source=<path>                 # only when hooks != not-found
  permission_rules=managed-only|not-found
  permission_rules_source=<path>      # only when managed-only
  summary=<one line>
  ```
  `disableAllHooks: true` in any managed source gives `disabled`, and this
  wins over `managed-only`. Otherwise `allowManagedHooksOnly: true` gives
  `managed-only`.

### 2. `/dev-flow:init-hooks` step 0: diagnose instead of stop

Keep steps 0.1 and 0.2 (name the copy, probe). Replace 0.3 with:

- **Probe blocked** → hooks are live. Proceed as today.
- **Probe not blocked** → delete the probe file (nothing guards it), then run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/hooks-policy.sh"`:
  - `hooks=disabled|managed-only` → announce **hookless mode**, with the
    `summary` and source. Mention the admin fix (force-enable in managed
    `enabledPlugins`). Continue.
  - `hooks=not-found` → offer both causes and ask the user which applies:
    (a) a stale copy, so give today's update steps and stop; or (b) the policy
    comes from a source the script cannot read (check `/status` "Setting
    sources" for `Enterprise managed settings (remote)` etc.), in which case
    continue in hookless mode.
- **Hookless mode, guard substitute.** Unless `permission_rules=managed-only`,
  show the user the exact rules and get a yes, then merge them with `jq` into
  the repo's shared `.claude/settings.json` (creating it from `{}` if absent),
  keeping every existing key:
  - `permissions.ask` += `Edit(AGENTS.md)`, `Edit(CLAUDE.md)`, `Edit(.claude/rules/**)`
  - `permissions.deny` += `Edit(/CLAUDE.md)`, only when `guidance-target.sh`
    reports `never_edit=CLAUDE.md`.
  If `permission_rules=managed-only`, say that the guard is instruction-only
  on this machine and write nothing.
- **Why the shared file (Decision 1).** The rules are a deliberate,
  always-on backstop for everyone who works in the repo, not a per-machine
  patch. The cost is accepted knowingly: anyone whose dev-flow hooks *do* run
  gets both the hook's diff-and-approve block and Claude Code's permission
  prompt for the same edit. Because the file is committed, adding the rules
  changes permission behaviour for everyone who pulls the repo, so the user
  must review that diff before committing it.

Later steps in hookless mode:
- Step 4: write `.claude/lint-cmd` whenever the repo has any per-file check,
  host or container, because the native checks only live inside the hook.
- Step 5: skip retries (no stop gate) and say so.
- Step 7: report hookless mode, its reason, the rules written (or why none
  were), and that the gates are now enforced only by instructions. Drop the
  hook-state gitignore reminder. Instead, say that the rules were added to
  the shared, committed `.claude/settings.json`, and tell the user to review
  that diff before committing it, because it changes permission behaviour for
  anyone who pulls the repo.

### 3. `/dev-flow:onboard`

- Step 0: follow init-hooks step 0, including the new diagnosis. Do not stop
  unless that step says stop. Delete the probe only if it was not blocked
  (keep the "hand the user `rm`" rule for the blocked case). Defer the
  permission-rules confirmation to step 0.5.
- Step 0.5: in hookless mode, add to the one announcement: the hookless
  reason, the proposed permission rules, and that step 2 will add a "Quality
  gates" section to the guidance file. Write the rules right after the
  go-ahead, before step 1.
- Step 2: tell `setup-rules` that hookless mode is on.
- "If a step is blocked": add the hookless branch. Before any change to an
  existing guarded file, show the complete change in chat and wait for an
  explicit yes. Then make the call, and the `ask` rule will raise Claude
  Code's own permission prompt (unless rules are managed-only).
- "Who owns what": the step 0 row also owns the hookless diagnosis. Add a row
  for the `.claude/settings.json` permission rules (init-hooks step 0,
  hookless only).
- Report: say hookless mode where it applies, skip the hook-state gitignore
  reminder, and pass on init-hooks step 7's "review the shared
  `.claude/settings.json` diff before committing" note.

### 4. `setup-rules` skill

- In hookless mode (told by the caller, or `hooks-policy.sh` reports
  `hooks=disabled|managed-only`), add a short "Quality gates" section to the
  guidance file. It is phrased so it is also correct for anyone whose hooks
  do run:
  - after editing a file, run `bash .claude/lint-cmd <repo-relative-path>`
    (when the file exists) and fix failures;
  - before saying work is done, `bash .claude/test-cmd` must exit 0;
  - before changing `AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md`, show the
    complete change and wait for an explicit yes.
- Qualify the "enforced mechanically" claim at `SKILL.md:73-75` for the case
  where hooks are disabled by policy.
- The `description` frontmatter is unchanged, so triggering is unaffected.

### 5. Explicit gates in the build path (unconditional)

These are cheap, have no mode state, and also help when hooks do run (the
turn-end `Stop` hook is not a per-task check):
- `implementer.md` procedure step 4: also run `bash .claude/lint-cmd <path>`
  for each changed file if `.claude/lint-cmd` exists, and `bash .claude/test-cmd`
  if it exists. Both must exit 0 before reporting.
- `verify-done/SKILL.md` checklist step 3: include
  `bash .claude/lint-cmd <path>` for each touched file when present.

### 6. Documentation and release

- README: a new Documentation subsection, "Managed settings: hooks disabled
  by your organization". It covers what the policy blocks (including the
  powerline and claude-mem side effects), how dev-flow detects it, a table of
  hook versus hookless substitute, what hookless mode does *not* enforce, and
  the admin fix, all marked "from the docs, not verified in a managed
  session". Add short cross-references in `README.md:14`, `README.md:204`,
  `README.md:468-474` and Known limits.
- `AGENTS.md` Layout: one bullet for `scripts/hooks-policy.sh`. `CLAUDE.md` is
  a symlink, so edit `AGENTS.md` only. This goes through the guard.
- Bump `plugins/dev-flow/.claude-plugin/plugin.json` to `1.13.0`.

## Data flow (onboard, hookless)

```
step 0: probe Edit not blocked
  -> rm probe
  -> hooks-policy.sh -> managed-only|disabled   -> hookless
                     -> not-found -> ask user   -> stale: stop with update steps
                                                -> policy: hookless
step 0.5: announce (+ hookless reason, proposed ask/deny rules, guidance section)
  -> go-ahead -> jq-merge rules into shared .claude/settings.json (unless rules managed-only)
step 1 codegraph (unchanged)
step 2 setup-rules (+ Quality gates section)
step 3 init-hooks (step 0 skipped; lint-cmd always if any per-file check; no retries file)
step 4 init-rules (unchanged, guarded writes via show-diff + ask prompt)
report (hookless called out; review the settings.json diff before committing)
```

## Risks and edge cases

- **Instruction-level gates can be skipped by the model.** This is the honest
  cost of having no hooks. The README must say plainly that hookless mode is
  weaker, and that the admin fix restores the real gates.
- **The `ask` rules are coarser than the guard.** They also prompt on
  creating a new guarded file and on no-op edits. They cover only file tools,
  not Bash writes (Bash commands prompt by default unless the user has
  allow-listed them). Whether `ask` prompts in `bypassPermissions` mode was not
  confirmed from the docs.
- **Detector false negative.** Server-managed or unreadable plist policy gives
  `not-found`, and the user is asked. That is the safe default.
- **Detector false positive.** It cannot misfire, because it runs only after
  the probe proves hooks are dead.
- **Contributors whose hooks work get a double prompt.** The rules live in
  the shared, committed `.claude/settings.json` (Decision 1), so anyone in the
  repo whose dev-flow hooks run gets the guard's block *and* Claude Code's
  permission prompt for the same guarded edit, and a permission prompt when
  creating a new guarded file. This is accepted as the price of a team-wide
  backstop. In this repo it affects nobody else today (single author); in
  consumer repos it affects every colleague who pulls the commit.
- **Contributors whose hooks work also get a redundant "Quality gates"
  section** in the guidance file, when it was added in hookless mode. It is
  phrased to stay correct for them (Decision 3).
- **Committing changes other people's permission behaviour.** The init-hooks
  and onboard reports tell the user to review the `.claude/settings.json` diff
  before committing it. Nothing is committed automatically.
- **Existing content in `.claude/settings.json`.** The jq merge appends to
  `permissions.ask`/`permissions.deny` and `unique`s them. Every other key,
  including `permissions.allow`, is kept. It never replaces the file, and it
  creates it from `{}` only when absent.
- **Sessions started in a subdirectory** do not load the project
  `.claude/settings.json` (no parent fallback), so the `ask` rules do not
  apply there. The guidance instruction still does.

## Migration and rollback

- There is nothing to migrate. Machines where hooks run take the "probe
  blocked" branch and behave exactly as before. The only visible change there
  is that `implementer` and `verify-done` run `lint-cmd`/`test-cmd`
  explicitly.
- Rollback means reverting the release commit and re-tagging a lower version.
  In a repo where hookless mode ran, someone removes the three `ask` entries
  (and any `deny` entry) from `.claude/settings.json` in a commit, since the
  file is shared, and removes the "Quality gates" section from the guidance
  file. If the rules were never committed, discarding the uncommitted
  `.claude/settings.json` change is enough.

## Decisions (confirmed by the user, 2026-09-30)

1. **Guard-substitute permission rules go in the shared, committed
   `.claude/settings.json`**, not `.claude/settings.local.json` and not
   instruction-only. They are a team-wide backstop; the redundant prompt for
   contributors whose hooks work is accepted (see Risks).
2. **No git pre-commit hook** in this change.
3. **"Quality gates" guidance section is added only in hookless mode.**
4. **Version is `1.13.0`.**

Not a decision, just a note for the live check: `/status` → "Setting sources"
on the managed laptop shows whether the detector will auto-detect the policy
(`(file)` or `(plist)`) or whether the "ask the user" branch will run
(`(remote)`). This does not change the plan.
