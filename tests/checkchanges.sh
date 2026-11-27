#!/bin/sh
# Runs scripts/check-changes.sh on a throwaway tree holding fragments, and checks what it accepts and rejects.
set -eu
src=$(cd "$(dirname "$0")/.." && pwd)
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/scripts" "$d/changes"
cp "$src/scripts/check-changes.sh" "$d/scripts/"
fail() { echo "checkchanges: $*" >&2; exit 1; }
run() { sh "$d/scripts/check-changes.sh" 2>&1; }
printf -- '# note\n- Short bullet.\n\n- Another one.\n' > "$d/changes/ADDON-1.md"
run >/dev/null || fail "rejected good bullets"
long=$(printf 'x%.0s' $(seq 1 141))
printf -- '- Fine.\n- %s\n' "$long" > "$d/changes/ADDON-2.md"   # "- " plus 141 = 143 characters
out=$(run) && fail "accepted a 143-character line"
echo "$out" | grep -q 'changes/ADDON-2.md line 2: 143 chars, max 100; split into bullets' || fail "message: $out"
printf -- 'Not a bullet.\n' > "$d/changes/ADDON-2.md"
out=$(run) && fail "accepted a non-bullet line"
echo "$out" | grep -q 'changes/ADDON-2.md line 1: not a bullet' || fail "message: $out"
echo "checkchanges: ok"
