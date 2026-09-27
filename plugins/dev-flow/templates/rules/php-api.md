---
paths:
  - "**/*.php"
---
<!-- TEMPLATE: verify each line against this repo before keeping it. Delete what doesn't apply. -->
- Follow the existing framework and layering (controller -> service -> repository); keep controllers thin, no business logic or raw SQL in them.
- Use `declare(strict_types=1);` and typed properties, parameters and returns where the codebase already does.
- Validate and normalise all request input at the boundary (form request/DTO); never trust route or body ids without an ownership check.
- SQL only through parameter binding or the query builder/ORM; no string concatenation.
- API responses use the repo's existing envelope and status codes; do not invent a new shape.
- Log with the PSR-3 logger; never log secrets, tokens, PAN or full request bodies.
- Wrap multi-write operations in a transaction; make external calls idempotent or retry-safe.
- Tests: PHPUnit/Pest next to existing tests; one behaviour per test; no network or real DB unless the suite already does.
- Run before finishing: the project's PHPUnit command, static analysis (PHPStan/Psalm) and code style (Pint/php-cs-fixer) if configured.
