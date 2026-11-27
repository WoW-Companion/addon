#!/bin/sh
# Guard: a normal change never edits the TOC ## Version, the What's-new CHANGELOG (WhatsNew.lua) or the
# WHATS_NEW_ lines in Locales/enUS.lua. Only a release-prep commit may (trailer "Release-Prep: true", or it
# deletes a changes/*.md fragment). Checks each non-merge commit on this branch since it left main.
set -eu
cd "$(dirname "$0")/.."
base=""
for ref in origin/main main; do
  if git rev-parse -q --verify "$ref" >/dev/null 2>&1; then base=$(git merge-base HEAD "$ref" 2>/dev/null || true); [ -n "$base" ] && break; fi
done
revs=""
if [ -n "$base" ]; then revs=$(git rev-list --no-merges "$base..HEAD"); else echo "check-changes: no main to compare with; commits skipped"; fi
bad=0
# Fragments: every line is a bullet ("- text") of at most 100 characters. Blank lines and "#" lines are ignored.
for f in changes/*.md; do
  [ -f "$f" ] || continue
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%"$(printf '\r')"}
    case "$line" in ''|'#'*) continue ;; esac
    len=$(printf '%s' "$line" | wc -m | tr -d ' ')
    case "$line" in
      "- "*) ;;
      *) echo "check-changes: $f line $n: not a bullet; start it with \"- \" (one change per line)" >&2; bad=1 ;;
    esac
    if [ "$len" -gt 100 ]; then
      echo "check-changes: $f line $n: $len chars, max 100; split into bullets" >&2; bad=1
    fi
  done < "$f"
done
for c in $revs; do
  if git log -1 --format=%B "$c" | grep -qi '^Release-Prep: *true *$'; then continue; fi
  if git diff-tree --no-commit-id --diff-filter=D --name-only -r "$c" | grep -q '^changes/.*\.md$'; then continue; fi
  hit=$(git show -U0 --format= "$c" -- 'WoWCompanion/*.toc' 'WoWCompanion_Digest/*.toc' WoWCompanion/WhatsNew.lua WoWCompanion/Locales/enUS.lua \
    | grep -E '^[+-](## Version:|    \["[0-9]+\.[0-9]+\.[0-9]+"\] =|    WHATS_NEW_[0-9_]+ *=)' || true)
  if [ -n "$hit" ]; then
    echo "check-changes: $(git log -1 --format=%h "$c") changes the version or What's new outside a release-prep commit: use changes/<ID>.md" >&2
    bad=1
  fi
done
[ "$bad" = 0 ] || exit 1
echo "check-changes: ok"
