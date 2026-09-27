---
description: Copy and adapt the plugin's stack rule templates (php-api, java-spring, python, node-ts) into this repo's .claude/rules
argument-hint: <php|java|python|node|all>
---

Install rule templates for: $ARGUMENTS

1. Templates live in `${CLAUDE_PLUGIN_ROOT}/templates/rules/`: `php-api.md`, `java-spring.md`, `python.md`, `node-ts.md`. Map the argument to files (`php` -> php-api, `java` -> java-spring, `python` -> python, `node` -> node-ts, `all` -> every one that matches languages actually present in this repo).
2. Inspect the repo first (manifests, lint config, compose files). To decide which guidance file is canonical, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guidance-target.sh"` and obey its `edit` / `never_edit` output — if `CLAUDE.md` is a symlink, hard link or `@AGENTS.md` import, it is only a pointer: everything goes in `AGENTS.md` and `CLAUDE.md` is left alone.
3. For each template, verify every line against the repo. Remove lines that do not apply or contradict existing conventions; adjust commands (test, lint, static analysis) to the real ones you confirmed by running them. If the toolchain runs in a container, the commands must be the containerised form (`docker compose exec -T <service> …`) — take the service name and container path from the compose file or the guidance file, never guess. Remove the TEMPLATE comment once verified.
4. Write results to `.claude/rules/<name>.md` in the repo. If a target file already exists, any change to it — by `Write`, `Edit` or `MultiEdit` — is blocked by the `pre-write-guard` hook, which hands you the exact change and an approval-marker command: show the change to the user, wait for an explicit yes, run that exact command, then retry. Propose the whole intended file in one call rather than several small edits, and never work around the gate. Then summarise what you kept, changed and dropped, with the evidence.
5. Offer to create `.claude/test-cmd` for the stop-gate hook if it is missing, and `.claude/lint-cmd` if this project's linters do not run on the host (templates: `${CLAUDE_PLUGIN_ROOT}/templates/test-cmd.docker.example` and `lint-cmd.docker.example`).
