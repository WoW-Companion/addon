#!/bin/sh
# Runs scripts/release-prep.sh on a throwaway copy and checks the result.
set -eu
src=$(cd "$(dirname "$0")/.." && pwd)
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/scripts" "$d/changes" "$d/WoWCompanion/Locales" "$d/WoWCompanion_Digest"
cp "$src/scripts/release-prep.sh" "$d/scripts/"
cp "$src/WoWCompanion/WoWCompanion.toc" "$src/WoWCompanion/WhatsNew.lua" "$d/WoWCompanion/"
cp "$src/WoWCompanion/Locales/enUS.lua" "$d/WoWCompanion/Locales/"
cp "$src/WoWCompanion_Digest/WoWCompanion_Digest.toc" "$d/WoWCompanion_Digest/"
fail() { echo "releaseprep: $*" >&2; exit 1; }
old=$(sed -n 's/^## Version: *//p' "$d/WoWCompanion/WoWCompanion.toc")
if sh "$d/scripts/release-prep.sh" "$d" 2>/dev/null; then fail "ran with no fragments"; fi
printf -- '- Second "quoted" line.\n' > "$d/changes/ADDON-2.md"
printf -- '# note\n- First line.\n\n' > "$d/changes/ADDON-1.md"
sh "$d/scripts/release-prep.sh" "$d" >/dev/null || fail "failed with fragments"
new="${old%.*}.$(( ${old##*.} + 1 ))"; key=$(echo "$new" | tr . _)
grep -q "^## Version: $new\$" "$d/WoWCompanion/WoWCompanion.toc" || fail "TOC not bumped"
grep -q "^## Version: $new\$" "$d/WoWCompanion_Digest/WoWCompanion_Digest.toc" || fail "Digest TOC not bumped"
grep -q "^    WHATS_NEW_${key}_1 = \"First line.\",\$" "$d/WoWCompanion/Locales/enUS.lua" || fail "line 1 (id order)"
grep -q "^    WHATS_NEW_${key}_2 = \"Second \\\\\"quoted\\\\\" line.\",\$" "$d/WoWCompanion/Locales/enUS.lua" || fail "line 2"
grep -q "\[\"$new\"\] = { \"WHATS_NEW_${key}_1\", \"WHATS_NEW_${key}_2\" }," "$d/WoWCompanion/WhatsNew.lua" || fail "CHANGELOG"
[ -z "$(ls "$d/changes")" ] || fail "fragments not deleted"
BUMP=minor; export BUMP
echo "- Minor." > "$d/changes/ADDON-3.md"
sh "$d/scripts/release-prep.sh" "$d" >/dev/null || fail "minor failed"
grep -q "^## Version: ${old%%.*}.$(( $(echo "$old" | cut -d. -f2) + 1 )).0\$" "$d/WoWCompanion/WoWCompanion.toc" || fail "minor bump"
echo "releaseprep: ok"
