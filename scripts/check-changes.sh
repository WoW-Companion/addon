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
[ -n "$base" ] || { echo "check-changes: no main to compare with; skipped"; exit 0; }
bad=0
for c in $(git rev-list --no-merges "$base..HEAD"); do
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
