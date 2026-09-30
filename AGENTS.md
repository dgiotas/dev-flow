# dev-flow

A private Claude Code plugin marketplace repo: one plugin (`dev-flow`) providing a spec-then-build workflow, quality-gate hooks, a pre-write guard for guidance files, and nine dev skills. Consumed by other repos via `claude plugin marketplace add` / `claude plugin install`. There is no app code here — the repo *is* the bash/JSON/Markdown plugin source, plus a colleague-facing `README.md` that documents everything in depth. Read that first; this file is the short version for an agent editing the plugin itself.

## Commands

| Task | Command |
|---|---|
| Validate the repo (JSON + shell syntax) | `bash .claude/test-cmd` |
| Check one file after an edit | `bash .claude/lint-cmd <repo-relative-path>` |
| Try the plugin locally without installing | `claude --plugin-dir ./plugins/dev-flow` |
| Release a change | bump `version` in `plugins/dev-flow/.claude-plugin/plugin.json`, push, then `claude plugin tag plugins/dev-flow --push` on main; colleagues run `claude plugin marketplace update` then `/plugin update`, then `/reload-plugins` or a new session |

No package manager, no build step, no CI config in this repo (verified: no `.github/`, no `package.json`). `.claude/test-cmd` — jq JSON validation plus `bash -n` syntax checks across the repo — is the closest thing to a test suite here.

## Layout

- `.claude-plugin/marketplace.json` — marketplace manifest, lists the one plugin at `./plugins/dev-flow`.
- `plugins/dev-flow/.claude-plugin/plugin.json` — plugin manifest; `version` here is what `/plugin update` picks up.
- `plugins/dev-flow/agents/*.md` — subagents (`implementer`, `reviewer`, `spec-architect`); frontmatter `model:` pins the model per stage.
- `plugins/dev-flow/commands/*.md` — slash commands (`/dev-flow:spec`, `/dev-flow:build`, `/dev-flow:init-hooks`, `/dev-flow:init-rules`, `/dev-flow:init-codegraph`, `/dev-flow:onboard`); same `model:` frontmatter.
- `plugins/dev-flow/skills/*/SKILL.md` — the nine dev skills; each is one directory with one `SKILL.md`.
- `plugins/dev-flow/hooks/hooks.json` — wires `PreToolUse` (pre-write-guard), `PostToolUse` (post-edit-check) and `Stop` (stop-gate) to scripts in `hooks/scripts/`.
- `plugins/dev-flow/hooks/scripts/*.sh` — the three hooks, pure bash + jq.
- `plugins/dev-flow/scripts/guidance-target.sh` — detects whether `AGENTS.md` or `CLAUDE.md` is canonical; used by `setup-rules` and `init-rules`.
- `plugins/dev-flow/templates/` — stack rule templates (`rules/*.md`) and containerised hook-command examples (`*.docker.example`).
- `install.sh` — colleague onboarding script (installs Superpowers + dev-flow, optional memory/powerline); on a TTY it shows an interactive component checklist and coloured output, degrading to plain non-interactive output under `-y`/CI/piped input/`--no-color`; defaults to the dgiotas/dev-flow GitHub source when piped (curl | bash); DEV_FLOW_VERSION pins a dev-flow--v<ver> tag.
- `uninstall.sh` — removes dev-flow (opt-in `--remove-tools` / `--remove-superpowers`); `curl | bash`-safe like `install.sh`.

## Conventions

- Hook scripts follow a strict stdin-JSON-in / exit-code-out contract — see `.claude/rules/hook-scripts.md` before touching `hooks/scripts/*.sh`.
- Skill `description` frontmatter drives auto-invocation, not just documentation — see `.claude/rules/skills.md` before touching `skills/*/SKILL.md`.
- Agent/command frontmatter `model:` (`opus`/`sonnet`/`haiku`/a model id/`inherit`) pins the model for that stage regardless of what model is running the parent session — this is the mechanism behind the Opus-plans/Sonnet-builds routing described in the README.
- `AGENTS.md`, `CLAUDE.md` and `.claude/rules/*.md` are gated by `pre-write-guard.sh`: any `Write`/`Edit`/`MultiEdit` to an *existing* one of these is blocked until the user approves the exact diff and a single-use marker is created. This applies here too.
- `CLAUDE.md` in this repo is a symlink to `AGENTS.md` — never edit `CLAUDE.md` directly; the guard refuses it outright with no approve-and-retry path. Edit `AGENTS.md`.
- Keep new skills/agents/commands consistent with the existing "report-only unless told to fix" / "never push, merge or force-push without approval" posture documented in `README.md` — don't add a skill or hook that acts destructively by default.
- Never add AI-attribution trailers to commit messages or PR descriptions in this repo — no `Co-Authored-By: Claude ...`, no `🤖 Generated with Claude Code`, no similar line. Omit them entirely, even if a harness default would otherwise add one.

## Hazards

- No CI: nothing runs automatically on push. `.claude/test-cmd` only runs inside a Claude Code session, via the stop-gate hook.
- Bumping `plugins/dev-flow/.claude-plugin/plugin.json` `version` is the release mechanism — forgetting it means colleagues' `/plugin update` sees no change. Non-Anthropic marketplaces (a local directory, or a non-Anthropic GitHub repo) don't auto-update, so an unbumped or un-updated plugin means colleagues keep running the copy they installed on day one, and its hooks silently behave like the old version.
- If this repo ever runs the plugin's own hooks against itself, `pre-write-guard.sh`'s approval markers live under `.claude/.approved-writes/`, and the stop gate writes `.claude/.stop-gate-state` / `.claude/stop-gate-giveup.log` — keep those gitignored, they're local run state, not content to commit.
- `README.md` marks several claims "not yet verified" / "unverified here" (e.g. whether command `model:` frontmatter actually pins the model live, hooks firing inside a real session). Don't restate those as settled fact.
