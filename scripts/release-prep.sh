#!/bin/sh
# Release prep: folds changes/*.md into one release. Bumps the TOC ## Version (both TOCs), adds that version's
# What's-new lines (Locales/enUS.lua WHATS_NEW_<v>_<n>) and CHANGELOG entry (WhatsNew.lua), deletes the fragments.
# Usage: scripts/release-prep.sh [root]      BUMP=patch (default) | minor
# Commit the result with the trailer "Release-Prep: true". Refuses when there are no fragments.
set -eu
root="${1:-$(dirname "$0")/..}"
cd "$root"
toc=WoWCompanion/WoWCompanion.toc
bump="${BUMP:-patch}"
set -- $(ls changes/*.md 2>/dev/null | LC_ALL=C sort) || true
[ "$#" -gt 0 ] && [ -f "$1" ] || { echo "release-prep: no changes/*.md fragments; nothing to release" >&2; exit 1; }
old=$(sed -n 's/^## Version: *//p' "$toc" | tr -d '\r')
case "$old" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "release-prep: bad ## Version '$old'" >&2; exit 1 ;; esac
major=${old%%.*}; rest=${old#*.}; minor=${rest%%.*}; patch=${rest#*.}
case "$bump" in
  patch) new="$major.$minor.$((patch + 1))" ;;
  minor) new="$major.$((minor + 1)).0" ;;
  *) echo "release-prep: BUMP must be patch or minor" >&2; exit 1 ;;
esac
key=$(echo "$new" | tr . _)
lines=$(mktemp); keys=$(mktemp); trap 'rm -f "$lines" "$keys"' EXIT
# Each non-blank line not starting with '#' is one player-facing line; a leading "- " is dropped.
for f in "$@"; do
  sed -e 's/\r$//' -e '/^[[:space:]]*$/d' -e '/^#/d' -e 's/^- *//' "$f" >> "$lines"
done
[ -s "$lines" ] || { echo "release-prep: the fragments hold no What's-new lines" >&2; exit 1; }
n=0
: > "$keys"
while IFS= read -r line; do
  n=$((n + 1))
  esc=$(printf '%s' "$line" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '    WHATS_NEW_%s_%s = "%s",\n' "$key" "$n" "$esc" >> "$keys.l"
  printf '"WHATS_NEW_%s_%s", ' "$key" "$n" >> "$keys"
done < "$lines"
list=$(sed 's/, $//' "$keys")
# enUS.lua: insert after the last existing WHATS_NEW line.
last=$(grep -n 'WHATS_NEW_[0-9_]* *=' WoWCompanion/Locales/enUS.lua | tail -1 | cut -d: -f1)
sed "${last}r $keys.l" WoWCompanion/Locales/enUS.lua > "$keys.e" && cat "$keys.e" > WoWCompanion/Locales/enUS.lua
# WhatsNew.lua: newest version first.
sed "/^WC.CHANGELOG = {/a\\
    [\"$new\"] = { $list }," WoWCompanion/WhatsNew.lua > "$keys.w" && cat "$keys.w" > WoWCompanion/WhatsNew.lua
rm -f "$keys.l" "$keys.e" "$keys.w"
for t in WoWCompanion/WoWCompanion.toc WoWCompanion_Digest/WoWCompanion_Digest.toc; do
  sed "s/^## Version:.*/## Version: $new/" "$t" > "$keys.t" && cat "$keys.t" > "$t"
done
rm -f "$keys.t"
rm -f "$@"
echo "release-prep: $old -> $new ($n line(s))"
