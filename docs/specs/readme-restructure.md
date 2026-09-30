# Spec: README restructure + one-liner install, version pinning, uninstall script

## Goal

1. Restructure `README.md` to follow the section layout of
   [maxritter/pilot-shell's README](https://github.com/maxritter/pilot-shell/blob/main/README.md):
   centred header, a short "Why" explanation, `Getting Started` (Prerequisites /
   Installation / First Steps), `Ways of Working`, a **main-commands table**, a
   **second table** for everything else, then `Documentation`, `Changelog`,
   `Contributing`.
2. Offer the same install surface as pilot-shell:
   - one-liner: `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh | bash`
   - specific version: `DEV_FLOW_VERSION=1.12.0` before the same one-liner
   - uninstall one-liner: `curl -fsSL https://raw.githubusercontent.com/dgiotas/dev-flow/main/uninstall.sh | bash`,
     with opt-in flags for removing more than dev-flow.
3. Keep every important existing fact (guard, stop gate, per-repo config files,
   containerised toolchains, MCP setup, model routing, troubleshooting, known limits),
   and keep every "unverified" caveat worded as a caveat.

## Non-goals

- No logo, no badges, no website (pilot-shell's "Visual Engineering" and "Console"
  sections have no counterpart here; drop them).
- No `--purge-data` equivalent: uninstall never deletes per-repo files, never edits
  `~/.claude/settings.json`, and never runs claude-mem's uninstaller. Those stay manual
  README steps (they are unverified and/or touch user data).
- No rollback engine, no dev-container support in the installer.
- No change to any plugin component (commands, skills, agents, hooks). Only `install.sh`,
  a new `uninstall.sh`, `README.md`, `AGENTS.md` (layout line) and the version bump change.
- No backfilled git tags for versions before the one that ships this change (see Open
  questions).

## Current behaviour (verified)

### Repo / hosting
- Remote is `git@github.com:dgiotas/dev-flow.git`. The repo is **public**: an
  unauthenticated `https://api.github.com/repos/dgiotas/dev-flow` returns 200, and so
  does `https://raw.githubusercontent.com/dgiotas/dev-flow/main/install.sh`. So a
  `curl | bash` one-liner works today as far as fetching is concerned.
- There are **no git tags** (`git tag -l` and `git ls-remote --tags origin` are empty).
- There is no `LICENSE` file; `plugins/dev-flow/.claude-plugin/plugin.json:8` declares
  `"license": "MIT"`.
- README still says "private" and tells users to `git clone <this repo>`
  (`README.md:1`, `README.md:8`, `README.md:272`).

### install.sh assumes it runs from a clone
- `install.sh:58`: `SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"`.
  Reproduced:
  - `curl … | bash`: `BASH_SOURCE[0]` is unset, and under `set -u` (`install.sh:21`) the
    substitution prints `BASH_SOURCE[0]: unbound variable`. `SRC` then silently becomes
    the caller's **current directory**, which is then passed to
    `claude plugin marketplace add`. So the one-liner is broken today.
  - `bash <(curl …)`: `BASH_SOURCE[0]` is `/dev/fd/N`, so `SRC=/dev/fd`, also wrong.
- The whole script runs at top level, so a truncated download under `curl | bash` would
  run a partial script.
- Commands the script runs get `</dev/null` (`install.sh:160`, `:198-199`), so they do not
  swallow the piped script from stdin. Interactive mode requires `[ -t 0 ]`
  (`install.sh:61`), so under `curl | bash` the checklist is skipped and the defaults
  apply (Superpowers + CodeGraph on, memory/powerline off). Under `bash <(curl …)`, stdin
  is still the terminal, so the checklist works.
- `--dry-run` prints the Plan, including `dev-flow  marketplace dev-flow-marketplace  <- $SRC`
  (`install.sh:328`), then exits 0 (`install.sh:364-368`). This is the behavioural hook
  for the tests.

### Version pinning in Claude Code (verified live, isolated with `CLAUDE_CONFIG_DIR`)
- `claude plugin marketplace add 'dgiotas/dev-flow#main'` succeeds. `marketplace list`
  then shows `Source: GitHub (dgiotas/dev-flow@main)`. The docs
  (code.claude.com/docs/en/plugins/marketplace-reference, "Marketplace sources") list
  `owner/repo`, `owner/repo@ref` and `owner/repo#ref` as valid inputs, where ref is a
  **branch or tag**.
- A bare commit SHA as ref fails: `fatal: Remote branch a9031c2 not found`. So pinning
  needs **tags**.
- A nonexistent ref fails loudly with `Remote branch <ref> not found`, and nothing is
  registered.
- Re-adding an already-registered marketplace with a **different** source/ref is
  refused: `Cannot add marketplace "dev-flow-marketplace": its network source differs from
  the one declared for it in settings …`. Switching version (or switching from a
  clone-path install to the GitHub one-liner) therefore needs a remove first.
- The marketplace entry uses a relative source (`.claude-plugin/marketplace.json:9`,
  `"./plugins/dev-flow"`), so pinning the marketplace clone to a tag pins the plugin too.
  Installing from the `#main`-pinned marketplace reported `Version: 1.11.0`.
- `claude plugin tag plugins/dev-flow --dry-run` ⇒ `would create tag dev-flow--v1.11.0`
  (format `{name}--v{version}`). It validates plugin.json against the marketplace entry
  and supports `--push`. Running it from the repo root without a path fails ("No plugin
  manifest found"). The path argument is required.
- `claude plugin uninstall <id>` and `claude plugin marketplace remove <name>` work with
  `</dev/null`. Both exit **1** when the target is absent ("not found"). Per the docs,
  `marketplace remove` also uninstalls that marketplace's plugins.

### README today
- 370 lines, 20 `##` sections, no `<details>`, no one-liner, uninstall is a manual
  6-step block (`README.md:274-329`), and the component table (`README.md:101-126`)
  mixes the main workflow commands with everything else.
- Unverified-caveat phrases present (the acceptance check must not lose them):
  `README.md:32` "not yet run end to end", `:153` "Not yet observed", `:256` "haven't
  verified", `:329` "not verified … unverified", `:360` "not verified", `:362` "not yet
  inside a live Claude Code stop-hook cycle", `:364` "unverified here".

## Proposed design

### A. `install.sh` (three small changes, plus usage text)

1. **Default source resolution** (replaces `install.sh:58`):
   ```bash
   REPO="dgiotas/dev-flow"
   here=""
   script="${BASH_SOURCE[0]:-}"
   if [ -n "$script" ] && [ -f "$(dirname "$script")/.claude-plugin/marketplace.json" ]; then
     here="$(cd "$(dirname "$script")" && pwd)"
   fi
   ```
   - explicit positional arg ⇒ used as-is (unchanged behaviour)
   - run from a clone ⇒ the clone dir (unchanged behaviour)
   - piped / process-substituted ⇒ `dgiotas/dev-flow` (new)
2. **Version pin** via env var `DEV_FLOW_VERSION` (accepts `1.12.0` or `v1.12.0`):
   - must match `^[0-9]+\.[0-9]+\.[0-9]+$` after stripping a leading `v`. Otherwise
     exit 2 with a message.
   - source becomes `${SRC_ARG:-$REPO}#dev-flow--v<ver>` (the `claude plugin tag`
     format). A clone dir is ignored when a version is requested, because pinning is a
     GitHub feature.
   - an explicit positional arg that is a local directory, combined with
     `DEV_FLOW_VERSION`, exits 2: "check out tag dev-flow--v<ver> in your clone instead".
   - The env var (not a flag) mirrors pilot-shell's `export VERSION=…` and works with a
     bare `curl | bash`. It is namespaced because a plain `VERSION` is commonly set by
     other tooling (see Open questions).
3. **Truncation guard**: wrap everything after the header comment in `{ … }` (one line
   before `set -u`, one line at EOF). Bash parses a brace group completely before running
   it, so a truncated download fails with a syntax error and runs nothing. This is a
   two-line diff with no re-indent.
4. **Source-conflict hint**: when the `add marketplace dev-flow` step fails **and**
   `has_marketplace dev-flow-marketplace` is true, print two `note` lines saying the
   marketplace is already registered from a different source or version, and to run
   `uninstall.sh` first and then re-run. The installer does not remove anything itself
   (non-destructive posture).
5. `usage()` and the header comment document `DEV_FLOW_VERSION` and the one-liner forms
   (`… | bash -s -- --with-memory`, `bash <(curl …)` for the interactive checklist).

### B. New `uninstall.sh` (repo root, self-contained; `curl | bash` cannot source siblings)

```
Usage: bash uninstall.sh [--remove-tools] [--remove-superpowers] [--dry-run] [-h|--help]
  (default)             uninstall dev-flow@dev-flow-marketplace, remove dev-flow-marketplace
  --remove-tools        also: claude-powerline plugin + marketplace; npm uninstall -g @colbymchenry/codegraph
  --remove-superpowers  also: superpowers plugin + superpowers-marketplace
  --dry-run             print what would run, run nothing, exit 0
```
- Wrapped in `{ … }` like install.sh. `set -u`. `GIT_TERMINAL_PROMPT=0`. Every command
  gets `</dev/null`. Plain output, no colour or progress bar (small by design).
- Presence detection reuses install.sh's idiom (`install.sh:198-201`): cache
  `claude plugin list` / `claude plugin marketplace list` once, match with
  `awk '{print $NF}' | grep -qxF`. An absent item prints `[skip] <x> not installed`
  and is not attempted, which avoids the verified exit-1-when-absent.
- Order per item: plugin uninstall, then marketplace remove (same as `README.md:286-302`).
- CodeGraph binary is removed only when `codegraph` and `npm` are both on PATH.
- Prints, at the end, the manual follow-ups it deliberately does not do: claude-mem
  (`npx claude-mem uninstall`), a legacy global `codegraph` MCP entry
  (`claude mcp remove codegraph`), `statusLine` in `~/.claude/settings.json`, and per-repo
  files. Each points to README "Uninstalling".
- Exit 0 if every attempted step succeeded, 1 otherwise.
- Requires `claude`. Exits 1 with a message if missing. Does not need `jq`.

### C. README layout (target outline; `##` order is asserted by the check script)

```
<div align="center"> # dev-flow / ### tagline / one sentence / bold 3-part line </div>
## Why dev-flow                         (brief explanation, 5–8 lines)
## Getting Started
### Prerequisites
### Installation                        one-liner; specific version; from a clone; manual /plugin
    <details> Installer flags
    <details> What the installer does   (sections 1–6 of install.sh)
    <details> Switching version / downgrading
    <details> Uninstalling              (uninstall.sh + flags, then the manual leftovers)
    <details> Try without installing    (--plugin-dir)
### First Steps                         restart, verify, /dev-flow:onboard (+ manual sequence)
## Ways of Working                      table: Path | What it adds
## Workflows                            MAIN table: Command | Use it when | What it does
## Other Commands, Skills and Agents    SECOND table: Name | Kind | Purpose
## Documentation
### Pre-write guard
### AGENTS.md or CLAUDE.md
### Stop gate
### Per-repo config files
### Containerised toolchains
### MCP servers
### Model routing                       (absorbs the `ok build` comparison table)
### Memory (optional)
### Status line (optional)
### Updating
### Troubleshooting
### Known limits
## Changelog                            points at tags dev-flow--v* on GitHub
## Contributing                         release steps (bump, test-cmd, claude plugin tag)
```
- **Main table** (Workflows) rows: `/dev-flow:spec <feature>`, `ok build` (reply),
  `/dev-flow:build <slug>`, `/dev-flow:onboard`.
- **Second table** rows: `/dev-flow:init-hooks`, `/dev-flow:init-rules <stack>`,
  `/dev-flow:init-codegraph`, the 3 agents, the 9 skills, the 3 hooks, and one MCP row.
  Main-table commands must not be repeated here.
- **Ways of Working** rows: "Plain request" (skills auto-trigger, from `README.md:244`),
  "Spec, then `ok build`", "Spec, then `/dev-flow:build`" (from `README.md:246-258`).
- **Content sources** (move, condense lightly, do not rephrase caveats): Prerequisites
  ← `:43`; Installation ← `:5-15,34-41` + new; Uninstalling ← `:274-329`; First Steps ←
  `:17-32`; Documentation subsections ← `:45-99,128-234,260-272,331-370`.
- **Wording fixes**: title drops "(v1.11)" (a stale-prone version); "private" becomes
  "hosted publicly on GitHub"; `README.md:272` "Host the marketplace in a private git
  repo…" is replaced by the Updating/Contributing text. The model-routing and `ok build`
  caveats stay caveats.
- **Updating** must state (all verified above): `claude plugin marketplace update
  dev-flow-marketplace` + `claude plugin update dev-flow@dev-flow-marketplace` +
  `/reload-plugins`. A pinned install stays on its tag. Changing version or source needs
  `uninstall.sh` and then a reinstall, because re-adding with a different ref is refused.

## Data flow (install)

```
curl … | [DEV_FLOW_VERSION=x.y.z] bash [-s -- flags]
  → bash parses whole { } group (truncation guard)
  → SRC = arg | clone dir | dgiotas/dev-flow ; + "#dev-flow--vX.Y.Z" if pinned
  → prerequisites → plan (shows "<- $SRC") → [--dry-run exits]
  → claude plugin marketplace add "$SRC"   (fails loudly on unknown tag / source conflict → hint)
  → claude plugin install -y dev-flow@dev-flow-marketplace
```

## Risks and edge cases

- **Tag must exist before a pinned install works.** Only versions tagged with `claude
  plugin tag` from this release on are installable by version. An unknown version gives
  git's `Remote branch dev-flow--vX not found`, surfaced by `run_step`'s failure tail
  (`install.sh:178`). README states "available from 1.12.0".
- **`raw.githubusercontent.com/…/main/install.sh` only changes after merge to main.**
  Tests before merge pipe the local file (`cat install.sh | bash -s -- …`).
- **Existing colleagues installed from a clone path.** The one-liner's `marketplace add`
  is refused because the source differs. The hint in A.4 plus README "Updating" cover
  this. Nothing is auto-removed.
- **Repo visibility.** The one-liner depends on the repo staying public. If it goes
  private, raw URLs 404 and the README's clone path is the fallback (see Open questions).
- **`uninstall.sh` default removes only dev-flow.** Superpowers may have been installed
  independently, so it is behind its own flag.
- **Pinned + `claude plugin marketplace update`** re-fetches the same tag. That is
  expected, and documented.
- **The truncation guard** changes nothing in behaviour. `bash -n` (test-cmd) still
  parses it.

## Migration / rollback

- Clone-based installs keep working unchanged (`bash install.sh` from a clone still uses
  the clone dir).
- Rollback = revert the commit(s). A pushed tag can be deleted with
  `git push origin :refs/tags/dev-flow--v1.12.0` (user action).
- Release: bump `plugins/dev-flow/.claude-plugin/plugin.json` to `1.12.0`, merge, then
  the **user** runs `claude plugin tag plugins/dev-flow --push` on main (pushing needs the
  user's approval per `AGENTS.md`).

## Open questions (answer before build; defaults in brackets are what the plan assumes)

1. **Will the repo stay public?** The one-liner depends on it. [Yes, public.]
2. **Env var name**: `DEV_FLOW_VERSION` (namespaced) or pilot-shell's exact `VERSION`?
   [`DEV_FLOW_VERSION`]
3. **Tag format**: `dev-flow--v1.12.0` (what `claude plugin tag` creates and validates)
   or plain `v1.12.0`? [`dev-flow--v1.12.0`, with the user-facing value just `1.12.0`]
4. **Backfill tags** for 1.11.0 and earlier, so they are installable by version? [No.
   Pinning starts at 1.12.0.]
5. **Uninstall shape**: separate `uninstall.sh` with `--remove-tools` /
   `--remove-superpowers`, default removing only dev-flow? Or `install.sh --uninstall`,
   or README-only? [Separate `uninstall.sh`, as specified]
6. **License section**: there is no `LICENSE` file, only `"license": "MIT"` in
   plugin.json. Add a `LICENSE` file plus a `## License` section, or omit the section?
   [Omit. Adding a license is a legal choice for the owner.]
7. **Changelog section**: point at GitHub tags (empty until the first release tag), or
   omit? [Include, pointing at `https://github.com/dgiotas/dev-flow/tags`]
8. **Badges / logo**: pilot-shell has both. [None]
