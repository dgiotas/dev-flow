#!/usr/bin/env bash
# Explains a dead hook-probe by reading the on-disk Claude Code managed
# settings for hooks and permission-rule restrictions. It never decides
# whether hooks are live — the probe is the source of truth for that — it
# only reports why a probe that came back unblocked did so. A server-managed
# (claude.ai) policy is not visible to this script; only on-disk sources are.
#
# Usage:  bash hooks-policy.sh
# Machine-readable key=value lines, plus a summary= line last.
#
# DEV_FLOW_MANAGED_DIR and DEV_FLOW_MANAGED_PLIST exist only as test seams.
set -u

command -v jq >/dev/null 2>&1 || { echo "error=jq-missing"; exit 1; }

case "$(uname -s)" in
  Darwin) def="/Library/Application Support/ClaudeCode" ;;
  *)      def="/etc/claude-code" ;;
esac
dir="${DEV_FLOW_MANAGED_DIR:-$def}"
plist="${DEV_FLOW_MANAGED_PLIST:-/Library/Managed Preferences/com.anthropic.claudecode.plist}"

hooks=not-found; hooks_source=""
perms=not-found; perms_source=""

check() {
  src="$1"; json="$2"
  if echo "$json" | jq -e '.disableAllHooks == true' >/dev/null 2>/dev/null; then
    hooks=disabled; hooks_source="$src"
  elif [ "$hooks" = "not-found" ] && echo "$json" | jq -e '.allowManagedHooksOnly == true' >/dev/null 2>/dev/null; then
    hooks=managed-only; hooks_source="$src"
  fi
  if [ "$perms" = "not-found" ] && echo "$json" | jq -e '.allowManagedPermissionRulesOnly == true' >/dev/null 2>/dev/null; then
    perms=managed-only; perms_source="$src"
  fi
}

for f in "$dir/managed-settings.json" "$dir"/managed-settings.d/*.json; do
  [ -r "$f" ] && check "$f" "$(cat "$f")"
done

if [ -r "$plist" ] && command -v plutil >/dev/null 2>&1; then
  j=$(plutil -convert json -o - "$plist" 2>/dev/null)
  [ -n "$j" ] && check "$plist" "$j"
fi

echo "hooks=$hooks"
[ "$hooks" != "not-found" ] && echo "hooks_source=$hooks_source"
echo "permission_rules=$perms"
[ "$perms" = "managed-only" ] && echo "permission_rules_source=$perms_source"

case "$hooks" in
  disabled)
    summary="Managed settings set disableAllHooks: no hooks run, including dev-flow's. Continue in hookless mode."
    ;;
  managed-only)
    summary="Managed settings set allowManagedHooksOnly: plugin hooks are blocked unless an admin force-enables dev-flow@dev-flow-marketplace in managed enabledPlugins. Continue in hookless mode."
    ;;
  not-found)
    summary="No hook restriction in on-disk managed settings. A server-managed (claude.ai) policy is not visible here: check /status -> Setting sources."
    ;;
esac
if [ "$perms" = "managed-only" ]; then
  summary="$summary Project/local permission rules are ignored (allowManagedPermissionRulesOnly), so the guard substitute is instruction-only."
fi
echo "summary=$summary"
exit 0
