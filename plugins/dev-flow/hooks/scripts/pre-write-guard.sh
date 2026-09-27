#!/usr/bin/env bash
# PreToolUse guard for AGENTS.md, CLAUDE.md and .claude/rules/*.md -- the files
# that carry a project's standing instructions.
#
# Covers Write (whole-file replace) AND Edit / MultiEdit (targeted changes), so a
# targeted edit cannot slip a change in without the diff being shown. This does
# NOT trust the model to "remember" to ask: any change to an existing guarded file
# is blocked unless a one-time approval marker matching that exact change already
# exists. The block message hands Claude the exact command to create the marker,
# so the only route through is: show the change -> get a yes -> write the marker
# -> retry. Exit 2 = block, stderr goes back to Claude. Exit 0 = allow.
#
# The marker hash binds the approval to (path + the exact change + the file's
# current content), so it cannot be reused for a different change, and it is
# invalidated if the file moves on underneath it. Pure bash/jq/sha256sum -- no
# reconstruction of the post-edit file is needed, and none is attempted.
set -u
input=$(cat)

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1
  fi
}
jqr() { printf '%s' "$input" | jq -r "$1"; }
trunc() { head -c 4000; }

tool=$(jqr '.tool_name // empty')
case "$tool" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

file=$(jqr '.tool_input.file_path // empty')
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

old_content=$(cat "$file" 2>/dev/null || true)
cur_hash=$(printf '%s' "$old_content" | hash_of)

# Build (a) a human-readable preview of the change and (b) the payload whose hash
# the approval marker must match.
preview=""
payload=""
case "$tool" in
  Write)
    new_content=$(jqr '.tool_input.content // empty')
    # No actual change: let it through without ceremony.
    [ "$new_content" = "$old_content" ] && exit 0
    preview="Whole-file replace. Diff (current -> proposed):
$(diff -u "$file" <(printf '%s' "$new_content") 2>&1 | tail -150)"
    payload="WRITE
$rel
$cur_hash
$new_content"
    ;;
  Edit)
    old_s=$(jqr '.tool_input.old_string // empty')
    new_s=$(jqr '.tool_input.new_string // empty')
    all=$(jqr '.tool_input.replace_all // false')
    [ "$old_s" = "$new_s" ] && exit 0
    preview="Targeted edit (replace_all=$all).
--- would replace this text -------------------------------
$(printf '%s' "$old_s" | trunc)
+++ with this text ----------------------------------------
$(printf '%s' "$new_s" | trunc)
-----------------------------------------------------------"
    payload="EDIT
$rel
$cur_hash
$all
$old_s
>>>---<<<
$new_s"
    ;;
  MultiEdit)
    n=$(jqr '(.tool_input.edits // []) | length')
    [ "$n" = "0" ] && exit 0
    preview="Targeted multi-edit ($n changes)."
    payload="MULTIEDIT
$rel
$cur_hash"
    i=0
    while [ "$i" -lt "$n" ]; do
      o=$(jqr ".tool_input.edits[$i].old_string // empty")
      w=$(jqr ".tool_input.edits[$i].new_string // empty")
      preview="$preview
--- [$((i+1))/$n] would replace ----------------------------
$(printf '%s' "$o" | trunc)
+++ [$((i+1))/$n] with -------------------------------------
$(printf '%s' "$w" | trunc)"
      payload="$payload
EDIT $i
$o
>>>---<<<
$w"
      i=$((i+1))
    done
    preview="$preview
-----------------------------------------------------------"
    ;;
esac

want_hash=$(printf '%s' "$payload" | hash_of)
marker_dir=".claude/.approved-writes"
marker="$marker_dir/${rel//\//__}.approved"

if [ -f "$marker" ] && [ "$(tr -d '[:space:]' < "$marker" 2>/dev/null)" = "$want_hash" ]; then
  rm -f "$marker" # single-use
  exit 0
fi

{
  echo "BLOCKED: $tool would change an existing protected file: $rel"
  echo "AGENTS.md, CLAUDE.md and .claude/rules/*.md are never changed without the user seeing it first."
  echo
  echo "$preview"
  echo
  echo "Required next step: show the user the change above verbatim and wait for an"
  echo "explicit yes/no reply in this turn. Do not retry, and do not work around this"
  echo "by splitting the change up, using a different tool, or recreating the file."
  echo
  echo "If they approve THIS exact change, run this, then retry the same call unchanged:"
  echo "  mkdir -p \"$marker_dir\" && printf '%s' \"$want_hash\" > \"$marker\""
  echo
  echo "The marker is single-use and bound to this exact change and the file's current"
  echo "content, so any revision needs a fresh approval. Prefer proposing the complete"
  echo "intended result in ONE call, so the user reviews one coherent change."
} >&2
exit 2
