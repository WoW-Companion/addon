#!/bin/sh
# Builds dist/WoWCompanion-<version>.zip holding the three addon folders at the top level.
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/^## Version: *//p' WoWCompanion/WoWCompanion.toc)
[ -n "$version" ] || { echo "no ## Version in WoWCompanion/WoWCompanion.toc" >&2; exit 1; }
mkdir -p dist
out="dist/WoWCompanion-$version.zip"
rm -f "$out"
zip -qr -X "$out" WoWCompanion WoWCompanion_Digest WoWCompanion_Answers
echo "$out"
