#!/usr/bin/env bash
# plan-edit-check.sh: detect plan edits an implementer may not make.
# An implementer may tick its own checkbox, add entries to its own Files
# block, and append lines "- Task N: ..." to ## Deviations. Anything else in
# the plan is a finding.
# Usage: bash plan-edit-check.sh <before> <after> <N>
# Output (key=value lines): one error=<code> line=<n>: <text> per finding
#   (foreign-edit|checkbox-edit|files-removed|deviation-rewritten|
#   deviation-task), then errors=<n>, result=ok|fail and a final summary=
#   line. Usage errors print error=<code> then summary=.
# Exit: 0 no findings, 1 findings, 2 usage or input error
#   (error=usage|plan-missing|task-missing).
set -u
export LC_ALL=C

here=$(cd "$(dirname "$0")" && pwd)
. "$here/plan-schema.sh"

die() { echo "error=$1"; echo "summary=$2"; exit 2; }

[ "$#" = 3 ] || die usage "usage: bash plan-edit-check.sh <before> <after> <N>"
before=$1; after=$2; n=$3
case $n in ''|*[!0-9]*|0*) die usage "N must be a positive integer: $n" ;; esac
[ -f "$before" ] || die plan-missing "plan not found: $before"
[ -f "$after" ] || die plan-missing "plan not found: $after"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Emits F (frame), C (checkbox), E (Files entry), V (Deviations line) and T
# (Task N found) records. Fenced lines never start or end a region.
records() {
  awk -v want="$1" '
    BEGIN {
      FS = "\n"
      label = "^(" ENVIRON["PLAN_REQUIRED"] "|" ENVIRON["PLAN_OPTIONAL"] "):"
    }
    function rec(k, t) { printf "%s\t%d\t%s\n", k, NR, t }
    {
      line = $0
      if (!fence) {
        if (line ~ /^## /) {
          intasks = (line == "## Tasks"); indev = (line == "## Deviations")
          intask = 0; infiles = 0
          rec("F", line); next
        }
        if (line ~ /^### /) {
          intask = 0; infiles = 0
          if (intasks && index(line, "### Task " want ":") == 1) { intask = 1; seen = 0; rec("T", "found") }
          rec("F", line); next
        }
        if (intask && infiles && (line ~ label || line ~ /^#/)) infiles = 0
      }
      if (indev && line != "") { rec("V", line) }
      else if (intask && infiles && line != "") { rec("E", line) }
      else if (intask && !seen && line != "") {
        seen = 1
        if (line ~ /^- \[[ xX]\]/) rec("C", line); else rec("F", line)
      }
      else {
        if (intask && !fence && line ~ /^Files:/) infiles = 1
        rec("F", line)
      }
      # A fence closes on its own character, at least as long as the opener.
      if (fence) {
        run = 0
        while (substr(line, run + 1, 1) == fchar) run++
        if (run >= flen && substr(line, run + 1) ~ /^ *$/) fence = 0
      } else if (line ~ /^(```|~~~)/) {
        fence = 1; fchar = substr(line, 1, 1); flen = 0
        while (substr(line, flen + 1, 1) == fchar) flen++
      }
    }' "$2"
}

records "$n" "$before" > "$tmp/b" 2>/dev/null
records "$n" "$after" > "$tmp/a" 2>/dev/null
grep -q '^T	[0-9]*	found$' "$tmp/b" || die task-missing "Task $n not found in $before"

# A Deviations section the implementer created is not frame: drop the heading
# from the after frame when the before plan has none.
hasdev=0; grep -q '^F	[0-9]*	## Deviations$' "$tmp/b" && hasdev=1

findings=$(awk -F'\t' -v n="$n" -v hasdev="$hasdev" '
  function text(s) { sub(/^[^\t]*\t[^\t]*\t/, "", s); return s }
  function cut(s) { return substr(s, 1, 120) }
  function emit(code, ln, t) { printf "error=%s line=%d: %s\n", code, ln, cut(t) }
  FNR == 1 { file++ }
  {
    kind = $1; ln = $2; t = text($0)
    if (kind == "T") { tline[file] = ln; next }
    cnt[file, kind]++; i = cnt[file, kind]
    val[file, kind, i] = t; num[file, kind, i] = ln
  }
  END {
    # Frame: drop trailing blanks, and a created Deviations heading.
    bn = cnt[1, "F"]; an = cnt[2, "F"]
    while (bn > 0 && val[1, "F", bn] == "") bn--
    while (an > 0 && val[2, "F", an] == "") an--
    if (!hasdev && an > 0 && val[2, "F", an] == "## Deviations") { an--; while (an > 0 && val[2, "F", an] == "") an-- }
    m = (bn > an) ? bn : an
    for (i = 1; i <= m; i++) {
      if (i > bn || i > an || val[1, "F", i] != val[2, "F", i]) {
        if (i <= an) emit("foreign-edit", num[2, "F", i], val[2, "F", i])
        else emit("foreign-edit", num[1, "F", i], val[1, "F", i])
        break
      }
    }
    # Checkbox: unchanged, or an unticked box ticked.
    bc = val[1, "C", 1]; ac = val[2, "C", 1]
    if (cnt[2, "C"] != 1 || cnt[1, "C"] != 1) emit("checkbox-edit", cnt[2, "C"] > 0 ? num[2, "C", 1] : tline[2] + 0, ac)
    else if (bc != ac) {
      if (!(substr(bc, 1, 5) == "- [ ]" && (substr(ac, 1, 5) == "- [x]" || substr(ac, 1, 5) == "- [X]") && substr(bc, 6) == substr(ac, 6)))
        emit("checkbox-edit", num[2, "C", 1], ac)
    }
    # Files: every before entry must survive.
    for (i = 1; i <= cnt[2, "E"]; i++) kept[val[2, "E", i]] = 1
    for (i = 1; i <= cnt[1, "E"]; i++)
      if (!(val[1, "E", i] in kept)) emit("files-removed", num[1, "E", i], val[1, "E", i])
    # Deviations: before lines are a prefix; new lines belong to Task N.
    bv = cnt[1, "V"]; av = cnt[2, "V"]
    rewritten = 0
    for (i = 1; !rewritten && i <= bv; i++) if (val[1, "V", i] != val[2, "V", i]) rewritten = i
    if (rewritten) emit("deviation-rewritten", num[1, "V", rewritten], val[1, "V", rewritten])
    else for (i = bv + 1; i <= av; i++)
      if (index(val[2, "V", i], "- Task " n ": ") != 1) emit("deviation-task", num[2, "V", i], val[2, "V", i])
  }' "$tmp/b" "$tmp/a")

if [ -z "$findings" ]; then
  echo "errors=0"
  echo "result=ok"
  echo "summary=plan-edit-check: Task $n edits stay inside its checkbox, Files block and Deviations lines"
  exit 0
fi
printf '%s\n' "$findings"
count=$(printf '%s\n' "$findings" | wc -l | tr -d ' ')
echo "errors=$count"
echo "result=fail"
echo "summary=plan-edit-check: $count edit(s) outside Task $n's own entries"
exit 1
