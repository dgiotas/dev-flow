#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/asset-lint.sh.
# They run from .claude/test-cmd, and every plugin tree is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/asset-lint.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# mkroot <dir>: a clean fixture root
mkroot() {
  R=$1
  P=$R/plugins/dev-flow
  mkdir -p "$P/.claude-plugin" "$P/agents" "$P/commands" "$P/skills/alpha" "$P/skills/beta" "$R/.claude/rules"
  echo '{"name":"dev-flow"}' > "$P/.claude-plugin/plugin.json"
  echo '{"mcpServers":{"codegraph":{}}}' > "$P/.mcp.json"
  cat > "$P/agents/helper.md" <<'EOF'
---
name: helper
description: Reads files and reports back.
tools: Read, Grep, mcp__plugin_dev-flow_codegraph
---
Body.
EOF
  cat > "$P/commands/go.md" <<'EOF'
---
description: Run the flow.
---
Use the `helper` subagent, then run `/dev-flow:go` again.
EOF
  cat > "$P/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: Format SQL migration files and check rollback safety before release.
---
Body.
EOF
  cat > "$P/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: Draft commit messages and pull request titles from staged git changes.
---
Body.
EOF
  printf -- '- keep it short\n' > "$R/.claude/rules/r.md"
}

clean="$tmp/clean"
mkroot "$clean"

# mk <label>: copy of the clean fixture, prints its path
mk() { cp -R "$clean" "$tmp/$1"; echo "$tmp/$1"; }

# edit <file> <sed expr>: in-place sed that works on BSD and GNU
edit() { sed -e "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }

# expect <label> <want exit> <want line prefix> [args...]
expect() {
  label=$1; want_rc=$2; want=$3; shift 3
  out=$(bash "$script" "$@" 2>&1); rc=$?
  hit=$(printf '%s\n' "$out" | WANT="$want" awk 'index($0, ENVIRON["WANT"]) == 1 { n++ } END { print n + 0 }')
  last=$(printf '%s\n' "$out" | tail -n 1)
  case $last in summary=*) sum=1 ;; *) sum=0 ;; esac
  if [ "$rc" = "$want_rc" ] && [ "$hit" -gt 0 ] && [ "$sum" = 1 ]; then
    pass "$label"
  else
    bad "$label (exit $rc, want $want_rc; want line starting '$want')"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

expect clean 0 "result=ok" --root "$clean"

if bash "$script" --json --root "$clean" | jq -e '.result == "ok" and .errors == 0 and .findings == []' >/dev/null; then
  pass json-clean
else
  bad json-clean
fi

r=$(mk fm-unquoted-colon)
edit "$r/plugins/dev-flow/skills/alpha/SKILL.md" 's/^description:.*/description: Use when: always/'
expect fm-unquoted-colon 1 "error=frontmatter file=plugins/dev-flow/skills/alpha/SKILL.md:" --root "$r"

r=$(mk fm-unclosed)
edit "$r/plugins/dev-flow/skills/beta/SKILL.md" '4d'
expect fm-unclosed 1 "error=frontmatter file=plugins/dev-flow/skills/beta/SKILL.md:" --root "$r"

r=$(mk fm-no-open)
edit "$r/plugins/dev-flow/commands/go.md" '1s/.*/description: x/'
expect fm-no-open 1 "error=frontmatter file=plugins/dev-flow/commands/go.md:" --root "$r"

r=$(mk field-missing)
edit "$r/plugins/dev-flow/skills/alpha/SKILL.md" '/^description:/d'
expect field-missing 1 "error=field-missing file=plugins/dev-flow/skills/alpha/SKILL.md:" --root "$r"

r=$(mk name-mismatch)
edit "$r/plugins/dev-flow/skills/alpha/SKILL.md" 's/^name:.*/name: alfa/'
expect name-mismatch 1 "error=name-mismatch file=plugins/dev-flow/skills/alpha/SKILL.md:" --root "$r"

r=$(mk agent-name-mismatch)
edit "$r/plugins/dev-flow/agents/helper.md" 's/^name:.*/name: helpr/'
expect agent-name-mismatch 1 "error=name-mismatch file=plugins/dev-flow/agents/helper.md:" --root "$r"

r=$(mk agent-no-tools)
edit "$r/plugins/dev-flow/agents/helper.md" '/^tools:/d'
expect agent-no-tools 1 "error=agent-tools file=plugins/dev-flow/agents/helper.md:" --root "$r"

r=$(mk agent-empty-tools)
edit "$r/plugins/dev-flow/agents/helper.md" 's/^tools:.*/tools:/'
expect agent-empty-tools 1 "error=agent-tools file=plugins/dev-flow/agents/helper.md:" --root "$r"

r=$(mk mcp-typo)
edit "$r/plugins/dev-flow/agents/helper.md" 's/^tools:.*/tools: Read, mcp__plugin_dev-flow_codegrph/'
expect mcp-typo 1 "error=mcp-unknown file=plugins/dev-flow/agents/helper.md:" --root "$r"

r=$(mk mcp-tool-ok)
edit "$r/plugins/dev-flow/agents/helper.md" 's/^tools:.*/tools: Read, mcp__plugin_dev-flow_codegraph__codegraph_explore/'
expect mcp-tool-ok 0 "result=ok" --root "$r"

r=$(mk mcp-wrong-plugin)
edit "$r/plugins/dev-flow/agents/helper.md" 's/^tools:.*/tools: mcp__codegraph__x/'
expect mcp-wrong-plugin 1 "error=mcp-unknown" --root "$r"

r=$(mk mcp-allowed-tools)
edit "$r/plugins/dev-flow/commands/go.md" '1a\
allowed-tools: mcp__plugin_dev-flow_nope'
expect mcp-allowed-tools 1 "error=mcp-unknown file=plugins/dev-flow/commands/go.md:" --root "$r"

r=$(mk mcp-no-config)
rm "$r/plugins/dev-flow/.mcp.json"
expect mcp-no-config 1 "error=mcp-unknown" --root "$r"

r=$(mk ref-command-missing)
echo 'Then run `/dev-flow:gone`.' >> "$r/plugins/dev-flow/skills/alpha/SKILL.md"
expect ref-command-missing 1 "error=ref-command file=plugins/dev-flow/skills/alpha/SKILL.md:" --root "$r"

r=$(mk ref-skill-ok)
echo 'Run `/dev-flow:beta`.' >> "$r/plugins/dev-flow/commands/go.md"
expect ref-skill-ok 0 "result=ok" --root "$r"

r=$(mk ref-agent-missing)
echo 'Use the `ghost` agent.' >> "$r/plugins/dev-flow/commands/go.md"
expect ref-agent-missing 1 "error=ref-agent file=plugins/dev-flow/commands/go.md:" --root "$r"

r=$(mk ref-subagent-missing)
echo 'Use the `phantom` subagent.' >> "$r/plugins/dev-flow/agents/helper.md"
expect ref-subagent-missing 1 "error=ref-agent file=plugins/dev-flow/agents/helper.md:" --root "$r"

r=$(mk budget-over)
head -c 20000 /dev/zero | tr '\0' x > "$r/.claude/rules/big.md"
expect budget-over 1 "error=budget file=-:" --root "$r"

expect budget-warn 0 "warning=budget file=-:" --warn-bytes 10 --max-bytes 100000 --root "$clean"

expect budget-metrics 0 "rule_bytes=16" --root "$clean"

if bash "$script" --json --root "$clean" | jq -e '.budget.rule_bytes == 16 and .budget.bytes == .budget.desc_bytes + 16 and .budget.max_bytes == 16000 and .budget.warn_bytes == 14000' >/dev/null; then
  pass json-budget
else
  bad json-budget
fi

r=$(mk similar-pair)
edit "$r/plugins/dev-flow/skills/beta/SKILL.md" 's/^description:.*/description: Format SQL migration files and check rollback safety before deploy./'
expect similar-pair 1 "error=skill-similar file=plugins/dev-flow/skills/alpha/SKILL.md:" --root "$r"
expect similar-threshold 0 "result=ok" --similarity 1 --root "$r"

expect similar-clean 0 "similarity_pair=alpha,beta" --root "$clean"

if bash "$script" --json --root "$clean" | jq -e '.similarity.threshold == 0.3 and (.similarity.pair == ["alpha","beta"])' >/dev/null; then
  pass json-similarity
else
  bad json-similarity
fi

r=$(mk single-skill)
rm -r "$r/plugins/dev-flow/skills/beta"
expect single-skill 0 "similarity_pair=-" --root "$r"

r=$(mk fm-line-number)
edit "$r/plugins/dev-flow/skills/alpha/SKILL.md" 's/^description:.*/description: Use when: always/'
expect fm-line-number 1 "error=frontmatter file=plugins/dev-flow/skills/alpha/SKILL.md: line 3:" --root "$r"

r=$(mk fm-multiline)
printf -- '---\nname: alpha\ndescription: Format SQL migration files\n  and check rollback safety.\n---\nBody.\n' > "$r/plugins/dev-flow/skills/alpha/SKILL.md"
expect fm-multiline 1 "error=frontmatter file=plugins/dev-flow/skills/alpha/SKILL.md: line 4:" --root "$r"

r=$(mk fm-block)
printf -- '---\nname: alpha\ndescription: >\n  Format SQL migration files.\n---\nBody.\n' > "$r/plugins/dev-flow/skills/alpha/SKILL.md"
expect fm-block 1 "error=field-missing file=plugins/dev-flow/skills/alpha/SKILL.md:" --root "$r"

r=$(mk fm-quoted)
printf -- '---\nname: "alpha"\ndescription: '"'"'It'"''"'s a: quoted value.'"'"'\n---\nBody.\n' > "$r/plugins/dev-flow/skills/alpha/SKILL.md"
expect fm-quoted 0 "result=ok" --root "$r"

r=$(mk mcp-list-form)
printf -- '---\ndescription: Run the flow.\nallowed-tools:\n  - Read\n  - mcp__plugin_dev-flow_nope\n---\nBody.\n' > "$r/plugins/dev-flow/commands/go.md"
expect mcp-list-form 1 "error=mcp-unknown file=plugins/dev-flow/commands/go.md:" --root "$r"

r=$(mk ref-agentic-prose)
echo 'The `loop` agentic flow, and the `a` agents.' >> "$r/plugins/dev-flow/commands/go.md"
expect ref-agentic-prose 1 "error=ref-agent file=plugins/dev-flow/commands/go.md: agent a " --root "$r"

r=$(mk ref-agentic-ok)
echo 'The `loop` agentic flow.' >> "$r/plugins/dev-flow/commands/go.md"
expect ref-agentic-ok 0 "result=ok" --root "$r"

r=$(mk json-findings)
head -c 20000 /dev/zero | tr '\0' x > "$r/.claude/rules/big.md"
if bash "$script" --json --root "$r" | jq -e '.result == "fail" and .findings[0].code == "budget" and .findings[0].file == null and .findings[0].severity == "error"' >/dev/null; then
  pass json-findings
else
  bad json-findings
fi

r=$(mk plugin-json)
rm "$r/plugins/dev-flow/.claude-plugin/plugin.json"
expect plugin-json 2 "error=plugin-json" --root "$r"

expect usage-flag 2 "error=usage" --bogus
expect root-missing 2 "error=root-missing" --root "$tmp/nope"
expect usage-warn-gt-max 2 "error=usage" --warn-bytes 20 --max-bytes 10 --root "$clean"
expect usage-similarity 2 "error=usage" --similarity 2 --root "$clean"

exit $fail
