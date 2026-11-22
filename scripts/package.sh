#!/bin/sh
# Builds dist/WoWCompanion-<version>.zip holding the two addon folders at the top level.
# The data file the companion writes (Digest.lua) is left out so unzipping an
# update over an install never overwrites a player's data; the addon copes with them missing.
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/^## Version: *//p' WoWCompanion/WoWCompanion.toc)
[ -n "$version" ] || { echo "no ## Version in WoWCompanion/WoWCompanion.toc" >&2; exit 1; }
mkdir -p dist
out="dist/WoWCompanion-$version.zip"
rm -f "$out"
zip -qr -X "$out" WoWCompanion WoWCompanion_Digest \
    -x WoWCompanion_Digest/Digest.lua WoWCompanion_Digest/Plan.lua
echo "$out"
