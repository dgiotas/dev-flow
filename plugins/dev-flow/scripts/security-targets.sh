#!/usr/bin/env bash
# Decides whether a load or active-security target may be used, per
# .claude/security-targets.json (schema dev-flow/security-targets/v1). It fails
# closed: exit 0 only for decision=allow, every other outcome is
# decision=refuse and exit 1. It never reads credential values.
#
# IPv6 literal hosts ([ in the authority) are refused: the host cut cannot match them.
#
# Usage:  bash security-targets.sh <name|url> [--vus N] [--duration SECONDS] [--rps N]
# Machine-readable key=value lines, plus a summary= line last.
#
# DEV_FLOW_SECURITY_TARGETS exists only as a test seam and config override.
set -u

refuse() {
  echo "decision=refuse"; echo "reason=$1"
  [ -n "${2:-}" ] && echo "detail=$2"
  echo "summary=$3"; exit 1
}

usage="Usage: security-targets.sh <name|url> [--vus N] [--duration SECONDS] [--rps N] (integers >= 1, each flag at most once, no credentials in the URL)."
[ $# -ge 1 ] && [ "${1#-}" = "$1" ] || refuse usage "" "$usage"
target=$1; shift
case "$target" in *[[:cntrl:]]*) refuse usage "" "$usage" ;; esac
want_vus=""; want_duration=""; want_rps=""
while [ $# -gt 0 ]; do
  val=${2:-}
  case "$val" in ''|*[!0-9]*|0*) refuse usage "" "$usage" ;; esac
  [ ${#val} -le 18 ] || refuse usage "" "$usage"
  case "$1" in
    --vus) [ -z "$want_vus" ] || refuse usage "" "$usage"; want_vus=$val ;;
    --duration) [ -z "$want_duration" ] || refuse usage "" "$usage"; want_duration=$val ;;
    --rps) [ -z "$want_rps" ] || refuse usage "" "$usage"; want_rps=$val ;;
    *) refuse usage "" "$usage" ;;
  esac
  shift 2
done

authority=""
if [[ $target =~ ^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]*) ]]; then
  authority=${BASH_REMATCH[1]}
  case "$authority" in *@*|*\[*) refuse usage "" "$usage" ;; esac
fi

command -v jq >/dev/null 2>&1 || refuse jq-missing "" "jq is not on PATH; cannot read the targets config, so nothing may run."

if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || refuse config-missing "" "CLAUDE_PROJECT_DIR does not exist or cannot be entered; refusing to fall back to the current directory."
fi
conf="${DEV_FLOW_SECURITY_TARGETS:-.claude/security-targets.json}"
[ -f "$conf" ] || refuse config-missing "" "No $conf: no config, no run. Copy templates/security-targets.example.json and have the owner fill it in."
jq empty "$conf" 2>/dev/null || refuse config-malformed "" "$conf is not valid JSON; nothing may run until it is fixed."

# Returns "" or the first failing rule; a jq runtime error counts as invalid.
bad=$(jq -r '
  def posint: type == "number" and . == floor and . >= 1 and . <= 1000000000;
  if .schema != "dev-flow/security-targets/v1" then "schema must be dev-flow/security-targets/v1"
  elif (.authorized_by | type) != "string" or (.authorized_by | length) == 0 then "authorized_by must be a non-empty string"
  elif (.authorized_on | type) != "string" or ((.authorized_on | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) | not) then "authorized_on must be YYYY-MM-DD"
  elif (.allow | type) != "array" or (.allow | length) == 0 then "allow must be a non-empty array"
  elif any(.allow[]; (.name | type) != "string" or (.env | type) != "string" or ((.env | test("^[A-Za-z0-9_-]+$")) | not)
        or (.base_url | type) != "string" or ((.base_url | test("^https?://[^/?#@\\[]+([/?#]|$)")) | not)) then "each allow entry needs a string name, an env matching [A-Za-z0-9_-]+ and an http(s) base_url without credentials or an IPv6 literal"
  elif any(.allow[] | .name, .base_url; test("[\u0001-\u001f\u007f]")) or any(.deny_patterns[]?; type == "string" and test("[\u0001-\u001f\u007f]")) then "allow name, base_url and deny_patterns must not contain control characters"
  elif any(.allow[]; has("credential_env") and ((.credential_env | type) != "array"
        or any(.credential_env[]; type != "string" or ((test("^[A-Z_][A-Z0-9_]*$")) | not)))) then "credential_env must be an array of environment variable names"
  elif (.deny_patterns | type) != "array" or any(.deny_patterns[]; type != "string") then "deny_patterns must be an array of strings"
  elif (.limits | type) != "object" or any([.limits.max_vus, .limits.max_duration_seconds, .limits.max_rps][]; posint | not) then "limits.max_vus, max_duration_seconds and max_rps must be integers from 1 to 1000000000"
  elif (.pci_scope | type) != "boolean" then "pci_scope must be a boolean"
  elif has("notes") and (.notes | type) != "string" then "notes must be a string"
  else "" end' "$conf" 2>/dev/null) || bad="schema check failed"
[ -z "$bad" ] || refuse config-invalid "$bad" "$conf does not match dev-flow/security-targets/v1: $bad."

jq -e '.pci_scope == true' "$conf" >/dev/null && refuse pci-scope "" "pci_scope is true: active and load testing are disabled for this repo; only threat modelling may run."

name=""; env=""; base_url=""
if [ -z "$authority" ]; then
  row=$(jq -r --arg n "$target" 'first(.allow[] | select(.name == $n)) | [.name, .env, .base_url] | @tsv' "$conf")
  [ -n "$row" ] || refuse not-allowlisted "" "$target is not under any allow[].base_url; refused."
  IFS=$'\t' read -r name env base_url <<< "$row"
  url=${base_url%/}
  [[ $url =~ ^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]*) ]] && authority=${BASH_REMATCH[1]}
else
  url=$target
  while IFS=$'\t' read -r n e b; do
    b=${b%/}
    case "$url" in "$b"|"$b"/*|"$b"\?*|"$b"#*) name=$n; env=$e; base_url=$b; break ;; esac
  done <<< "$(jq -r '.allow[] | [.name, .env, .base_url] | @tsv' "$conf")"
fi
host=$(printf '%s' "$authority" | sed 's/:.*//' | tr '[:upper:]' '[:lower:]')
host=${host%.}

# Deny always wins over allow; $pat stays unquoted so it is a glob.
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  pat=$(printf '%s' "$pat" | tr '[:upper:]' '[:lower:]')
  case "$host" in
    $pat) echo "pattern=$pat"; refuse deny-pattern "" "$host matches deny pattern $pat; deny always wins over allow." ;;
  esac
done <<< "$(jq -r '.deny_patterns[]' "$conf")"

why=""
case "$(printf '%s' "$env" | tr '[:upper:]' '[:lower:]')" in prod|production|live) why="env $env" ;; esac
if [ -z "$why" ]; then
  IFS=. read -r -a labels <<< "$host"
  for label in "${labels[@]}"; do
    case "$label" in prod|production|live) why="host label $label"; break ;; esac
  done
fi
[ -z "$why" ] || refuse production "" "$target is production ($why): agents never test production; that needs a human owner, a window and a rollback plan."

[ -n "$name" ] || refuse not-allowlisted "" "$target is not under any allow[].base_url; refused."

# Over-limit requests are refused, not capped.
for pair in "vus:$want_vus:max_vus" "duration:$want_duration:max_duration_seconds" "rps:$want_rps:max_rps"; do
  IFS=: read -r what want key <<< "$pair"
  [ -n "$want" ] || continue
  ceil=$(jq -r --arg k "$key" '.limits[$k] | floor | tostring' "$conf")
  # Inverted so a non-integer operand (test exit 2) refuses instead of allowing.
  if ! [ "$want" -le "$ceil" ] 2>/dev/null; then
    detail="requested $what=$want > $key=$ceil"
    refuse limit-exceeded "$detail" "Requested load exceeds the configured ceiling ($detail); propose a lower value or ask the owner to change the config."
  fi
done

max_vus=$(jq -r '.limits.max_vus | floor | tostring' "$conf")
max_duration=$(jq -r '.limits.max_duration_seconds | floor | tostring' "$conf")
max_rps=$(jq -r '.limits.max_rps | floor | tostring' "$conf")
cred=$(jq -r --arg n "$name" 'first(.allow[] | select(.name == $n)) | (.credential_env // []) | join(",")' "$conf")
echo "decision=allow"
echo "name=$name"
echo "env=$env"
echo "base_url=$base_url"
echo "url=$url"
echo "max_vus=$max_vus"
echo "max_duration_seconds=$max_duration"
echo "max_rps=$max_rps"
echo "credential_env=$cred"
echo "summary=Target $name ($env) $url is allowlisted; ceilings: vus <= $max_vus, duration <= ${max_duration}s, rps <= $max_rps."
