#!/usr/bin/env bash
# Deterministic tests for plugins/dev-flow/scripts/security-targets.sh.
# They run from .claude/test-cmd, and every config is generated into a
# temporary directory.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
script="$here/plugins/dev-flow/scripts/security-targets.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
base='{"schema":"dev-flow/security-targets/v1","authorized_by":"Test Owner","authorized_on":"2026-10-03",
 "allow":[{"name":"local","base_url":"http://localhost:8080","env":"local"},
          {"name":"dev","base_url":"https://api.dev.internal","env":"dev","credential_env":["DEV_API_TOKEN"]}],
 "deny_patterns":["*.prod.*","*.live.*","api.example.com"],
 "limits":{"max_vus":200,"max_duration_seconds":600,"max_rps":500},"pci_scope":false}'
cfg() { printf '%s' "$base" | jq "$2" > "$tmp/$1.json"; echo "$tmp/$1.json"; }   # cfg <name> <jq filter> -> path

# expect <label> <config path> <want exit> <want exact line> [args...]
expect() {
  label=$1; conf=$2; want_rc=$3; want_line=$4; shift 4
  out=$(DEV_FLOW_SECURITY_TARGETS="$conf" bash "$script" "$@" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -n 1)
  if [ "$rc" = "$want_rc" ] && printf '%s\n' "$out" | grep -qxF -- "$want_line" && [ "${last#summary=}" != "$last" ]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
  fi
}

ok=$(cfg ok '.')
printf '{' > "$tmp/malformed.txt"

expect no-args "$ok" 1 reason=usage
expect unknown-flag "$ok" 1 reason=usage local --foo 1
expect userinfo-in-url "$ok" 1 reason=usage 'http://localhost:8080@evil.example/'
expect missing "$tmp/nope.json" 1 reason=config-missing local
expect malformed "$tmp/malformed.txt" 1 reason=config-malformed local
expect wrong-schema "$(cfg s '.schema="v0"')" 1 reason=config-invalid local
expect empty-allow "$(cfg e '.allow=[]')" 1 reason=config-invalid local
expect zero-limit "$(cfg z '.limits.max_vus=0')" 1 reason=config-invalid local
expect bad-credential-env "$(cfg c '.allow[1].credential_env=["dev_token"]')" 1 reason=config-invalid local
expect pci "$(cfg p '.pci_scope=true')" 1 reason=pci-scope local
expect by-name "$ok" 0 url=http://localhost:8080 local
expect by-url "$ok" 0 name=local 'http://localhost:8080/api/bookings?x=1'
expect exact-base "$ok" 0 decision=allow http://localhost:8080
expect port-extension "$ok" 1 reason=not-allowlisted 'http://localhost:80801/'
expect host-extension "$ok" 1 reason=not-allowlisted 'https://api.dev.internal.evil.com/'
expect unknown-name "$ok" 1 reason=not-allowlisted staging
expect credential-env "$ok" 0 credential_env=DEV_API_TOKEN dev

d1=$(cfg d1 '.allow += [{"name":"stage","base_url":"https://api.prod.example.net","env":"staging"}]')
expect deny-wins-over-allow "$d1" 1 reason=deny-pattern stage
expect deny-pattern-named "$d1" 1 'pattern=*.prod.*' stage
expect deny-exact-host "$(cfg d2 '.allow += [{"name":"x","base_url":"https://api.example.com","env":"dev"}]')" 1 reason=deny-pattern 'https://api.example.com/v1'
expect deny-uppercase-host "$d1" 1 reason=deny-pattern 'HTTPS://API.PROD.EXAMPLE.NET/'
expect deny-trailing-dot-host "$(cfg d3 '.allow += [{"name":"x","base_url":"https://api.example.com.","env":"dev"}]')" 1 reason=deny-pattern x
expect deny-uppercase-pattern "$(cfg d4 '.deny_patterns=["API.EXAMPLE.COM"] | .allow += [{"name":"x","base_url":"https://api.example.com","env":"dev"}]')" 1 reason=deny-pattern x
expect env-leading-space "$(cfg e1 '.allow += [{"name":"p","base_url":"https://api.example.org","env":" prod"}]')" 1 reason=config-invalid p
expect env-trailing-space "$(cfg e2 '.allow += [{"name":"p","base_url":"https://api.example.org","env":"prod "}]')" 1 reason=config-invalid p
expect repeated-vus "$ok" 1 reason=usage local --vus 300 --vus 5
expect repeated-duration "$ok" 1 reason=usage local --duration 300 --duration 5
expect repeated-rps "$ok" 1 reason=usage local --rps 300 --rps 5
expect prod-env "$(cfg p1 '.allow += [{"name":"p","base_url":"https://api.example.org","env":"Production"}]')" 1 reason=production p
expect prod-host-label "$(cfg p2 '.deny_patterns=[] | .allow += [{"name":"l","base_url":"https://live.example.org","env":"dev"}]')" 1 reason=production l
expect over-vus "$ok" 1 'detail=requested vus=1000 > max_vus=200' local --vus 1000
expect over-duration "$ok" 1 reason=limit-exceeded local --duration 601
expect over-rps "$ok" 1 reason=limit-exceeded local --rps 501
expect at-ceiling "$ok" 0 decision=allow local --vus 200 --duration 600 --rps 500
expect non-integer "$ok" 1 reason=usage local --vus abc
expect zero-value "$ok" 1 reason=usage local --vus 0
expect huge-flag-value "$ok" 1 reason=usage local --vus 99999999999999999999999
printf '%s' "$base" | sed 's/"max_vus":200/"max_vus":200.0/' > "$tmp/float.json"
expect float-ceiling-refuses "$tmp/float.json" 1 'detail=requested vus=100000 > max_vus=200' local --vus 100000
printf '%s' "$base" | sed 's/"max_vus":200/"max_vus":1e30/' > "$tmp/huge.json"
expect huge-ceiling-invalid "$tmp/huge.json" 1 reason=config-invalid local --vus 5
expect at-in-base-url "$(cfg at '.allow += [{"name":"at","base_url":"http://localhost:8080@api.prod.example.com","env":"dev"}]')" 1 reason=config-invalid at

expect ipv6-base-url "$(cfg v6 '.deny_patterns += ["[::1]"] | .allow += [{"name":"v6","base_url":"http://[::1]:8080","env":"dev"}]')" 1 reason=config-invalid local
expect ipv6-url-target "$ok" 1 reason=usage 'http://[::1]:8080/'
expect control-char-in-config "$(cfg cc '.deny_patterns += ["x\ndecision=allow"]')" 1 reason=config-invalid local

# A control character in the target must give exactly one decision= line.
out=$(DEV_FLOW_SECURITY_TARGETS="$ok" bash "$script" $'evil\ndecision=allow' 2>&1); rc=$?
if [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^decision=')" = 1 ] && printf '%s\n' "$out" | grep -qxF decision=refuse && printf '%s\n' "$out" | grep -qxF reason=usage; then
  echo "PASS: newline-in-target"
else
  echo "FAIL: newline-in-target (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
fi

# A bad CLAUDE_PROJECT_DIR must not fall back to the current directory's config.
mkdir -p "$tmp/proj/.claude"; cp "$ok" "$tmp/proj/.claude/security-targets.json"
out=$(cd "$tmp/proj" && env -u DEV_FLOW_SECURITY_TARGETS CLAUDE_PROJECT_DIR=/nonexistent bash "$script" local 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qxF decision=refuse && ! printf '%s\n' "$out" | grep -qxF decision=allow; then
  echo "PASS: bad-project-dir"
else
  echo "FAIL: bad-project-dir (exit $rc)"; printf '%s\n' "$out" | sed 's/^/    /'; fail=1
fi

ex="$here/plugins/dev-flow/templates/security-targets.example.json"
expect example-local "$ex" 0 decision=allow local
expect example-denies "$ex" 1 reason=deny-pattern https://api.example.com/

[ "$fail" = 0 ] && echo ALL-PASS; exit "$fail"
