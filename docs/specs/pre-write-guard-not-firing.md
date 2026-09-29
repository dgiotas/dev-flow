# Spec: pre-write-guard does not fire in consuming repos

Status: ready for implementation (one scope decision open — see Open questions)
Investigated: 2026-09-29, against Claude Code v2.1.277 on macOS 15 (darwin 25.6.0), GNU bash 3.2.57, jq 1.7.1.

## Goal

Make the `pre-write-guard` PreToolUse hook actually gate `AGENTS.md` / `CLAUDE.md` /
`.claude/rules/*.md` in the repos where colleagues use the plugin, and make it
*visible* when it is not gating them. Today the guard fails silently: every
non-match path in the script is a bare `exit 0`, so "guard armed and working" and
"guard absent, stale or broken" look identical from inside a session.

## Non-goals

- Turning the guard into a security boundary. It is a guardrail against model
  error and forgetfulness, exactly as `README.md:323` already frames the
  `ALLOW-CLAUDE-MD-EDIT` override. Anyone who wants to edit `AGENTS.md` can.
- Reworking the approval-marker scheme. It is correct and was re-verified in this
  investigation (see Reproduction, cases A–D).
- Adding CI to this repo. `.claude/test-cmd` stays the test suite.
- Touching `post-edit-check.sh` or `stop-gate.sh`.

---

## Root cause

### Confirmed — the running copy of the plugin is v1.4.0, not v1.9.1

The plugin source in this repo is at `1.9.1`
(`plugins/dev-flow/.claude-plugin/plugin.json:3`), and its guard is correct. The
copy Claude Code actually loads is **v1.4.0**, installed once on 2026-09-27 and
never updated:

```
$ claude plugin list
  ❯ dev-flow@dev-flow-marketplace
    Version: 1.4.0
    Scope: user
    Status: ✔ enabled

$ jq '.plugins["dev-flow@dev-flow-marketplace"]' ~/.claude/plugins/installed_plugins.json
[
  {
    "scope": "user",
    "installPath": "/Users/dgiotas/.claude/plugins/cache/dev-flow-marketplace/dev-flow/1.4.0",
    "version": "1.4.0",
    "installedAt": "2026-09-27T07:36:00.081Z",
    "lastUpdated": "2026-09-27T07:36:00.081Z"
  }
]
```

`enabledPlugins` in `~/.claude/settings.json` has `"dev-flow@dev-flow-marketplace": true`
at **user** scope, so this one cached copy is what every project on the machine
gets. `installedAt == lastUpdated` — it has never been updated. Commits
`26e2dd8` (11:18), `c788a04` "Update to 1.8.0" (11:59), `adb97ae` "Bump version
to 1.9" (12:36) and `50a3ae3` "bump to 1.9.1" (18:04) all landed *after* the
10:36 local install time, so none of them ever reached a session.

The cached v1.4.0 `hooks/hooks.json` is:

```json
"PreToolUse": [
  {
    "matcher": "Write",
    "hooks": [
      { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/pre-write-guard.sh\"" }
    ]
  }
],
```

— `Write` only, no `Edit`. And the cached v1.4.0 `pre-write-guard.sh` guards only
`CLAUDE.md` and `.claude/rules/*.md`; `AGENTS.md` is not in its guarded set at all:

```bash
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Write" ] || exit 0
...
base=$(basename -- "$file")
rel="${file#"$PWD"/}"
guarded=0
[ "$base" = "CLAUDE.md" ] && guarded=1
case "$rel" in .claude/rules/*.md) guarded=1 ;; esac
[ "$guarded" = "1" ] || exit 0
```

That explains both halves of the user's report exactly:

- *"the AGENTS.md write earlier"* went through — v1.4.0 does not guard `AGENTS.md`
  at any tool, so the script reaches `exit 0` on the `guarded` check.
- *"This edit went through without it blocking"* — v1.4.0's matcher is `Write`,
  so an `Edit` never invokes the script at all.

Reproduced literally against the live cached copy (see Reproduction, cases M–P).

### Confirmed — nothing in the plugin makes staleness or silence detectable

This is the reason the wrong version survived for days across several repos.

- Every non-match in `pre-write-guard.sh` is a bare `exit 0`
  (`plugins/dev-flow/hooks/scripts/pre-write-guard.sh:29,32,41,99,112,124,141`).
  Claude Code treats exit 0 as "allow, say nothing". There is no signal.
- Nothing prints the loaded plugin version. `${CLAUDE_PLUGIN_ROOT}` is exported
  to hook processes and its last path segment *is* the loaded version, but no
  script or command reads it for that purpose.
- `/dev-flow:init-hooks` has a "Prove they work (do not skip this)" section
  (`plugins/dev-flow/commands/init-hooks.md:52-59`) that even makes `lint-cmd`
  fail on purpose — but it says nothing about the pre-write guard.
- The one existing diagnostic, `README.md:308`, is itself broken. Run verbatim:

  ```
  $ jq '.hooks.PreToolUse' ~/.claude/plugins/**/dev-flow/hooks/hooks.json
  jq: error: Could not open file /Users/dgiotas/.claude/plugins/**/dev-flow/hooks/hooks.json: No such file or directory
  ```

  `**` does not recurse in bash without `globstar`, and the real path is
  `~/.claude/plugins/cache/<marketplace>/dev-flow/<version>/hooks/hooks.json`.

### Confirmed — two further silent no-ops in the *current* (1.9.1) script

Both reproduced; both would have kept biting after an update.

1. **`jq` missing → the write is allowed.** `jqr()`
   (`plugins/dev-flow/hooks/scripts/pre-write-guard.sh:25`) has no guard; if `jq`
   is not on PATH, `tool` is empty, the `case` at line 29 falls through to
   `exit 0`, and Claude Code shows only a non-blocking `jq: command not found`
   notice. Case K below: exit 0 on a `Write` that overwrites `AGENTS.md`.
2. **`.claude/rules/*.md` is unguarded whenever `$PWD` is not a literal string
   prefix of `file_path`.** Line 37 does `rel="${file#"$PWD"/}"` and line 40
   matches `.claude/rules/*.md` against `rel` only. If `CLAUDE_PROJECT_DIR` is a
   symlinked path (the ordinary macOS `/tmp` → `/private/tmp` case, and any repo
   reached through a symlinked parent) or is unset, the strip is a no-op, `rel`
   stays absolute, and the `case` never matches. Cases H and J below: exit 0.
   `AGENTS.md`/`CLAUDE.md` survive this because line 39 matches on `basename`.

### Confirmed — the `Bash` write bypass is real

`hooks.json:5` matches `Write|Edit|MultiEdit`, and the script's `case` at line 29
exits 0 for anything else. A heredoc, `sed -i`, `tee`, `cp`, `mv` or `python -c`
that rewrites `AGENTS.md` is not seen at all (case F below: exit 0). The script
already knows this — its own block message at line 184 asks the model not to
"work around this by splitting the change up, using a different tool, or
recreating the file" — i.e. the bypass is currently closed by instruction, which
contradicts the design note at line 7 ("does NOT trust the model to 'remember' to
ask"). See Scope decision.

### Ruled out (checked, not the cause)

| Candidate | Evidence |
|---|---|
| Matcher syntax invalid / no match | Per the [hooks reference](https://code.claude.com/docs/en/hooks), a matcher containing only letters, digits, `_`, `-`, spaces, `,` and `\|` is an **exact** string or pipe-separated list of exact strings; only other characters make it an unanchored regex. `Write\|Edit\|MultiEdit` is therefore an exact list that matches `Write` and `Edit`. |
| `hooks` not declared in `plugin.json` | Not needed. `hooks/hooks.json` is the documented default location and loads on its own ([manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference), Standard layout). `claude plugin validate ./plugins/dev-flow` → `✔ Validation passed`. |
| Wrong blocking mechanism (exit 1 vs exit 2 vs JSON) | Exit 2 is correct and is the stronger form: "A hook that exits with code 2 stops the tool call before permission rules are evaluated" ([permissions](https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks)). The script uses `exit 2` with stderr throughout, matching `.claude/rules/hook-scripts.md:6`. |
| `${CLAUDE_PLUGIN_ROOT}` not resolving | It is substituted in hook `command` strings and exported to the hook process ([manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves)). It is correctly double-quoted in `hooks.json`, so an install path with a space is fine. |
| Missing exec bit / CRLF | `git ls-files -s` shows `100644` for all three scripts, which is correct: `hooks.json` invokes them as `bash "<path>"`, per `.claude/rules/hook-scripts.md:7`. No CRLF in the tree. |
| Plugin not enabled in that repo | `"dev-flow@dev-flow-marketplace": true` is set at **user** scope in `~/.claude/settings.json`, which "reaches you in every project" ([loading reference](https://code.claude.com/docs/en/plugins/loading#find-where-a-plugin-is-enabled)). |
| `disableAllHooks` | Not set in `~/.claude/settings.json`. |
| Permission mode suppressing PreToolUse | Not supported by the docs. [permissions](https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks): "When Claude Code makes a tool call, PreToolUse hooks run before the permission prompt, for every tool except `EndConversation`." Neither that page nor [permission-modes](https://code.claude.com/docs/en/permission-modes) says any mode skips them. Session mode here is `auto`. |
| Restart needed after install | Not for hooks *configuration* — but see Risks: a plugin *update* does need `/reload-plugins` or a new session. |
| Stale/over-broad approval marker | Marker names are derived per file (`${rel//\//__}.approved`) and compared against a hash of path + exact change + current file content, then deleted. No wildcard path. Cases A–D all blocked with no marker present. |
| `NotebookEdit` not covered | `NotebookEdit` writes `.ipynb` cells; it cannot target `AGENTS.md` or a `.md` rule file. No change needed — do not add speculative coverage. |
| `realpath` / GNU-only flags / bash 4 features | The script uses only `basename`, `cat`, `diff`, `head`, `tr`, `ls -Li`, `awk`, `readlink`, `grep -qE` and bash 3.2-compatible parameter expansion. It runs clean on macOS bash 3.2.57. |

---

## Reproduction (literal output)

Fixture: a throwaway repo with `AGENTS.md`, `CLAUDE.md -> AGENTS.md` (symlink),
`.claude/rules/foo.md` and an unrelated `src.txt`. Each case pipes a realistic
`PreToolUse` payload into the script with `CLAUDE_PROJECT_DIR` pointing at that
repo.

### Current source, `plugins/dev-flow/hooks/scripts/pre-write-guard.sh` (v1.9.1)

| # | Payload | exit | stderr (first line) |
|---|---|---|---|
| A | `Write` abs `AGENTS.md` | **2** | `BLOCKED: Write would change an existing protected file: AGENTS.md` |
| B | `Edit` abs `AGENTS.md` | **2** | `BLOCKED: Edit would change an existing protected file: AGENTS.md` |
| C | `Edit` abs `CLAUDE.md` (symlink) | **2** | `REFUSED: CLAUDE.md is only a pointer to AGENTS.md (symlink).` |
| D | `Edit` abs `.claude/rules/foo.md` | **2** | `BLOCKED: Edit would change an existing protected file: .claude/rules/foo.md` |
| E | `Edit` unrelated `src.txt` | 0 | *(none)* — correct |
| F | `Bash` heredoc `cat > AGENTS.md <<EOF` | **0** | *(none)* — **bypass** |
| G | `NotebookEdit` | 0 | *(none)* — correct, cannot target a `.md` |
| H | `Edit` `.claude/rules/foo.md`, `CLAUDE_PROJECT_DIR` = a **symlink** to the repo | **0** | *(none)* — **bug** |
| I | same as H but `AGENTS.md` | 2 | blocked (basename match saves it) |
| J | `Edit` `.claude/rules/foo.md`, `CLAUDE_PROJECT_DIR` **unset** | **0** | *(none)* — **bug** |
| K | `Write` `AGENTS.md` with **`jq` not on PATH** | **0** | `pre-write-guard.sh: line 25: jq: command not found` — **bug** |
| L | `Edit` `.claude/rules/foo.md` passed as a repo-relative path | 2 | blocked — correct |

Case A's full stderr, for reference (this is what a working guard looks like):

```
BLOCKED: Write would change an existing protected file: AGENTS.md
AGENTS.md, CLAUDE.md and .claude/rules/*.md are never changed without the user seeing it first.

Whole-file replace. Diff (current -> proposed):
--- .../AGENTS.md	2026-09-29 21:28:39
+++ /dev/fd/63	2026-09-29 21:28:53
@@ -1,3 +1,3 @@
 # Guidance

-Original line.
+CHANGED.
\ No newline at end of file

Required next step: show the user the change above verbatim and wait for an
explicit yes/no reply in this turn. Do not retry, and do not work around this
by splitting the change up, using a different tool, or recreating the file.

If they approve THIS exact change, run this, then retry the same call unchanged:
  mkdir -p ".claude/.approved-writes" && printf '%s' "e03ac9d3c32f1ec0ee8bb63c712eaaaa42455322575d1e700e32aeab919bf436" > ".claude/.approved-writes/AGENTS.md.approved"
```

### The copy that is actually live, `~/.claude/plugins/cache/dev-flow-marketplace/dev-flow/1.4.0/hooks/scripts/pre-write-guard.sh`

| # | Payload | exit | result |
|---|---|---|---|
| M | `Write` `AGENTS.md` | **0** | allowed — matches *"the AGENTS.md write earlier"* |
| N | `Edit` `AGENTS.md` | **0** | allowed — matches *"this edit went through"* |
| O | `Edit` `.claude/rules/foo.md` | **0** | allowed |
| P | `Write` `.claude/rules/foo.md` | 2 | the only thing v1.4.0 blocks |

(Case N would not even have reached the script: v1.4.0's matcher is `Write`.)

### Baseline

```
$ bash .claude/test-cmd ; echo $?
0
$ claude plugin validate ./plugins/dev-flow
✔ Validation passed
```

---

## Proposed design

Smallest change that fixes the root cause, in the order it matters.

### 1. Make the guard self-identifying

Read `version` from `"$CLAUDE_PLUGIN_ROOT"/.claude-plugin/plugin.json` and print
it, together with `$CLAUDE_PLUGIN_ROOT` itself, in the `BLOCKED:`/`REFUSED:`
headers. The path's last segment is the cache version directory, so a firing
guard now names the exact copy that fired. Roughly:

```
BLOCKED: Edit would change an existing protected file: AGENTS.md
  (dev-flow pre-write-guard v1.10.0 — /Users/…/cache/dev-flow-marketplace/dev-flow/1.10.0)
```

No new files, no new dependency (jq is already required).

### 2. Add a live probe to `/dev-flow:init-hooks`

`/dev-flow:init-hooks` is already the per-repo "wire the gates and prove they
work" command, and already contains the pattern this needs: create a deliberately
broken temp file, prove the gate fails on it, delete the temp file
(`plugins/dev-flow/commands/init-hooks.md:57`). Extend the same command rather
than inventing a new one. A new section **0. Prove the pre-write guard is live**,
run before everything else:

1. **Version check (static).** The command body prints `${CLAUDE_PLUGIN_ROOT}`
   — substituted inline in command Markdown, per the
   [manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves)
   — and compares its trailing version segment with `claude plugin list`. A path
   that ends in an old version is the whole bug, stated in one line.
2. **Live probe (end-to-end).** Create `.claude/rules/devflow-guard-probe.md`
   (creating a *new* guarded file is allowed by design — `pre-write-guard.sh:99`),
   then `Edit` it. The guard must block with `BLOCKED: Edit would change an
   existing protected file`. Delete the probe file either way.
   - Blocked → the hook is wired, matched, executed and its exit code honoured.
     Nothing was written; the probe is side-effect-free.
   - Not blocked → report loudly, print the remediation (`claude plugin
     marketplace update`, `claude plugin update dev-flow@…`, then
     `/reload-plugins`), and stop.

   The probe deliberately targets a throwaway rules file, not `AGENTS.md`, so
   that a *dead* guard cannot damage real guidance.

`setup-rules` would also benefit, but one surface is enough — keep the scope to
the command whose stated job is proving gates.

### 3. Close the two silent no-ops in the script

- `jq` absent → `exit 2` with a one-line message naming the missing dependency,
  instead of allowing the write. This intentionally departs from
  `.claude/rules/hook-scripts.md:9` ("missing host tools are skipped, not
  failed"), which is about optional *linters* in `post-edit-check.sh`; `jq` is
  this script's parser, and a guard that cannot parse its input must not say
  "allow". Consistent with the repo's "raise, never return null for failures".
- Path matching: fall back to `pwd -P` when the `$PWD` prefix strip is a no-op,
  and match `.claude/rules/*.md` on the tail of the raw `file_path` as well as on
  `rel`, so a symlinked or unset `CLAUDE_PROJECT_DIR` cannot disarm it.

### 4. Fix the documentation that sent the user down a dead end

- `README.md:308`: replace the non-globbing `**` command with the real cache path
  and point at the new `/dev-flow:init-hooks` probe.
- Add a troubleshooting entry for the actual failure mode: *the guard does not
  fire and you are on a stale cached copy*, with the three commands that fix it.
  This matters because a marketplace added from a local directory or a non-
  Anthropic GitHub repo has auto-update **off** by default
  ([loading reference](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs)),
  so a plugin installed once stays frozen until someone runs an update *and*
  `/reload-plugins`.
- `AGENTS.md:12` / `AGENTS.md:42`: the release row says colleagues "run
  `/plugin update`". Add that this is not automatic and that a reload or new
  session is required afterwards.

### Data flow (unchanged)

Claude Code → PreToolUse, matcher on `tool_name` → `bash
"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/pre-write-guard.sh"` with the event JSON on
stdin → exit 0 (allow, silent) or exit 2 (block, stderr returned to Claude). No
schema or API change. `hooks.json` changes only if the Bash task is taken.

---

## Scope decision: the `Bash` write bypass

**Recommendation: close it, as the last and separable task.**

For: the script's own premise is that it does not trust the model to remember;
today its line-184 plea not to "use a different tool" is precisely that trust.
A one-word matcher change plus ~20 lines closes the everyday case (`cat > AGENTS.md
<<EOF`, `sed -i … AGENTS.md`, `tee AGENTS.md`, `mv x AGENTS.md`).

Against: `PreToolUse` on `Bash` means the script runs on *every* shell command in
every repo the plugin is installed in, and pattern-matching command text risks
false positives that block legitimate work. Mitigation is to block only when a
guarded basename appears *together with* a write construct (`>`, `>>`, `tee`,
`sed -i`, `cp`, `mv`, `dd`, `truncate`, `python -c`, heredoc), so `cat AGENTS.md`
and `grep -n foo .claude/rules/*.md` stay untouched.

Honest limit to state in the README if it lands: this is a guardrail, not a
boundary. Obfuscated command text (`"AGENT""S.md"`, a variable, a script file,
base64) walks past it. Same posture as `ALLOW-CLAUDE-MD-EDIT` in `README.md:323`.

It is genuinely separable from the root-cause fix, so it is the last plan task
and can be dropped without affecting anything before it.

---

## Risks, edge cases, migration, rollback

- **The fix does not deploy itself.** Every change here is inert until the user
  runs `claude plugin marketplace update dev-flow-marketplace`, `claude plugin
  update dev-flow@dev-flow-marketplace`, and then `/reload-plugins` or starts a
  new session. The version bump is what makes the update visible at all
  (`AGENTS.md:42`). This is exactly the trap that produced the bug, so the plan
  ends with those commands as an explicit user step.
- **Mid-session updates keep the old path.** Per the
  [loading reference](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs),
  "when a copied plugin updates mid-session, hook commands … keep using the
  previous version's path. Run `/reload-plugins` to switch". A user who updates
  and does not reload will still see the old guard — and, after task 1, will see
  the old version number in the block message, which is the point.
- **`jq` now hard-fails.** On a machine without `jq`, every `Write`/`Edit` is
  blocked with a clear message instead of silently allowed. `jq` is already a
  stated requirement (`README.md:35`) and `install.sh:184` checks for it. Loud is
  the correct trade here, but it is a behaviour change worth a README line.
- **Approval-marker naming when `CLAUDE_PROJECT_DIR` is unset.** After the path
  fix the guard blocks, but `rel` may still be an absolute path, making the
  printed marker filename ugly (`__private__tmp__…approved`). It is
  self-consistent — the same value is used to write and to check — so
  approve-and-retry still works. Accepted; Claude Code exports
  `CLAUDE_PROJECT_DIR` to hook processes in practice.
- **The probe file.** `.claude/rules/devflow-guard-probe.md` must be deleted by
  the command whether the probe blocked or not. If a session dies mid-probe it
  leaves one stray file in `.claude/rules/`; harmless, and `.claude/rules/*.md`
  is repo content the user can see.
- **Rollback.** Everything is text in one plugin directory. `git revert` the
  commit and re-bump the version; colleagues' next `/plugin update` moves them
  back. No state migration, no data.

---

## Open questions

1. **Take the `Bash` task (task 8)?** It is the difference between "the guard is
   a mechanism for `Write`/`Edit` and an instruction for `Bash`" and "the guard is
   a mechanism". Cost: the hook runs on every Bash command, and command-text
   matching can produce false positives. Needs an explicit yes before that task
   is implemented; tasks 1–7 stand alone.
2. **Drop `MultiEdit`?** The current
   [hooks reference](https://code.claude.com/docs/en/hooks) lists `Bash`, `Edit`,
   `Write`, `PowerShell` and `NotebookEdit` as tool names and does not mention
   `MultiEdit`. The repo's own rule is to delete dead code outright. Against:
   removing it reopens a hole for anyone on an older Claude Code that still has
   the tool, and in an exact-match matcher list the dead name costs nothing. The
   plan leaves it in place; say if you want it removed.
3. **Which repo produced the report, and what is `claude plugin list` there?**
   Only the consuming repo can confirm which version it loaded. Everything above
   is measured on this machine, where the user-scope install is v1.4.0 and
   therefore applies to every project — but if that colleague's repo pins a
   different scope (`.claude/settings.json` / `.claude/settings.local.json`
   `enabledPlugins`), the version could differ. Ask for `claude plugin list`
   and `ls ~/.claude/plugins/cache/*/dev-flow/` from that repo.
4. **Did `AGENTS.md` exist before the reported write?** If the session *created*
   it, v1.9.1 would also have allowed that write — new files pass through by
   design (`pre-write-guard.sh:99`). The follow-up `Edit` is the unambiguous
   symptom; the write may be a red herring. Worth confirming, but it does not
   change the fix.
5. **Should `jq` failing hard be gated on a repo opt-out?** The plan assumes not
   (simplest solution first). Say if any of your environments lack `jq`.
