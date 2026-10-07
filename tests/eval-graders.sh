#!/usr/bin/env bash
# Offline checks of eval grader patterns under plugins/dev-flow/evals. They run
# from .claude/test-cmd and never call `claude plugin eval`; each grader's
# frontmatter is read with ruby and its pattern is applied to sample text with node.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
ev="$here/plugins/dev-flow/evals"
if ! command -v node >/dev/null 2>&1 || ! command -v ruby >/dev/null 2>&1; then
  echo "SKIP: node/ruby not found"; exit 0
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# fm <grader-file>: the frontmatter as JSON
fm() {
  ruby -ryaml -rjson -e 't=File.read(ARGV[0]); puts JSON.generate(YAML.safe_load(t.split(/^---\s*$/,3)[1]))' "$1"
}

# rx <label> <grader-file> <sample-file> <pass|fail>: a type: regex grader against sample text
rx() {
  got=$(node -e 'const g=JSON.parse(process.argv[1]); const t=require("fs").readFileSync(process.argv[2],"utf8"); const m=new RegExp(g.pattern,g.flags||"").test(t); process.stdout.write(((g.match==="not_contains")?!m:m)?"pass":"fail")' "$(fm "$2")" "$3")
  if [ "$got" = "$4" ]; then pass "$1"; else echo "FAIL: $1 (got $got, want $4)"; fail=1; fi
}

# inp <label> <grader-file> <key> <json-sample-file> <pass|fail>: input_match against a JSON tool input.
# key is input_match, or before/after for the g[key].input_match form.
inp() {
  got=$(node -e 'const g=JSON.parse(process.argv[1]); const k=process.argv[2]; const t=require("fs").readFileSync(process.argv[3],"utf8"); const re=(k==="input_match")?g.input_match:g[k].input_match; process.stdout.write(new RegExp(re).test(t)?"pass":"fail")' "$(fm "$2")" "$3" "$4")
  if [ "$got" = "$5" ]; then pass "$1"; else echo "FAIL: $1 (got $got, want $5)"; fail=1; fi
}

printf '%s' '{"subagent_type":"dev-flow:threat-modeler","prompt":"x"}' > "$tmp/agent-input"
printf '%s' '{"subagent_type":"general-purpose","prompt":"x"}' > "$tmp/agent-other"

af="$ev/threat-bola/graders/agent-fired.md"
inp bola-agent-fired "$af" input_match "$tmp/agent-input" pass
inp bola-agent-other "$af" input_match "$tmp/agent-other" fail

cat > "$tmp/doc-bola-good.md" <<'EOF'
# Threat model: src
Generated: 2026-10-07 · Commit: 1a2b3c4 · Baseline: OWASP API Security Top 10 2023 (current edition not checked) · Reviewed by:

## Findings
### T1 — Booking lookup lacks ownership check  [API1 / CWE-639]  Severity: high  Confidence: verified
- **Where:** `src/routes/bookings.js:7`
- **Mechanism:** x
### T2 — Other  [API4]  Severity: medium  Confidence: unverified
- **Where:** `src/app.js:6`
EOF
sed 's/Confidence: verified/Confidence: unverified/' "$tmp/doc-bola-good.md" > "$tmp/doc-bola-unverified.md"
cat > "$tmp/doc-wrongfile.md" <<'EOF'
### T1 — x  [API1 / CWE-639]  Severity: high  Confidence: verified
- **Where:** `src/app.js:8`
### T2 — y  [API4]  Severity: low  Confidence: verified
- **Where:** `src/routes/bookings.js:7`
EOF
{ echo '```markdown'; cat "$tmp/doc-bola-good.md"; } > "$tmp/doc-fenced.md"
printf '%s' '{"file_path":"/tmp/w/docs/threats/src.md","content":"# Threat model: src"}' > "$tmp/write-input"
printf '%s' '{"file_path":"/tmp/w/notes.md","content":"# Threat model: src"}' > "$tmp/write-other"

bg="$ev/threat-bola/graders"
rx bola-format-good "$bg/doc-format.md" "$tmp/doc-bola-good.md" pass
rx bola-format-fenced "$bg/doc-format.md" "$tmp/doc-fenced.md" fail
rx bola-format-wrongfile "$bg/doc-format.md" "$tmp/doc-wrongfile.md" fail
rx bola-finding-good "$bg/finding-regex.md" "$tmp/doc-bola-good.md" pass
rx bola-finding-unverified "$bg/finding-regex.md" "$tmp/doc-bola-unverified.md" fail
rx bola-finding-wrongfile "$bg/finding-regex.md" "$tmp/doc-wrongfile.md" fail
cat > "$tmp/doc-wrongfile-notchecked.md" <<'EOF'
### T1 — x  [API1 / CWE-639]  Severity: high  Confidence: verified
- **Where:** `src/app.js:8`
## Not checked
- `src/routes/bookings.js:7`
EOF
rx bola-finding-wrongfile-section "$bg/finding-regex.md" "$tmp/doc-wrongfile-notchecked.md" fail
inp bola-order-before "$bg/writes-after-agent.md" before "$tmp/agent-input" pass
inp bola-order-after "$bg/writes-after-agent.md" after "$tmp/write-input" pass
inp bola-order-after-other "$bg/writes-after-agent.md" after "$tmp/write-other" fail

cat > "$tmp/doc-nofp-good.md" <<'EOF'
# Threat model: src
Generated: 2026-10-07 · Commit: 1a2b3c4 · Baseline: x · Reviewed by:

## Findings
### T1 — Rate limits  [API4]  Severity: medium  Confidence: verified
- **Where:** `src/app.js:6`
### Low-severity notes
| BOLA ownership check present | low |
EOF
printf '%s\n' '### T1 — idor on booking  [api1]  severity: High' > "$tmp/doc-nofp-lower.md"

ng="$ev/threat-no-fp/graders"
rx nofp-format-good "$ng/doc-format.md" "$tmp/doc-nofp-good.md" pass
rx nofp-nohigh-good "$ng/no-high-bola.md" "$tmp/doc-nofp-good.md" pass
rx nofp-nohigh-bad "$ng/no-high-bola.md" "$tmp/doc-bola-good.md" fail
rx nofp-nohigh-lowercase "$ng/no-high-bola.md" "$tmp/doc-nofp-lower.md" fail
printf '%s\n' '### T1 — Token check bypass (IDOR)  [API2 / CWE-287]  Severity: high  Confidence: verified' > "$tmp/doc-nofp-api2.md"
rx nofp-nohigh-api2-idor-title "$ng/no-high-bola.md" "$tmp/doc-nofp-api2.md" pass
cat > "$tmp/doc-nofp-bullet.md" <<'EOF'
### T1 — idor on booking  [API1 / CWE-639]
- **Severity:** high
- **Where:** `src/routes/bookings.js:7`
EOF
rx nofp-nohigh-severity-bullet "$ng/no-high-bola.md" "$tmp/doc-nofp-bullet.md" fail
printf '%s\n' '### T1 — idor on booking  [API1 / CWE-639]  Confidence: verified  Severity: **high**' > "$tmp/doc-nofp-bold.md"
rx nofp-nohigh-severity-bold "$ng/no-high-bola.md" "$tmp/doc-nofp-bold.md" fail
cat > "$tmp/doc-nofp-later-high.md" <<'EOF'
### T1 — idor on booking  [API1 / CWE-639]
- **Severity:** medium
### T2 — rate limits  [API4]
- **Severity:** high
EOF
rx nofp-nohigh-later-finding "$ng/no-high-bola.md" "$tmp/doc-nofp-later-high.md" pass
inp nofp-order-after "$ng/writes-after-agent.md" after "$tmp/write-input" pass

cat > "$tmp/doc-unv-good.md" <<'EOF'
# Threat model: src
Generated: 2026-10-07 · Commit: 1a2b3c4 · Baseline: x · Reviewed by:

## Findings
### T1 — Booking BOLA depends on external middleware  [API1 / CWE-639]  Severity: high  Confidence: unverified
- **Where:** `src/routes/bookings.js:7`
## Not checked
- @acme/policy-gateway enforceOwnership('booking') at `src/app.js:8`
EOF

ug="$ev/threat-unverified/graders"
rx unv-format-good "$ug/doc-format.md" "$tmp/doc-unv-good.md" pass
rx unv-api1-unverified-good "$ug/api1-unverified.md" "$tmp/doc-unv-good.md" pass
rx unv-api1-unverified-bad "$ug/api1-unverified.md" "$tmp/doc-bola-good.md" fail
rx unv-no-verified-good "$ug/no-verified-api1.md" "$tmp/doc-unv-good.md" pass
rx unv-no-verified-bad "$ug/no-verified-api1.md" "$tmp/doc-bola-good.md" fail
rx unv-names-gateway-good "$ug/names-gateway.md" "$tmp/doc-unv-good.md" pass
rx unv-names-gateway-bad "$ug/names-gateway.md" "$tmp/doc-bola-good.md" fail

printf '%s' 'The threat-modeler found no API surface: src is a pure slug helper. Nothing was written.' > "$tmp/msg-nosurface"
printf '%s' 'NO-SURFACE: pure library, no routes or handlers.' > "$tmp/msg-nosurface-raw"
printf '%s' 'Wrote docs/threats/src.md with 2 findings (1 high, 1 medium).' > "$tmp/msg-findings"

sg="$ev/threat-no-surface/graders"
rx nosurface-says-so "$sg/says-so-regex.md" "$tmp/msg-nosurface" pass
rx nosurface-says-so-raw "$sg/says-so-regex.md" "$tmp/msg-nosurface-raw" pass
for m in 'found no attack surface' 'has no network surface' "The library doesn't expose an API" 'does not have routes' 'The library doesn’t expose an API' 'found no externally-reachable API surface'; do
  printf '%s' "$m" > "$tmp/msg-wide"
  rx "nosurface-says-so-wide: $m" "$sg/says-so-regex.md" "$tmp/msg-wide" pass
done
printf '%s' 'I found 3 findings in src/app.js' > "$tmp/msg-plain"
rx nosurface-says-so-plain "$sg/says-so-regex.md" "$tmp/msg-plain" fail
rx nosurface-says-so-findings "$sg/says-so-regex.md" "$tmp/msg-findings" fail
if [ ! -e "$sg/no-file.md" ]; then pass "nosurface-no-file-removed"; else bad "nosurface-no-file-removed"; fi

[ "$fail" = 0 ] && echo ALL-PASS
exit "$fail"
