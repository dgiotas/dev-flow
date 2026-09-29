#!/usr/bin/env bash
# PreToolUse guard for AGENTS.md, CLAUDE.md and .claude/rules/*.md -- the files
# that carry a project's standing instructions.
#
# Covers Write (whole-file replace), Edit / MultiEdit (targeted changes), AND
# Bash commands whose text looks like it writes one of these files directly, so a
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

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we cannot even parse tool_name, so fall back to a raw-text check
  # on the whole payload. Only hard-fail when a guarded file is plausibly
  # mentioned -- otherwise every Bash command (including the "brew install jq"
  # remediation this message recommends) would be blocked too.
  if printf '%s' "$input" | grep -qE '(AGENTS|CLAUDE)\.md|\.claude/rules/'; then
    echo "BLOCKED: dev-flow pre-write-guard cannot run: 'jq' is not on PATH." >&2
    echo "It parses the hook payload, so it cannot tell whether this write touches a" >&2
    echo "protected guidance file. Install jq (brew install jq / apt install jq) in a" >&2
    echo "terminal outside this session, then retry." >&2
    exit 2
  fi
  exit 0
fi

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1
  fi
}
jqr() { printf '%s' "$input" | jq -r "$1"; }
# Identifies the exact installed copy that is running, so a stale cached plugin
# is visible in the block message instead of looking like a working guard.
whoami_line() {
  root="${CLAUDE_PLUGIN_ROOT:-}"
  if [ -z "$root" ]; then
    printf 'dev-flow pre-write-guard (CLAUDE_PLUGIN_ROOT unset)'
  elif [ -f "$root/.claude-plugin/plugin.json" ]; then
    v=$(jq -r '.version // "unknown"' "$root/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)
    printf 'dev-flow pre-write-guard v%s -- %s' "$v" "$root"
  else
    printf 'dev-flow pre-write-guard (manifest missing) -- %s' "$root"
  fi
}
trunc() { head -c 4000; }

tool=$(jqr '.tool_name // empty')
case "$tool" in Write|Edit|MultiEdit|Bash) ;; *) exit 0 ;; esac

if [ "$tool" = "Bash" ]; then
  cmd=$(jqr '.tool_input.command // empty')

  # Guarded-name matcher with a real boundary: the character right after ".md"
  # must not be able to extend the filename -- so "AGENTS.md.approved" (the
  # approval-marker file) does NOT match "AGENTS.md", but "AGENTS.md",
  # "AGENTS.md;", "AGENTS.md )", "AGENTS.md<<EOF" etc. all do.
  gname='(AGENTS\.md|CLAUDE\.md|\.claude/rules/[^[:space:]"'\''`]*\.md)'
  gbound='([^.[:alnum:]_-]|$)'
  gprefix='[^[:space:]]*'
  gtarget="${gprefix}${gname}${gbound}"
  gtarget_last="${gprefix}${gname}[\"']?[[:space:]]*\$"

  # Fast bail: nothing resembling a guarded name, with a real boundary,
  # appears anywhere in the command at all.
  printf '%s' "$cmd" | grep -qE "$gtarget" || exit 0

  # Split into clauses on control operators (&&, ||, ;, |) so the end-of-clause
  # anchor ($) used below is well-defined -- the true end of a clause, not an
  # arbitrary spot mid-regex, and so a guarded mention in one clause (e.g.
  # `head AGENTS.md`) cannot make an unrelated command in another clause
  # (e.g. `mv a b`) look like it targets that file.
  clauses=$(printf '%s' "$cmd" | tr -s ';&|' '\n')

  # Per-construct: the guarded name must be the actual TARGET of that
  # construct, not merely co-occurring somewhere in the command.
  redirect_re="(^|[[:space:]])>{1,2}\\|?[[:space:]]*[\"']?${gtarget}"          # >, >>, >| (also catches heredocs: the > before <<EOF)
  tee_re="(^|[[:space:]])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[\"']?${gtarget}"
  dd_re="(^|[[:space:]])dd([[:space:]][^[:space:]]*)*[[:space:]]of=${gtarget}"
  truncate_re="(^|[[:space:]])truncate[[:space:]].*${gtarget}"
  cpmv_re="(^|[[:space:]])(cp|mv|install)[[:space:]].*[[:space:]]${gtarget_last}"     # cp/mv/install: destination is the LAST word
  sedperl_re="(^|[[:space:]])(sed|perl)[[:space:]].*-[a-zA-Z]*i[a-zA-Z]*.*[[:space:]]${gtarget_last}"   # in-place edit (incl. bundled flags like -pi/-ni/-ri): file is the LAST word
  rm_re="(^|[[:space:]])(rm|unlink|shred)([[:space:]]+-[a-zA-Z-]+)*[[:space:]]+[\"']?${gtarget}"
  gitrestore_re="(^|[[:space:]])git[[:space:]]+restore[[:space:]]+(--[[:space:]]+)?[\"']?${gtarget}"
  gitcheckout_re="(^|[[:space:]])git[[:space:]]+checkout([[:space:]]+[^[:space:]]+)*[[:space:]]+--[[:space:]]+[\"']?${gtarget}"

  blocked=0
  if printf '%s\n' "$clauses" | grep -qE "$redirect_re" \
     || printf '%s\n' "$clauses" | grep -qE "$tee_re" \
     || printf '%s\n' "$clauses" | grep -qE "$dd_re" \
     || printf '%s\n' "$clauses" | grep -qE "$truncate_re" \
     || printf '%s\n' "$clauses" | grep -qE "$cpmv_re" \
     || printf '%s\n' "$clauses" | grep -qE "$sedperl_re" \
     || printf '%s\n' "$clauses" | grep -qE "$rm_re" \
     || printf '%s\n' "$clauses" | grep -qE "$gitrestore_re" \
     || printf '%s\n' "$clauses" | grep -qE "$gitcheckout_re" \
     || printf '%s' "$cmd" | grep -qE 'python[0-9.]*[[:space:]]+-c'; then
    blocked=1
  fi
  [ "$blocked" = 1 ] || exit 0

  { echo "BLOCKED: this Bash command looks like it writes a protected guidance file."
    printf '  (%s)\n' "$(whoami_line)"
    echo "AGENTS.md, CLAUDE.md and .claude/rules/*.md are only changed through the Write"
    echo "or Edit tool, so the guard can show the user the exact diff first."
    echo "Re-issue this change with the Write or Edit tool instead."
  } >&2
  exit 2
fi

file=$(jqr '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

base=$(basename -- "$file")
rel="${file#"$PWD"/}"
[ "$rel" = "$file" ] && rel="${file#"$(pwd -P)"/}"
guarded=0
case "$base" in AGENTS.md|CLAUDE.md) guarded=1 ;; esac
case "$rel" in .claude/rules/*.md) guarded=1 ;; esac
case "$file" in */.claude/rules/*.md|.claude/rules/*.md) guarded=1 ;; esac
[ "$guarded" = "1" ] || exit 0

# ---------------------------------------------------------------------------
# HARD RULE: if CLAUDE.md is linked to AGENTS.md (symlink, hard link, or an
# @AGENTS.md import), CLAUDE.md is only a pointer. Editing it is either
# pointless or actively dangerous -- a write through a symlink silently rewrites
# AGENTS.md while looking like a CLAUDE.md change. Refuse and redirect; do NOT
# offer the normal approve-and-retry path, since there is nothing to approve.
# ---------------------------------------------------------------------------
if [ "$base" = "CLAUDE.md" ]; then
  link_kind=none; link_detail=""
  if [ -L "$file" ]; then
    tgt=$(readlink "$file" 2>/dev/null || true)
    case "$(basename -- "${tgt:-}")" in
      AGENTS.md) link_kind=symlink; link_detail="$rel -> $tgt" ;;
    esac
  elif [ -f AGENTS.md ] && [ -f "$file" ]; then
    ia=$(ls -Li AGENTS.md 2>/dev/null | awk '{print $1}')
    ic=$(ls -Li "$file"   2>/dev/null | awk '{print $1}')
    [ -n "$ia" ] && [ "$ia" = "$ic" ] && { link_kind=hardlink; link_detail="same inode ($ia)"; }
  fi
  if [ "$link_kind" = "none" ] && [ -f "$file" ] && [ ! -L "$file" ]; then
    if grep -qE '@[.~/]*([A-Za-z0-9_.-]+/)*AGENTS\.md' "$file" 2>/dev/null; then
      link_kind=import
      link_detail=$(grep -nE '@[.~/]*([A-Za-z0-9_.-]+/)*AGENTS\.md' "$file" 2>/dev/null | head -3)
    fi
  fi

  if [ "$link_kind" != "none" ]; then
    override=".claude/.approved-writes/ALLOW-CLAUDE-MD-EDIT"
    if [ -f "$override" ]; then
      rm -f "$override" # single-use
    else
      {
        echo "REFUSED: $rel is only a pointer to AGENTS.md ($link_kind)."
        printf '  (%s)\n' "$(whoami_line)"
        [ -n "$link_detail" ] && printf '  %s\n' "$link_detail"
        echo
        if [ "$link_kind" = "symlink" ] || [ "$link_kind" = "hardlink" ]; then
          echo "Writing to it would silently rewrite AGENTS.md through the link, while"
          echo "appearing to change $rel. That is never what is wanted here."
        else
          echo "It imports AGENTS.md, so guidance added here would be duplicated or lost."
        fi
        echo
        echo "Put the change in AGENTS.md instead, and leave $rel alone. Re-issue the same"
        echo "change targeting AGENTS.md (it is gated normally: you will be shown the diff"
        echo "to confirm with the user)."
        echo
        echo "Do NOT create an override yourself. Only if the USER explicitly wants to edit"
        echo "the pointer file itself (e.g. to fix the import line) they can run:"
        echo "  mkdir -p .claude/.approved-writes && touch $override"
      } >&2
      exit 2
    fi
  fi
fi

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
  printf '  (%s)\n' "$(whoami_line)"
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
