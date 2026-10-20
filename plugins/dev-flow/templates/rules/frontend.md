---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/*.svelte"
  - "**/*.css"
  - "**/*.scss"
---
<!-- TEMPLATE: verify each line against this repo before keeping it. Delete what doesn't apply. -->
- Design tokens live in `<token file>`: find it (CSS custom properties, theme module, Tailwind config or token JSON), replace this placeholder with its path, and use its tokens instead of raw colour, spacing, type, radius or breakpoint values.
- Reuse the components in `<components dir>` before writing new ones; follow their props, state and styling patterns.
- Use semantic elements, labelled controls, visible keyboard focus and alt text.
- Keep secrets and server-only config out of the client bundle.
- Test behaviour with the repo's runner; e2e tests belong to `[qa]` tasks.
- Before finishing a UI change, run .claude/test-cmd and the `visual-verify` skill.
