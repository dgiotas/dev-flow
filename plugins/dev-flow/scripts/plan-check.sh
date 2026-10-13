#!/usr/bin/env bash
# Validates the structure of a .claude/plans/<slug>.md against the plan contract in plan-schema.sh.
# Checks structure only, never plan quality, and changes nothing. Existence checks and Spec: resolve
# against the repo root derived from the plan's location.
#
# Usage:  bash plan-check.sh [--json] [--strict] <repo>/.claude/plans/<slug>.md
# Prints key=value lines: plan, status, approved, one error=/warning= line per finding
# (<sev>=<code> task=<N|-> line=<L>: <message>), open=<N>: <title> for each unticked task,
# blocked=<N> line=<L>: <reason> for each unresolved BLOCKED deviation, errors, warnings, overrides,
# result=ok|fail; the last line is always summary=.
# Exit 0 when there are no errors, 1 when there are errors, 2 on a usage problem
# (error=<reason> then summary=).
set -u
export LC_ALL=C
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/plan-schema.sh"

die() { echo "error=$1"; echo "summary=$2"; exit 2; }

json=0; strict=0; tpl=0; plan=""
for arg in "$@"; do
  case "$arg" in
    --json) json=1 ;;
    --strict) strict=1 ;;
    --template) tpl=1 ;;
    -*) die usage "usage: plan-check.sh [--json] [--strict] <plan> | --template; unknown flag $arg" ;;
    *) [ -z "$plan" ] || die usage "usage: plan-check.sh [--json] [--strict] <plan>; one plan only"
       plan=$arg ;;
  esac
done

if [ "$tpl" = 1 ]; then
  [ "$json$strict" = 00 ] && [ -z "$plan" ] || die usage "usage: plan-check.sh --template; it takes no other flag or plan"
  verbs=$(printf '%s\n' "$PLAN_VERBS" | sed -e 's/^rename|//' -e 's/|rename$//' -e 's/|rename|/|/')
  sed -e "s#@VERBS@#$verbs#" -e "s#@RISK@#$PLAN_RISK#" \
      -e "s#@STATUS@#${PLAN_STATUS%%|*}#" -e "s#@APPROVED@#${PLAN_APPROVED##*|}#" <<'TPL'
# Plan: <title>

Status: @STATUS@
Approved: @APPROVED@
Spec: .claude/specs/<slug>.md

## Tasks

### Task 1: <title>

- [ ] Done

Objective: <one sentence: what this task achieves>

Files:
- <@VERBS@> <repo-relative path>
- rename <old repo-relative path> -> <new repo-relative path>

Test first: <the failing test: name, location, what it asserts>

Test command: `<exact command>`

Change: <precise change, with function signatures and key logic>

Done when:
- run `<exact command>` and expect <result>

Risk: <@RISK@>

### Task 2: <title>

- [ ] Done

Objective: <one sentence>

Files:
- <@VERBS@> <repo-relative path>

Test first: <the failing test>

Test command: `<exact command>`

Done when:
- <observable check>

Depends on: 1

## Acceptance criteria

- [ ] <check verify-done can run>
TPL
  exit 0
fi

[ -n "$plan" ] || die usage "usage: plan-check.sh [--json] [--strict] <plan> | --template"

case "$plan" in
  .claude/plans/*.md|*/.claude/plans/*.md) ;;
  *) die plan-path "not a .claude/plans/<file>.md path: $plan" ;;
esac
case "${plan#*.claude/plans/}" in
  */*) die plan-path "not a .claude/plans/<file>.md path: $plan" ;;
esac
[ -f "$plan" ] || die plan-missing "plan not found: $plan"

root=$(cd "$(dirname "$plan")/../.." && pwd)
planrel=".claude/plans/$(basename "$plan")"

tbl=$(mktemp); trap 'rm -f "$tbl"' EXIT
tr -d '\r' < "$plan" | tr ' \t`' '\n\n\n' | grep -E '^[A-Za-z0-9_.@+/-]+$' | sort -u | while IFS= read -r p; do
  if [ -f "$root/$p" ]; then printf 'f\t%s\n' "$p"
  elif [ -e "$root/$p" ]; then printf 'e\t%s\n' "$p"
  fi
done > "$tbl"

# Toolchain words: the first command word of each segment in the repo's test-cmd and lint-cmd.
# The awk uses octal \140 for the backtick, which bash 3.2 cannot hold literally inside a heredoc.
hastool=0; toolwords=""
for tf in "$root/.claude/test-cmd" "$root/.claude/lint-cmd"; do
  [ -f "$tf" ] || continue
  hastool=1
  toolwords="$toolwords $(awk '
    function qsplit(s, out, deep,   n, i, c, d, q, cur, len) {
      # Split s at && || | ; (and, when deep, $( ( { and backtick) outside single and double quotes.
      n = 0; q = ""; cur = ""; len = length(s)
      for (i = 1; i <= len; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          cur = cur c
          if (q == "\"" && c == "\\") { i++; cur = cur substr(s, i, 1) }
          else if (c == q) q = ""
          continue
        }
        if (c == "\"" || c == "\047") { q = c; cur = cur c; continue }
        d = substr(s, i + 1, 1)
        if ((c == "&" && d == "&") || (c == "|" && d == "|")) { out[++n] = cur; cur = ""; i++; continue }
        if (c == "|" || c == ";" || (deep && (c == "(" || c == "{" || c == "\140"))) { out[++n] = cur; cur = ""; continue }
        if (deep && c == "$" && d == "(") { out[++n] = cur; cur = ""; i++; continue }
        cur = cur c
      }
      out[++n] = cur
      return n
    }
    /^[ \t]*#/ { next }
    {
      ns = qsplit($0, seg, 1)
      for (k = 1; k <= ns; k++) {
        s = seg[k]; sub(/^[ \t]+/, "", s)
        do {
          prev = s
          sub(/^(if|then|else|elif|do|while|until|for|!|time|exec)([ \t]+|$)/, "", s)
          sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*([ \t]+|$)/, "", s)
        } while (s != prev)
        sub(/[ \t].*/, "", s)
        if (s ~ /^[A-Za-z0-9_.\/-]+$/) print s
      }
    }' "$tf" | tr '\n' ' ')"
done
export PLAN_TOOLWORDS="$toolwords" PLAN_HASTOOL="$hastool"

prog=$(cat <<'AWK'
function qsplit(s, out, deep,   n, i, c, d, q, cur, len) {
  # Split s at && || | ; (and, when deep, $( ( { and backtick) outside single and double quotes.
  n = 0; q = ""; cur = ""; len = length(s)
  for (i = 1; i <= len; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      cur = cur c
      if (q == "\"" && c == "\\") { i++; cur = cur substr(s, i, 1) }
      else if (c == q) q = ""
      continue
    }
    if (c == "\"" || c == "\047") { q = c; cur = cur c; continue }
    d = substr(s, i + 1, 1)
    if ((c == "&" && d == "&") || (c == "|" && d == "|")) { out[++n] = cur; cur = ""; i++; continue }
    if (c == "|" || c == ";" || (deep && (c == "(" || c == "{" || c == "\140"))) { out[++n] = cur; cur = ""; continue }
    if (deep && c == "$" && d == "(") { out[++n] = cur; cur = ""; i++; continue }
    cur = cur c
  }
  out[++n] = cur
  return n
}
function inlist(v, list,   n, a, i) {
  n = split(list, a, "|")
  for (i = 1; i <= n; i++) if (a[i] == v) return 1
  return 0
}
function add(line, sev, code, task, msg) {
  gsub(/\t/, " ", msg)
  nf++
  FL[nf] = line; FV[nf] = sev; FC[nf] = code; FT[nf] = task; FM[nf] = msg; FO[nf] = ""
}
function inwords(v, list,   n, a, i) {
  n = split(list, a, " ")
  for (i = 1; i <= n; i++) if (a[i] == v) return 1
  return 0
}
function devpaths(text,   s) {
  while (match(text, /\140[^\140]+\140/)) {
    s = substr(text, RSTART + 1, RLENGTH - 2)
    text = substr(text, RSTART + RLENGTH)
    if (s ~ /^[A-Za-z0-9_.@+\/-]+$/) DECL[s] = 1
  }
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function parse_override(line, text,   w, nw, code, scope, from, reason, k) {
  nw = split(substr(text, 10), w, "[ ]")
  while (nw > 0 && w[1] == "") { for (k = 1; k < nw; k++) w[k] = w[k + 1]; nw-- }
  code = w[1]; scope = ""
  if (w[2] == "plan:") { scope = "plan"; from = 3 }
  else if (w[2] == "task" && w[3] ~ /^[0-9]+:$/) { scope = substr(w[3], 1, length(w[3]) - 1) + 0; from = 4 }
  reason = ""
  for (k = from; k <= nw; k++) reason = reason " " w[k]
  reason = trim(reason); gsub(/\t/, " ", reason)
  if (scope == "" || reason == "" || inwords(code, ENVIRON["PLAN_NO_OVERRIDE"]) || (code != "all" && !inwords(code, ENVIRON["PLAN_CODES"]))) {
    add(line, "error", "override-malformed", "-", "Override line must be 'Override: <code|all> plan: <reason>' or 'Override: <code|all> task <N>: <reason>' with an overridable code and a reason")
    return
  }
  NO++; O_CODE[NO] = code; O_SCOPE[NO] = scope; O_REASON[NO] = reason; O_LINE[NO] = line
}
function apply_overrides(   i, k, hit) {
  for (i = 1; i <= nf; i++) {
    if (inwords(FC[i], ENVIRON["PLAN_NO_OVERRIDE"])) continue
    for (k = 1; k <= NO; k++) {
      hit = (O_CODE[k] == "all" || O_CODE[k] == FC[i]) && (O_SCOPE[k] == "plan" || (FT[i] != "-" && O_SCOPE[k] == FT[i] + 0))
      if (hit) { FV[i] = "overridden"; FO[i] = k; O_USED[k] = 1; break }
    }
  }
  for (k = 1; k <= NO; k++)
    if (!O_USED[k]) add(O_LINE[k], "warning", "override-unused", "-", "matches no finding")
}
function check_header(key, count, val, ln, ln2, code, set,   ok) {
  if (count == 0) { add(1, "error", code, "-", key ": line is missing"); return }
  if (count > 1) { add(ln2, "error", code, "-", key ": line appears more than once"); return }
  if (set != "" && !inlist(val, set)) add(ln, "error", code, "-", key ": " val " is not one of " set)
}
function check_spec(path, rel, specline,   r, line, n, insec, c, cat, cells) {
  if (!(rel in ISF)) { add(specline, "error", "spec-missing", "-", "no spec at " path); return }
  r = (getline line < path)
  if (r < 0) { add(specline, "error", "spec-missing", "-", "no spec at " path); return }
  n = 0; insec = 0
  while (r > 0) {
    n++
    if (index(line, "## ") == 1) insec = (index(line, "## Assumptions and open questions") == 1)
    else if (insec && index(line, "|") == 1) {
      split(line, cells, "|")
      c = trim(cells[3]); gsub("\140", "", c); c = tolower(c)
      if (c == "blocking") {
        cat = trim(cells[2])
        add(specline, "error", "blocking-row", "-", "spec line " n ": " cat " is blocking; answer it and re-run /dev-flow:spec")
      }
    }
    r = (getline line < path)
  }
  close(path)
}
function check_depends(i, line, val,   parts, np, k, d) {
  if (val == "none") return
  np = split(val, parts, ",")
  for (k = 1; k <= np; k++) {
    d = trim(parts[k])
    if (d !~ /^[0-9]+$/ || d + 0 < 1) {
      add(line, "error", "depends-malformed", i, "Depends on must be none or a comma-separated list of positive integers, got " val)
      return
    }
    if (d + 0 >= T_NUM[i]) add(line, "error", "depends-forward", i, "Depends on " d " must name an earlier task")
  }
}
function strip_ticks(p) { sub(/^\140/, "", p); sub(/\140$/, "", p); return p }
function check_path(i, line, p,   q) {
  q = strip_ticks(p)
  if (substr(q, 1, 1) == "/" || substr(q, 1, 1) == "~") { add(line, "error", "path-absolute", i, "Files path must be repo-relative, got " q); return 0 }
  if (q ~ /(^|\/)\.\.(\/|$)/) { add(line, "error", "path-dotdot", i, "Files path must not contain a .. segment, got " q); return 0 }
  if (q !~ /^[A-Za-z0-9_.@+\/-]+$/) { add(line, "error", "files-entry", i, "Files path has characters outside [A-Za-z0-9_.@+/-]: " q); return 0 }
  return 1
}
function parse_entry(i, line, text,   w, nw, v, ok) {
  text = trim(substr(text, 3))
  nw = split(text, w, / +/)
  v = w[1]
  if (text == "" || (v == "rename" ? (nw != 4 || w[3] != "->") : nw != 2)) {
    add(line, "error", "files-entry", i, "Files entry must be '- <verb> <path>' or '- rename <old> -> <new>'")
    return
  }
  if (!inlist(v, ENVIRON["PLAN_VERBS"])) { add(line, "error", "files-verb", i, "verb " v " is not one of " ENVIRON["PLAN_VERBS"]); return }
  ok = check_path(i, line, w[2])
  if (v == "rename") ok = check_path(i, line, w[4]) && ok
  if (!ok) return
  NE++
  E_TASK[NE] = i; E_VERB[NE] = v; E_PATH[NE] = strip_ticks(w[2]); E_LINE[NE] = line
  E_NEW[NE] = (v == "rename" ? strip_ticks(w[4]) : "")
  FILESET[E_PATH[NE]] = 1
  if (v == "rename") FILESET[E_NEW[NE]] = 1
}
function first_word(seg) {
  sub(/^[ \t]+/, "", seg)
  while (sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]*/, "", seg)) { }
  sub(/[ \t].*/, "", seg)
  return seg
}
function add_cmd(task, line, text) { NC++; C_TASK[NC] = task; C_LINE[NC] = line; C_TEXT[NC] = text }
function span(s,   t) {
  if (!match(s, /\140[^\140]*[^\140 \t][^\140]*\140/)) return ""
  t = substr(s, RSTART + 1, RLENGTH - 2)
  return t
}
function check_cmds(   k, ns, segs, j, w, bad) {
  for (k = 1; k <= NC; k++) {
    ns = qsplit(C_TEXT[k], segs, 0)
    for (j = 1; j <= ns; j++) {
      w = first_word(segs[j])
      if (w == "" || (w in BASEW) || (w in TOOLW)) continue
      add(C_LINE[k], "error", "verify-toolchain", C_TASK[k], "\"" w "\" is not a baseline tool or a command used by .claude/test-cmd or .claude/lint-cmd; run it the way the repo does")
      break
    }
  }
}
function exists(p) { return (p in ADDED) || ((p in EX) && !(p in REMOVED)) }
function walk(   k, v, p, np, i, line, chk) {
  for (k = 1; k <= NE; k++) {
    v = E_VERB[k]; p = E_PATH[k]; np = E_NEW[k]; i = E_TASK[k]; line = E_LINE[k]
    chk = !(T_DONE[i] + 0)
    if (v == "create") {
      if (chk && exists(p)) add(line, "error", "path-exists", i, p " already exists; /dev-flow:build ticks a task only after its verify passes, so a half-done task needs the user, not a tick")
      ADDED[p] = 1; delete REMOVED[p]
    } else if (v == "modify") {
      if (chk && !exists(p)) add(line, "error", "path-missing", i, p " does not exist at this point in the plan")
    } else if (v == "delete") {
      if (chk && !exists(p)) add(line, "error", "path-missing", i, p " does not exist at this point in the plan")
      delete ADDED[p]; REMOVED[p] = 1
    } else if (v == "rename") {
      if (chk && !exists(p)) add(line, "error", "path-missing", i, p " does not exist at this point in the plan")
      if (chk && exists(np)) add(line, "error", "path-exists", i, np " already exists; /dev-flow:build ticks a task only after its verify passes, so a half-done task needs the user, not a tick")
      delete ADDED[p]; REMOVED[p] = 1; ADDED[np] = 1; delete REMOVED[np]
    } else {
      ADDED[p] = 1; delete REMOVED[p]
    }
  }
}
function placeholder(task,   t, nw, w, k, re, m) {
  t = $0
  gsub(/\140[^\140]*\140/, "", t)
  nw = split(ENVIRON["PLAN_PLACEHOLDER_WORDS"], w, "|")
  for (k = 1; k <= nw; k++) {
    re = "(^|[^A-Za-z0-9_])" w[k] "([^A-Za-z0-9_]|$)"
    if (t ~ re) { add(NR, "error", "placeholder", task, "placeholder text: " w[k]); return }
  }
  t = tolower(t)
  re = "(^|[^a-z0-9_])(" ENVIRON["PLAN_PLACEHOLDER_PHRASES"] ")"
  if (match(t, re)) {
    m = substr(t, RSTART, RLENGTH); sub(/^[^a-z0-9_]/, "", m)
    add(NR, "error", "placeholder", task, "placeholder text: " m)
  }
}
function mentions(task, line, text,   s) {
  while (match(text, /\140[^\140]+\140/)) {
    s = substr(text, RSTART + 1, RLENGTH - 2)
    text = substr(text, RSTART + RLENGTH)
    if (s !~ /^[A-Za-z0-9_.@+-][A-Za-z0-9_.@+\/-]*$/ || index(s, "/") == 0 || substr(s, length(s), 1) == "/") continue
    if (!(s in ISF)) {
      if (s in EX) continue
      lastseg = s; sub(/^.*\//, "", lastseg)
      if (index(lastseg, ".") == 0) continue
    }
    if (s == pv || s == planrel || ((task SUBSEP s) in MSEEN)) continue
    MSEEN[task, s] = 1
    NM++; M_TASK[NM] = task; M_PATH[NM] = s; M_LINE[NM] = line
  }
}
function finish_task(   i, k, nl, lab, empty) {
  i = cur
  if (i < 1) return
  nl = split(ENVIRON["PLAN_REQUIRED"], lab, "|")
  for (k = 1; k <= nl; k++) {
    if (CNT[i, lab[k]] == 0) { add(T_LINE[i], "error", "field-missing", i, "missing " lab[k] ":"); continue }
    empty = 0
    if (lab[k] == "Objective" || lab[k] == "Test first") empty = (trim(TXT[i, lab[k]]) == "")
    else if (lab[k] == "Files") empty = (NFILES[i] == 0)
    else if (lab[k] == "Done when") empty = (NDONE[i] == 0)
    if (empty) add(LINE[i, lab[k]], "error", "field-empty", i, lab[k] " is empty")
  }
}
BEGIN {
  while ((getline row < tbl) > 0) {
    split(row, kv, "\t")
    EX[kv[2]] = 1
    if (kv[1] == "f") ISF[kv[2]] = 1
  }
  close(tbl)
  nb = split(ENVIRON["PLAN_BASELINE_COMMANDS"], bw, " ")
  for (k = 1; k <= nb; k++) BASEW[bw[k]] = 1
  nb = split(ENVIRON["PLAN_TOOLWORDS"], bw, " ")
  for (k = 1; k <= nb; k++) TOOLW[bw[k]] = 1
  sec = "header"; infence = 0
}
{
  if (sub(/\r$/, "") && !crlf_seen) {
    crlf_seen = 1
    add(NR, "error", "crlf", "-", "CRLF line endings; convert the plan to LF")
  }
  head3 = substr($0, 1, 3)
  if (infence) {
    run = 0
    while (substr($0, run + 1, 1) == fchar) run++
    if (run >= flen && substr($0, run + 1) ~ /^ *$/) infence = 0
    next
  }
  if (head3 == "\140\140\140" || head3 == "\176\176\176") {
    infence = 1; fchar = substr(head3, 1, 1); flen = 0; fence_line = NR
    while (substr($0, flen + 1, 1) == fchar) flen++
    fence_task = (sec == "tasks" && cur > 0 ? cur : "-"); next
  }
  if (substr($0, 1, 3) == "## ") {
    if (sec == "tasks") { finish_task(); cur = 0; expect_box = 0 }
    if ($0 == "## Tasks") { sec = "tasks"; if (!has_tasks) { has_tasks = 1; tasks_line = NR } }
    else if ($0 == "## Deviations") sec = "dev"
    else sec = "other"
  }
  else if (sec != "tasks" && $0 ~ /^### Task [0-9]+:/) {
    add(NR, "error", "task-heading", "-", "task heading outside ## Tasks: it is not validated but build would dispatch it")
  }
  else if (sec == "tasks" && substr($0, 1, 4) == "### ") {
    if ($0 ~ /^### Task [0-9]+: .*[^ ]/) {
      finish_task()
      n++; cur = n; expect_box = 1; fld = ""
      num = $0; sub(/^### Task /, "", num); num = num + 0
      T_LINE[n] = NR; T_NUM[n] = num
      title = $0; sub(/^### Task [0-9]+: /, "", title); gsub(/\t/, " ", title); T_TITLE[n] = title
      if (num != n) add(NR, "error", "task-number", n, "expected Task " n ", found Task " num)
      placeholder(n)
    } else {
      add(NR, "error", "task-heading", "-", "heading must be '### Task <N>: <title>'")
      finish_task(); cur = 0; expect_box = 0
      placeholder("-")
    }
    next
  }
  if (sec != "dev") placeholder(sec == "tasks" && cur > 0 ? cur : "-")
  if (sec == "dev" && $0 != "## Deviations" && $0 !~ /^[ \t]*$/) {
    if ($0 ~ /^- Task [0-9]+: .*[^ ]/) { nd++; D_LINE[nd] = NR; D_NUM[nd] = substr($0, 8) + 0
      rest = $0; sub(/^- Task [0-9]+: /, "", rest)
      tag = ENVIRON["PLAN_BLOCKED"] ":"
      if (index(rest, tag) == 1) { NB++; B_TASK[NB] = D_NUM[nd]; B_LINE[NB] = NR; btext = trim(substr(rest, length(tag) + 1)); gsub(/\t/, " ", btext); B_TEXT[NB] = btext }
      devpaths($0)
    }
    else add(NR, "error", "deviation-line", "-", "Deviations line must be '- Task N: <text>'")
  }
  if (sec == "tasks" && expect_box && $0 !~ /^[ \t]*$/) {
    if ($0 ~ /^- \[[ xX]\]( |$)/) {
      T_DONE[cur] = (substr($0, 4, 1) == " " ? 0 : 1)
      expect_box = 0
      next
    }
    add(T_LINE[cur], "error", "checkbox", cur, "first line after the heading must be '- [ ] Done' or '- [x] Done'")
    expect_box = 0
  }
  if (sec == "tasks" && cur > 0) {
    if ($0 ~ /^(Objective|Files|Test first|Test command|Change|Done when|Depends on|Risk):( |$)/) {
      fld = $0; sub(/:.*/, "", fld)
      val = $0; sub(/^[^:]*:/, "", val); val = trim(val)
      CNT[cur, fld]++
      if (CNT[cur, fld] == 2) add(NR, "error", "field-duplicate", cur, fld " appears twice")
      LINE[cur, fld] = NR
      TXT[cur, fld] = val
      if (fld == "Files" && val != "") add(NR, "error", "files-entry", cur, "put Files entries on their own lines")
      if (fld == "Test command") {
        cmd = span(val)
        if (cmd == "") add(NR, "error", "test-command-empty", cur, "Test command must contain a backticked command")
        else add_cmd(cur, NR, cmd)
      }
      if (fld == "Depends on") check_depends(cur, NR, val)
      else if (fld == "Risk" && !inlist(val, ENVIRON["PLAN_RISK"])) add(NR, "error", "risk-value", cur, "Risk must be one of " ENVIRON["PLAN_RISK"] ", got " val)
    } else if ($0 !~ /^[ \t]*$/) {
      if (fld == "Objective" || fld == "Test first" || fld == "Change") TXT[cur, fld] = trim(TXT[cur, fld] " " $0)
      else if (fld == "Files") {
        if (substr($0, 1, 2) == "- ") { NFILES[cur]++; parse_entry(cur, NR, $0) }
        else add(NR, "error", "files-entry", cur, "Files entries must start with '- '")
      }
      else if (fld == "Done when" && substr($0, 1, 2) == "- ") {
        NDONE[cur]++
        if ($0 ~ /^- run \140[^\140]+\140( |$)/) add_cmd(cur, NR, span($0))
      }
    }
  }
  if (sec == "tasks" && cur > 0 && !(fld == "Files" && substr($0, 1, 2) == "- ")) mentions(cur, NR, $0)
  if (sec == "header") {
    if (index($0, "Status:") == 1) { sn++; if (sn == 1) { sv = trim(substr($0, 8)); gsub(/\t/, " ", sv); sl = NR } else if (sn == 2) sl2 = NR }
    else if (index($0, "Approved:") == 1) { an++; if (an == 1) { av = trim(substr($0, 10)); gsub(/\t/, " ", av); al = NR } else if (an == 2) al2 = NR }
    else if (index($0, "Override:") == 1) parse_override(NR, $0)
    else if (index($0, "Spec:") == 1) { pn++; if (pn == 1) { pv = trim(substr($0, 6)); pl = NR } else if (pn == 2) pl2 = NR }
  }
}
END {
  if (infence) add(fence_line, "error", "fence-unclosed", fence_task, "code fence opened here is never closed; the rest of the plan is not validated")
  finish_task()
  walk()
  for (k = 1; k <= NM; k++)
    if (!(M_PATH[k] in FILESET)) add(M_LINE[k], "warning", "unlisted-path", M_TASK[k], M_PATH[k] " is mentioned but listed in no Files block")
  mx = ENVIRON["PLAN_MAX_FILES"] + 0
  for (i = 1; i <= n; i++)
    if (NFILES[i] > mx) add(T_LINE[i], "warning", "too-many-files", i, NFILES[i] " Files entries; split the task (at most " mx ")")
  if (ENVIRON["PLAN_HASTOOL"] == 1) check_cmds()
  check_header("Status", sn, sv, sl, sl2, "header-status", ENVIRON["PLAN_STATUS"])
  check_header("Approved", an, av, al, al2, "header-approved", ENVIRON["PLAN_APPROVED"])
  if (pn == 0) add(1, "error", "header-spec", "-", "Spec: line is missing")
  else if (pn > 1) add(pl2, "error", "header-spec", "-", "Spec: line appears more than once")
  else if (substr(pv, 1, 1) == "/" || substr(pv, 1, 1) == "~") add(pl, "error", "header-spec", "-", "Spec: path must be repo-relative, got " pv)
  else if (index("/" pv "/", "/../") > 0) add(pl, "error", "header-spec", "-", "Spec: path must not contain a .. segment, got " pv)
  else if (pv !~ /^[A-Za-z0-9_.@+\/-]+$/) add(pl, "error", "header-spec", "-", "Spec: path has characters outside [A-Za-z0-9_.@+/-]")
  else check_spec(root "/" pv, pv, pl)

  for (i = 1; i <= nd; i++)
    if (D_NUM[i] < 1 || D_NUM[i] > n) add(D_LINE[i], "error", "deviation-line", "-", "Deviations line names Task " D_NUM[i] ", which does not exist")

  if (!has_tasks) add(1, "error", "tasks-missing", "-", "no ## Tasks section")
  else if (n == 0) add(tasks_line, "error", "tasks-missing", "-", "## Tasks section has no ### Task N: headings")

  apply_overrides()

  for (i = 2; i <= nf; i++) {
    for (j = i; j > 1; j--) {
      if (FL[j - 1] + 0 > FL[j] + 0 || (FL[j - 1] + 0 == FL[j] + 0 && FC[j - 1] > FC[j])) {
        t = FL[j]; FL[j] = FL[j - 1]; FL[j - 1] = t
        t = FV[j]; FV[j] = FV[j - 1]; FV[j - 1] = t
        t = FC[j]; FC[j] = FC[j - 1]; FC[j - 1] = t
        t = FT[j]; FT[j] = FT[j - 1]; FT[j - 1] = t
        t = FM[j]; FM[j] = FM[j - 1]; FM[j - 1] = t
        t = FO[j]; FO[j] = FO[j - 1]; FO[j - 1] = t
      } else break
    }
  }
  if (strict == 1) for (i = 1; i <= nf; i++) if (FV[i] == "warning") FV[i] = "error"
  for (i = 1; i <= nf; i++) if (FV[i] == "error") errs++; else if (FV[i] == "warning") warns++; else ovr++
  if (json == 1) {
    print "H\tstatus\t" sv
    print "H\tapproved\t" av
    for (i = 1; i <= n; i++) if (!(T_DONE[i] + 0)) print "O\t" T_NUM[i] "\t" T_TITLE[i]
    for (k = 1; k <= NB; k++) print "B\t" B_TASK[k] "\t" B_LINE[k] "\t" B_TEXT[k]
    for (p in FILESET) print "D\t" p
    for (p in DECL) print "D\t" p
    for (i = 1; i <= nf; i++) {
      ol = ""; orr = ""
      if (FV[i] == "overridden") { ol = O_LINE[FO[i]]; orr = O_REASON[FO[i]] }
      print "F\t" FV[i] "\t" FC[i] "\t" FT[i] "\t" FL[i] "\t" FM[i] "\t" ol "\t" orr
    }
    if (errs > 0) {
      legacy = (sn == 0 && an == 0 && pn == 0 && !has_tasks) ? " -- this looks like a plan written before the 1.19.0 plan contract; regenerate it with /dev-flow:spec" : ""
      print "S\t" errs "\t" warns + 0 "\t" ovr + 0 "\tfail\tplan-check: " plan " has " errs " errors (" warns + 0 " warnings, " ovr + 0 " overridden); fix them, or the user overrides a false positive with an Override: header line" legacy
      exit 1
    }
    print "S\t0\t" warns + 0 "\t" ovr + 0 "\tok\tplan-check: " plan " passes (" warns + 0 " warnings, " ovr + 0 " overridden)"
    exit 0
  }
  print "plan=" plan
  print "status=" sv
  print "approved=" av
  for (i = 1; i <= n; i++) if (!(T_DONE[i] + 0)) print "open=" T_NUM[i] ": " T_TITLE[i]
  for (k = 1; k <= NB; k++) print "blocked=" B_TASK[k] " line=" B_LINE[k] ": " B_TEXT[k]
  for (i = 1; i <= nf; i++) {
    suffix = ""
    if (FV[i] == "overridden") suffix = " (override line " O_LINE[FO[i]] ": " O_REASON[FO[i]] ")"
    print FV[i] "=" FC[i] " task=" FT[i] " line=" FL[i] ": " FM[i] suffix
  }
  print "errors=" errs + 0
  print "warnings=" warns + 0
  print "overrides=" ovr + 0
  if (errs > 0) {
    print "result=fail"
    legacy = (sn == 0 && an == 0 && pn == 0 && !has_tasks) ? " -- this looks like a plan written before the 1.19.0 plan contract; regenerate it with /dev-flow:spec" : ""
    print "summary=plan-check: " plan " has " errs " errors (" warns + 0 " warnings, " ovr + 0 " overridden); fix them, or the user overrides a false positive with an Override: header line" legacy
    exit 1
  }
  print "result=ok"
  print "summary=plan-check: " plan " passes (" warns + 0 " warnings, " ovr + 0 " overridden)"
  exit 0
}
AWK
)

run_awk() { awk -v plan="$plan" -v planrel="$planrel" -v root="$root" -v tbl="$tbl" -v strict="$strict" -v json="$json" "$prog" "$plan"; }

if [ "$json" = 1 ]; then
  command -v jq > /dev/null || die jq-missing "--json needs jq on PATH"
  rows=$(mktemp); trap 'rm -f "$tbl" "$rows"' EXIT
  run_awk > "$rows"; rc=$?
  jq -R -s --arg plan "$plan" '
    def num: if . == "" or . == "-" then null else tonumber end;
    [split("\n")[] | select(length > 0) | split("\t")] as $r
    | ([$r[] | select(.[0] == "H") | {(.[1]): .[2]}] | add) as $h
    | ($r[] | select(.[0] == "S")) as $s
    | {plan: $plan, status: $h.status, approved: $h.approved,
       result: $s[4], errors: ($s[1] | tonumber), warnings: ($s[2] | tonumber), overrides: ($s[3] | tonumber),
       summary: $s[5],
       open: [$r[] | select(.[0] == "O") | {task: (.[1] | tonumber), title: .[2]}],
       blocked: [$r[] | select(.[0] == "B") | {task: (.[1] | tonumber), line: (.[2] | tonumber), text: .[3]}],
       declared: ([$r[] | select(.[0] == "D") | .[1]] | unique),
       findings: [$r[] | select(.[0] == "F") | {severity: .[1], code: .[2], task: (.[3] | num), line: (.[4] | tonumber), message: .[5],
         override: (if .[6] == "" then null else {line: (.[6] | tonumber), reason: .[7]} end)}]}' "$rows"
  jrc=$?
  [ "$jrc" = 0 ] || rc=$jrc
  exit "$rc"
fi
run_awk
exit $?
