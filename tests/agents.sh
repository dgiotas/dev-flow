#!/usr/bin/env bash
# Deterministic checks of the agent files: builders carry the implementer contract verbatim,
# readers have no write tools, no agent delegates. They run from .claude/test-cmd.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
A=$here/plugins/dev-flow/agents
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

fm() { awk -v k="$2" 'NR == 1 { next } /^---$/ { exit } index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$1"; }
contract() { sed -n '/^## Procedure$/,$p' "$1"; }

base_tools=$(fm "$A/implementer.md" tools)
browser=mcp__plugin_dev-flow_chrome-devtools
BUILDERS="backend-implementer:sonnet:plain frontend-implementer:sonnet:browser devops-engineer:sonnet:plain docs-writer:haiku:plain qa-engineer:sonnet:browser"
READERS="security-reviewer:opus:noshell requirements-analyst:opus:noshell bug-triager:sonnet:shell"

for entry in $BUILDERS; do
  IFS=: read -r name model kind <<< "$entry"
  f=$A/$name.md
  if [ ! -f "$f" ]; then bad "$name exists"; continue; fi
  pass "$name exists"
  if [ "$(fm "$f" model)" = "$model" ]; then pass "$name model is $model"; else bad "$name model is $model"; fi
  want=$base_tools
  [ "$kind" = browser ] && want="$base_tools, $browser"
  if [ "$(fm "$f" tools)" = "$want" ]; then pass "$name tools"; else bad "$name tools"; fi
  body=$(contract "$f")
  if [ -n "$body" ] && [ "$body" = "$(contract "$A/implementer.md")" ]; then pass "$name carries the implementer contract"; else bad "$name carries the implementer contract"; fi
  if [ "$(fm "$f" description | wc -c)" -le 121 ]; then pass "$name description length"; else bad "$name description length"; fi
done

for entry in $READERS; do
  IFS=: read -r name model kind <<< "$entry"
  f=$A/$name.md
  if [ ! -f "$f" ]; then bad "$name exists"; continue; fi
  pass "$name exists"
  if [ "$(fm "$f" model)" = "$model" ]; then pass "$name model is $model"; else bad "$name model is $model"; fi
  tools=", $(fm "$f" tools),"
  case "$tools" in
    *", Edit,"*|*", Write,"*|*", MultiEdit,"*|*", NotebookEdit,"*) bad "$name has no write tools" ;;
    *) pass "$name has no write tools" ;;
  esac
  if [ "$kind" = noshell ]; then
    case "$tools" in
      *", Bash,"*) bad "$name has no Bash" ;;
      *) pass "$name has no Bash" ;;
    esac
  fi
  if [ "$(fm "$f" description | wc -c)" -le 121 ]; then pass "$name description length"; else bad "$name description length"; fi
done

for f in "$A"/*.md; do
  if [ -n "$(fm "$f" tools)" ]; then pass "$(basename "$f") has a tools list"; else bad "$(basename "$f") has a tools list"; fi
  tools=", $(fm "$f" tools),"
  case "$tools" in
    *", Agent,"*|*", Task,"*) bad "$(basename "$f") does not delegate" ;;
    *) pass "$(basename "$f") does not delegate" ;;
  esac
done

if [ "$(fm "$here/plugins/dev-flow/skills/visual-verify/SKILL.md" description | wc -c)" -le 201 ]; then pass "visual-verify description length"; else bad "visual-verify description length"; fi

if [ "$fail" -eq 0 ]; then echo ALL-PASS; else exit 1; fi
