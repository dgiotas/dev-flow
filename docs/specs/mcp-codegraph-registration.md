# Spec: register CodeGraph as a plugin-scoped MCP server

Slug: `mcp-codegraph-registration`

## Goal

Make CodeGraph available as an MCP server to every project that installs the
`dev-flow` plugin, the same way `context7`, `semble` and `chrome-devtools`
already are — by adding it to the plugin's own `.mcp.json` rather than relying
on a per-machine global registration.

Secondary goal: stop `install.sh` from reporting success for a CodeGraph wiring
step that in fact writes nothing (root cause of "once installed, they are not
registered and not running").

## Non-goals

- Changing semble's invocation. It was verified healthy as-is (see below); the
  pilot-shell `$HOME/.pilot/bin/semble` form is vendored to that project and is
  not adopted here.
- Adding new hooks, skills, agents or commands.
- Auto-running `codegraph init` for consuming repos. Indexing stays an explicit
  per-repo user action.
- Anything beyond a patch version bump.

## The user's direct question, answered

> "Is an `.mcp.json` entry needed in order to make this available on projects?"

**Yes — for a server to ship *with the plugin*, a `plugins/dev-flow/.mcp.json`
entry is the mechanism, and it is discovered by convention.**

Evidence gathered in this repo:

1. `plugins/dev-flow/.claude-plugin/plugin.json` contains only `name`,
   `version`, `description`, `author`, `license` — **no** reference to
   `.mcp.json`. So the file is not declared; it is picked up by its conventional
   path/name.
2. The three servers listed in `plugins/dev-flow/.mcp.json:2-14` appear live in
   a session as `plugin:dev-flow:<server>`, and their tools are namespaced
   `mcp__plugin_dev-flow_<server>__<tool>` (e.g. semble's `search`,
   `find_related`).
3. `claude mcp list` run in this repo reports exactly:
   ```
   plugin:dev-flow:context7: npx -y @upstash/context7-mcp - ✔ Connected
   plugin:dev-flow:semble: uvx --from semble[mcp] semble - ✔ Connected
   plugin:dev-flow:chrome-devtools: npx chrome-devtools-mcp@latest - ✔ Connected
   ```
   and shows **no** `codegraph` entry at any scope on this machine.
4. Adding a `codegraph` entry to a scratch copy of the plugin and running
   `claude --plugin-dir <copy> mcp list` produced:
   ```
   plugin:dev-flow:codegraph: codegraph serve --mcp - ✔ Connected
   ```
   This is the decisive proof that the `.mcp.json` entry is both necessary and
   sufficient.

Caveat consistent with `README.md`'s posture: the *installed-from-marketplace*
path was not re-verified here; the above used `--plugin-dir`, which is the
repo's documented local-try mechanism (`README.md:35`).

## Current behaviour

- `plugins/dev-flow/.mcp.json` registers three servers: `context7`, `semble`,
  `chrome-devtools`. **`codegraph` is absent.**
- CodeGraph is instead handled per-machine by `install.sh:391-407`, which
  npm-installs the binary and then runs `codegraph install` at
  `install.sh:402`. That registration lands in `~/.claude.json`, outside the
  plugin, so it never travels with the plugin to a colleague.
- `README.md:116` states: `| MCP | context7, semble, chrome-devtools | Bundled
  in .mcp.json, start automatically. CodeGraph is set up by install.sh. |`
- `README.md:327` states the expected inventory includes "MCP servers 3".
- `README.md:23` already tells users to run `codegraph init` per repo and to add
  `.codegraph/` to `.gitignore`.

### Root cause of "not registered and not running"

`install.sh`'s `run_step` deliberately runs every command with stdin closed
(`out=$(cap "$t" "$@" </dev/null 2>&1)` — `install.sh:160`, documented at
`install.sh:150` as "runs the command with no stdin").

`codegraph install` prompts by default: `codegraph install --help` documents
`-t/--target` and `-l/--location` as "Default: prompt".

Verified in a sandboxed fake `HOME`:

- `codegraph install </dev/null` → **exit 0**, prints the agent-selection
  prompt, and writes **nothing** (`.mcpServers` stayed absent from
  `~/.claude.json`). Because it exits 0, `run_step` prints `[OK] wire codegraph
  into Claude Code` — a false success.
- `codegraph install -y </dev/null` → exit 0 and *does* write
  `{"codegraph":{"type":"stdio","command":"codegraph","args":["serve","--mcp"]}}`
  plus a `permissions.allow` entry `mcp__codegraph__*`.

So of the four candidate causes:

| Candidate | Verdict |
|---|---|
| (a) codegraph missing from `.mcp.json` | **True — fixed by this change.** |
| (b) colleagues never ran `marketplace update` + `/plugin update` | Real, but a pre-existing onboarding hazard (`AGENTS.md` Hazards). Addressed only by the version bump + release note, not by code. |
| (c) binaries not on PATH in a fresh env | Real secondary cause. `codegraph` requires the npm-installed binary on PATH. Addressed by a prerequisite warning, not a hard fix. |
| (d) plugin MCP servers need approval/enabling | Not observed. The three existing plugin servers connected with no approval step. |
| (e) **`codegraph install` silently no-ops under `install.sh`** | **True, newly found — fixed by this change.** |

(b) and (c) are documentation/onboarding concerns. (a) and (e) are the two the
plan actually fixes.

## Proposed design

### 1. Add codegraph to the plugin's `.mcp.json`

```json
"codegraph": {
  "type": "stdio",
  "command": "codegraph",
  "args": ["serve", "--mcp"],
  "env": { "CODEGRAPH_TELEMETRY": "0" }
}
```

Justification for each piece, from evidence:

- `codegraph serve --mcp` — `serve` is **not** in `codegraph --help`'s command
  list for v1.6.0 (it is a hidden command), so it was confirmed from the tool
  itself: `codegraph install --print-config claude` emits exactly
  `"command": "codegraph", "args": ["serve", "--mcp"]`. A live MCP
  `initialize` + `tools/list` handshake piped into `codegraph serve --mcp`
  returned `serverInfo {"name":"codegraph","version":"1.6.0"}` and the tool
  `codegraph_explore`.
- `"type": "stdio"` — matches codegraph's own `--print-config` output. The three
  existing entries omit it; including it here is harmless and was part of the
  verified-connected configuration.
- `env.CODEGRAPH_TELEMETRY=0` — codegraph prints on install that it "collects
  anonymous usage stats ... `CODEGRAPH_TELEMETRY=0` disables". Opting out by
  default is the conservative choice for a plugin pushed to colleagues. This
  matches the pilot-shell reference config.

Resulting tool namespace: `mcp__plugin_dev-flow_codegraph__codegraph_explore`.

Note on permissions: `codegraph install -y` writes an auto-allow entry for
`mcp__codegraph__*`, which does **not** match the plugin-scoped name. No
allowlist is added by this change; tool use follows normal prompting, which is
consistent with the other three bundled servers.

### 2. Remove the broken `codegraph install` step from `install.sh`

Once the plugin registers codegraph, `codegraph install` is both redundant and
actively harmful:

- it would create a **second**, global `codegraph` server alongside
  `plugin:dev-flow:codegraph`;
- as invoked, it silently does nothing while reporting `[OK]`.

Per the repo preference to delete dead code rather than soft-deprecate, the
`run_step ... codegraph install` line goes away. `install.sh` keeps installing
the **binary** (which the plugin server needs on PATH) and keeps the
`codegraph init` hint.

### 3. Prerequisite visibility

`install.sh:186-187` already warns when `node` or `uvx` is missing, naming the
affected servers. Add the matching one-line warning for `codegraph` so a fresh
environment learns why the server will not start. This is the minimal treatment
of cause (c); no new install machinery.

### 4. Indexing and `.gitignore`

CodeGraph's MCP server connects and lists its tool with or without an index —
`tools/list` returned exactly `codegraph_explore` in both states. The index only
affects whether results are useful:

- With no index, stderr warns `[CodeGraph MCP] No .codegraph/ at or above
  <cwd>: no default project, live sync disabled.`
- After `codegraph init -y`, a `codegraph_explore` call returned real symbols,
  blast radius and verbatim source.

So per-repo `codegraph init` remains required for usefulness and stays a
documented user action (`README.md:23`) — the plan does not automate it.

`codegraph init` creates `.codegraph/` containing its own
`.gitignore` (`*` / `!.gitignore`), so the database and logs are self-ignored —
but `git status` in a scratch project still showed `?? .codegraph/` because that
`.gitignore` is itself committable. This repo has no `.codegraph/` today; add
`.codegraph/` to this repo's `.gitignore` alongside the other local run-state
entries, matching the advice the README already gives colleagues.

### 5. Version bump

`plugins/dev-flow/.claude-plugin/plugin.json` `version`: `1.10.0` → `1.10.1`
(patch only, as requested). Without it, colleagues' `/plugin update` sees no
change and they keep running a plugin with no codegraph server — the exact
hazard called out in `AGENTS.md`.

## Data flow / API changes

No code APIs. One new stdio MCP server process per session, spawned by Claude
Code as `codegraph serve --mcp` with cwd at the project root; it locates the
nearest `.codegraph/` index at or above cwd, or accepts an explicit
`projectPath` argument per call.

## Risks and edge cases

| Risk | Mitigation |
|---|---|
| `codegraph` binary not on PATH → server fails to start. | Prerequisite warning in `install.sh`. Failure is contained to one server; the other three are unaffected. |
| Duplicate registration for anyone who previously ran `codegraph install -y` successfully: both `codegraph` and `plugin:dev-flow:codegraph` appear, doubling the tool surface. | Document `claude mcp remove codegraph` as the cleanup. `README.md:270-272` already documents that removal path. |
| CodeGraph is a Node-based npm tool; a slow or absent Node makes startup slow. | Same class of risk as the two existing `npx` servers; no new mitigation. |
| `serve` is an undocumented/hidden subcommand — a future codegraph release could rename it. | It is what codegraph's own `--print-config` emits, so it is the vendor-sanctioned form. Pin nothing; revisit if `claude mcp list` shows a failure. |
| Consuming repo has no index → tool returns nothing useful and looks broken. | README keeps the `codegraph init` per-repo instruction; troubleshooting line notes the stderr warning. |

## Migration and rollback

Migration: none required beyond `claude plugin marketplace update` +
`/plugin update` and a restart. Users who had a working global codegraph should
run `claude mcp remove codegraph` to avoid the duplicate.

Rollback: revert the `.mcp.json`, `install.sh`, `README.md`, `.gitignore` and
`plugin.json` changes in one commit. No state is migrated, nothing is deleted on
a user's machine, so revert is total.

## Test / verification strategy

This repo has no CI and no package manager; `bash .claude/test-cmd` (jq JSON
validation + `bash -n`) is the suite and it **does** already cover
`.mcp.json` — its `find . -name '*.json'` loop validates every JSON file in the
repo, so a malformed edit is caught by the existing gate. Baseline confirmed:
`bash .claude/test-cmd` exits 0 today.

Beyond that, verification is behavioural and was rehearsed for real:

- `claude --plugin-dir <plugin> mcp list` → expect a
  `plugin:dev-flow:codegraph: codegraph serve --mcp - ✔ Connected` line.
- A raw MCP handshake piped into `codegraph serve --mcp` → expect
  `serverInfo.name == "codegraph"` and tool `codegraph_explore`.
- The same handshake into `uvx --from 'semble[mcp]' semble` → expect
  `serverInfo {"name":"semble","version":"1.30.0"}` and tools `search`,
  `find_related`. **Semble is healthy; no change is warranted.**

## Open questions

1. **Should `CODEGRAPH_TELEMETRY=0` be set?** The spec proposes yes (privacy-safe
   default, matches the reference config), but it silently overrides a colleague
   who deliberately opted in via `codegraph telemetry on`. Confirm this is
   wanted, or drop the `env` block to match codegraph's own `--print-config`
   exactly.
2. **Is removing `codegraph install` from `install.sh` in scope for a patch
   bump?** It is the fix for the false-success bug and prevents a duplicate
   server, but it is a behaviour change to the installer rather than a pure
   config addition. The alternative minimal path is to leave `install.sh` alone
   and accept the duplicate + the misleading `[OK]`. The plan assumes removal;
   say so if you want it deferred to its own change.
3. **Should `chrome-devtools`/`context7` also gain `"type": "stdio"`** for
   consistency, now that one entry has it? Cosmetic; not included.
