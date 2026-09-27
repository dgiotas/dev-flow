---
paths:
  - "**/*.py"
---
<!-- TEMPLATE: verify each line against this repo before keeping it. Delete what doesn't apply. -->
- Follow the project's formatter and linter config (ruff/black); do not reformat unrelated code.
- Type-hint public functions; keep pydantic/dataclass models at boundaries.
- No bare `except:`; catch specific exceptions and keep the traceback when re-raising.
- Use context managers for files, connections and locks; no mutable default arguments.
- Config from environment or settings objects; no secrets in code.
- Tests with pytest next to existing tests; use fixtures over setup duplication; no real network calls.
- Run before finishing: `ruff check .`, the type checker if configured (mypy/pyright), and `pytest -x -q` for touched modules.
