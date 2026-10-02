---
description: Run this repo's whole dev-flow onboarding in order — CodeGraph index, guidance file and rules, then verified hook commands — pausing for approval at every guarded write.
argument-hint: [php|java|python|node|all] [retries=N] [force-container] [force-host]
---

Onboard this repo to dev-flow. Arguments (all optional): $ARGUMENTS

## How this runs

This is interactive and interruptible, not a batch job. Every step below is
idempotent, so re-running this command resumes rather than redoing work. The
pre-write-guard **will** stop this run on any repo that already has
`AGENTS.md`, `CLAUDE.md` or `.claude/rules/*.md` — i.e. every second run — by
design, not a bug. See "If a step is blocked" below. On a machine where the
organization's managed settings block plugin hooks, there is no guard and
this command runs in hookless mode (see step 0).

## Who owns what

| Artifact | Owner step | Other steps must |
|---|---|---|
| guard liveness proof and hookless-mode diagnosis | step 0 of this command | `/dev-flow:init-hooks` step 0 is skipped — already done |
| `.codegraph/`, `.gitignore` entry | `/dev-flow:init-codegraph` | — |
| guidance file (AGENTS.md/CLAUDE.md) | `setup-rules` skill | — |
| `.claude/rules/<topic>.md` (inspection-derived) | `setup-rules` skill | — |
| `.claude/rules/<template>.md` (stack templates) | `/dev-flow:init-rules` | skip a template whose content `setup-rules` already covered; never restate the same convention in two files |
| `.claude/test-cmd`, `.claude/lint-cmd`, `.claude/test-cmd-retries` | `/dev-flow:init-hooks` | `setup-rules` skips its own hook-command step (already conditional in `SKILL.md:54-57`); `/dev-flow:init-rules` skips its offer-to-create step (already just an offer in `init-rules.md:12`) |
| shared `.claude/settings.json` permission rules (hookless mode only) | `/dev-flow:init-hooks` step 0, performed in step 0 here | — |

## Step 0 — prove the guard is live, once

Perform `/dev-flow:init-hooks`'s own step 0 as written there, with one exception noted below:
state the loaded plugin root and version once, then probe
`.claude/rules/devflow-guard-probe.md` end to end — never probe `AGENTS.md`,
never create an approval marker. If the probe is not blocked, follow that
step's diagnosis. Stop only where it says stop; otherwise continue in
hookless mode. Defer its permission-rules confirmation to step 0.5. Reference
that step; do not copy its text. The exception is deletion, and only when the
probe **was** blocked: never delete the probe file yourself in that case —
the guard blocks `rm`/`unlink`/`shred` on guarded paths too, with no
approve-and-retry path for a deletion, so any attempt just fails loudly or
tempts a guard-bypass, forbidden below. Instead tell the user the probe is a
throwaway file this command cannot delete for the same reason it just proved
the guard works, and give them `rm .claude/rules/devflow-guard-probe.md` to
remove it themselves. If the probe was not blocked, delete the probe yourself
— nothing guards it.

## Step 0.5 — announce the plan (the one and only up-front confirmation)

Detect the stack from manifests (`package.json`, `composer.json`,
`pyproject.toml`, `pom.xml`, etc.), mirroring `setup-rules` step 1. Run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/guidance-target.sh"` to find the
guidance target. Print the ordered step list below, the detected stack with
its evidence, and the guidance target, then get an explicit go-ahead before
any write. Ask the user for the stack only if detection finds nothing or is
genuinely ambiguous. If the guidance-target detector reports `ask-the-user`
(both `AGENTS.md`/`CLAUDE.md` present but unlinked, or neither exists), fold
that question into this same announcement — do not ask it separately later.

This is the **only** confirmation this command asks for of its own accord —
there is no per-step "shall I continue?" prompt after this go-ahead. The
guard stops in *If a step is blocked by the pre-write-guard* below are the
unavoidable exception, not an additional confirmation gate.

In hookless mode, the announcement also states the reason, the exact
permission rules proposed for the shared, committed `.claude/settings.json`
(or that permission rules are managed-only), that these apply to everyone who
pulls the repo once committed, and that step 2 will add a 'Quality gates'
section to the guidance file. Write the rules right after the go-ahead,
before step 1. This keeps it the only up-front confirmation.

## Step 1 — `/dev-flow:init-codegraph`

Run it as-is. It's first because it writes nothing guarded and can't stall
the sequence, and a fresh index improves the inspection later steps do
(`setup-rules` step 1, `init-hooks` step 1, `code-intel` for the rest).

## Step 2 — `setup-rules` skill, scoped to guidance + inspection rules

Invoke the `setup-rules` skill for the guidance file and path-scoped
`.claude/rules/<topic>.md` files only, telling it to skip its own
hook-command step — `/dev-flow:init-hooks` (step 3) owns
`.claude/test-cmd`/`.claude/lint-cmd` with more rigorous verification. This
runs before steps 3 and 4, which both read the guidance file first. In
hookless mode, tell the skill so, so that it adds its Quality gates section.

## Step 3 — `/dev-flow:init-hooks`

Run it, passing through any `retries=N`/`force-container`/`force-host`
argument given to this command, with its own step 0 skipped (done above). In
hookless mode, apply init-hooks' hookless branches in steps 4, 5 and 7
(always write `.claude/lint-cmd`, skip the retries step, and report
accordingly).

## Step 4 — `/dev-flow:init-rules <stack>` as a deduplicated top-up

Run it only for templates not already covered by `setup-rules` in step 2 —
never restate the same convention in two files. Skip this step entirely,
stating why, when no stack was detected or every candidate template is
already covered. It runs last as a top-up after the guidance file exists.

## If a step is blocked by the pre-write-guard

Stop. Show the hook's change verbatim, wait for an explicit yes that turn,
run the exact marker command it gave, then retry the same call unchanged and
continue. Never batch approvals, pre-create markers, split a change to get
past the gate, switch tools, delete and recreate a file, or create
`ALLOW-CLAUDE-MD-EDIT`.

In hookless mode there is no guard to block you. Before any change to an
existing `AGENTS.md`/`CLAUDE.md`/`.claude/rules/*.md`, show the complete
change in chat and wait for an explicit yes that turn, then make the call in
one piece. Claude Code's permission prompt (from the `ask` rules) follows
unless permission rules are managed-only. The same never-route-around rules
apply.

## Report

One line per step: done / skipped + why / blocked-then-approved / abandoned.
State hookless mode and its reason if it applied. List the files written,
then repeat the follow-ups `init-hooks.md` already prescribes at its own end:
commit advice for `.claude/test-cmd` and `.claude/lint-cmd`, plus a gitignore
reminder for `.claude/.stop-gate-state`, `.claude/stop-gate-giveup.log`, `.claude/.devflow-state.json` and
`.claude/.approved-writes/` — in hookless mode this is replaced by review the
`.claude/settings.json` diff before committing it.
