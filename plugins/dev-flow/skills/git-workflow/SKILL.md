---
name: git-workflow
description: Handle branching, commits, pull requests and review feedback cleanly. Use whenever the user asks to commit, create a branch, write a commit message, open or describe a PR, split a change into commits, rebase, resolve conflicts, or respond to code-review comments, even if they only say "ship it", "push this" or "address the review". When it creates a new branch it asks whether to use a branch (default) or a git worktree and whether to start from the current branch (default) or the default branch, and it does not list, remove or clean up worktrees. Never pushes, merges or force-pushes without explicit approval.
---

# Git workflow

## Before any commit
1. `git status` and `git diff` (staged and unstaged). Read what will actually be committed.
2. Confirm you are not on the default branch (`main`/`master`/`develop`). If you are, create it with **New branch** below before committing.
3. Stage **specific files by name**. Never `git add -A` blindly. Never stage `.env`, credentials, keys, dumps, or build output. If you see one, stop and warn.
4. Run the fast checks (`.claude/test-cmd` if present) before committing. Do not commit a red tree unless the user asks for a WIP commit.

## New branch
Follow this whenever you are about to create a branch: step 2 above, or the user asks for a new branch.
1. Name the branch. Pick `<type>` from the change at hand: `fix` if it corrects a bug, `refactor` if it restructures code without changing behaviour, `chore` if it is maintenance that changes no product behaviour such as dependencies, build, CI, tooling, docs or a version bump, otherwise `feature`. These are branch types: a feature branch is `feature/...` even though its commits use the `feat` commit type. Pick a short kebab-case `<short-slug>` for the change. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/branch-name.sh" <type> <short-slug>` from the repository root and propose its `branch=` value as `<branch>`; it adds the project prefix from `.claude/branch-prefix` when the repo has one. If it exits 1, report its `error=` and `summary=` lines and stop.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/default-branch.sh"` from the repository root. Offer the base choice only if it exits 0, prints `on_default=no`, and `git status --porcelain -- . ':!.claude/plans' ':!.claude/specs' ':!.claude/worktrees'` is empty. Otherwise start from the current branch, and give the reason in one line if the script exited 1 (its `summary=` line) or the tree has uncommitted changes (switching base could mix or lose them).
3. Offer **Worktree** only if all of these hold; otherwise use **Branch** and give the reason in one line:
   - `git status --porcelain -- . ':!.claude/plans' ':!.claude/specs' ':!.claude/worktrees'` is empty: a worktree starts from a commit and would leave uncommitted changes behind.
   - `git rev-parse --git-dir` and `git rev-parse --git-common-dir` print the same path when both are run from the repository root (`git rev-parse --show-toplevel`): otherwise this session is already in a linked worktree.
   - `EnterWorktree` is among your tools.
4. Ask once, with one `AskUserQuestion` call holding the questions that apply and that the user has not already answered: header `Git workflow`, question "Where should <branch> live?", options **Branch (default)**: "Create it in this checkout and switch to it." and **Worktree**: "Create a separate checkout in .claude/worktrees/<short-slug> on the new branch; this checkout stays untouched."; and header `Start from`, question "Which branch should <branch> start from?", options **Current branch (default)**: "Start from <current branch, or HEAD if detached> as it is now." and **Default branch**: "Start from <default= value>, the repository's default branch." Answering approves the name. If no question applies, or `AskUserQuestion` is unavailable, ask the user in plain text to approve the name and make any choice that applies. If the user wants a different type or slug, run the script again with it and use the new `branch=` value. Any answer that is not a clear choice of **Worktree** means **Branch**, and any answer that is not a clear choice of **Default branch** means **Current branch**.
5. **Branch**: once the name is approved, run `git switch -c <branch>` for **Current branch**, or `git switch --no-track -c <branch> <ref>` for **Default branch**, where `<ref>` is the script's `ref=` value.
6. **Worktree**: from the repository root run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh" <short-slug> <branch> <start>`, where `<start>` is `HEAD` for **Current branch** or the `ref=` value for **Default branch**. If it exits 1, report its `error=` and `summary=` lines and stop; for `error=copy-failed` the worktree and branch already exist, so also tell the user the cleanup commands in its `summary=` and do not run them yourself. Otherwise call `EnterWorktree` with its `path=` value and say this session now works there. If it printed `ignored=no`, tell the user to add `.claude/worktrees/` to `.gitignore`. Never remove the worktree yourself; after merging, it is removed with `git worktree remove <path>`. Do not use any other worktree procedure or skill.

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
