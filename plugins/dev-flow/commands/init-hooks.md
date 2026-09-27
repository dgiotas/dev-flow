---
description: Wire up this repo's dev-flow hook commands (.claude/test-cmd, .claude/lint-cmd, .claude/test-cmd-retries) by reading how the repo itself documents testing and linting, then prove they work.
argument-hint: [retries=N] [force-container] [force-host]
---

Set up the hook commands for this repo. Arguments (all optional): $ARGUMENTS

Goal: the stop gate and per-edit check run this project's *real* commands. Do not invent commands, and do not finish until you have run what you wrote.

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

## 5. Write `.claude/test-cmd-retries` — only if asked

A single number: how many times the stop gate blocks and lets Claude retry before giving up loudly. Default is 3 when the file is absent. Write it only if I passed `retries=N`.

## 6. Prove they work (do not skip this)

1. **`test-cmd` passes on a clean tree**: run `bash .claude/test-cmd`, time it, and report the duration. If it exits non-zero, report that the repo is already failing its own checks and stop — do not "fix" the command to make it pass.
2. **Warn if slow**: over ~60s is friction on every turn; suggest a narrower command.
3. **`lint-cmd` passes a good file**: `bash .claude/lint-cmd <an existing source file>` → expect 0.
4. **`lint-cmd` can actually fail** — a gate that never fails is worthless. Create a deliberately broken file in a temp path inside the repo (e.g. `tmp-devflow-check.php` with a syntax error), run `bash .claude/lint-cmd tmp-devflow-check.php`, confirm non-zero, then **delete the temp file**. Report both results.
5. Before running anything that might touch a shared database, staging environment or external service, stop and ask me first. Never run migrations or destructive commands as part of verification.

## 7. Report

- Each file written, with the command in it and **where you found that command**.
- Verification results: exit codes and the timing of `test-cmd`.
- What you deliberately excluded (integration tests, etc.).
- Commit advice: `.claude/test-cmd` and `.claude/lint-cmd` are usually worth committing so the team shares the same gate; `.claude/test-cmd-retries` is personal.
- Remind me to gitignore the hooks' state files: `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log`, `.claude/.approved-writes/`.

Note: these files are plain text, so I can also just write them by hand — this command exists to derive them from what the repo already documents and to verify them.
