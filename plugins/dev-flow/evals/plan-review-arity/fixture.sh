set -eu
mkdir -p .claude/specs .claude/plans src tests
cat > package.json <<'EOF'
{"name":"fixture-badges","private":true,"scripts":{"test":"node --test tests/"}}
EOF
printf '%s\n' 'node --test tests/' > .claude/test-cmd
cat > src/names.js <<'EOF'
// Display names for badges and emails.

function displayName(first, last, title) {
  return `${title} ${first} ${last}`;
}

module.exports = { displayName };
EOF
cat > tests/names.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { displayName } = require('../src/names');

test('puts the title first', () => {
  assert.strictEqual(displayName('Ada', 'Lovelace', 'Dr'), 'Dr Ada Lovelace');
});
EOF
cat > .claude/specs/badge.md <<'EOF'
# Spec: badge

## Goal

Add badge(user) in src/badge.js. It returns the greeting printed on a conference badge for a user object with the fields first, last and title.

## Acceptance criteria

1. badge({ first: 'Ada', last: 'Lovelace', title: 'Dr' }) returns 'Hello, Dr Ada Lovelace!'.
2. badge({ first: 'Ada', last: 'Lovelace', title: '' }) returns 'Hello, Ada Lovelace!', with no leading space.

## Non-goals

- No translation of the greeting.
- No change to the signature of displayName.

## Design

- displayName in src/names.js keeps its signature and joins only the non-empty parts with one space.
- New greeting(name) in src/greeting.js returns 'Hello, <name>!'.
- New badge(user) in src/badge.js greets the user's display name, built with the existing displayName.

## Assumptions and open questions

| Category | Status | Resolution | Source |
|---|---|---|---|
| Scope boundary | answered | badge text only; no translation | request |
| Acceptance | answered | the two outputs above, checked with node --test | request |
| Data and contracts | answered | displayName keeps its signature | src/names.js:3 |
| Failure behaviour | answered | an empty title is omitted; first and last are always present | request |
| Compatibility | answered | existing displayName callers keep working | src/names.js:3 |
| Non-functional | answered | none: pure string formatting | request |
| Reuse | answered | reuse displayName for the name | src/names.js:3 |
EOF
cat > .claude/plans/badge.md <<'EOF'
# Plan: badge

Status: IN_PROGRESS
Approved: yes
Spec: .claude/specs/badge.md

## Tasks

### Task 1: Omit an empty title in displayName

Task status: NOT_STARTED

Objective: Make displayName join only its non-empty parts.

Files:
- modify src/names.js
- modify tests/names.test.js

Test first: In tests/names.test.js add the test 'omits an empty title', asserting that displayName('Ada', 'Lovelace', '') returns 'Ada Lovelace'. It fails now because the function returns ' Ada Lovelace'.

Test command: `node --test tests/names.test.js`

Change: Keep the signature displayName(first, last, title). Replace the body with: return [title, first, last].filter(Boolean).join(' ');

Done when:
- run `node --test tests/names.test.js` and expect both tests to pass

Risk: low

### Task 2: Add greeting

Task status: NOT_STARTED

Objective: Add a function that wraps a name in the badge greeting.

Files:
- create src/greeting.js
- create tests/greeting.test.js

Test first: Create tests/greeting.test.js with the test 'greets by name', asserting that greeting('Ada Lovelace') returns 'Hello, Ada Lovelace!'. It fails now because src/greeting.js does not exist.

Test command: `node --test tests/greeting.test.js`

Change: Create src/greeting.js defining function greeting(name), which returns 'Hello, ' + name + '!', and export it with module.exports = { greeting };

Done when:
- run `node --test tests/greeting.test.js` and expect the test to pass

Risk: low

### Task 3: Add badge

Task status: NOT_STARTED

Objective: Add badge(user), which greets the user's display name.

Files:
- create src/badge.js
- create tests/badge.test.js

Test first: Create tests/badge.test.js with two tests. 'includes the title' asserts that badge({ first: 'Ada', last: 'Lovelace', title: 'Dr' }) returns 'Hello, Dr Ada Lovelace!'. 'omits an empty title' asserts that badge({ first: 'Ada', last: 'Lovelace', title: '' }) returns 'Hello, Ada Lovelace!'. Both fail now because src/badge.js does not exist.

Test command: `node --test tests/badge.test.js`

Change: Create src/badge.js. Require displayName from ./names and greeting from ./greeting, then define function badge(user) { return greeting(displayName(user)); } and export it with module.exports = { badge };

Done when:
- run `node --test tests/badge.test.js` and expect both tests to pass
- run `node --test tests/` and expect every test to pass

Depends on: 1, 2

Risk: low

## Acceptance criteria

- [ ] run `node --test tests/` and expect every test to pass
EOF
git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -qm fixture
