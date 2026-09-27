---
name: git-workflow
description: Handle branching, commits, pull requests and review feedback cleanly. Use whenever the user asks to commit, create a branch, write a commit message, open or describe a PR, split a change into commits, rebase, resolve conflicts, or respond to code-review comments, even if they only say "ship it", "push this" or "address the review". Never pushes, merges or force-pushes without explicit approval.
---

# Git workflow

## Before any commit
1. `git status` and `git diff` (staged and unstaged). Read what will actually be committed.
2. Confirm you are not on the default branch (`main`/`master`/`develop`). If you are, propose a branch name `type/short-slug` (`feat/`, `fix/`, `chore/`, `refactor/`) and create it after approval.
3. Stage **specific files by name**. Never `git add -A` blindly. Never stage `.env`, credentials, keys, dumps, or build output. If you see one, stop and warn.
4. Run the fast checks (`.claude/test-cmd` if present) before committing. Do not commit a red tree unless the user asks for a WIP commit.

## Commits
- One logical change per commit. If the diff mixes a refactor with a behaviour change, split it (`git add -p` equivalents by file, or ask).
- Follow the repo's existing message style (`git log --oneline -15`). If none, use Conventional Commits: `type(scope): imperative summary` under 72 chars, blank line, body explaining **why**, not what.
- Reference the ticket/issue if the branch name or user gives one.
- Create new commits. Do not amend or rewrite published history unless asked. Never use `--no-verify`. If a hook fails, fix the cause and make a new commit.

## Pull requests
Title under 70 characters. Body:
```
## Summary
<1-3 bullets: what and why>

## Changes
<notable files/behaviour, migrations, config or env changes>

## Testing
<commands run and results; what was NOT tested>

## Risks / rollout
<breaking changes, feature flags, rollback plan>
```
Base the description on the **whole branch** (`git diff <base>...HEAD`, `git log <base>..HEAD`), not just the last commit. Push and create the PR only when asked.

## Review feedback
1. Read every comment before changing anything. Group them into: must-fix, questions, suggestions, disagree.
2. Verify each claim against the code before acting; a reviewer can be wrong. If you disagree, reply with evidence rather than complying blindly.
3. Fix in small commits (`fix: address review - <topic>`), re-run checks, then summarise what changed per comment.

## Hard rules
- Never push, force-push, merge, delete branches or reset `--hard` without explicit approval for that specific action.
- Never rewrite someone else's commits or the default branch.
- Conflicts: show both sides and the intended resolution; do not guess on logic conflicts.
