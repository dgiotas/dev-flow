# Plan: register CodeGraph as a plugin-scoped MCP server

Spec: `docs/specs/mcp-codegraph-registration.md`
Slug: `mcp-codegraph-registration`

## Before you start

Answer **Open question 1 and 2** in the spec first (telemetry `env` block; and
whether Task 4's `install.sh` change is in scope). Tasks 1-3 and 5-8 do not
depend on those answers. If Q2 is answered "defer", skip Task 4 and adjust
Task 6's README wording accordingly.

All paths are relative to the repo root
`/Users/dgiotas/Projects/personal/dev-flow`.

`codegraph`, `uvx`, `jq` and `claude` must be on PATH. On this machine
`codegraph` is at `/opt/homebrew/bin/codegraph` (v1.6.0) and `uvx` at
`~/.local/bin/uvx`. Prefix commands with
`export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"` if a step reports
`command not found`.

Note: `CLAUDE.md` is a symlink to `AGENTS.md`. No task here touches either, nor
`.claude/rules/*.md`, so the pre-write guard is not involved.

---

## Task 1 — Capture the failing baseline (evidence first)

**Files**: none (read-only). Optionally record output under
`/tmp` scratch; do not commit it.

**Evidence to capture before any edit** — run all four and paste the output into
the commit message body or the PR description:

```bash
bash .claude/test-cmd; echo "test-cmd exit=$?"
jq -r '.mcpServers|keys[]' plugins/dev-flow/.mcp.json
claude mcp list 2>&1 | grep -E '^plugin:dev-flow:'
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json
```

**Expected (this is the "failing" state)**:
- `test-cmd exit=0`
- keys: `chrome-devtools`, `context7`, `semble` — **no `codegraph`**
- `claude mcp list` shows three `plugin:dev-flow:` lines (context7, semble,
  chrome-devtools), all `✔ Connected`, and **no codegraph line at any scope**
- version `1.10.0`

**Verify**: the four commands above produce exactly that. If `codegraph` already
appears in the keys or in `claude mcp list`, stop — the premise has changed;
re-read the spec.

**Depends on**: none.

---

## Task 2 — Confirm both server binaries answer an MCP handshake

**Files**: none (read-only).

**Change**: none. This is the pre-flight proof that the commands we are about to
put in `.mcp.json` actually work on this machine.

**Verify** — run both; both were run for real and produced the stated output:

```bash
HS='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"p","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# codegraph
printf '%s\n' "$HS" | codegraph serve --mcp 2>/dev/null \
  | jq -r 'select(.id==1)|.result.serverInfo.name, select(.id==2)|.result.tools[].name'

# semble (first run downloads via uvx; can take a couple of minutes)
printf '%s\n' "$HS" | uvx --from 'semble[mcp]' semble 2>/dev/null \
  | jq -r 'select(.id==1)|.result.serverInfo.name, select(.id==2)|.result.tools[].name'
```

**Expected**:
- codegraph → `codegraph` then `codegraph_explore`
- semble → `semble` then `search` then `find_related`

Also confirm the flag spelling is vendor-sanctioned, not guessed:

```bash
codegraph install --print-config claude
```

**Expected**: a JSON snippet containing `"command": "codegraph"` and
`"args": ["serve", "--mcp"]`. (`serve` is a hidden subcommand — it is absent
from `codegraph --help`, so this is the authoritative check.)

**Outcome**: semble is healthy → **make no change to the semble entry.**

**Depends on**: 1.

---

## Task 3 — Add the `codegraph` entry to the plugin's `.mcp.json`

**Files**: `plugins/dev-flow/.mcp.json`

**Change**: add one `codegraph` key inside `mcpServers`, leaving the existing
three entries byte-for-byte unchanged. Place it after `semble` (alphabetical
order is not used in this file; insertion order is cosmetic).

```json
"codegraph": {
  "type": "stdio",
  "command": "codegraph",
  "args": ["serve", "--mcp"],
  "env": { "CODEGRAPH_TELEMETRY": "0" }
}
```

Match the file's existing 2-space indentation and its style of keeping short
`args` arrays on one line. Drop the `env` block if Open question 1 was answered
"no telemetry override".

**Verify**:

```bash
bash .claude/lint-cmd plugins/dev-flow/.mcp.json && echo "lint OK"
jq -r '.mcpServers|keys[]' plugins/dev-flow/.mcp.json
jq -c '.mcpServers.codegraph' plugins/dev-flow/.mcp.json
bash .claude/test-cmd; echo "test-cmd exit=$?"
```

**Expected**: `lint OK`; keys now list four entries including `codegraph`;
the `jq -c` line prints the object above; `test-cmd exit=0`.

**Depends on**: 2.

---

## Task 4 — Remove the silently-failing `codegraph install` step from `install.sh`

Skip this task if Open question 2 was answered "defer".

**Files**: `install.sh`

**Evidence first** — reproduce the false success in a sandboxed `HOME` so
nothing on the real machine is touched:

```bash
FH=$(mktemp -d)/h; mkdir -p "$FH/.claude"; echo '{}' > "$FH/.claude.json"
HOME="$FH" codegraph install </dev/null >/dev/null 2>&1; echo "exit=$?"
jq -c '.mcpServers // "none"' "$FH/.claude.json"
```

**Expected**: `exit=0` but `"none"` — exit 0 with nothing written. That is why
`run_step` (which closes stdin at `install.sh:160`) prints
`[OK] wire codegraph into Claude Code` while registering nothing.

**Change**: in the CodeGraph section (`install.sh:391-407`), delete the
`run_step 120 "wire codegraph into Claude Code" codegraph install` line
(`install.sh:402`). Keep the surrounding `if command -v codegraph` block only if
it still guards the `note` line; otherwise collapse it so the `note` about
`codegraph init` is still printed. The npm binary install
(`install.sh:398-399`) stays — the plugin server needs the binary on PATH.

Then fix the two places that counted that step, so the progress bar total and
the dry-run preview stay truthful:
- the `STEP_TOTAL` arithmetic for codegraph around `install.sh:301-307`
- the dry-run preview lines around `install.sh:335-343`, which currently print
  `codegraph install   (registers an MCP server in ~/.claude.json)` — remove
  those two preview lines, since that is no longer what happens.

**Verify**:

```bash
bash .claude/lint-cmd install.sh && echo "syntax OK"
grep -n 'codegraph install' install.sh   # expect: no output
bash install.sh --dry-run --no-color 2>&1 | grep -i -A2 codegraph
bash .claude/test-cmd; echo "test-cmd exit=$?"
```

**Expected**: `syntax OK`; the `grep -n` finds nothing; the dry-run output
mentions only the npm install (and `[have]`/`[skip]` state), never
`codegraph install`; `test-cmd exit=0`.

`--dry-run` must not modify anything — confirm with `git status --porcelain`
afterwards (expect only your intended edits).

**Depends on**: 3.

---

## Task 5 — Add a `codegraph` prerequisite warning to `install.sh`

**Files**: `install.sh`

**Evidence first**:

```bash
bash install.sh --dry-run --no-color 2>&1 | sed -n '/Prerequisites/,/^$/p'
```

**Expected before the change**: warnings exist for `node` and `uvx` naming the
servers they affect (`install.sh:186-187`), but nothing mentions `codegraph`.

**Change**: add one line to the Prerequisites section, immediately after the
`uvx` line (`install.sh:187`), following the exact existing idiom
`command -v X >/dev/null && ok "..." || warn "..."`:

- on success: `ok "codegraph"`
- on failure: a `warn` saying codegraph was not found, that the bundled CodeGraph
  MCP server will not start, and that section 3 installs it (or
  `npm install -g @colbymchenry/codegraph`).

Keep it to a single line, consistent in tone and length with its neighbours. Do
not make it a `bad`/`MISSING` — CodeGraph is optional, exactly like node and uv.

**Verify**:

```bash
bash .claude/lint-cmd install.sh && echo "syntax OK"
bash install.sh --dry-run --no-color 2>&1 | sed -n '/Prerequisites/,/^$/p' | grep -i codegraph
bash .claude/test-cmd; echo "test-cmd exit=$?"
```

**Expected**: `syntax OK`; the Prerequisites block now contains a codegraph line
(`[OK] codegraph` on this machine, since the binary is present);
`test-cmd exit=0`.

**Depends on**: 4 (same file region; sequence them to avoid conflicts).

---

## Task 6 — Update `README.md`

**Files**: `README.md`

**Evidence first**:

```bash
grep -n 'MCP | context7' README.md
grep -n 'MCP servers 3' README.md
grep -n 'only for the Context7 / DevTools / Semble MCP servers' README.md
```

**Expected**: each finds exactly one line (currently `README.md:116`, `:327`,
`:35`) — these are the three claims the change falsifies.

**Change** — four edits, wording kept minimal:

1. `README.md:116` — the inventory table row. Change the server list to
   `context7, semble, chrome-devtools, codegraph` and replace
   "CodeGraph is set up by `install.sh`." with a statement that all four are
   bundled in `.mcp.json` and start automatically, that CodeGraph additionally
   needs its binary on PATH (`install.sh` installs it), and that results need a
   per-repo `codegraph init`.
2. `README.md:327` — change `MCP servers 3` to `MCP servers 4`.
3. `README.md:35` — the Optional prerequisites sentence. `npm (CodeGraph)`
   should now read as required for the bundled CodeGraph MCP server rather than
   an optional side install.
4. `README.md:9` and `README.md:15` — `install.sh` no longer *registers*
   CodeGraph, it installs the binary. Adjust only if the existing wording
   implies registration; `:9` says "(+ optional CodeGraph)" which stays accurate.

Also add one troubleshooting line near `README.md:334`: if CodeGraph tools return
nothing, the repo has no index — run `codegraph init`; and if a duplicate
`codegraph` server appears alongside `plugin:dev-flow:codegraph` from a previous
global install, `claude mcp remove codegraph`.

Do **not** promote any of README's existing "not yet verified" claims to settled
fact. Where you state that the four servers start automatically, scope it the way
the rest of the README does.

**Verify**:

```bash
grep -n 'MCP servers 4' README.md
grep -n 'codegraph' README.md | head -20
bash .claude/test-cmd; echo "test-cmd exit=$?"
```

**Expected**: `MCP servers 4` found; the inventory row lists codegraph;
`test-cmd exit=0`. (`test-cmd` does not lint Markdown, so this only guards
against collateral damage to JSON/shell.)

**Depends on**: 3.

---

## Task 7 — Gitignore `.codegraph/` in this repo

**Files**: `.gitignore`

**Evidence first**:

```bash
cat .gitignore
```

**Expected**: three entries, all local run state
(`.claude/.approved-writes/`, `.claude/.stop-gate-state`,
`.claude/stop-gate-giveup.log`) — no `.codegraph/`.

**Change**: append `.codegraph/` as a fourth line. Rationale: anyone running
`codegraph init` here (now likely, since the plugin ships the server) creates
`.codegraph/`. It writes its own inner `.gitignore` (`*` / `!.gitignore`), so its
database and logs self-ignore, but `git status` still surfaces `?? .codegraph/`
— this keeps local index state out of the repo, matching the advice
`README.md:23` already gives colleagues.

**Verify**:

```bash
cat .gitignore
git check-ignore -v .codegraph/ && echo "ignored"
git status --porcelain
```

**Expected**: `.codegraph/` present in the file; `git check-ignore` reports the
matching rule and prints `ignored`; `git status` shows only your intended edits.

**Depends on**: none (independent; can run any time).

---

## Task 8 — Patch version bump

**Files**: `plugins/dev-flow/.claude-plugin/plugin.json`

**Evidence first**:

```bash
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json
```

**Expected**: `1.10.0`.

**Change**: set `version` to `1.10.1`. **Patch component only** — do not touch
minor or major. Change nothing else in the file; in particular leave
`description` alone (it already says "bundled MCP servers" without a count).

This is the release mechanism: without it, colleagues' `/plugin update` sees no
change and they keep running a plugin with no codegraph server
(`AGENTS.md` Hazards).

**Verify**:

```bash
jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json
bash .claude/lint-cmd plugins/dev-flow/.claude-plugin/plugin.json && echo "lint OK"
git diff --stat plugins/dev-flow/.claude-plugin/plugin.json
bash .claude/test-cmd; echo "test-cmd exit=$?"
```

**Expected**: `1.10.1`; `lint OK`; the diffstat shows `1 insertion(+), 1
deletion(-)`; `test-cmd exit=0`.

**Depends on**: 3 (bump last, once the content change is in).

---

## Task 9 — End-to-end verification against the real plugin loader

**Files**: none (read-only).

**Change**: none.

**Verify** — this is the acceptance test, and it was run for real against a
scratch copy of the plugin during planning:

```bash
claude --plugin-dir ./plugins/dev-flow mcp list 2>&1 | grep -E '^plugin:dev-flow:'
```

**Expected**: four lines, each ending `✔ Connected`:

```
plugin:dev-flow:context7: npx -y @upstash/context7-mcp - ✔ Connected
plugin:dev-flow:semble: uvx --from semble[mcp] semble - ✔ Connected
plugin:dev-flow:chrome-devtools: npx chrome-devtools-mcp@latest - ✔ Connected
plugin:dev-flow:codegraph: codegraph serve --mcp - ✔ Connected
```

If codegraph shows `✘ Failed to connect`, check `command -v codegraph` first —
that is cause (c) from the spec, not a config error.

**Depends on**: 3, 8.

---

## Acceptance criteria (for `verify-done`)

Each is a single command with an unambiguous expected result.

1. `bash .claude/test-cmd; echo $?` → `0`.
2. `jq -r '.mcpServers|keys[]' plugins/dev-flow/.mcp.json | sort | tr '\n' ' '`
   → `chrome-devtools codegraph context7 semble`.
3. `jq -r '.mcpServers.codegraph.command' plugins/dev-flow/.mcp.json` →
   `codegraph`.
4. `jq -r '.mcpServers.codegraph.args|join(" ")' plugins/dev-flow/.mcp.json` →
   `serve --mcp`.
5. `jq -r '.mcpServers.semble.args|join(" ")' plugins/dev-flow/.mcp.json` →
   `--from semble[mcp] semble` (**unchanged** — proves semble was not touched).
6. `jq -r '.version' plugins/dev-flow/.claude-plugin/plugin.json` → `1.10.1`.
7. `grep -c 'codegraph install' install.sh` → `0` (skip if Open question 2 was
   answered "defer").
8. `bash .claude/lint-cmd install.sh; echo $?` → `0`.
9. `bash install.sh --dry-run --no-color 2>&1 | grep -ci codegraph` → non-zero,
   and `git status --porcelain` unchanged by the dry run.
10. `grep -c 'MCP servers 4' README.md` → `1`.
11. `git check-ignore -q .codegraph/; echo $?` → `0`.
12. `claude --plugin-dir ./plugins/dev-flow mcp list 2>&1 | grep -c '^plugin:dev-flow:.*✔ Connected'`
    → `4`.
13. Handshake still passes:
    `printf '...initialize/initialized/tools-list...' | codegraph serve --mcp | jq -r 'select(.id==2)|.result.tools[].name'`
    → `codegraph_explore` (full command in Task 2).

## Commit guidance

One commit. No AI-attribution trailers in this repo (`AGENTS.md` Conventions) —
omit `Co-Authored-By` and any "Generated with" line entirely. Do not push,
merge or force-push without explicit approval.
