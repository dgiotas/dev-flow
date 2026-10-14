#!/usr/bin/env bash
# Lints the plugin's skills, agents and commands. Deterministic, no model calls, changes nothing.
#
# Usage:  bash asset-lint.sh [--json] [--root <dir>] [--max-bytes <n>] [--warn-bytes <n>] [--similarity <x>]
# Prints one line per finding (<sev>=<code> file=<path|->: <message>), then the metrics as key=value
# lines, then errors, warnings, result=ok|fail; the last line is always summary=.
# Finding codes: frontmatter, field-missing, name-mismatch, agent-tools, mcp-unknown,
# ref-command, ref-agent, budget, skill-similar.
# Exit 0 when there are no errors (warnings allowed), 1 when there are errors, 2 on a usage or
# environment problem (error=<reason> then summary=): usage, root-missing, jq-missing, plugin-json.
set -u
export LC_ALL=C

die() { echo "error=$1"; echo "summary=$2"; exit 2; }

max=16000; warn=14000; sim=0.30; json=0; root=.

int() { case $2 in ''|*[!0-9]*) die usage "$1 needs a non-negative integer" ;; esac; }

while [ $# -gt 0 ]; do
  case $1 in
    --json) json=1; shift ;;
    --root) [ $# -ge 2 ] || die usage "--root needs a value"; root=$2; shift 2 ;;
    --max-bytes) [ $# -ge 2 ] || die usage "--max-bytes needs a value"; int --max-bytes "$2"; max=$2; shift 2 ;;
    --warn-bytes) [ $# -ge 2 ] || die usage "--warn-bytes needs a value"; int --warn-bytes "$2"; warn=$2; shift 2 ;;
    --similarity)
      [ $# -ge 2 ] || die usage "--similarity needs a value"
      printf '%s\n' "$2" | grep -Eq '^(0|1|0?\.[0-9]+|1\.0+)$' || die usage "--similarity needs a number from 0 to 1"
      sim=$2; shift 2 ;;
    *) die usage "unknown argument $1" ;;
  esac
done
[ "$warn" -le "$max" ] || die usage "--warn-bytes must not exceed --max-bytes"

P=$root/plugins/dev-flow
[ -d "$P" ] || die root-missing "no $P"
command -v jq >/dev/null 2>&1 || die jq-missing "jq is required"
plugin=$(jq -r '.name // empty' "$P/.claude-plugin/plugin.json" 2>/dev/null)
[ -n "$plugin" ] || die plugin-json "no .name in $P/.claude-plugin/plugin.json"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
: > "$tmp/findings"; : > "$tmp/metrics"; : > "$tmp/desc"

add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$tmp/findings"; }
metric() { printf '%s\t%s\n' "$1" "$2" >> "$tmp/metrics"; }

# Prints K<TAB>key<TAB>value rows for top-level keys and E<TAB>line<TAB>message rows for syntax problems.
IFS= read -r -d "" FM_AWK <<'EOF' || true
function err(n, m) { print "E\t" n "\t" m }
function emit(   v, q, c) {
  if (key == "") return
  v = val
  gsub(/\r/, "", v)
  sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
  q = substr(v, 1, 1)
  if (v == "|" || v == ">" || v == "|-" || v == ">-") v = "<block>"
  else if (q == "\047") {
    if (length(v) < 2 || substr(v, length(v), 1) != "\047") err(kline, "value of " key " starts with a single quote but does not end with one")
    else { v = substr(v, 2, length(v) - 2); gsub(/\047\047/, "\047", v) }
  } else if (q == "\"") {
    if (length(v) < 2 || substr(v, length(v), 1) != "\"") err(kline, "value of " key " starts with a double quote but does not end with one")
    else { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v) }
  } else if (v != "") {
    if (index(v, ": ") > 0) err(kline, "unquoted value of " key " contains \": \"; quote it")
    else if (index(v, " #") > 0) err(kline, "unquoted value of " key " contains \" #\"; quote it")
    else if (substr(v, length(v), 1) == ":") err(kline, "unquoted value of " key " ends with a colon; quote it")
    else if (index("[{&*!%@`", q) > 0) err(kline, "unquoted value of " key " starts with " q "; quote it")
  }
  print "K\t" key "\t" v
  if (extra != "") print "X\t" key "\t" extra
  key = ""; extra = ""
}
BEGIN { key = ""; extra = ""; closed = 0; stop = 0 }
NR == 1 {
  l = $0; gsub(/\r/, "", l)
  if (l != "---") { err(1, "frontmatter does not start with ---"); stop = 1; exit }
  next
}
{
  l = $0; gsub(/\r/, "", l)
  if (l == "---") { emit(); closed = 1; exit }
  if (l ~ /^[ \t]*$/ || l ~ /^#/) next
  if (l ~ /^[ \t]/ || l ~ /^- /) {
    t = val; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
    if (key == "") next
    if (t == "" && l ~ /^[ \t]*- /) { item = l; sub(/^[ \t]*- /, "", item); extra = extra " " item }
    else if (t != "" && t != "|" && t != ">" && t != "|-" && t != ">-") err(NR, "value of " key " continues on another line; keep it on one line")
    next
  }
  if (l ~ /^[A-Za-z][A-Za-z0-9_-]*:/) {
    i = index(l, ":")
    rest = substr(l, i + 1)
    if (rest == "" || substr(rest, 1, 1) == " " || substr(rest, 1, 1) == "\t") {
      emit()
      key = substr(l, 1, i - 1); val = rest; kline = NR
      next
    }
  }
  err(NR, "is not `key: value`")
}
END { if (!stop && !closed) { emit(); err(NR, "frontmatter not closed") } }
EOF

# Reads skill rows (name<TAB>description, sorted by name); prints F rows for pairs over SIM and one M row for the maximum.
IFS= read -r -d "" SIM_AWK <<'EOF' || true
BEGIN {
  FS = "\t"
  n = split("and any are asks before does even for from how into its not only says that the then this use user when what why with without", w, " ")
  for (i = 1; i <= n; i++) stop[w[i]] = 1
  sim = ENVIRON["SIM"] + 0
  rows = 0
}
$1 == "skill" {
  rows++
  name[rows] = $2
  d = tolower($3)
  gsub(/[^a-z0-9]+/, " ", d)
  m = split(d, t, " ")
  cnt[rows] = 0
  for (k = 1; k <= m; k++) {
    if (length(t[k]) < 3 || (t[k] in stop) || ((rows SUBSEP t[k]) in has)) continue
    has[rows, t[k]] = 1
    cnt[rows]++
    tok[rows, cnt[rows]] = t[k]
  }
}
END {
  max = -1; best = "-"
  for (i = 1; i <= rows; i++)
    for (j = i + 1; j <= rows; j++) {
      shared = 0
      for (k = 1; k <= cnt[i]; k++) if ((j SUBSEP tok[i, k]) in has) shared++
      u = cnt[i] + cnt[j] - shared
      jac = (u > 0) ? shared / u : 0
      if (jac > sim) print "F\t" name[i] "\t" name[j] "\t" sprintf("%.3f", jac)
      if (jac > max) { max = jac; best = name[i] "," name[j] }
    }
  if (max < 0) print "M\t0.00\t-"
  else print "M\t" sprintf("%.2f", max) "\t" best
}
EOF

fm() { awk "$FM_AWK" "$1"; }

# get <rows> <key>: value of the first K row for that key
get() { awk -F'\t' -v k="$2" '$1 == "K" && $2 == k { print $3; exit }' "$1"; }

# getx <rows> <key>: the "- item" lines under that key when its value is empty, joined by spaces
getx() { awk -F'\t' -v k="$2" '$1 == "X" && $2 == k { print $3; exit }' "$1"; }

# check_asset <kind> <file>: kind is skill, agent or command
check_asset() {
  kind=$1; f=$2
  rel=${f#"$root"/}
  case $kind in
    skill) stem=$(basename "$(dirname "$f")") ;;
    *) stem=$(basename "$f" .md) ;;
  esac
  fm "$f" > "$tmp/rows"
  while IFS="$(printf '\t')" read -r t a b; do
    [ "$t" = E ] && add error frontmatter "$rel" "line $a: $b"
  done < "$tmp/rows"

  name=$(get "$tmp/rows" name)
  desc=$(get "$tmp/rows" description)
  if [ "$kind" != command ]; then
    case $name in
      '') add error field-missing "$rel" "name is missing or empty" ;;
      '<block>') add error field-missing "$rel" "name must be a single-line value" ;;
      *) [ "$name" = "$stem" ] || add error name-mismatch "$rel" "name $name does not match $stem" ;;
    esac
  fi
  case $desc in
    '') add error field-missing "$rel" "description is missing or empty" ;;
    '<block>') add error field-missing "$rel" "description must be a single-line value" ;;
    *) printf '%s\t%s\t%s\n' "$kind" "$stem" "$desc" >> "$tmp/desc" ;;
  esac

  if [ "$kind" = agent ]; then
    t=$(get "$tmp/rows" tools)
    case $t in
      ''|'<block>') add error agent-tools "$rel" "no inline tools: allowlist; an agent without one inherits every tool" ;;
    esac
  fi

  for key in tools allowed-tools; do
    v="$(get "$tmp/rows" "$key") $(getx "$tmp/rows" "$key")"
    for tok in $(printf '%s\n' "$v" | grep -oE 'mcp__[A-Za-z0-9_-]+'); do
      rest=${tok#mcp__plugin_"${plugin}"_}
      if [ "$rest" = "$tok" ]; then
        add error mcp-unknown "$rel" "$tok is not a $plugin plugin MCP name"
        continue
      fi
      server=${rest%%__*}
      case " $servers " in
        *" $server "*) ;;
        *) add error mcp-unknown "$rel" "$tok names server $server, not declared in plugins/dev-flow/.mcp.json (servers: $servers)" ;;
      esac
    done
  done
}

check_refs() {
  f=$1; rel=${f#"$root"/}
  for n in $(grep -oE '/dev-flow:[a-z0-9-]+' "$f" | sed 's#^/dev-flow:##' | sort -u); do
    [ -f "$P/commands/$n.md" ] || [ -f "$P/skills/$n/SKILL.md" ] || add error ref-command "$rel" "/dev-flow:$n names no command or skill"
  done
  for n in $(grep -oE '`[a-z0-9-]+` (sub)?agents?([^a-z]|$)' "$f" | sed -e 's/^`//' -e 's/`.*$//' | sort -u); do
    [ -f "$P/agents/$n.md" ] || add error ref-agent "$rel" "agent $n has no plugins/dev-flow/agents/$n.md"
  done
}

servers=$(jq -r '.mcpServers // {} | keys[]' "$P/.mcp.json" 2>/dev/null | tr '\n' ' ')

for f in "$P"/skills/*/SKILL.md; do [ -f "$f" ] || continue; check_asset skill "$f"; check_refs "$f"; done
for f in "$P"/agents/*.md; do [ -f "$f" ] || continue; check_asset agent "$f"; check_refs "$f"; done
for f in "$P"/commands/*.md; do [ -f "$f" ] || continue; check_asset command "$f"; check_refs "$f"; done

desc_bytes=$(awk -F'\t' '{ n += length($3) } END { print n + 0 }' "$tmp/desc")
rule_bytes=0; rule_lines=0
for r in "$root"/.claude/rules/*.md; do
  [ -f "$r" ] || continue
  rule_bytes=$((rule_bytes + $(wc -c < "$r")))
  rule_lines=$((rule_lines + $(wc -l < "$r")))
done
budget_bytes=$((desc_bytes + rule_bytes))
budget_lines=$((rule_lines + $(wc -l < "$tmp/desc")))
metric desc_bytes "$desc_bytes"
metric rule_bytes "$rule_bytes"
metric budget_bytes "$budget_bytes"
metric budget_lines "$budget_lines"
metric est_tokens $((budget_bytes / 4))
metric max_bytes "$max"
metric warn_bytes "$warn"
if [ "$budget_bytes" -gt "$max" ]; then
  add error budget - "always-loaded text is $budget_bytes bytes, over the $max-byte ceiling (descriptions $desc_bytes, rules $rule_bytes)"
elif [ "$budget_bytes" -gt "$warn" ]; then
  add warning budget - "always-loaded text is $budget_bytes bytes, past the $warn-byte warning band (ceiling $max)"
fi

sort -t "$(printf '\t')" -k2,2 "$tmp/desc" > "$tmp/desc.sorted"
while IFS="$(printf '\t')" read -r t a b c; do
  case $t in
    F) add error skill-similar "plugins/dev-flow/skills/$a/SKILL.md" "description similarity with $b is $c, above the $sim threshold" ;;
    M) metric similarity_max "$a"; metric similarity_pair "$b" ;;
  esac
done <<EOF
$(SIM=$sim awk "$SIM_AWK" "$tmp/desc.sorted")
EOF

errors=$(awk -F'\t' '$1 == "error" { n++ } END { print n + 0 }' "$tmp/findings")
warnings=$(awk -F'\t' '$1 == "warning" { n++ } END { print n + 0 }' "$tmp/findings")
if [ "$errors" -gt 0 ]; then result=fail; else result=ok; fi
summary="asset-lint: $errors errors, $warnings warnings"

if [ "$json" = 1 ]; then
  jq -n --rawfile f "$tmp/findings" --rawfile m "$tmp/metrics" \
    --arg root "$root" --arg result "$result" --arg summary "$summary" \
    --argjson errors "$errors" --argjson warnings "$warnings" --arg sim "$sim" '
    def n: if . == null then null else tonumber end;
    ($m | split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1]}) | from_entries) as $M
    | {root: $root, result: $result, errors: $errors, warnings: $warnings, summary: $summary,
       budget: {desc_bytes: ($M.desc_bytes | n), rule_bytes: ($M.rule_bytes | n), bytes: ($M.budget_bytes | n),
                lines: ($M.budget_lines | n), est_tokens: ($M.est_tokens | n),
                max_bytes: ($M.max_bytes | n), warn_bytes: ($M.warn_bytes | n)},
       similarity: {max: ($M.similarity_max | n),
                    pair: (if $M.similarity_pair == null or $M.similarity_pair == "-" then null else ($M.similarity_pair | split(",")) end),
                    threshold: ($sim | tonumber)},
       findings: ($f | split("\n") | map(select(length > 0) | split("\t")
                 | {severity: .[0], code: .[1], file: (if .[2] == "-" then null else .[2] end), message: .[3]}))}'
else
  awk -F'\t' '{ print $1 "=" $2 " file=" $3 ": " $4 }' "$tmp/findings"
  awk -F'\t' '{ print $1 "=" $2 }' "$tmp/metrics"
  echo "errors=$errors"
  echo "warnings=$warnings"
  echo "result=$result"
  echo "summary=$summary"
fi
[ "$errors" -eq 0 ]
