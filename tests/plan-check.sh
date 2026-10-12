#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/plan-check.sh.
# They run from .claude/test-cmd, and every fixture repo and plan is generated
# into a temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/plan-check.sh"
. "$here/plugins/dev-flow/scripts/plan-schema.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0; golden_n=0; bad_n=0

R=$tmp/r
mkdir -p "$R/.claude/plans" "$R/.claude/specs" "$R/src" "$R/tests"
echo 'echo app' > "$R/src/app.sh"
echo 'old' > "$R/old.txt"
echo 'bash tests/greet.sh' > "$R/.claude/test-cmd"
cat > "$R/.claude/specs/demo.md" <<'SPEC'
# Spec: demo

## Notes

| a | blocking | b |

## Assumptions and open questions

| Category | Status | Resolution | Source |
|---|---|---|---|
| Scope boundary | answered | only greeting | request |
| Acceptance | assumed | prints hello | request |

1. [Acceptance] Should it print hello? (blocking) (default: yes)
SPEC
cat > "$tmp/base.md" <<'PLAN'
# Plan: demo

Status: DRAFT
Approved: no
Spec: .claude/specs/demo.md

## Tasks

### Task 1: Add the greeter

- [ ] Done

Objective: Add a greeter script.

Files:
- create src/greet.sh
- test tests/greet.sh

Test first: tests/greet.sh asserts that src/greet.sh prints hello.

Test command: `bash tests/greet.sh`

Done when:
- run `bash tests/greet.sh` and expect PASS

Risk: low

### Task 2: Call the greeter

- [ ] Done

Objective: Make the app call the greeter.

Files:
- modify src/app.sh
- modify src/greet.sh

Test first: tests/greet.sh asserts that src/app.sh prints hello.

Test command: `bash tests/greet.sh`

Done when:
- the app prints hello

Depends on: 1

## Acceptance criteria

- [ ] `bash tests/greet.sh` passes
PLAN

mk() { awk "$2" "$tmp/base.md" > "${3:-$R}/.claude/plans/$1.md"; echo "${3:-$R}/.claude/plans/$1.md"; }   # mk <name> <awk program> [repo] -> path

# expect <label> <want rc> <want prefix> <args...>
expect() {
  label=$1; want_rc=$2; want_prefix=$3; shift 3
  out=$(bash "$script" "$@" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  hit=$(printf '%s\n' "$out" | awk -v p="$want_prefix" 'index($0, p) == 1 { f = 1 } END { print f + 0 }')
  [ "$want_rc" = 1 ] && bad_n=$((bad_n + 1))
  if [ "$rc" = "$want_rc" ] && [ "$hit" = 1 ] && [ "${last#summary=}" != "$last" ]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

# also <label> <prefix>: re-checks the last output
also() {
  if printf '%s\n' "$out" | awk -v p="$2" 'index($0, p) == 1 { f = 1 } END { exit !f }'; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

# golden <label> <plan> [flags]
golden() {
  label=$1; plan=$2; shift 2
  out=$(bash "$script" "$@" "$plan" 2>&1); rc=$?
  golden_n=$((golden_n + 1))
  bad=$(printf '%s\n' "$out" | awk '/^(error|warning|overridden)=/ { n++ } END { print n + 0 }')
  if [ "$rc" = 0 ] && [ "$bad" = 0 ] && printf '%s\n' "$out" | grep -qxF errors=0 \
     && printf '%s\n' "$out" | grep -qxF warnings=0 && printf '%s\n' "$out" | grep -qxF overrides=0; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

# usage errors
expect no-args 2 error=usage
expect unknown-flag 2 error=usage --nope "$tmp/base.md"
expect two-plans 2 error=usage "$R/.claude/plans/a.md" "$R/.claude/plans/b.md"
expect not-a-plan 2 error=plan-path "$tmp/base.md"
expect plan-missing 2 error=plan-missing "$R/.claude/plans/nope.md"

# golden
base=$(mk base '1')
golden base "$base"
out=$(bash "$script" "$base" 2>&1)
also base-status status=DRAFT
also base-approved approved=no

# header and CRLF
expect status-bad 1 'error=header-status task=- line=3:' "$(mk status-bad '{sub(/^Status: DRAFT$/,"Status: WIP")}1')"
expect status-missing 1 'error=header-status task=- line=1:' "$(mk status-missing '!/^Status:/')"
expect status-dup 1 'error=header-status task=- line=4:' "$(mk status-dup '{print} /^Status:/{print}')"
expect approved-bad 1 'error=header-approved task=- line=4:' "$(mk approved-bad '{sub(/^Approved: no$/,"Approved: maybe")}1')"
expect spec-abs 1 'error=header-spec task=- line=5:' "$(mk spec-abs '{sub(/^Spec: .*/,"Spec: /tmp/x.md")}1')"
expect crlf 1 'error=crlf task=- line=1:' "$(mk crlf '{printf "%s\r\n", $0}')"

# spec existence and blocking rows
expect spec-missing 1 'error=spec-missing task=- line=5:' "$(mk spec-missing '{sub(/^Spec: .*/,"Spec: .claude/specs/nope.md")}1')"
expect spec-dir 1 'error=spec-missing task=- line=5:' "$(mk spec-dir '{sub(/^Spec: .*/,"Spec: .claude/specs")}1')"
{ cat "$R/.claude/specs/demo.md"; echo '| Compatibility | blocking | which callers | request |'; } > "$R/.claude/specs/blocked.md"
expect blocking-row 1 'error=blocking-row task=- line=5:' "$(mk blocking-row '{sub(/^Spec: .*/,"Spec: .claude/specs/blocked.md")}1')"

# tasks section, headings, numbering, checkboxes
expect tasks-missing 1 'error=tasks-missing task=- line=1:' "$(mk tasks-missing '/^## Tasks$/{next}1')"
expect tasks-empty 1 'error=tasks-missing task=- line=7:' "$(mk tasks-empty '/^### Task 1:/{exit}1')"
expect task-heading 1 'error=task-heading task=- line=28:' "$(mk task-heading '{sub(/^### Task 2: /,"### Task two: ")}1')"
expect task-gap 1 'error=task-number task=2 line=28:' "$(mk task-gap '{sub(/^### Task 2:/,"### Task 3:")}1')"
expect task-dup 1 'error=task-number task=2 ' "$(mk task-dup '{sub(/^### Task 2:/,"### Task 1:")}1')"
expect checkbox-missing 1 'error=checkbox task=2 line=28:' "$(mk checkbox-missing 'NR==30{next}1')"
expect checkbox-bad 1 'error=checkbox task=1 line=9:' "$(mk checkbox-bad '{sub(/^- \[ \] Done$/,"- [] Done")}1')"
printf '# Plan: old\n## Task 1\n' > "$R/.claude/plans/legacy.md"
expect legacy 1 'error=tasks-missing task=- line=1:' "$R/.claude/plans/legacy.md"
case "$last" in *'written before the 1.19.0 plan contract'*) echo "PASS: legacy-summary" ;; *) echo "FAIL: legacy-summary"; fail=1 ;; esac
golden fence "$(mk fence 'BEGIN{q=sprintf("%c%c%c",96,96,96)} NR==20{print q; print "### Task 9: fenced"; print "Files:"; print "TBD"; print q} 1')"
expect heading-after-notes 1 'error=task-heading task=- line=32:' "$(mk heading-after-notes 'NR==28{print "## Notes"; print ""; print "prose"; print ""} 1')"
expect heading-in-deviations 1 'error=task-heading task=- ' "$(mk heading-in-deviations '{print} END{print ""; print "## Deviations"; print ""; print "### Task 3: x"}')"
golden notes-after-tasks "$(mk notes-after-tasks '{print} END{print ""; print "## Notes"; print ""; print "Plain prose, see Task 3: nothing."}')"
golden fenced-heading-in-task "$(mk fenced-heading-in-task 'BEGIN{q=sprintf("%c%c%c",126,126,126)} NR==20{print q; print "### Task 1: demo"; print q} 1')"
golden fence-nested "$(mk fence-nested 'BEGIN{b=sprintf("%c%c%c",96,96,96); o=b sprintf("%c",96)} NR==20{print o; print b "bash"; print "### Task 9: x"; print b; print o} 1')"
expect fence-unclosed 1 'error=fence-unclosed task=1 line=20:' "$(mk fence-unclosed 'BEGIN{q=sprintf("%c%c%c",96,96,96)} NR==20{print q} 1')"
expect fence-unclosed-tilde 1 'error=fence-unclosed task=2 line=' "$(mk fence-unclosed-tilde 'NR==44{print "~~~"} 1')"
expect fence-unclosed-nooverride 1 'error=fence-unclosed task=1 line=21:' "$(mk fence-unclosed-nooverride 'BEGIN{q=sprintf("%c%c%c",96,96,96)} NR==5{print; print "Override: fence-unclosed plan: x"; next} NR==20{print q} 1')"
also fence-unclosed-nooverride-malformed 'error=override-malformed task=- '

# task fields, Depends on, Risk
expect obj-missing 1 'error=field-missing task=1 ' "$(mk obj-missing '!/^Objective: Add a greeter/')"
expect testcmd-missing 1 'error=field-missing task=1 ' "$(mk testcmd-missing 'NR==21{next}1')"
expect donewhen-missing 1 'error=field-missing task=1 ' "$(mk donewhen-missing 'NR==23||NR==24{next}1')"
expect obj-empty 1 'error=field-empty task=1 ' "$(mk obj-empty '{sub(/^Objective: Add a greeter script\.$/,"Objective:")}1')"
expect files-empty 1 'error=field-empty task=1 ' "$(mk files-empty 'NR==16||NR==17{next}1')"
expect donewhen-empty 1 'error=field-empty task=2 ' "$(mk donewhen-empty 'NR==43{next}1')"
expect field-dup 1 'error=field-duplicate task=1 ' "$(mk field-dup '{print} /^Risk: low$/{print}')"
expect dep-self 1 'error=depends-forward task=2 ' "$(mk dep-self '{sub(/^Depends on: 1$/,"Depends on: 2")}1')"
expect dep-forward 1 'error=depends-forward task=1 ' "$(mk dep-forward '{print} /^Risk: low$/{print "Depends on: 2"}')"
expect dep-word 1 'error=depends-malformed task=2 ' "$(mk dep-word '{sub(/^Depends on: 1$/,"Depends on: one")}1')"
expect dep-zero 1 'error=depends-malformed task=2 ' "$(mk dep-zero '{sub(/^Depends on: 1$/,"Depends on: 0")}1')"
expect risk-bad 1 'error=risk-value task=1 ' "$(mk risk-bad '{sub(/^Risk: low$/,"Risk: severe")}1')"
golden dep-none "$(mk dep-none '{sub(/^Depends on: 1$/,"Depends on: none")}1')"

# Files entries, verbs, path rules, existence walk
expect verb-bad 1 'error=files-verb task=2 ' "$(mk verb-bad 'NR==35{print "- edit src/app.sh"; next}1')"
expect entry-nopath 1 'error=files-entry task=1 ' "$(mk entry-nopath 'NR==16{print "- create"; next}1')"
expect entry-twopaths 1 'error=files-entry task=1 ' "$(mk entry-twopaths 'NR==16{print "- create src/a.sh src/b.sh"; next}1')"
expect entry-prose 1 'error=files-entry task=1 ' "$(mk entry-prose 'NR==17{print; print "see below"; next}1')"
expect entry-inline 1 'error=files-entry task=1 ' "$(mk entry-inline '{sub(/^Files:$/,"Files: src/a.sh")}1')"
expect entry-chars 1 'error=files-entry task=1 ' "$(mk entry-chars 'NR==16{print "- create src/a$b.sh"; next}1')"
expect abs 1 'error=path-absolute task=2 ' "$(mk abs 'NR==35{print "- modify /etc/hosts"; next}1')"
expect home 1 'error=path-absolute task=2 ' "$(mk home 'NR==35{print "- modify ~/x.sh"; next}1')"
expect dotdot 1 'error=path-dotdot task=2 ' "$(mk dotdot 'NR==35{print "- modify ../x.sh"; next}1')"
expect missing 1 'error=path-missing task=2 ' "$(mk missing 'NR==35{print "- modify src/nope.sh"; next}1')"
expect exists 1 'error=path-exists task=1 ' "$(mk exists 'NR==16{print "- create src/app.sh"; next}1')"
expect exists-msg 1 'error=path-exists task=1 line=16: src/app.sh already exists; /dev-flow:build ticks a task only after its verify passes, so a half-done task needs the user, not a tick' "$(mk exists-msg 'NR==16{print "- create src/app.sh"; next}1')"
expect exists2 1 'error=path-exists task=1 ' "$(mk exists2 'NR==16{print; print "- create old.txt"; next}1')"
also exists2-count errors=1
expect delete-then-modify 1 'error=path-missing task=2 ' "$(mk delete-then-modify 'NR==36{print; print "- delete old.txt"; print "- modify old.txt"; next}1')"
expect rename-src 1 'error=path-missing task=2 ' "$(mk rename-src 'NR==35{print "- rename src/nope.sh -> src/x.sh"; next}1')"
expect rename-dst 1 'error=path-exists task=2 ' "$(mk rename-dst 'NR==35{print "- rename old.txt -> src/app.sh"; next}1')"
golden backticked "$(mk backticked 'BEGIN{q=sprintf("%c",96)} NR==35{print "- modify " q "src/app.sh" q; next}1')"
golden verbs "$(mk verbs 'NR==36{print; print "- delete old.txt"; print "- rename src/greet.sh -> src/hello.sh"; next}1')"
R4=$tmp/r4; cp -R "$R" "$R4"; echo 'echo greet' > "$R4/src/greet.sh"
golden ticked "$(mk ticked 'NR==11{print "- [x] Done"; next}1' "$R4")"
expect ticked-off 1 'error=path-exists task=1 ' "$(mk ticked-off '1' "$R4")"
golden ticked-delete-skip "$(mk ticked-delete-skip 'NR==11{print "- [x] Done"; next} NR==17{print; print "- delete src/gone.sh"; next}1' "$R4")"
expect ticked-delete-effect 1 'error=path-missing task=2 ' "$(mk ticked-delete-effect 'NR==11{print "- [x] Done"; next} NR==17{print; print "- delete src/greet.sh"; next}1' "$R4")"
golden ticked-rename-skip "$(mk ticked-rename-skip 'NR==11{print "- [x] Done"; next} NR==17{print; print "- rename src/nope.sh -> src/app.sh"; next}1' "$R4")"
expect ticked-rename-effect 1 'error=path-missing task=2 ' "$(mk ticked-rename-effect 'NR==11{print "- [x] Done"; next} NR==17{print; print "- rename src/greet.sh -> src/hello.sh"; next}1' "$R4")"

# Test command and verify-command toolchain
expect cmd-empty 1 'error=test-command-empty task=1 ' "$(mk cmd-empty 'NR==21{print "Test command: ``"; next}1')"
expect cmd-unquoted 1 'error=test-command-empty task=1 ' "$(mk cmd-unquoted 'NR==21{print "Test command: bash tests/greet.sh"; next}1')"
expect tool-php 1 'error=verify-toolchain task=1 ' "$(mk tool-php 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "php artisan test" q; next}1')"
expect tool-run 1 'error=verify-toolchain task=1 ' "$(mk tool-run 'BEGIN{q=sprintf("%c",96)} NR==24{print "- run " q "npm test" q " and expect PASS"; next}1')"
expect tool-segment 1 'error=verify-toolchain task=1 ' "$(mk tool-segment 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "bash tests/greet.sh && php x" q; next}1')"
golden tool-env "$(mk tool-env 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "FOO=1 bash tests/greet.sh" q; next}1')"
R2=$tmp/r2; cp -R "$R" "$R2"; echo 'docker compose run --rm app make test' > "$R2/.claude/test-cmd"
golden docker "$(mk docker 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "docker compose run --rm app make test" q; next}1' "$R2")"
expect docker-make 1 'error=verify-toolchain task=1 ' "$(mk docker-make 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "make test" q; next}1' "$R2")"
R3=$tmp/r3; cp -R "$R" "$R3"; rm "$R3/.claude/test-cmd"
golden no-toolchain "$(mk no-toolchain 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "php artisan test" q; next}1' "$R3")"
golden quoted-pipe "$(mk quoted-pipe 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "jq -e \047.a | length == 2\047 f.json" q; next}1')"
golden quoted-semicolon "$(mk quoted-semicolon 'BEGIN{q=sprintf("%c",96)} NR==24{print "- run " q "grep -c \"a;b\" f" q " and expect 1"; next}1')"
expect bare-pipe 1 'error=verify-toolchain task=1 line=21: "php"' "$(mk bare-pipe 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "cat f | php x" q; next}1')"
expect quoted-pipe-bad 1 'error=verify-toolchain task=1 line=21: "php"' "$(mk quoted-pipe-bad 'BEGIN{q=sprintf("%c",96)} NR==21{print "Test command: " q "jq \047.a | b\047 f | php x" q; next}1')"

# placeholders and the Deviations section
obj() { mk "$1" "NR==13{print \"Objective: $2\"; next}1"; }   # obj <name> <objective text> -> path
expect ph-tbd 1 'error=placeholder task=1 line=13:' "$(obj ph-tbd 'Add a greeter script, TBD.')"
expect ph-todo-header 1 'error=placeholder task=- line=6:' "$(mk ph-todo-header 'NR==5{print; print "TODO later"; next}1')"
expect ph-etc 1 'error=placeholder task=1 ' "$(obj ph-etc 'Add greeters etc.')"
expect ph-appropriate 1 'error=placeholder task=1 ' "$(obj ph-appropriate 'Add a greeter as appropriate.')"
expect ph-similar 1 'error=placeholder task=1 ' "$(obj ph-similar 'Do it similar to Task 1.')"
expect ph-handle 1 'error=placeholder task=1 ' "$(obj ph-handle 'Handle errors in the greeter.')"
expect ph-tests 1 'error=placeholder task=1 ' "$(obj ph-tests 'Update tests accordingly.')"
expect dev-unknown 1 'error=deviation-line task=- ' "$(mk dev-unknown '{print} END{print ""; print "## Deviations"; print ""; print "- Task 9: x"}')"
expect dev-prose 1 'error=deviation-line task=- ' "$(mk dev-prose '{print} END{print ""; print "## Deviations"; print ""; print "free text"}')"
golden ph-negatives "$(mk ph-negatives 'BEGIN{q=sprintf("%c",96)} NR==13{print "Objective: Fetch the greeter, see the " q "TODO" q " marker in Todoist."; next}1')"
golden dev-free-text "$(mk dev-free-text '{print} END{print ""; print "## Deviations"; print ""; print "- Task 1: kept the old parser, etc."; print "- Task 1: added a retry to handle errors"}')"
expect dev-body-placeholder 1 'error=placeholder task=1 ' "$(obj dev-body-placeholder 'Kept the old parser, etc.')"
golden progress "$(mk progress 'NR==11{print "- [x] Done"; next} {sub(/^Status: DRAFT$/,"Status: IN_PROGRESS"); sub(/^Approved: no$/,"Approved: yes")} 1 END{print ""; print "## Deviations"; print ""; print "- Task 1: used printf instead of echo"}' "$R4")"

# unlisted paths, too many files, --strict
unl=$(mk unlisted "BEGIN{q=sprintf(\"%c\",96)} NR==13{print \"Objective: Wire in \" q \"src/other.sh\" q \".\"; next}1")
expect unlisted 0 'warning=unlisted-path task=1 ' "$unl"
expect unlisted-strict 1 'error=unlisted-path task=1 ' --strict "$unl"
many=$(mk many-files 'NR==17{print; for (k=1;k<=5;k++) print "- test tests/t" k ".sh"; next}1')
expect many-files 0 'warning=too-many-files task=1 ' "$many"
expect many-files-strict 1 'error=too-many-files task=1 ' --strict "$many"
golden six-files "$(mk six-files 'NR==17{print; for (k=1;k<=4;k++) print "- test tests/t" k ".sh"; next}1')"
golden listed "$(mk listed 'BEGIN{q=sprintf("%c",96)} NR==32{print "Objective: Call " q "src/app.sh" q "."; next}1')"
golden dir-and-spec "$(mk dir-and-spec 'BEGIN{q=sprintf("%c",96)} NR==13{print "Objective: Add a greeter under " q "src/" q " per " q ".claude/specs/demo.md" q "."; next}1')"

# Override lines
ov() { mk "$1" "NR==5{$3 print; print \"Override: $2\"; next} $4 1"; }   # ov <name> <override text> [pre-print stmt] [extra rules] -> path
EX2='NR==16{print; print "- create old.txt"; next}'
BLK='sub(/^Spec: .*/,"Spec: .claude/specs/blocked.md");'
expect ov-task 0 'overridden=path-exists task=1 ' "$(ov ov-task 'path-exists task 1: generated by the build' '' "$EX2")"
also ov-task-count overrides=1
case "$out" in *'generated by the build'*) echo "PASS: ov-task-reason" ;; *) echo "FAIL: ov-task-reason"; fail=1 ;; esac
expect ov-plan 0 'overridden=path-exists task=1 ' "$(ov ov-plan 'path-exists plan: generated' '' "$EX2")"
expect ov-all 0 'overridden=header-status task=- ' "$(ov ov-all 'all plan: legacy plan' '' '{sub(/^Status: DRAFT$/,"Status: WIP")}')"
expect ov-wrong-task 1 'error=path-exists task=1 ' "$(ov ov-wrong-task 'path-exists task 2: x' '' "$EX2")"
also ov-wrong-task-unused 'warning=override-unused task=- '
expect ov-blocking-code 1 'error=override-malformed task=- ' "$(ov ov-blocking-code 'blocking-row plan: x' "$BLK" '')"
expect ov-all-blocking 1 'error=blocking-row task=- ' "$(ov ov-all-blocking 'all plan: x' "$BLK" '')"
expect ov-bad-task 1 'error=override-malformed task=- ' "$(ov ov-bad-task 'path-exists task x: y' '' '')"
expect ov-unknown 1 'error=override-malformed task=- ' "$(ov ov-unknown 'nosuch plan: y' '' '')"
expect ov-no-reason 1 'error=override-malformed task=- ' "$(ov ov-no-reason 'path-exists plan:' '' '')"
ovu=$(ov ov-unused 'placeholder plan: kept for later' '' '')
expect ov-unused 0 'warning=override-unused task=- line=6:' "$ovu"
expect ov-unused-strict 1 'error=override-unused task=- line=6:' --strict "$ovu"

ovs=$(ov ov-strict 'unlisted-path task 1: wired elsewhere' '' 'NR==13{print "Objective: Wire in " sprintf("%c",96) "src/other.sh" sprintf("%c",96) "."; next}')
expect ov-strict 0 'overridden=unlisted-path task=1 ' --strict "$ovs"
also ov-strict-count overrides=1
also ov-strict-errors errors=0

# --json
# jexpect <label> <want rc> <jq filter> <args...>
jexpect() {
  label=$1; want_rc=$2; filter=$3; shift 3
  out=$(bash "$script" --json "$@" 2>&1); rc=$?
  if [ "$rc" = "$want_rc" ] && printf '%s\n' "$out" | jq -e "$filter" > /dev/null 2>&1; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}
jexpect json-base 0 '.result == "ok" and .errors == 0 and .findings == []' "$base"
jexpect json-exists2 1 '.findings[0].code == "path-exists" and .findings[0].task == 1 and .findings[0].severity == "error"' "$(mk json-exists2 'NR==16{print; print "- create old.txt"; next}1')"
jexpect json-ov-task 0 '.findings[0].override.reason == "generated by the build"' "$(ov json-ov-task 'path-exists task 1: generated by the build' '' "$EX2")"
jexpect json-status-bad 1 '.findings[0].task == null' "$(mk json-status-bad '{sub(/^Status: DRAFT$/,"Status: WIP")}1')"
jexpect json-escapes 1 '.findings[0].code == "placeholder"' "$(mk json-escapes 'NR==13{print "Objective: Say \"hi\" a\\b TBD."; next}1')"
jexpect json-ov-tab 0 '.findings[0].override.reason == "gen erated" and (.findings | length) == 1' "$(ov json-ov-tab 'path-exists task 1: gen\terated' '' "$EX2")"
jexpect json-header-tab 1 '.status == "A B" and (.findings | length) == 1' "$(mk json-header-tab '{sub(/^Status: DRAFT$/,"Status: A\tB")}1')"
expect json-usage 2 error=usage --json --nope

# jq missing: a PATH with the tools the script needs but no jq
nojq=$tmp/nojq; mkdir -p "$nojq"
for t in bash awk sed sort mktemp tr grep cat rm dirname basename head tail; do ln -s "$(command -v $t)" "$nojq/$t"; done
out=$(PATH="$nojq" bash "$script" --json "$base" 2>&1); rc=$?
last=$(printf '%s\n' "$out" | tail -n 1)
if [ "$rc" = 2 ] && [ "$(printf '%s\n' "$out" | head -n 1)" = error=jq-missing ] && [ "${last#summary=}" != "$last" ]; then echo "PASS: jq-missing"; else echo "FAIL: jq-missing (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1; fi

# --template
expect template-usage 2 error=usage --template "$base"
first=$(bash "$script" --template | head -n 1)
if [ "$first" = '# Plan: <title>' ]; then echo "PASS: template"; else echo "FAIL: template (first line: $first)"; fail=1; fi
bash "$script" --template | sed -e 's#<slug>#demo#g' \
    -e 's#<create|modify|delete|test> <repo-relative path>#test tests/greet.sh#' \
    -e 's#rename <old repo-relative path> -> <new repo-relative path>#rename old.txt -> new.txt#' \
    -e 's#`<exact command>`#`bash tests/greet.sh`#g' \
    -e 's#<low|medium|high>#low#' \
    -e 's#<[^>]*>#x#g' > "$R/.claude/plans/template.md"
golden template-golden "$R/.claude/plans/template.md"

# determinism: three plain and three --json runs per plan must match byte for byte
detfail=0
for p in "$R"/.claude/plans/*.md "$R2"/.claude/plans/*.md "$R3"/.claude/plans/*.md "$R4"/.claude/plans/*.md; do
  same=1
  for flag in "" "--json"; do
    bash "$script" $flag "$p" > "$tmp/d1" 2>&1
    bash "$script" $flag "$p" > "$tmp/d2" 2>&1
    bash "$script" $flag "$p" > "$tmp/d3" 2>&1
    cmp -s "$tmp/d1" "$tmp/d2" && cmp -s "$tmp/d1" "$tmp/d3" || same=0
  done
  [ "$same" = 1 ] || { echo "FAIL: determinism $p"; fail=1; detfail=1; }
done
[ "$detfail" = 0 ] && echo "PASS: determinism"

# drift-rules, drift-agent: the rule file and the spec-architect agent repeat the schema value sets
words=$(printf '%s' "$PLAN_PLACEHOLDER_WORDS" | tr '|' ' ')
for name in rules agent; do
  if [ "$name" = rules ]; then target="$here/.claude/rules/plans.md"; else target="$here/plugins/dev-flow/agents/spec-architect.md"; fi
  drift=1
  if [ -f "$target" ]; then
    for s in "$PLAN_STATUS" "$PLAN_APPROVED" "$PLAN_VERBS" "$PLAN_RISK" "at most $PLAN_MAX_FILES" $words; do
      grep -qiF -- "$s" "$target" || { echo "FAIL: drift-$name missing '$s'"; drift=0; }
    done
    if [ "$name" = agent ]; then
      grep -qF -- 'plan-check.sh --template' "$target" || { echo "FAIL: drift-agent missing 'plan-check.sh --template'"; drift=0; }
    fi
  else
    echo "FAIL: drift-$name $target missing"; drift=0
  fi
  [ "$drift" = 1 ] && echo "PASS: drift-$name" || fail=1
done

# drift-readme: README.md lists every finding code in backticks
drift=1
for c in $PLAN_CODES; do
  grep -qF -- "\`$c\`" "$here/README.md" || { echo "FAIL: drift-readme missing '$c'"; drift=0; }
done
[ "$drift" = 1 ] && echo "PASS: drift-readme" || fail=1

# acceptance counts
echo "golden_n=$golden_n bad_n=$bad_n"
if [ "$golden_n" -ge 5 ] && [ "$bad_n" -ge 10 ]; then echo "PASS: counts"; else echo "FAIL: counts"; fail=1; fi

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
