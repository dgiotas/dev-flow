#!/usr/bin/env bash
# PreToolUse guard for whole-file overwrites of AGENTS.md, CLAUDE.md and
# .claude/rules/*.md -- the files that carry a project's standing instructions.
#
# This does NOT trust the model to "remember" to ask. It mechanically blocks any
# Write that would change an existing guarded file's content, unless a one-time
# approval marker matching the exact proposed content's hash already exists.
# The block message hands Claude the exact commands to create that marker, so the
# only way past this gate is: show the user the diff -> get a yes -> write the
# marker -> retry. Exit 2 = block, stderr goes back to Claude. Exit 0 = allow.
set -u
input=$(cat)

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1
  fi
}

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Write" ] || exit 0

file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

base=$(basename -- "$file")
rel="${file#"$PWD"/}"
guarded=0
case "$base" in AGENTS.md|CLAUDE.md) guarded=1 ;; esac
case "$rel" in .claude/rules/*.md) guarded=1 ;; esac
[ "$guarded" = "1" ] || exit 0

# New file: nothing to protect yet.
[ -f "$file" ] || exit 0

new_content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty')
old_content=$(cat "$file" 2>/dev/null || true)

# No actual change: let it through without ceremony.
if [ "$new_content" = "$old_content" ]; then exit 0; fi

new_hash=$(printf '%s' "$new_content" | hash_of)
marker_dir=".claude/.approved-writes"
marker_name="${rel//\//__}.approved"
marker="$marker_dir/$marker_name"

if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null | tr -d '[:space:]')" = "$new_hash" ]; then
  rm -f "$marker" # single-use
  exit 0
fi

diff_out=$(diff -u "$file" <(printf '%s' "$new_content") 2>&1 | tail -150)

{
  echo "BLOCKED: this would overwrite an existing protected file: $rel"
  echo "Protected files (AGENTS.md, CLAUDE.md, .claude/rules/*.md) are never silently overwritten."
  echo
  echo "Diff (old -> new):"
  echo "$diff_out"
  echo
  echo "Required next step: show this diff to the user verbatim and wait for an"
  echo "explicit yes/no reply in this turn before doing anything else. Do not retry"
  echo "the write until they approve."
  echo
  echo "If they approve this exact content, run this, then retry the same Write unchanged:"
  echo "  mkdir -p \"$marker_dir\" && printf '%s' \"$new_hash\" > \"$marker\""
  echo
  echo "If they want changes instead, propose new content and repeat this process --"
  echo "each distinct version needs its own approval (the marker is single-use and"
  echo "content-specific)."
} >&2
exit 2
