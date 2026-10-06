---
description: Wire up this repo's dev-flow hook commands (.claude/test-cmd, .claude/lint-cmd, .claude/test-cmd-retries) by reading how the repo itself documents testing and linting, then prove they work.
argument-hint: '[retries=N] [force-container] [force-host]'
---

Set up the hook commands for this repo. Arguments (all optional): $ARGUMENTS

Goal: the stop gate and per-edit check run this project's *real* commands. Do not invent commands, and do not finish until you have run what you wrote.

## 0. Prove the pre-write guard is live (do this first)

This repo's `pre-write-guard.sh` hook gates `Write`/`Edit` on `AGENTS.md`,
`CLAUDE.md` and `.claude/rules/*.md`. It fails silently: a stale or unwired
copy looks identical to a working one, because every non-match is a bare
`exit 0`. Prove it fires before doing anything else.

1. **Name the loaded copy.** State the plugin root path (`${CLAUDE_PLUGIN_ROOT}`
   — Claude Code substitutes it inline in command Markdown) and run
   `claude plugin list`. The last path segment of the plugin root is the
   loaded version. If it differs from the version `claude plugin list`
   reports, or is older than the marketplace's, say so and give the
   remediation in step 3(3a) (the stale-copy update steps).
2. **Probe it end to end, side-effect-free.** Create a throwaway guarded file
   `.claude/rules/devflow-guard-probe.md` with the `Write` tool (a brand-new
   guarded file is allowed by design), then issue an `Edit` on it changing
   one word. The guard must block that `Edit` with
   `BLOCKED: Edit would change an existing protected file`, and the second
   line of the block message names the version that fired. Delete
   `.claude/rules/devflow-guard-probe.md` afterwards whether or not it
   blocked. Do not create an approval marker, and do not retry the edit. If
   the guard blocked the delete too, leave it and give the user
   `rm .claude/rules/devflow-guard-probe.md`. Probe the throwaway file, never
   `AGENTS.md` — if the guard is dead, a probe against `AGENTS.md` would
   damage real guidance.
3. **If the `Edit` was not blocked, find out why.**
   1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/hooks-policy.sh"` and show its
      output.
   2. `hooks=disabled` or `hooks=managed-only`: the organization's managed
      settings block dev-flow's hooks. Say so, quoting the script's `summary`
      and `hooks_source`. Tell the user the real fix is an admin
      force-enabling `dev-flow@dev-flow-marketplace` with `[true]` in managed
      `enabledPlugins`, because hooks of force-enabled plugins are exempt from
      the policy. Do not tell them to update the plugin — that cannot help
      here. Then continue in **hookless mode** (below).
   3. `hooks=not-found`: the on-disk sources show no restriction, so ask the
      user which of two things is going on:
      - (a) a stale or unwired copy — give the existing update steps and stop:
        ```
        claude plugin marketplace update dev-flow-marketplace
        claude plugin update dev-flow@dev-flow-marketplace
        /reload-plugins        # or start a new session
        ```
        then re-run `/dev-flow:init-hooks`. Note that a marketplace added from
        a local directory or a non-Anthropic GitHub repo does not auto-update,
        so this is a manual step.
      - (b) the org's policy comes from a source this script cannot read
        (server-managed / claude.ai console policy is not on disk). Check
        `/status` → "Setting sources": if it shows something like
        `Enterprise managed settings (remote)` rather than a local file or
        plist, that confirms it. Continue in hookless mode.
   4. Never try to re-enable hooks by editing any settings file.

### Hookless mode

No pre-write guard, no per-edit check, no stop gate run automatically. The
remaining steps in this command still write and verify `.claude/test-cmd` and
`.claude/lint-cmd` — the `implementer` agent and the `verify-done` skill run
those explicitly, without needing a hook.

**Guard substitute.** If `hooks-policy.sh` reported `permission_rules=managed-only`,
say the guard substitute is instruction-only on this machine (project/local
permission rules are ignored under that policy) and write nothing. Otherwise:

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guidance-target.sh"` to learn
   whether `CLAUDE.md` is a pointer (`never_edit=CLAUDE.md`).
2. Show the user the exact rules below and get an explicit yes before writing
   anything:
   - `permissions.ask`: `Edit(AGENTS.md)`, `Edit(CLAUDE.md)`, `Edit(.claude/rules/**)`
   - `permissions.deny`: `Edit(/CLAUDE.md)` — only when `never_edit=CLAUDE.md`.
3. On a yes, merge them into the repo's shared, committed `.claude/settings.json`
   with this exact snippet. It creates the file from `{}` only if absent (no
   dev-flow step writes this file today, so in many target repos it will be
   new; this repo has none either). If the file already exists, it keeps every
   existing key (`permissions.allow`, `env`, `enabledPlugins`, …), appends to
   `ask`/`deny`, and dedupes:
   ```bash
   f=.claude/settings.json; mkdir -p .claude; [ -f "$f" ] || echo '{}' > "$f"
   jq --argjson ask '["Edit(AGENTS.md)","Edit(CLAUDE.md)","Edit(.claude/rules/**)"]' \
     '.permissions.ask = ((.permissions.ask // []) as $a | $a + ($ask - $a))' "$f" > "$f.tmp" \
     && mv "$f.tmp" "$f" || rm -f "$f.tmp"
   # only when never_edit=CLAUDE.md:
   jq --argjson deny '["Edit(/CLAUDE.md)"]' \
     '.permissions.deny = ((.permissions.deny // []) as $d | $d + ($deny - $d))' "$f" > "$f.tmp" \
     && mv "$f.tmp" "$f" || rm -f "$f.tmp"
   ```

**Why:** an `ask` rule raises Claude Code's own permission prompt — showing
the change — for every Write/Edit to those files, and it applies without
waiting for workspace trust. These rules go in the shared, committed settings
file on purpose, as an always-on backstop for everyone in the repo; anyone
whose dev-flow hooks do run will get both the guard's block and this prompt
for the same edit, and that redundancy is accepted. They do not cover Bash
writes, and they only load in sessions started at the repo root (project
settings have no parent-directory fallback).

Committing this file changes permission behaviour for everyone who pulls the
repo, so tell the user to review the diff before committing it. Do not commit
it yourself.

## 1. Find the commands (read, do not guess)

Look in this order and stop at the first authoritative answer, noting where each command came from:

1. `AGENTS.md`, then `CLAUDE.md` — check `AGENTS.md` first; whichever exists is the source of truth. Look for a commands/testing/development section.
2. `.claude/rules/*.md`, `CONTRIBUTING.md`, `README.md` (a "Running tests" / "Development" section).
3. Runner definitions: `Makefile`, `justfile`, `Taskfile.yml`, `bin/` or `scripts/` wrappers.
4. Manifests: `composer.json` (`scripts`), `package.json` (`scripts`), `pyproject.toml`, `tox.ini`, `pom.xml`, `build.gradle`.
5. CI, which shows what the team actually trusts: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`.

If two sources disagree, prefer the guidance file, and say so in the report. If you find nothing, ask me rather than inventing a command.

## 2. Decide host or container

Check `docker-compose.yml` / `compose.yaml` / `Dockerfile` and whether the needed binaries exist on the host (`command -v php`, `python`, `mvn`, `node`).

- Container form: `docker compose exec -T <service> <command>`. Take the **service name** from the compose file's `services:` and the **container path** from its `volumes:` mapping — never guess either.
- Always `-T` (hooks have no TTY; an interactive exec hangs). If the stack may not be running, prefer `docker compose run --rm <service> …`, or make the script skip cleanly when the service is down.
- `force-container` / `force-host` in my arguments overrides your detection.
- Templates to start from: `${CLAUDE_PLUGIN_ROOT}/templates/test-cmd.docker.example` and `lint-cmd.docker.example`.

## 3. Write `.claude/test-cmd` (the stop gate)

It is a shell script body run as `bash .claude/test-cmd` from the repo root. Exit 0 = the turn may finish; non-zero blocks it and the output goes back to Claude. No shebang or `chmod` needed.

Pick the **fastest command set that still catches most breakage**, because it runs at the end of every turn that changed files:

- Include: unit tests, linters, type/static checks (`phpstan`, `tsc --noEmit`, `mypy`, `ruff`).
- Exclude: integration, e2e, browser and snapshot-heavy suites; anything needing external services or credentials. List what you excluded in the report.
- Prefer fail-fast flags (`--stop-on-failure`, `-x`, `--bail`) so feedback is quick.
- Chain with `&&`, or use explicit `|| exit 1` per line.

## 4. Write `.claude/lint-cmd` (per-edit check) — only when needed

Only create it if the per-edit checks cannot run on the host (containerised toolchain, or a custom runner). The hook calls it with the **repo-relative path of the edited file as `$1`** and it fully replaces the built-in native checks. It must translate `$1` into the container path itself. Dispatch on extension and exit 0 for file types you do not check.

If the host has the tools natively, skip this file — the built-in checks already handle php/python/ts/js/json, and silently skip any tool that is not installed.

In hookless mode, always write `.claude/lint-cmd` when the repo has any
per-file check (host or container): the built-in native checks only run
inside the hook, so without it nothing checks individual files.

## 5. Write `.claude/test-cmd-retries` — only if asked

A single number: how many times the stop gate blocks and lets Claude retry before giving up loudly. Default is 3 when the file is absent. Write it only if I passed `retries=N`.

In hookless mode, skip this step: there is no stop gate to retry. Say so in
the report.

## 6. Prove they work (do not skip this)

1. **`test-cmd` passes on a clean tree**: run `bash .claude/test-cmd`, time it, and report the duration. If it exits non-zero, report that the repo is already failing its own checks and stop — do not "fix" the command to make it pass.
2. **Warn if slow**: over ~60s is friction on every turn; suggest a narrower command.
3. **`lint-cmd` passes a good file**: `bash .claude/lint-cmd <an existing source file>` → expect 0.
4. **`lint-cmd` can actually fail** — a gate that never fails is worthless. Create a deliberately broken file in a temp path inside the repo (e.g. `tmp-devflow-check.php` with a syntax error), run `bash .claude/lint-cmd tmp-devflow-check.php`, confirm non-zero, then **delete the temp file**. Report both results.
5. Before running anything that might touch a shared database, staging environment or external service, stop and ask me first. Never run migrations or destructive commands as part of verification.

## 7. Report

- Hookless mode, if it applied: the reason (the `hooks-policy.sh` summary or
  the user's answer), the permission rules added to the shared
  `.claude/settings.json` (or why none were), that the three gates are now
  enforced only by instructions, and the admin fix (managed `enabledPlugins`
  force-enable).
- Whether the pre-write guard blocked the probe, and the plugin version and root path it reported.
- Each file written, with the command in it and **where you found that command**.
- Verification results: exit codes and the timing of `test-cmd`.
- What you deliberately excluded (integration tests, etc.).
- Commit advice: `.claude/test-cmd` and `.claude/lint-cmd` are usually worth committing so the team shares the same gate; `.claude/test-cmd-retries` is personal.
- Remind me to gitignore the hooks' state files: `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log`, `.claude/.devflow-state.json`, `.claude/.approved-writes/`, `.claude/plans/`, `.claude/specs/`, `.claude/worktrees/` — in hookless mode, instead tell me to review the `.claude/settings.json` diff before committing it, because it changes permission behaviour for anyone who pulls the repo.

Note: these files are plain text, so I can also just write them by hand — this command exists to derive them from what the repo already documents and to verify them.
