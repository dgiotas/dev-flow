---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
<!-- TEMPLATE: verify each line against this repo before keeping it. Delete what doesn't apply. -->
- Follow the existing ESLint and Prettier config; do not change tooling config unless asked.
- TypeScript: no `any` without a comment; prefer narrow types and `unknown` at boundaries; validate external data at runtime (zod or the repo's validator).
- Await every promise; handle rejections; no floating promises.
- React: keep components small, no state derived from props without a reason, keys on lists, effects with correct dependencies.
- Do not read `process.env` all over; use the existing config module. No secrets in the client bundle.
- Tests with the repo's runner (Jest/Vitest/Testing Library); test behaviour, not implementation details.
- Run before finishing: `npx tsc --noEmit`, lint, and the tests for touched files.
