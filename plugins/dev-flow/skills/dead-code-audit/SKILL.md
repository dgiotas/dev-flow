---
name: dead-code-audit
description: 'Find dead code, unused dependencies, duplicated logic, and stale config in a repository and produce a report without changing any files. Use when the user asks to clean up, find unused code, audit dependencies, reduce tech debt, prune a service, or asks "what can we delete". Report-only: never delete anything unless the user explicitly approves specific items afterward.'
---

# Dead-code audit (report only)

Do not modify files. Produce a ranked report the user can act on.

## Procedure

1. **Scope.** Confirm the target directory or service. Ask nothing else; assume the whole repo if unspecified.
2. **Collect candidates** with the tools available for the stack:
   - PHP: `vendor/bin/phpstan analyse` (unused private members and dead code checks), `composer why-not`/`composer unused` if installed, `rg` for unreferenced classes.
   - Python: `vulture .` and `ruff check --select F401,F841 .` if installed; `pip-check`/`deptry` for dependencies.
   - Node/TS: `npx knip` or `npx ts-prune`, `npx depcheck`.
   - Java: IDE/compiler unused warnings, `mvn dependency:analyze`.
   - Always: `codegraph` for zero-caller functions; `rg` for feature flags and config keys that nothing reads.
3. **Verify each candidate before listing it.** Static tools produce false positives. For every candidate check for:
   - Dynamic use: reflection, string-based class or method names, DI containers, annotations, route files, event listeners, serialization, test fixtures.
   - Public API: exported from a library, HTTP endpoints, queue consumers, cron entries, CLI commands.
   - Use from other repos or services (search sibling repos if available and say so if not).
4. **Classify** each item: `Safe` (no references, verified), `Likely` (no static refs, possible dynamic use), `Needs owner` (public surface or cross-service).
5. **Report** as a table sorted by confidence, then size: `item | location | evidence | class | suggested action`. Add totals (lines removable, dependencies removable).
6. **Stop.** Ask which items to remove. Only after explicit approval, delete them in small commits with tests run after each.

## Rules

- If a tool is not installed, say so and continue with what you have. Do not install tools without asking.
- Never list something as `Safe` on the strength of one tool alone.
