#!/usr/bin/env bash
# Reports which file carries this repo's agent guidance, and whether CLAUDE.md is
# merely a link/pointer to AGENTS.md (in which case AGENTS.md is the only file to
# edit, and CLAUDE.md must be left alone).
#
# Usage:  bash guidance-target.sh [repo-root]
# Machine-readable key=value lines, plus a human summary on the last line.
#
# Detects: symlink (including a broken one), hard link (same inode), and a
# Claude Code import/mention of AGENTS.md inside CLAUDE.md (e.g. "@AGENTS.md").
set -u
cd "${1:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null || { echo "error=cannot-cd"; exit 1; }

A=AGENTS.md
C=CLAUDE.md

inode_of() { ls -Li "$1" 2>/dev/null | awk '{print $1}'; }

has_a=0; [ -e "$A" ] && has_a=1
has_c=0; [ -e "$C" ] || [ -L "$C" ] && has_c=1

link_kind=none
link_detail=""
if [ "$has_c" = "1" ]; then
  if [ -L "$C" ]; then
    tgt=$(readlink "$C" 2>/dev/null || true)
    case "$(basename -- "${tgt:-}")" in
      AGENTS.md) link_kind=symlink; link_detail="$C -> $tgt" ;;
      *)         link_kind=symlink-elsewhere; link_detail="$C -> ${tgt:-?}" ;;
    esac
  elif [ "$has_a" = "1" ]; then
    ia=$(inode_of "$A"); ic=$(inode_of "$C")
    if [ -n "$ia" ] && [ "$ia" = "$ic" ]; then
      link_kind=hardlink; link_detail="same inode ($ia)"
    fi
  fi
  # A real, separate CLAUDE.md may still just point at AGENTS.md via an import.
  if [ "$link_kind" = "none" ] && [ -f "$C" ]; then
    if grep -qE '@[.~/]*([A-Za-z0-9_.-]+/)*AGENTS\.md' "$C" 2>/dev/null; then
      link_kind=import
      link_detail=$(grep -nE '@[.~/]*([A-Za-z0-9_.-]+/)*AGENTS\.md' "$C" 2>/dev/null | head -3 | tr '\n' ';')
    fi
  fi
fi

echo "agents_md=$has_a"
echo "claude_md=$has_c"
echo "link_kind=$link_kind"
[ -n "$link_detail" ] && echo "link_detail=$link_detail"

if [ "$link_kind" = "symlink" ] || [ "$link_kind" = "hardlink" ] || [ "$link_kind" = "import" ]; then
  echo "canonical=AGENTS.md"
  echo "edit=AGENTS.md"
  echo "never_edit=CLAUDE.md"
  echo "summary=CLAUDE.md is linked to AGENTS.md ($link_kind). Put ALL guidance in AGENTS.md and do not touch CLAUDE.md."
  exit 0
fi

if [ "$has_a" = "1" ] && [ "$has_c" = "1" ]; then
  echo "canonical=ambiguous"
  echo "edit=ask-the-user"
  echo "summary=Both AGENTS.md and CLAUDE.md exist independently. Ask which is canonical; do not duplicate rules across both."
  exit 0
fi
if [ "$has_a" = "1" ]; then
  echo "canonical=AGENTS.md"; echo "edit=AGENTS.md"
  echo "summary=AGENTS.md is the source of truth. Claude Code may need a CLAUDE.md pointer (symlink or @AGENTS.md import) to load it."
  exit 0
fi
if [ "$has_c" = "1" ]; then
  echo "canonical=CLAUDE.md"; echo "edit=CLAUDE.md"
  echo "summary=Only CLAUDE.md exists. Write guidance there."
  exit 0
fi
echo "canonical=none"; echo "edit=ask-the-user"
echo "summary=Neither file exists. Ask which the user wants (default: AGENTS.md plus a CLAUDE.md pointer)."
